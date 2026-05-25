import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  QueryCommand,
  PutCommand,
  UpdateCommand,
  DeleteCommand,
} from "@aws-sdk/lib-dynamodb";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { randomUUID } from "crypto";
import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";

const ddb    = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const s3     = new S3Client({ region: process.env.AWS_ACCOUNT_REGION ?? "us-east-1" });
const TABLE  = process.env.EXPENSES_TABLE!;
const BUCKET = process.env.RECEIPTS_BUCKET!;
const GSI    = "vehicleId-expenseDate-index";

type Category =
  | "fuel" | "maintenance" | "insurance" | "parking" | "tolls"
  | "meals" | "travel" | "lodging" | "groceries" | "home_supplies"
  | "utilities" | "entertainment" | "medical" | "other";

interface ExpenseBody {
  vehicleId?:    string | null;
  tripId?:       string | null;
  category:      Category;
  amount:        number;
  expenseDate:   string;
  merchant?:     string;
  notes?:        string;
  receiptS3Key?: string | null;
}

export const handler = async (
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
  const userId    = event.requestContext.authorizer?.claims?.sub as string;
  const method    = event.httpMethod;
  const expenseId = event.pathParameters?.expenseId;
  const filterVehicleId = event.queryStringParameters?.vehicleId;

  try {
    // ── GET /expenses/upload-url?expenseId=xxx ────────────────────────────────
    // Returns a pre-signed S3 PUT URL the mobile app uses to upload receipt photos
    if (method === "GET" && event.queryStringParameters?.uploadUrl === "1") {
      const eid     = event.queryStringParameters?.expenseId ?? randomUUID();
      const s3Key   = `receipts/${userId}/${eid}.jpg`;
      const command = new PutObjectCommand({
        Bucket:      BUCKET,
        Key:         s3Key,
        ContentType: "image/jpeg",
      });
      const url = await getSignedUrl(s3, command, { expiresIn: 300 }); // 5 min
      return ok({ uploadUrl: url, s3Key });
    }

    // ── GET /expenses ─────────────────────────────────────────────────────────
    if (method === "GET") {
      if (filterVehicleId) {
        const result = await ddb.send(
          new QueryCommand({
            TableName:                 TABLE,
            IndexName:                 GSI,
            KeyConditionExpression:    "vehicleId = :vid",
            FilterExpression:          "userId = :uid",
            ExpressionAttributeValues: { ":vid": filterVehicleId, ":uid": userId },
            ScanIndexForward:          false,
          })
        );
        return ok(result.Items ?? []);
      }

      const result = await ddb.send(
        new QueryCommand({
          TableName:                 TABLE,
          KeyConditionExpression:    "userId = :uid",
          ExpressionAttributeValues: { ":uid": userId },
          ScanIndexForward:          false,
        })
      );
      return ok(result.Items ?? []);
    }

    // ── POST /expenses ────────────────────────────────────────────────────────
    if (method === "POST") {
      const body = JSON.parse(event.body ?? "{}") as ExpenseBody;

      const item: Record<string, unknown> = {
        userId,
        expenseId:    randomUUID(),
        tripId:       body.tripId      || undefined,
        category:     body.category,
        amount:       body.amount,
        expenseDate:  body.expenseDate ?? new Date().toISOString().split("T")[0],
        merchant:     body.merchant    ?? "",
        notes:        body.notes       ?? "",
        receiptS3Key: body.receiptS3Key || undefined,
        ocrStatus:    body.receiptS3Key ? "pending" : "none",
        ocrData:      undefined,
        createdAt:    new Date().toISOString(),
        updatedAt:    new Date().toISOString(),
      };

      if (body.vehicleId) {
        item.vehicleId = body.vehicleId;
      }

      await ddb.send(new PutCommand({ TableName: TABLE, Item: item }));
      return ok(item, 201);
    }

    // ── PUT /expenses/{expenseId} ─────────────────────────────────────────────
    if (method === "PUT" && expenseId) {
      const body = JSON.parse(event.body ?? "{}") as Partial<ExpenseBody>;

      let updateParts = [
        "category = :cat",
        "amount = :amt",
        "expenseDate = :date",
        "merchant = :merchant",
        "notes = :notes",
        "updatedAt = :ts",
      ];

      const exprValues: Record<string, unknown> = {
        ":cat":      body.category,
        ":amt":      body.amount,
        ":date":     body.expenseDate,
        ":merchant": body.merchant ?? "",
        ":notes":    body.notes    ?? "",
        ":ts":       new Date().toISOString(),
      };

      if (body.vehicleId) {
        updateParts.push("vehicleId = :vid");
        exprValues[":vid"] = body.vehicleId;
      }

      // Only update receiptS3Key + ocrStatus when a NEW receipt is being attached.
      // Never overwrite ocrStatus if the key isn't changing — the OCR Lambda may
      // have already set it to "complete" or "failed".
      if (body.receiptS3Key) {
        updateParts.push("receiptS3Key = :s3key");
        updateParts.push("ocrStatus = :ocrStatus");
        exprValues[":s3key"]    = body.receiptS3Key;
        exprValues[":ocrStatus"] = "pending";
      }

      const result = await ddb.send(
        new UpdateCommand({
          TableName:        TABLE,
          Key:              { userId, expenseId },
          ConditionExpression: "attribute_exists(expenseId)",
          UpdateExpression: "SET " + updateParts.join(", "),
          ExpressionAttributeValues: exprValues,
          ReturnValues: "ALL_NEW",
        })
      );
      return ok(result.Attributes);
    }

    // ── DELETE /expenses/{expenseId} ──────────────────────────────────────────
    if (method === "DELETE" && expenseId) {
      await ddb.send(
        new DeleteCommand({
          TableName: TABLE,
          Key:       { userId, expenseId },
          ConditionExpression: "attribute_exists(expenseId)",
        })
      );
      return ok({ deleted: expenseId });
    }

    return errResponse(405, "Method not allowed");
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes("ConditionalCheckFailed")) return errResponse(404, "Expense not found");
    console.error(e);
    return errResponse(500, msg);
  }
};

const headers = {
  "Content-Type":                "application/json",
  "Access-Control-Allow-Origin": "*",
};

const ok = (body: unknown, status = 200): APIGatewayProxyResult => ({
  statusCode: status, headers, body: JSON.stringify(body),
});

const errResponse = (status: number, message: string): APIGatewayProxyResult => ({
  statusCode: status, headers, body: JSON.stringify({ error: message }),
});

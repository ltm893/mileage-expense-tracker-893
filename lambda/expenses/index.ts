import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  QueryCommand,
  PutCommand,
  UpdateCommand,
  DeleteCommand,
} from "@aws-sdk/lib-dynamodb";
import { randomUUID } from "crypto";
import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";

const ddb   = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE = process.env.EXPENSES_TABLE!;
const GSI   = "vehicleId-expenseDate-index";

// Expense categories
type Category = "fuel" | "maintenance" | "insurance" | "parking" | "tolls" | "other";

interface ExpenseBody {
  vehicleId:    string;
  tripId?:      string;       // optional — links expense to a specific trip
  category:     Category;
  amount:       number;       // in dollars
  expenseDate:  string;       // ISO date "2026-04-28"
  merchant?:    string;
  notes?:       string;
  receiptS3Key?: string;      // set by mobile app after S3 upload e.g. "receipts/{userId}/{expenseId}.jpg"
}

export const handler = async (
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
  const userId    = event.requestContext.authorizer?.claims?.sub as string;
  const method    = event.httpMethod;
  const expenseId = event.pathParameters?.expenseId;

  const filterVehicleId = event.queryStringParameters?.vehicleId;

  try {
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

    // ── POST /expenses — create expense record ────────────────────────────────
    // The mobile app:
    //   1. POSTs here → gets back expenseId
    //   2. Uploads receipt to S3 at receipts/{userId}/{expenseId}.jpg
    //   3. PUTs here with receiptS3Key to link the receipt
    // OR skips steps 2-3 if there's no receipt.
    // The OCR Lambda fires automatically when S3 upload completes.
    if (method === "POST") {
      const body = JSON.parse(event.body ?? "{}") as ExpenseBody;
      const item = {
        userId,
        expenseId:    randomUUID(),
        vehicleId:    body.vehicleId,
        tripId:       body.tripId    ?? null,
        category:     body.category,
        amount:       body.amount,
        expenseDate:  body.expenseDate ?? new Date().toISOString().split("T")[0],
        merchant:     body.merchant  ?? "",
        notes:        body.notes     ?? "",
        receiptS3Key: body.receiptS3Key ?? null,
        ocrStatus:    body.receiptS3Key ? "pending" : "none",
        ocrData:      null,  // filled in by OCR Lambda after Textract runs
        createdAt:    new Date().toISOString(),
        updatedAt:    new Date().toISOString(),
      };
      await ddb.send(new PutCommand({ TableName: TABLE, Item: item }));
      return ok(item, 201);
    }

    // ── PUT /expenses/{expenseId} — update expense (also used to attach receipt) ──
    if (method === "PUT" && expenseId) {
      const body = JSON.parse(event.body ?? "{}") as Partial<ExpenseBody>;
      const result = await ddb.send(
        new UpdateCommand({
          TableName:        TABLE,
          Key:              { userId, expenseId },
          ConditionExpression: "attribute_exists(expenseId)",
          UpdateExpression: [
            "SET vehicleId = :vid",
            "tripId = :tid",
            "category = :cat",
            "amount = :amt",
            "expenseDate = :date",
            "merchant = :merchant",
            "notes = :notes",
            "receiptS3Key = :s3key",
            "ocrStatus = :ocrStatus",
            "updatedAt = :ts",
          ].join(", "),
          ExpressionAttributeValues: {
            ":vid":       body.vehicleId,
            ":tid":       body.tripId      ?? null,
            ":cat":       body.category,
            ":amt":       body.amount,
            ":date":      body.expenseDate,
            ":merchant":  body.merchant    ?? "",
            ":notes":     body.notes       ?? "",
            ":s3key":     body.receiptS3Key ?? null,
            // If a receipt key was just attached, mark OCR as pending
            ":ocrStatus": body.receiptS3Key ? "pending" : "none",
            ":ts":        new Date().toISOString(),
          },
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
  statusCode: status,
  headers,
  body: JSON.stringify(body),
});

const errResponse = (status: number, message: string): APIGatewayProxyResult => ({
  statusCode: status,
  headers,
  body: JSON.stringify({ error: message }),
});

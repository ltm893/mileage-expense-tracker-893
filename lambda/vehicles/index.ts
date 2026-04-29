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
const TABLE = process.env.VEHICLES_TABLE!;

// ── Vehicle shape ──────────────────────────────────────────────────────────
interface VehicleBody {
  name:            string;
  make:            string;
  model:           string;
  year:            number;
  currentOdometer: number;
}

export const handler = async (
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
  // userId comes from the validated Cognito JWT — API Gateway injects it
  const userId    = event.requestContext.authorizer?.claims?.sub as string;
  const method    = event.httpMethod;
  const vehicleId = event.pathParameters?.vehicleId;

  try {
    // ── GET /vehicles — list all vehicles for this user ──────────────────────
    if (method === "GET") {
      const result = await ddb.send(
        new QueryCommand({
          TableName:                 TABLE,
          KeyConditionExpression:    "userId = :uid",
          ExpressionAttributeValues: { ":uid": userId },
        })
      );
      return ok(result.Items ?? []);
    }

    // ── POST /vehicles — create a new vehicle ────────────────────────────────
    if (method === "POST") {
      const body = JSON.parse(event.body ?? "{}") as VehicleBody;
      const item = {
        userId,
        vehicleId:       randomUUID(),
        name:            body.name,
        make:            body.make,
        model:           body.model,
        year:            body.year,
        currentOdometer: body.currentOdometer ?? 0,
        createdAt:       new Date().toISOString(),
        updatedAt:       new Date().toISOString(),
      };
      await ddb.send(new PutCommand({ TableName: TABLE, Item: item }));
      return ok(item, 201);
    }

    // ── PUT /vehicles/{vehicleId} — update a vehicle ─────────────────────────
    if (method === "PUT" && vehicleId) {
      const body   = JSON.parse(event.body ?? "{}") as Partial<VehicleBody>;
      const result = await ddb.send(
        new UpdateCommand({
          TableName:        TABLE,
          Key:              { userId, vehicleId },
          UpdateExpression: "SET #n = :n, make = :make, model = :model, #yr = :yr, currentOdometer = :odo, updatedAt = :ts",
          ExpressionAttributeNames:  { "#n": "name", "#yr": "year" },
          ExpressionAttributeValues: {
            ":n":    body.name,
            ":make": body.make,
            ":model":body.model,
            ":yr":   body.year,
            ":odo":  body.currentOdometer,
            ":ts":   new Date().toISOString(),
          },
          ReturnValues:     "ALL_NEW",
          ConditionExpression: "attribute_exists(vehicleId)", // 404 if not found
        })
      );
      return ok(result.Attributes);
    }

    // ── DELETE /vehicles/{vehicleId} — remove a vehicle ───────────────────────
    if (method === "DELETE" && vehicleId) {
      await ddb.send(
        new DeleteCommand({
          TableName: TABLE,
          Key:       { userId, vehicleId },
          ConditionExpression: "attribute_exists(vehicleId)",
        })
      );
      return ok({ deleted: vehicleId });
    }

    return errResponse(405, "Method not allowed");
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    // DynamoDB throws ConditionalCheckFailedException when ConditionExpression fails
    if (msg.includes("ConditionalCheckFailed")) return errResponse(404, "Vehicle not found");
    console.error(e);
    return errResponse(500, msg);
  }
};

// ── Helpers ────────────────────────────────────────────────────────────────
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

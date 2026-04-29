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
const TABLE = process.env.TRIPS_TABLE!;
const GSI   = "vehicleId-tripDate-index";

interface TripBody {
  vehicleId:        string;
  startOdometer:    number;
  endOdometer:      number;
  odometerDistance: number;   // endOdometer - startOdometer (calculated by app)
  gpsDistance:      number;   // CoreLocation measured distance
  tripDate:         string;
  purpose?:         string;
  notes?:           string;
}

export const handler = async (
  event: APIGatewayProxyEvent
): Promise<APIGatewayProxyResult> => {
  const userId  = event.requestContext.authorizer?.claims?.sub as string;
  const method  = event.httpMethod;
  const tripId  = event.pathParameters?.tripId;
  const filterVehicleId = event.queryStringParameters?.vehicleId;

  try {
    // ── GET /trips ────────────────────────────────────────────────────────────
    if (method === "GET") {
      if (filterVehicleId) {
        const result = await ddb.send(
          new QueryCommand({
            TableName:                 TABLE,
            IndexName:                 GSI,
            KeyConditionExpression:    "vehicleId = :vid",
            FilterExpression:          "userId = :uid",
            ExpressionAttributeValues: { ":vid": filterVehicleId, ":uid": userId },
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

    // ── POST /trips ───────────────────────────────────────────────────────────
    if (method === "POST") {
      const body = JSON.parse(event.body ?? "{}") as TripBody;

      // Derive the display distance: prefer odometer if both provided
      const odometerDistance = body.odometerDistance ?? 0;
      const gpsDistance      = body.gpsDistance      ?? 0;

      const item = {
        userId,
        tripId:           randomUUID(),
        vehicleId:        body.vehicleId,
        startOdometer:    body.startOdometer    ?? 0,
        endOdometer:      body.endOdometer      ?? 0,
        odometerDistance,
        gpsDistance,
        tripDate:         body.tripDate ?? new Date().toISOString().split("T")[0],
        purpose:          body.purpose ?? "",
        notes:            body.notes   ?? "",
        createdAt:        new Date().toISOString(),
        updatedAt:        new Date().toISOString(),
      };
      await ddb.send(new PutCommand({ TableName: TABLE, Item: item }));
      return ok(item, 201);
    }

    // ── PUT /trips/{tripId} ───────────────────────────────────────────────────
    if (method === "PUT" && tripId) {
      const body = JSON.parse(event.body ?? "{}") as Partial<TripBody>;
      const result = await ddb.send(
        new UpdateCommand({
          TableName:        TABLE,
          Key:              { userId, tripId },
          ConditionExpression: "attribute_exists(tripId)",
          UpdateExpression: [
            "SET vehicleId = :vid",
            "startOdometer = :start",
            "endOdometer = :end",
            "odometerDistance = :odoDistance",
            "gpsDistance = :gpsDistance",
            "tripDate = :date",
            "purpose = :purpose",
            "notes = :notes",
            "updatedAt = :ts",
          ].join(", "),
          ExpressionAttributeValues: {
            ":vid":         body.vehicleId,
            ":start":       body.startOdometer    ?? 0,
            ":end":         body.endOdometer       ?? 0,
            ":odoDistance": body.odometerDistance  ?? 0,
            ":gpsDistance": body.gpsDistance       ?? 0,
            ":date":        body.tripDate,
            ":purpose":     body.purpose ?? "",
            ":notes":       body.notes   ?? "",
            ":ts":          new Date().toISOString(),
          },
          ReturnValues: "ALL_NEW",
        })
      );
      return ok(result.Attributes);
    }

    // ── DELETE /trips/{tripId} ────────────────────────────────────────────────
    if (method === "DELETE" && tripId) {
      await ddb.send(
        new DeleteCommand({
          TableName: TABLE,
          Key:       { userId, tripId },
          ConditionExpression: "attribute_exists(tripId)",
        })
      );
      return ok({ deleted: tripId });
    }

    return errResponse(405, "Method not allowed");
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes("ConditionalCheckFailed")) return errResponse(404, "Trip not found");
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

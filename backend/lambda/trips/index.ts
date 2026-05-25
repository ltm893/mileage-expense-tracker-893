import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, QueryCommand, PutCommand, UpdateCommand, DeleteCommand } from "@aws-sdk/lib-dynamodb";
import { randomUUID } from "crypto";
import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";

const ddb   = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE = process.env.TRIPS_TABLE!;
const GSI   = "vehicleId-tripDate-index";

interface TripBody {
  vehicleId: string; startOdometer: number; endOdometer: number;
  odometerDistance: number; gpsDistance: number;
  tripDate: string; purpose?: string; notes?: string;
}

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  const userId = event.requestContext.authorizer?.claims?.sub as string;
  const method = event.httpMethod;
  const tripId = event.pathParameters?.tripId;
  const filterVehicleId = event.queryStringParameters?.vehicleId;

  try {
    if (method === "GET") {
      if (filterVehicleId) {
        const result = await ddb.send(new QueryCommand({ TableName: TABLE, IndexName: GSI, KeyConditionExpression: "vehicleId = :vid", FilterExpression: "userId = :uid", ExpressionAttributeValues: { ":vid": filterVehicleId, ":uid": userId } }));
        return ok(result.Items ?? []);
      }
      const result = await ddb.send(new QueryCommand({ TableName: TABLE, KeyConditionExpression: "userId = :uid", ExpressionAttributeValues: { ":uid": userId }, ScanIndexForward: false }));
      return ok(result.Items ?? []);
    }
    if (method === "POST") {
      const body = JSON.parse(event.body ?? "{}") as TripBody;
      const item = { userId, tripId: randomUUID(), vehicleId: body.vehicleId, startOdometer: body.startOdometer ?? 0, endOdometer: body.endOdometer ?? 0, odometerDistance: body.odometerDistance ?? 0, gpsDistance: body.gpsDistance ?? 0, tripDate: body.tripDate ?? new Date().toISOString().split("T")[0], purpose: body.purpose ?? "", notes: body.notes ?? "", createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() };
      await ddb.send(new PutCommand({ TableName: TABLE, Item: item }));
      return ok(item, 201);
    }
    if (method === "PUT" && tripId) {
      const body = JSON.parse(event.body ?? "{}") as Partial<TripBody>;
      const result = await ddb.send(new UpdateCommand({ TableName: TABLE, Key: { userId, tripId }, ConditionExpression: "attribute_exists(tripId)", UpdateExpression: "SET vehicleId = :vid, startOdometer = :start, endOdometer = :end, odometerDistance = :odo, gpsDistance = :gps, tripDate = :date, purpose = :purpose, notes = :notes, updatedAt = :ts", ExpressionAttributeValues: { ":vid": body.vehicleId, ":start": body.startOdometer ?? 0, ":end": body.endOdometer ?? 0, ":odo": body.odometerDistance ?? 0, ":gps": body.gpsDistance ?? 0, ":date": body.tripDate, ":purpose": body.purpose ?? "", ":notes": body.notes ?? "", ":ts": new Date().toISOString() }, ReturnValues: "ALL_NEW" }));
      return ok(result.Attributes);
    }
    if (method === "DELETE" && tripId) {
      await ddb.send(new DeleteCommand({ TableName: TABLE, Key: { userId, tripId }, ConditionExpression: "attribute_exists(tripId)" }));
      return ok({ deleted: tripId });
    }
    return errResponse(405, "Method not allowed");
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes("ConditionalCheckFailed")) return errResponse(404, "Trip not found");
    console.error(e); return errResponse(500, msg);
  }
};

const headers = { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" };
const ok = (body: unknown, status = 200): APIGatewayProxyResult => ({ statusCode: status, headers, body: JSON.stringify(body) });
const errResponse = (status: number, message: string): APIGatewayProxyResult => ({ statusCode: status, headers, body: JSON.stringify({ error: message }) });

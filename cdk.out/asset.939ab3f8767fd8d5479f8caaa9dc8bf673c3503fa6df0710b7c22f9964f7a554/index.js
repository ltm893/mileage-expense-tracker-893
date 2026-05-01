"use strict";
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// lambda/trips/index.ts
var trips_exports = {};
__export(trips_exports, {
  handler: () => handler
});
module.exports = __toCommonJS(trips_exports);
var import_client_dynamodb = require("@aws-sdk/client-dynamodb");
var import_lib_dynamodb = require("@aws-sdk/lib-dynamodb");
var import_crypto = require("crypto");
var ddb = import_lib_dynamodb.DynamoDBDocumentClient.from(new import_client_dynamodb.DynamoDBClient({}));
var TABLE = process.env.TRIPS_TABLE;
var GSI = "vehicleId-tripDate-index";
var handler = async (event) => {
  const userId = event.requestContext.authorizer?.claims?.sub;
  const method = event.httpMethod;
  const tripId = event.pathParameters?.tripId;
  const filterVehicleId = event.queryStringParameters?.vehicleId;
  try {
    if (method === "GET") {
      if (filterVehicleId) {
        const result2 = await ddb.send(
          new import_lib_dynamodb.QueryCommand({
            TableName: TABLE,
            IndexName: GSI,
            KeyConditionExpression: "vehicleId = :vid",
            FilterExpression: "userId = :uid",
            ExpressionAttributeValues: { ":vid": filterVehicleId, ":uid": userId }
          })
        );
        return ok(result2.Items ?? []);
      }
      const result = await ddb.send(
        new import_lib_dynamodb.QueryCommand({
          TableName: TABLE,
          KeyConditionExpression: "userId = :uid",
          ExpressionAttributeValues: { ":uid": userId },
          ScanIndexForward: false
          // newest first
        })
      );
      return ok(result.Items ?? []);
    }
    if (method === "POST") {
      const body = JSON.parse(event.body ?? "{}");
      const distance = body.endOdometer - body.startOdometer;
      const item = {
        userId,
        tripId: (0, import_crypto.randomUUID)(),
        vehicleId: body.vehicleId,
        startOdometer: body.startOdometer,
        endOdometer: body.endOdometer,
        distance: distance > 0 ? distance : 0,
        tripDate: body.tripDate ?? (/* @__PURE__ */ new Date()).toISOString().split("T")[0],
        purpose: body.purpose ?? "",
        notes: body.notes ?? "",
        createdAt: (/* @__PURE__ */ new Date()).toISOString(),
        updatedAt: (/* @__PURE__ */ new Date()).toISOString()
      };
      await ddb.send(new import_lib_dynamodb.PutCommand({ TableName: TABLE, Item: item }));
      return ok(item, 201);
    }
    if (method === "PUT" && tripId) {
      const body = JSON.parse(event.body ?? "{}");
      const distance = body.endOdometer && body.startOdometer ? body.endOdometer - body.startOdometer : void 0;
      const result = await ddb.send(
        new import_lib_dynamodb.UpdateCommand({
          TableName: TABLE,
          Key: { userId, tripId },
          ConditionExpression: "attribute_exists(tripId)",
          UpdateExpression: [
            "SET vehicleId = :vid",
            "startOdometer = :start",
            "endOdometer = :end",
            "distance = :dist",
            "tripDate = :date",
            "purpose = :purpose",
            "notes = :notes",
            "updatedAt = :ts"
          ].join(", "),
          ExpressionAttributeValues: {
            ":vid": body.vehicleId,
            ":start": body.startOdometer,
            ":end": body.endOdometer,
            ":dist": distance ?? 0,
            ":date": body.tripDate,
            ":purpose": body.purpose ?? "",
            ":notes": body.notes ?? "",
            ":ts": (/* @__PURE__ */ new Date()).toISOString()
          },
          ReturnValues: "ALL_NEW"
        })
      );
      return ok(result.Attributes);
    }
    if (method === "DELETE" && tripId) {
      await ddb.send(
        new import_lib_dynamodb.DeleteCommand({
          TableName: TABLE,
          Key: { userId, tripId },
          ConditionExpression: "attribute_exists(tripId)"
        })
      );
      return ok({ deleted: tripId });
    }
    return errResponse(405, "Method not allowed");
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes("ConditionalCheckFailed"))
      return errResponse(404, "Trip not found");
    console.error(e);
    return errResponse(500, msg);
  }
};
var headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*"
};
var ok = (body, status = 200) => ({
  statusCode: status,
  headers,
  body: JSON.stringify(body)
});
var errResponse = (status, message) => ({
  statusCode: status,
  headers,
  body: JSON.stringify({ error: message })
});
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  handler
});

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

// lambda/expenses/index.ts
var expenses_exports = {};
__export(expenses_exports, {
  handler: () => handler
});
module.exports = __toCommonJS(expenses_exports);
var import_client_dynamodb = require("@aws-sdk/client-dynamodb");
var import_lib_dynamodb = require("@aws-sdk/lib-dynamodb");
var import_client_s3 = require("@aws-sdk/client-s3");
var import_s3_request_presigner = require("@aws-sdk/s3-request-presigner");
var import_crypto = require("crypto");
var ddb = import_lib_dynamodb.DynamoDBDocumentClient.from(new import_client_dynamodb.DynamoDBClient({}));
var s3 = new import_client_s3.S3Client({ region: process.env.AWS_ACCOUNT_REGION ?? "us-east-1" });
var TABLE = process.env.EXPENSES_TABLE;
var BUCKET = process.env.RECEIPTS_BUCKET;
var GSI = "vehicleId-expenseDate-index";
var handler = async (event) => {
  const userId = event.requestContext.authorizer?.claims?.sub;
  const method = event.httpMethod;
  const expenseId = event.pathParameters?.expenseId;
  const filterVehicleId = event.queryStringParameters?.vehicleId;
  try {
    if (method === "GET" && event.queryStringParameters?.uploadUrl === "1") {
      const eid = event.queryStringParameters?.expenseId ?? (0, import_crypto.randomUUID)();
      const s3Key = `receipts/${userId}/${eid}.jpg`;
      const command = new import_client_s3.PutObjectCommand({
        Bucket: BUCKET,
        Key: s3Key,
        ContentType: "image/jpeg"
      });
      const url = await (0, import_s3_request_presigner.getSignedUrl)(s3, command, { expiresIn: 300 });
      return ok({ uploadUrl: url, s3Key });
    }
    if (method === "GET") {
      if (filterVehicleId) {
        const result2 = await ddb.send(
          new import_lib_dynamodb.QueryCommand({
            TableName: TABLE,
            IndexName: GSI,
            KeyConditionExpression: "vehicleId = :vid",
            FilterExpression: "userId = :uid",
            ExpressionAttributeValues: { ":vid": filterVehicleId, ":uid": userId },
            ScanIndexForward: false
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
        })
      );
      return ok(result.Items ?? []);
    }
    if (method === "POST") {
      const body = JSON.parse(event.body ?? "{}");
      const item = {
        userId,
        expenseId: (0, import_crypto.randomUUID)(),
        tripId: body.tripId || void 0,
        category: body.category,
        amount: body.amount,
        expenseDate: body.expenseDate ?? (/* @__PURE__ */ new Date()).toISOString().split("T")[0],
        merchant: body.merchant ?? "",
        notes: body.notes ?? "",
        receiptS3Key: body.receiptS3Key || void 0,
        ocrStatus: body.receiptS3Key ? "pending" : "none",
        ocrData: void 0,
        createdAt: (/* @__PURE__ */ new Date()).toISOString(),
        updatedAt: (/* @__PURE__ */ new Date()).toISOString()
      };
      if (body.vehicleId) {
        item.vehicleId = body.vehicleId;
      }
      await ddb.send(new import_lib_dynamodb.PutCommand({ TableName: TABLE, Item: item }));
      return ok(item, 201);
    }
    if (method === "PUT" && expenseId) {
      const body = JSON.parse(event.body ?? "{}");
      let updateParts = [
        "category = :cat",
        "amount = :amt",
        "expenseDate = :date",
        "merchant = :merchant",
        "notes = :notes",
        "ocrStatus = :ocrStatus",
        "updatedAt = :ts"
      ];
      const exprValues = {
        ":cat": body.category,
        ":amt": body.amount,
        ":date": body.expenseDate,
        ":merchant": body.merchant ?? "",
        ":notes": body.notes ?? "",
        ":ocrStatus": body.receiptS3Key ? "pending" : "none",
        ":ts": (/* @__PURE__ */ new Date()).toISOString()
      };
      if (body.vehicleId) {
        updateParts.push("vehicleId = :vid");
        exprValues[":vid"] = body.vehicleId;
      }
      if (body.receiptS3Key) {
        updateParts.push("receiptS3Key = :s3key");
        exprValues[":s3key"] = body.receiptS3Key;
      }
      const result = await ddb.send(
        new import_lib_dynamodb.UpdateCommand({
          TableName: TABLE,
          Key: { userId, expenseId },
          ConditionExpression: "attribute_exists(expenseId)",
          UpdateExpression: "SET " + updateParts.join(", "),
          ExpressionAttributeValues: exprValues,
          ReturnValues: "ALL_NEW"
        })
      );
      return ok(result.Attributes);
    }
    if (method === "DELETE" && expenseId) {
      await ddb.send(
        new import_lib_dynamodb.DeleteCommand({
          TableName: TABLE,
          Key: { userId, expenseId },
          ConditionExpression: "attribute_exists(expenseId)"
        })
      );
      return ok({ deleted: expenseId });
    }
    return errResponse(405, "Method not allowed");
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (msg.includes("ConditionalCheckFailed"))
      return errResponse(404, "Expense not found");
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

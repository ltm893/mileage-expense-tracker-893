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

// lambda/ocr/index.ts
var ocr_exports = {};
__export(ocr_exports, {
  handler: () => handler
});
module.exports = __toCommonJS(ocr_exports);
var import_client_textract = require("@aws-sdk/client-textract");
var import_client_dynamodb = require("@aws-sdk/client-dynamodb");
var import_lib_dynamodb = require("@aws-sdk/lib-dynamodb");
var textract = new import_client_textract.TextractClient({});
var ddb = import_lib_dynamodb.DynamoDBDocumentClient.from(new import_client_dynamodb.DynamoDBClient({}));
var TABLE = process.env.EXPENSES_TABLE;
var BUCKET = process.env.RECEIPTS_BUCKET;
var handler = async (event) => {
  for (const record of event.Records) {
    const bucketName = record.s3.bucket.name;
    const objectKey = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));
    const parts = objectKey.split("/");
    if (parts.length !== 3 || parts[0] !== "receipts") {
      console.warn(`Unexpected S3 key format, skipping: ${objectKey}`);
      continue;
    }
    const userId = parts[1];
    const expenseId = parts[2].replace(/\.[^/.]+$/, "");
    console.log(`Running Textract on ${objectKey} for expense ${expenseId}`);
    try {
      const textractResult = await textract.send(
        new import_client_textract.AnalyzeExpenseCommand({
          Document: {
            S3Object: { Bucket: bucketName, Name: objectKey }
          }
        })
      );
      const ocrData = {
        total: null,
        date: null,
        merchant: null,
        lineItems: [],
        rawFields: {}
      };
      for (const doc of textractResult.ExpenseDocuments ?? []) {
        for (const field of doc.SummaryFields ?? []) {
          const type = field.Type?.Text ?? "";
          const value = field.ValueDetection?.Text ?? "";
          ocrData.rawFields[type] = value;
          if (type === "TOTAL")
            ocrData.total = value;
          if (type === "INVOICE_RECEIPT_DATE")
            ocrData.date = value;
          if (type === "VENDOR_NAME")
            ocrData.merchant = value;
        }
        for (const group of doc.LineItemGroups ?? []) {
          for (const lineItem of group.LineItems ?? []) {
            const itemFields = {};
            for (const field of lineItem.LineItemExpenseFields ?? []) {
              itemFields[field.Type?.Text ?? ""] = field.ValueDetection?.Text ?? "";
            }
            if (itemFields["ITEM"] || itemFields["PRODUCT_CODE"]) {
              ocrData.lineItems.push({
                description: itemFields["ITEM"] ?? itemFields["PRODUCT_CODE"] ?? "",
                amount: itemFields["PRICE"] ?? itemFields["UNIT_PRICE"] ?? ""
              });
            }
          }
        }
      }
      await ddb.send(
        new import_lib_dynamodb.UpdateCommand({
          TableName: TABLE,
          Key: { userId, expenseId },
          UpdateExpression: "SET ocrData = :data, ocrStatus = :status, updatedAt = :ts",
          ExpressionAttributeValues: {
            ":data": ocrData,
            ":status": "complete",
            ":ts": (/* @__PURE__ */ new Date()).toISOString()
          }
        })
      );
      console.log(`OCR complete for expense ${expenseId}:`, JSON.stringify(ocrData));
    } catch (err) {
      console.error(`Textract failed for ${objectKey}:`, err);
      await ddb.send(
        new import_lib_dynamodb.UpdateCommand({
          TableName: TABLE,
          Key: { userId, expenseId },
          UpdateExpression: "SET ocrStatus = :status, updatedAt = :ts",
          ExpressionAttributeValues: {
            ":status": "failed",
            ":ts": (/* @__PURE__ */ new Date()).toISOString()
          }
        })
      );
    }
  }
};
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  handler
});

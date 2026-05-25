import { TextractClient, AnalyzeExpenseCommand } from "@aws-sdk/client-textract";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import { S3Event } from "aws-lambda";

const textract = new TextractClient({});
const ddb      = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE    = process.env.EXPENSES_TABLE!;

interface OcrData {
  total: string|null; date: string|null; merchant: string|null;
  lineItems: { description: string; amount: string }[];
  rawFields: Record<string, string>;
}

export const handler = async (event: S3Event): Promise<void> => {
  for (const record of event.Records) {
    const bucketName = record.s3.bucket.name;
    const objectKey  = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));
    const parts      = objectKey.split("/");

    if (parts.length !== 3 || parts[0] !== "receipts") {
      console.warn(`Unexpected S3 key format, skipping: ${objectKey}`);
      continue;
    }

    const userId    = parts[1];
    const expenseId = parts[2].replace(/\.[^/.]+$/, "");

    try {
      const textractResult = await textract.send(new AnalyzeExpenseCommand({
        Document: { S3Object: { Bucket: bucketName, Name: objectKey } },
      }));
      const ocrData: OcrData = { total: null, date: null, merchant: null, lineItems: [], rawFields: {} };

      for (const doc of textractResult.ExpenseDocuments ?? []) {
        for (const field of doc.SummaryFields ?? []) {
          const type  = field.Type?.Text ?? "";
          const value = field.ValueDetection?.Text ?? "";
          ocrData.rawFields[type] = value;
          if (type === "TOTAL")                ocrData.total    = value;
          if (type === "INVOICE_RECEIPT_DATE")  ocrData.date     = value;
          if (type === "VENDOR_NAME")           ocrData.merchant = value;
        }
        for (const group of doc.LineItemGroups ?? []) {
          for (const lineItem of group.LineItems ?? []) {
            const itemFields: Record<string, string> = {};
            for (const field of lineItem.LineItemExpenseFields ?? []) {
              itemFields[field.Type?.Text ?? ""] = field.ValueDetection?.Text ?? "";
            }
            if (itemFields["ITEM"] || itemFields["PRODUCT_CODE"]) {
              ocrData.lineItems.push({
                description: itemFields["ITEM"] ?? itemFields["PRODUCT_CODE"] ?? "",
                amount:      itemFields["PRICE"] ?? itemFields["UNIT_PRICE"] ?? "",
              });
            }
          }
        }
      }

      await ddb.send(new UpdateCommand({
        TableName: TABLE, Key: { userId, expenseId },
        UpdateExpression: "SET ocrData = :data, ocrStatus = :status, updatedAt = :ts",
        ExpressionAttributeValues: { ":data": ocrData, ":status": "complete", ":ts": new Date().toISOString() },
      }));
    } catch (err) {
      console.error(`Textract failed for ${objectKey}:`, err);
      await ddb.send(new UpdateCommand({
        TableName: TABLE, Key: { userId, expenseId },
        UpdateExpression: "SET ocrStatus = :status, updatedAt = :ts",
        ExpressionAttributeValues: { ":status": "failed", ":ts": new Date().toISOString() },
      }));
    }
  }
};

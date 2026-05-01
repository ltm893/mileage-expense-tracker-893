#!/usr/bin/env node
// backend/bin/app.ts
import "source-map-support/register";
import * as cdk from "aws-cdk-lib";
import * as fs from "fs";
import * as path from "path";
import { MileageExpenseStack } from "../lib/met-stack";
import { BaseOutputs } from "../lib/base-outputs";

const baseOutputsPath = process.env.BASE_OUTPUTS_PATH;
if (!baseOutputsPath) {
  console.error("\n  ❌ BASE_OUTPUTS_PATH env var is not set.");
  console.error("     Example:");
  console.error("       BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json npx cdk deploy\n");
  process.exit(1);
}

const resolvedPath = path.resolve(baseOutputsPath);
if (!fs.existsSync(resolvedPath)) {
  console.error(`\n  ❌ base_outputs.json not found at: ${resolvedPath}`);
  console.error("     Deploy the base stack first.\n");
  process.exit(1);
}

const base: BaseOutputs = JSON.parse(fs.readFileSync(resolvedPath, "utf-8"));

// Derive id prefix from public bucket name: "test893-public" → "test893"
const idPrefix = base.storage.public_bucket.replace(/-public$/, "");

const app = new cdk.App();

new MileageExpenseStack(app, `MileageExpenseStack-${idPrefix}`, {
  base,
  idPrefix,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region:  base.aws_region,
  },
});

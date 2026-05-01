#!/usr/bin/env node
// backend/bin/app.ts
// Entry point for the Mileage Expense Tracker CDK app.
// Reads base_outputs.json via BASE_OUTPUTS_PATH env var.
// Example:
//   BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json npx cdk deploy

import "source-map-support/register";
import * as cdk from "aws-cdk-lib";
import * as fs from "fs";
import * as path from "path";
import { MileageExpenseStack } from "../lib/met-stack";
import { BaseOutputs } from "../lib/base-outputs";

const baseOutputsPath = process.env.BASE_OUTPUTS_PATH;
if (!baseOutputsPath) {
  console.error("\n  ❌ BASE_OUTPUTS_PATH env var is not set.");
  console.error("     Point it to base_outputs.json from your cognito-s3-stack-893 deployment.");
  console.error("     Example:");
  console.error("       BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json npx cdk deploy\n");
  process.exit(1);
}

const resolvedPath = path.resolve(baseOutputsPath);
if (!fs.existsSync(resolvedPath)) {
  console.error(`\n  ❌ base_outputs.json not found at: ${resolvedPath}`);
  console.error("     Deploy the base stack first: cd cognito-s3-stack-893/base && ./scripts/deploy.sh\n");
  process.exit(1);
}

const base: BaseOutputs = JSON.parse(fs.readFileSync(resolvedPath, "utf-8"));

const app = new cdk.App();

new MileageExpenseStack(app, "MileageExpenseStack", {
  base,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region:  base.aws_region,
  },
});

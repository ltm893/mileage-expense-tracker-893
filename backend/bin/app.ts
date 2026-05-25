#!/usr/bin/env node
// backend/bin/app.ts
import "source-map-support/register";
import * as cdk from "aws-cdk-lib";
import * as fs from "fs";
import * as path from "path";
import { MileageExpenseStack } from "../lib/met-stack";
import { BaseOutputs } from "../lib/base-outputs";

// ID_PREFIX, USER_POOL_ID, AWS_REGION can be supplied directly as env var overrides
// (Option B — no base_outputs.json needed). Fall back to base_outputs.json if any are missing.
const idPrefixOverride  = process.env.ID_PREFIX    || "";
const userPoolOverride  = process.env.USER_POOL_ID || "";
const regionOverride    = process.env.AWS_REGION   || "";

let base: BaseOutputs;
let idPrefix: string;

if (idPrefixOverride && userPoolOverride && regionOverride) {
  // All three overrides provided — synthesise a BaseOutputs without reading a file
  base = {
    version:    "1",
    aws_region: regionOverride,
    auth: {
      user_pool_id:        userPoolOverride,
      user_pool_client_id: "",
      user_pool_provider:  `cognito-idp.${regionOverride}.amazonaws.com/${userPoolOverride}`,
      identity_pool_id:    "",
      auth_role_arn:       "",
    },
    storage: {
      public_bucket:  `${idPrefixOverride}-public`,
      private_bucket: `${idPrefixOverride}-private`,
    },
  };
  idPrefix = idPrefixOverride;
} else {
  // Fall back to base_outputs.json
  const baseOutputsPath = process.env.BASE_OUTPUTS_PATH;
  if (!baseOutputsPath) {
    console.error("\n  ❌ BASE_OUTPUTS_PATH env var is not set.");
    console.error("     Either provide it, or set ID_PREFIX, USER_POOL_ID, and AWS_REGION directly.\n");
    process.exit(1);
  }

  const resolvedPath = path.resolve(baseOutputsPath);
  if (!fs.existsSync(resolvedPath)) {
    console.error(`\n  ❌ base_outputs.json not found at: ${resolvedPath}`);
    console.error("     Deploy the base stack first.\n");
    process.exit(1);
  }

  base     = JSON.parse(fs.readFileSync(resolvedPath, "utf-8"));
  idPrefix = base.storage.public_bucket.replace(/-public$/, "");
}

// Pre-resolved by deploy.sh — undefined on first deploy, set on all subsequent deploys.
// When set, CDK imports the existing resource instead of creating a new one.
const metClientId    = process.env.MET_CLIENT_ID     || undefined;
const metApiId       = process.env.MET_API_ID        || undefined;
const metApiRootId   = process.env.MET_API_ROOT_ID   || undefined;

const app = new cdk.App();

new MileageExpenseStack(app, `MileageExpenseStack-${idPrefix}`, {
  base,
  idPrefix,
  metClientId,
  metApiId,
  metApiRootId,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region:  base.aws_region,
  },
});

#!/usr/bin/env node
import "source-map-support/register";
import * as cdk from "aws-cdk-lib";
import { METStack } from "../lib/met-stack";
import { config } from "./config";

const app = new cdk.App();

new METStack(app, "METStack", {
  appId:          config.appId,
  awsRegion:      config.awsRegion,
  dlivUserPoolId: config.dlivUserPoolId,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region:  config.awsRegion,
  },
});

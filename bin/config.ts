// bin/config.ts
// dliv.com's existing Cognito User Pool is shared — do not create a new one.
// The mileage app gets its own App Client on the same pool.

export const config = {
  appId:          "met893",           // used as prefix for all resource names
  awsRegion:      "us-east-1",
  dlivUserPoolId: "us-east-1_9v0zP2VID",  // dliv.com's existing Cognito User Pool
};

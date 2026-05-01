// backend/lib/met-stack.ts
// Mileage Expense Tracker — standalone CDK stack.
// Consumes base_outputs.json from cognito-s3-stack-893 via BASE_OUTPUTS_PATH.
// Deploys:
//   - Cognito App Client on shared User Pool
//   - Cognito Group: mileage-access
//   - Identity Pool for direct S3 receipt uploads
//   - S3 receipts bucket
//   - DynamoDB: met-vehicles, met-trips, met-expenses
//   - Lambda: vehicles, trips, expenses, ocr
//   - API Gateway (Cognito-authorised)
//   - Textract IAM for OCR Lambda
//   - Writes met_outputs.json at repo root via deploy.sh

import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as dynamodb from "aws-cdk-lib/aws-dynamodb";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as s3n from "aws-cdk-lib/aws-s3-notifications";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as lambdaNodejs from "aws-cdk-lib/aws-lambda-nodejs";
import * as apigateway from "aws-cdk-lib/aws-apigateway";
import * as iam from "aws-cdk-lib/aws-iam";
import * as path from "path";
import { BaseOutputs } from "./base-outputs";

export interface MileageExpenseStackProps extends cdk.StackProps {
  base: BaseOutputs;
}

export class MileageExpenseStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: MileageExpenseStackProps) {
    super(scope, id, props);

    const { base } = props;

    // ── Import shared User Pool from base ─────────────────────────────────────
    const userPool = cognito.UserPool.fromUserPoolId(
      this, "SharedUserPool", base.auth.user_pool_id
    );

    // ── New App Client ────────────────────────────────────────────────────────
    const appClient = userPool.addClient("MileageExpenseClient", {
      userPoolClientName: "mileage-expense-client",
      authFlows: { userPassword: true, userSrp: true, adminUserPassword: true },
      preventUserExistenceErrors: true,
    });

    // ── Cognito Group ─────────────────────────────────────────────────────────
    new cognito.CfnUserPoolGroup(this, "MileageAccessGroup", {
      groupName:   "mileage-access",
      userPoolId:  userPool.userPoolId,
      description: "Users with access to the mileage expense tracker",
    });

    // ── Identity Pool for direct S3 receipt uploads ───────────────────────────
    const identityPool = new cognito.CfnIdentityPool(this, "METIdentityPool", {
      identityPoolName:               "mileage_expense_identity_pool",
      allowUnauthenticatedIdentities: false,
      cognitoIdentityProviders: [{
        clientId:     appClient.userPoolClientId,
        providerName: userPool.userPoolProviderName,
      }],
    });

    // ── S3 Receipts Bucket ────────────────────────────────────────────────────
    const receiptsBucket = new s3.Bucket(this, "ReceiptsBucket", {
      bucketName:        `${base.auth.user_pool_id.split("_")[1].toLowerCase()}-met-receipts`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy:     cdk.RemovalPolicy.RETAIN,
      cors: [{
        allowedOrigins: ["*"],
        allowedMethods: [s3.HttpMethods.PUT, s3.HttpMethods.GET],
        allowedHeaders: ["*"],
        exposedHeaders: ["ETag"],
        maxAge: 3000,
      }],
    });

    // ── DynamoDB Tables ───────────────────────────────────────────────────────
    const vehiclesTable = new dynamodb.Table(this, "VehiclesTable", {
      tableName:     "met-vehicles",
      partitionKey:  { name: "userId",    type: dynamodb.AttributeType.STRING },
      sortKey:       { name: "vehicleId", type: dynamodb.AttributeType.STRING },
      billingMode:   dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    const tripsTable = new dynamodb.Table(this, "TripsTable", {
      tableName:     "met-trips",
      partitionKey:  { name: "userId", type: dynamodb.AttributeType.STRING },
      sortKey:       { name: "tripId", type: dynamodb.AttributeType.STRING },
      billingMode:   dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
    tripsTable.addGlobalSecondaryIndex({
      indexName:      "vehicleId-tripDate-index",
      partitionKey:   { name: "vehicleId", type: dynamodb.AttributeType.STRING },
      sortKey:        { name: "tripDate",  type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    const expensesTable = new dynamodb.Table(this, "ExpensesTable", {
      tableName:     "met-expenses",
      partitionKey:  { name: "userId",    type: dynamodb.AttributeType.STRING },
      sortKey:       { name: "expenseId", type: dynamodb.AttributeType.STRING },
      billingMode:   dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
    expensesTable.addGlobalSecondaryIndex({
      indexName:      "vehicleId-expenseDate-index",
      partitionKey:   { name: "vehicleId",   type: dynamodb.AttributeType.STRING },
      sortKey:        { name: "expenseDate", type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // ── Lambda factory ────────────────────────────────────────────────────────
    const commonEnv: Record<string, string> = {
      VEHICLES_TABLE:     vehiclesTable.tableName,
      TRIPS_TABLE:        tripsTable.tableName,
      EXPENSES_TABLE:     expensesTable.tableName,
      RECEIPTS_BUCKET:    receiptsBucket.bucketName,
      AWS_ACCOUNT_REGION: base.aws_region,
    };

    const makeLambda = (name: string, entry: string, timeoutSecs = 10) =>
      new lambdaNodejs.NodejsFunction(this, name, {
        entry, handler: "handler",
        runtime:     lambda.Runtime.NODEJS_20_X,
        environment: commonEnv,
        timeout:     cdk.Duration.seconds(timeoutSecs),
        bundling: {
          externalModules: [
            "@aws-sdk/client-dynamodb", "@aws-sdk/lib-dynamodb",
            "@aws-sdk/client-s3", "@aws-sdk/client-textract",
            "@aws-sdk/s3-request-presigner",
          ],
        },
      });

    const vehiclesLambda = makeLambda("VehiclesLambda", path.join(__dirname, "../lambda/vehicles/index.ts"));
    const tripsLambda    = makeLambda("TripsLambda",    path.join(__dirname, "../lambda/trips/index.ts"));
    const expensesLambda = makeLambda("ExpensesLambda", path.join(__dirname, "../lambda/expenses/index.ts"));
    const ocrLambda      = makeLambda("OCRLambda",      path.join(__dirname, "../lambda/ocr/index.ts"), 30);

    // ── IAM grants ───────────────────────────────────────────────────────────
    [vehiclesLambda, tripsLambda, expensesLambda].forEach(fn => {
      vehiclesTable.grantReadWriteData(fn);
      tripsTable.grantReadWriteData(fn);
      expensesTable.grantReadWriteData(fn);
    });
    receiptsBucket.grantPut(expensesLambda);
    receiptsBucket.grantRead(expensesLambda);
    receiptsBucket.grantRead(ocrLambda);
    expensesTable.grantReadWriteData(ocrLambda);
    ocrLambda.addToRolePolicy(new iam.PolicyStatement({
      actions:   ["textract:AnalyzeExpense", "textract:DetectDocumentText"],
      resources: ["*"],
    }));

    receiptsBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(ocrLambda),
      { prefix: "receipts/" }
    );

    // ── Identity Pool auth role ───────────────────────────────────────────────
    const authRole = new iam.Role(this, "METAuthRole", {
      assumedBy: new iam.FederatedPrincipal("cognito-identity.amazonaws.com", {
        StringEquals: { "cognito-identity.amazonaws.com:aud": identityPool.ref },
        "ForAnyValue:StringLike": { "cognito-identity.amazonaws.com:amr": "authenticated" },
      }, "sts:AssumeRoleWithWebIdentity"),
    });
    authRole.addToPolicy(new iam.PolicyStatement({
      actions:   ["s3:PutObject", "s3:GetObject"],
      resources: [`${receiptsBucket.bucketArn}/receipts/\${cognito-identity.amazonaws.com:sub}/*`],
    }));
    new cognito.CfnIdentityPoolRoleAttachment(this, "METIdentityPoolRoles", {
      identityPoolId: identityPool.ref,
      roles: { authenticated: authRole.roleArn },
    });

    // ── API Gateway ───────────────────────────────────────────────────────────
    const api = new apigateway.RestApi(this, "METAPI", {
      restApiName: "mileage-expense-api",
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ["Content-Type", "Authorization"],
      },
    });

    const authorizer = new apigateway.CognitoUserPoolsAuthorizer(this, "METAuthorizer", {
      cognitoUserPools: [userPool],
    });
    const auth: apigateway.MethodOptions = {
      authorizer,
      authorizationType: apigateway.AuthorizationType.COGNITO,
    };

    const vehicles = api.root.addResource("vehicles");
    vehicles.addMethod("GET",  new apigateway.LambdaIntegration(vehiclesLambda), auth);
    vehicles.addMethod("POST", new apigateway.LambdaIntegration(vehiclesLambda), auth);
    const vehicle = vehicles.addResource("{vehicleId}");
    vehicle.addMethod("PUT",    new apigateway.LambdaIntegration(vehiclesLambda), auth);
    vehicle.addMethod("DELETE", new apigateway.LambdaIntegration(vehiclesLambda), auth);

    const trips = api.root.addResource("trips");
    trips.addMethod("GET",  new apigateway.LambdaIntegration(tripsLambda), auth);
    trips.addMethod("POST", new apigateway.LambdaIntegration(tripsLambda), auth);
    const trip = trips.addResource("{tripId}");
    trip.addMethod("PUT",    new apigateway.LambdaIntegration(tripsLambda), auth);
    trip.addMethod("DELETE", new apigateway.LambdaIntegration(tripsLambda), auth);

    const expenses = api.root.addResource("expenses");
    expenses.addMethod("GET",  new apigateway.LambdaIntegration(expensesLambda), auth);
    expenses.addMethod("POST", new apigateway.LambdaIntegration(expensesLambda), auth);
    const expense = expenses.addResource("{expenseId}");
    expense.addMethod("PUT",    new apigateway.LambdaIntegration(expensesLambda), auth);
    expense.addMethod("DELETE", new apigateway.LambdaIntegration(expensesLambda), auth);

    // ── Outputs ───────────────────────────────────────────────────────────────
    new cdk.CfnOutput(this, "ApiUrlOutput",        { value: api.url,                    exportName: "METApiUrl" });
    new cdk.CfnOutput(this, "UserPoolIdOutput",     { value: userPool.userPoolId,        exportName: "METUserPoolId" });
    new cdk.CfnOutput(this, "AppClientIdOutput",    { value: appClient.userPoolClientId, exportName: "METAppClientId" });
    new cdk.CfnOutput(this, "IdentityPoolIdOutput", { value: identityPool.ref,           exportName: "METIdentityPoolId" });
    new cdk.CfnOutput(this, "ReceiptsBucketOutput", { value: receiptsBucket.bucketName,  exportName: "METReceiptsBucket" });
    new cdk.CfnOutput(this, "VehiclesTableOutput",  { value: vehiclesTable.tableName,    exportName: "METVehiclesTable" });
    new cdk.CfnOutput(this, "TripsTableOutput",     { value: tripsTable.tableName,       exportName: "METTripsTable" });
    new cdk.CfnOutput(this, "ExpensesTableOutput",  { value: expensesTable.tableName,    exportName: "METExpensesTable" });
  }
}

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

export interface METStackProps extends cdk.StackProps {
  appId:          string;  // "met893"
  awsRegion:      string;
  dlivUserPoolId: string;  // dliv.com's existing Cognito User Pool ID
}

export class METStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: METStackProps) {
    super(scope, id, props);

    // ── Import dliv.com's existing Cognito User Pool ──────────────────────────
    const userPool = cognito.UserPool.fromUserPoolId(
      this, "DlivUserPool", props.dlivUserPoolId
    );

    // ── New App Client for the mileage app ────────────────────────────────────
    const metAppClient = userPool.addClient("METMobileClient", {
      userPoolClientName: "met893-mobile-client",
      authFlows: {
        userPassword:      true,
        userSrp:           true,
        adminUserPassword: true,
      },
      preventUserExistenceErrors: true,
    });

    // ── Cognito Groups ────────────────────────────────────────────────────────
    new cognito.CfnUserPoolGroup(this, "DlivAccessGroup", {
      groupName:   "dliv-access",
      userPoolId:  userPool.userPoolId,
      description: "Users allowed to access dliv.com",
    });

    new cognito.CfnUserPoolGroup(this, "MileageAccessGroup", {
      groupName:   "mileage-access",
      userPoolId:  userPool.userPoolId,
      description: "Users allowed to access the mileage expense tracker",
    });

    // ── Identity Pool for MET ─────────────────────────────────────────────────
    const identityPool = new cognito.CfnIdentityPool(this, "METIdentityPool", {
      identityPoolName:               "met893_identity_pool",
      allowUnauthenticatedIdentities: false,
      cognitoIdentityProviders: [
        {
          clientId:     metAppClient.userPoolClientId,
          providerName: userPool.userPoolProviderName,
        },
      ],
    });

    // ── S3 Receipts Bucket ────────────────────────────────────────────────────
    const receiptsBucket = new s3.Bucket(this, "METReceiptsBucket", {
      bucketName:        `${props.appId}-receipts`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned:         false,
      removalPolicy:     cdk.RemovalPolicy.RETAIN,
      cors: [
        {
          allowedOrigins: ["*"],
          allowedMethods: [s3.HttpMethods.PUT, s3.HttpMethods.GET],
          allowedHeaders: ["*"],
          exposedHeaders: ["ETag"],
          maxAge:         3000,
        },
      ],
    });

    // ── DynamoDB Tables ───────────────────────────────────────────────────────
    const vehiclesTable = new dynamodb.Table(this, "METVehiclesTable", {
      tableName:     `${props.appId}-vehicles`,
      partitionKey:  { name: "userId",    type: dynamodb.AttributeType.STRING },
      sortKey:       { name: "vehicleId", type: dynamodb.AttributeType.STRING },
      billingMode:   dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    const tripsTable = new dynamodb.Table(this, "METTripsTable", {
      tableName:     `${props.appId}-trips`,
      partitionKey:  { name: "userId", type: dynamodb.AttributeType.STRING },
      sortKey:       { name: "tripId", type: dynamodb.AttributeType.STRING },
      billingMode:   dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    tripsTable.addGlobalSecondaryIndex({
      indexName:      "vehicleId-tripDate-index",
      partitionKey:   { name: "vehicleId", type: dynamodb.AttributeType.STRING },
      sortKey:        { name: "tripDate",   type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    const expensesTable = new dynamodb.Table(this, "METExpensesTable", {
      tableName:     `${props.appId}-expenses`,
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

    // ── Shared Lambda environment variables ───────────────────────────────────
    const commonEnv: Record<string, string> = {
      VEHICLES_TABLE:     vehiclesTable.tableName,
      TRIPS_TABLE:        tripsTable.tableName,
      EXPENSES_TABLE:     expensesTable.tableName,
      RECEIPTS_BUCKET:    receiptsBucket.bucketName,
      AWS_ACCOUNT_REGION: props.awsRegion,
    };

    // ── Lambda function factory ───────────────────────────────────────────────
    const makeLambda = (name: string, entry: string, timeoutSecs = 10) =>
      new lambdaNodejs.NodejsFunction(this, name, {
        entry,
        handler:     "handler",
        runtime:     lambda.Runtime.NODEJS_20_X,
        environment: commonEnv,
        timeout:     cdk.Duration.seconds(timeoutSecs),
        bundling: {
          externalModules: [
            "@aws-sdk/client-dynamodb",
            "@aws-sdk/lib-dynamodb",
            "@aws-sdk/client-s3",
            "@aws-sdk/client-textract",
            "@aws-sdk/s3-request-presigner",
          ],
        },
      });

    // ── API Lambda functions ──────────────────────────────────────────────────
    const vehiclesLambda = makeLambda(
      "VehiclesLambda",
      path.join(__dirname, "../lambda/vehicles/index.ts")
    );
    const tripsLambda = makeLambda(
      "TripsLambda",
      path.join(__dirname, "../lambda/trips/index.ts")
    );
    const expensesLambda = makeLambda(
      "ExpensesLambda",
      path.join(__dirname, "../lambda/expenses/index.ts")
    );
    const ocrLambda = makeLambda(
      "OCRLambda",
      path.join(__dirname, "../lambda/ocr/index.ts"),
      30
    );

    // ── IAM grants ───────────────────────────────────────────────────────────
    [vehiclesLambda, tripsLambda, expensesLambda].forEach((fn) => {
      vehiclesTable.grantReadWriteData(fn);
      tripsTable.grantReadWriteData(fn);
      expensesTable.grantReadWriteData(fn);
    });

    receiptsBucket.grantRead(ocrLambda);
    expensesTable.grantReadWriteData(ocrLambda);
    ocrLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions:   ["textract:AnalyzeExpense", "textract:DetectDocumentText"],
        resources: ["*"],
      })
    );

    // ── S3 → OCR Lambda trigger ───────────────────────────────────────────────
    receiptsBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(ocrLambda),
      { prefix: "receipts/" }
    );

    // ── Identity Pool authenticated role ──────────────────────────────────────
    const authRole = new iam.Role(this, "METAuthenticatedRole", {
      description: "Temporary creds for authenticated MET mobile app users",
      assumedBy: new iam.FederatedPrincipal(
        "cognito-identity.amazonaws.com",
        {
          StringEquals: {
            "cognito-identity.amazonaws.com:aud": identityPool.ref,
          },
          "ForAnyValue:StringLike": {
            "cognito-identity.amazonaws.com:amr": "authenticated",
          },
        },
        "sts:AssumeRoleWithWebIdentity"
      ),
    });

    authRole.addToPolicy(
      new iam.PolicyStatement({
        sid:     "ReceiptUpload",
        actions: ["s3:PutObject", "s3:GetObject"],
        resources: [
          `${receiptsBucket.bucketArn}/receipts/\${cognito-identity.amazonaws.com:sub}/*`,
        ],
      })
    );

    new cognito.CfnIdentityPoolRoleAttachment(this, "METIdentityPoolRoles", {
      identityPoolId: identityPool.ref,
      roles: { authenticated: authRole.roleArn },
    });

    // ── API Gateway ───────────────────────────────────────────────────────────
    const api = new apigateway.RestApi(this, "METAPI", {
      restApiName: "met893-api",
      description: "Mileage & expense tracker REST API",
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ["Content-Type", "Authorization"],
      },
    });

    const authorizer = new apigateway.CognitoUserPoolsAuthorizer(
      this, "METAuthorizer",
      {
        cognitoUserPools: [userPool],
        authorizerName:   "met893-cognito-authorizer",
      }
    );

    const authOptions: apigateway.MethodOptions = {
      authorizer,
      authorizationType: apigateway.AuthorizationType.COGNITO,
    };

    // ── Routes ────────────────────────────────────────────────────────────────
    const vehiclesResource = api.root.addResource("vehicles");
    vehiclesResource.addMethod("GET",  new apigateway.LambdaIntegration(vehiclesLambda), authOptions);
    vehiclesResource.addMethod("POST", new apigateway.LambdaIntegration(vehiclesLambda), authOptions);
    const vehicleResource = vehiclesResource.addResource("{vehicleId}");
    vehicleResource.addMethod("PUT",    new apigateway.LambdaIntegration(vehiclesLambda), authOptions);
    vehicleResource.addMethod("DELETE", new apigateway.LambdaIntegration(vehiclesLambda), authOptions);

    const tripsResource = api.root.addResource("trips");
    tripsResource.addMethod("GET",  new apigateway.LambdaIntegration(tripsLambda), authOptions);
    tripsResource.addMethod("POST", new apigateway.LambdaIntegration(tripsLambda), authOptions);
    const tripResource = tripsResource.addResource("{tripId}");
    tripResource.addMethod("PUT",    new apigateway.LambdaIntegration(tripsLambda), authOptions);
    tripResource.addMethod("DELETE", new apigateway.LambdaIntegration(tripsLambda), authOptions);

    const expensesResource = api.root.addResource("expenses");
    expensesResource.addMethod("GET",  new apigateway.LambdaIntegration(expensesLambda), authOptions);
    expensesResource.addMethod("POST", new apigateway.LambdaIntegration(expensesLambda), authOptions);
    const expenseResource = expensesResource.addResource("{expenseId}");
    expenseResource.addMethod("PUT",    new apigateway.LambdaIntegration(expensesLambda), authOptions);
    expenseResource.addMethod("DELETE", new apigateway.LambdaIntegration(expensesLambda), authOptions);

    // ── CloudFormation Outputs ────────────────────────────────────────────────
    // Note: Output logical IDs must be unique AND different from construct IDs above.
    new cdk.CfnOutput(this, "ApiUrl",               { value: api.url,                       description: "API Gateway base URL" });
    new cdk.CfnOutput(this, "UserPoolId",            { value: userPool.userPoolId,           description: "Cognito User Pool ID (shared with dliv.com)" });
    new cdk.CfnOutput(this, "UserPoolClientId",      { value: metAppClient.userPoolClientId, description: "MET mobile app client ID" });
    new cdk.CfnOutput(this, "IdentityPoolId",        { value: identityPool.ref,              description: "MET Identity Pool ID" });
    new cdk.CfnOutput(this, "ReceiptsBucketName",    { value: receiptsBucket.bucketName,     description: "S3 bucket for receipt images" });
    new cdk.CfnOutput(this, "VehiclesTableName",     { value: vehiclesTable.tableName,       description: "DynamoDB vehicles table" });
    new cdk.CfnOutput(this, "TripsTableName",        { value: tripsTable.tableName,          description: "DynamoDB trips table" });
    new cdk.CfnOutput(this, "ExpensesTableName",     { value: expensesTable.tableName,       description: "DynamoDB expenses table" });
  }
}

// backend/lib/met-stack.ts
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
  base:      BaseOutputs;
  idPrefix:  string;   // e.g. "test893" — drives all resource names

  // Pre-resolved by deploy.sh via idempotent AWS CLI checks.
  // When provided, CDK imports the existing resource instead of creating a new one.
  // When absent (first deploy), CDK creates and deploy.sh persists the ID on next run.
  metClientId?: string;   // existing Cognito app client ID
  metApiId?:    string;   // existing API Gateway REST API ID
  metApiRootId?: string;  // root resource ID of existing API Gateway
}

export class MileageExpenseStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: MileageExpenseStackProps) {
    super(scope, id, props);

    const { base, idPrefix, metClientId, metApiId, metApiRootId } = props;

    // ── Cognito ───────────────────────────────────────────────────────────────
    const userPool = cognito.UserPool.fromUserPoolId(
      this, "SharedUserPool", base.auth.user_pool_id
    );

    // Import existing app client if deploy.sh found one, otherwise create.
    // The client is created once by deploy.sh and never recreated — CDK only
    // imports it here so it can reference the client ID in other constructs.
    let appClientId: string;
    if (metClientId) {
      // Import — CDK does not manage lifecycle, no risk of recreation.
      appClientId = metClientId;
    } else {
      // First deploy: create the client. deploy.sh will persist the ID
      // and pass it back on all future deploys via MET_CLIENT_ID env var.
      const appClient = userPool.addClient("MileageExpenseClient", {
        userPoolClientName: `${idPrefix}-met-client`,
        authFlows: {
          userPassword:      true,
          userSrp:           true,
          adminUserPassword: true,
        },
        preventUserExistenceErrors: true,
      });
      appClientId = appClient.userPoolClientId;
    }

    new cognito.CfnUserPoolGroup(this, "MileageAccessGroup", {
      groupName:   `${idPrefix}-mileage-access`,
      userPoolId:  userPool.userPoolId,
      description: "Users with access to the mileage expense tracker",
    });

    const identityPool = new cognito.CfnIdentityPool(this, "METIdentityPool", {
      identityPoolName:               `${idPrefix}_met_identity_pool`,
      allowUnauthenticatedIdentities: false,
      cognitoIdentityProviders: [{
        clientId:     appClientId,
        providerName: userPool.userPoolProviderName,
      }],
    });

    // ── S3 ────────────────────────────────────────────────────────────────────
    const receiptsBucket = new s3.Bucket(this, "ReceiptsBucket", {
      bucketName:        `${idPrefix}-met-receipts`,
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

    // ── DynamoDB ──────────────────────────────────────────────────────────────
    const vehiclesTable = new dynamodb.Table(this, "VehiclesTable", {
      tableName:     `${idPrefix}-met-vehicles`,
      partitionKey:  { name: "userId",    type: dynamodb.AttributeType.STRING },
      sortKey:       { name: "vehicleId", type: dynamodb.AttributeType.STRING },
      billingMode:   dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    const tripsTable = new dynamodb.Table(this, "TripsTable", {
      tableName:     `${idPrefix}-met-trips`,
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
      tableName:     `${idPrefix}-met-expenses`,
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

    // ── Lambdas ───────────────────────────────────────────────────────────────
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

    // ── IAM auth role for Identity Pool ──────────────────────────────────────
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
    // Import existing API Gateway if deploy.sh found one, otherwise create.
    // Importing prevents CDK from ever recreating it and changing its ID,
    // which would break all iOS clients that have the URL baked in.
    let api: apigateway.IRestApi;
    if (metApiId && metApiRootId) {
      // Import — CDK references the existing API, never recreates it.
      api = apigateway.RestApi.fromRestApiAttributes(this, "METAPI", {
        restApiId:      metApiId,
        rootResourceId: metApiRootId,
      });
    } else {
      // First deploy: create the API. deploy.sh persists the ID after this run.
      api = new apigateway.RestApi(this, "METAPI", {
        restApiName: `${idPrefix}-mileage-expense-api`,
        defaultCorsPreflightOptions: {
          allowOrigins: apigateway.Cors.ALL_ORIGINS,
          allowMethods: apigateway.Cors.ALL_METHODS,
          allowHeaders: ["Content-Type", "Authorization"],
        },
      });
    }

    const authorizer = new apigateway.CognitoUserPoolsAuthorizer(this, "METAuthorizer", {
      cognitoUserPools: [userPool],
    });
    const authOptions: apigateway.MethodOptions = {
      authorizer,
      authorizationType: apigateway.AuthorizationType.COGNITO,
    };

    const vehicles = api.root.addResource("vehicles");
    vehicles.addMethod("GET",  new apigateway.LambdaIntegration(vehiclesLambda), authOptions);
    vehicles.addMethod("POST", new apigateway.LambdaIntegration(vehiclesLambda), authOptions);
    const vehicle = vehicles.addResource("{vehicleId}");
    vehicle.addMethod("PUT",    new apigateway.LambdaIntegration(vehiclesLambda), authOptions);
    vehicle.addMethod("DELETE", new apigateway.LambdaIntegration(vehiclesLambda), authOptions);

    const trips = api.root.addResource("trips");
    trips.addMethod("GET",  new apigateway.LambdaIntegration(tripsLambda), authOptions);
    trips.addMethod("POST", new apigateway.LambdaIntegration(tripsLambda), authOptions);
    const trip = trips.addResource("{tripId}");
    trip.addMethod("PUT",    new apigateway.LambdaIntegration(tripsLambda), authOptions);
    trip.addMethod("DELETE", new apigateway.LambdaIntegration(tripsLambda), authOptions);

    const expenses = api.root.addResource("expenses");
    expenses.addMethod("GET",  new apigateway.LambdaIntegration(expensesLambda), authOptions);
    expenses.addMethod("POST", new apigateway.LambdaIntegration(expensesLambda), authOptions);
    const expense = expenses.addResource("{expenseId}");
    expense.addMethod("PUT",    new apigateway.LambdaIntegration(expensesLambda), authOptions);
    expense.addMethod("DELETE", new apigateway.LambdaIntegration(expensesLambda), authOptions);

    // ── Outputs ───────────────────────────────────────────────────────────────
    // Always reconstruct the URL from the actual API ID — never rely on
    // api.url from an imported IRestApi as it may reflect a stale/deleted ID.
    const resolvedApiId = metApiId ?? (api as apigateway.RestApi).restApiId;
    const apiUrl = `https://${resolvedApiId}.execute-api.${base.aws_region}.amazonaws.com/prod/`;

    new cdk.CfnOutput(this, "METApiUrl",        { value: apiUrl });
    new cdk.CfnOutput(this, "METUserPoolId",     { value: userPool.userPoolId });
    new cdk.CfnOutput(this, "METAppClientId",    { value: appClientId });
    new cdk.CfnOutput(this, "METIdentityPoolId", { value: identityPool.ref });
    new cdk.CfnOutput(this, "METReceiptsBucket", { value: receiptsBucket.bucketName });
    new cdk.CfnOutput(this, "METVehiclesTable",  { value: vehiclesTable.tableName });
    new cdk.CfnOutput(this, "METTripsTable",     { value: tripsTable.tableName });
    new cdk.CfnOutput(this, "METExpensesTable",  { value: expensesTable.tableName });
  }
}

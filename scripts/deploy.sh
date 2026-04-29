#!/bin/bash
# deploy.sh — Build and deploy the MET CDK stack, then write met_outputs.json
set -e

STACK_NAME="METStack"
REGION="us-east-1"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   Mileage & Expense Tracker — CDK Deploy (met893) ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "  Using dliv.com Cognito pool (us-east-1_9v0zP2VID)"
echo "  Stack: $STACK_NAME  |  Region: $REGION"
echo ""
read -p "  Proceed with deploy? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "  Cancelled."
  exit 0
fi

# ── Install dependencies ──────────────────────────────────────────────────────
if [ ! -d "node_modules" ]; then
  echo ""
  echo "  Installing dependencies..."
  npm install
fi

# ── Deploy ────────────────────────────────────────────────────────────────────
echo ""
echo "  Running cdk deploy..."
echo ""
npx cdk deploy --require-approval never

# ── Pull CloudFormation outputs ───────────────────────────────────────────────
echo ""
echo "  Reading stack outputs..."

get_output() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" \
    --output text
}

API_URL=$(get_output "ApiUrl")
USER_POOL_ID=$(get_output "UserPoolId")
USER_POOL_CLIENT_ID=$(get_output "UserPoolClientId")
IDENTITY_POOL_ID=$(get_output "IdentityPoolId")
RECEIPTS_BUCKET=$(get_output "ReceiptsBucketName")
VEHICLES_TABLE=$(get_output "VehiclesTableName")
TRIPS_TABLE=$(get_output "TripsTableName")
EXPENSES_TABLE=$(get_output "ExpensesTableName")

# ── Write met_outputs.json ────────────────────────────────────────────────────
echo "  Writing met_outputs.json..."

cat > met_outputs.json << EOF
{
  "version": "1",
  "api": {
    "aws_region": "${REGION}",
    "base_url":   "${API_URL}"
  },
  "auth": {
    "aws_region":          "${REGION}",
    "user_pool_id":        "${USER_POOL_ID}",
    "user_pool_client_id": "${USER_POOL_CLIENT_ID}",
    "identity_pool_id":    "${IDENTITY_POOL_ID}"
  },
  "storage": {
    "aws_region":      "${REGION}",
    "receipts_bucket": "${RECEIPTS_BUCKET}"
  },
  "tables": {
    "vehicles": "${VEHICLES_TABLE}",
    "trips":    "${TRIPS_TABLE}",
    "expenses": "${EXPENSES_TABLE}"
  }
}
EOF

echo ""
echo "  ✅ met_outputs.json written"
echo ""
echo "  ────────────────────────────────────────────────────"
echo "  API URL:         $API_URL"
echo "  User Pool:       $USER_POOL_ID"
echo "  App Client:      $USER_POOL_CLIENT_ID"
echo "  Identity Pool:   $IDENTITY_POOL_ID"
echo "  Receipts Bucket: $RECEIPTS_BUCKET"
echo "  ────────────────────────────────────────────────────"
echo ""
echo "  Next: copy met_outputs.json into your iOS and Android projects."
echo ""

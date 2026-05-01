#!/bin/bash
# backend/scripts/deploy.sh
# Deploys the Mileage Expense Tracker CDK stack.
# Reads base_outputs.json via BASE_OUTPUTS_PATH env var.
#
# Usage:
#   BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json ./scripts/deploy.sh
#
# Or set it in your shell profile:
#   export BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json

set -e

STACK_NAME="MileageExpenseStack"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Mileage Expense Tracker — Backend Deploy   ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Validate BASE_OUTPUTS_PATH ────────────────────────────────────────────────
if [ -z "$BASE_OUTPUTS_PATH" ]; then
  echo "  ❌ BASE_OUTPUTS_PATH is not set."
  echo ""
  echo "     Set it to the base_outputs.json from your cognito-s3-stack-893 deployment:"
  echo "     export BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json"
  echo ""
  exit 1
fi

if [ ! -f "$BASE_OUTPUTS_PATH" ]; then
  echo "  ❌ base_outputs.json not found at: $BASE_OUTPUTS_PATH"
  echo "     Deploy the base stack first: cd cognito-s3-stack-893/base && ./scripts/deploy.sh"
  echo ""
  exit 1
fi

AWS_REGION=$(node -e "const b=require('${BASE_OUTPUTS_PATH}'); console.log(b.aws_region)" 2>/dev/null || echo "us-east-1")

echo "  Stack:     $STACK_NAME"
echo "  Region:    $AWS_REGION"
echo "  Base from: $BASE_OUTPUTS_PATH"
echo ""
read -p "  Proceed? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then echo "  Cancelled."; exit 0; fi

cd "$REPO_ROOT"
[ ! -d "node_modules" ] && npm install

echo ""
BASE_OUTPUTS_PATH="$BASE_OUTPUTS_PATH" npx cdk deploy --require-approval never

# ── Capture outputs ───────────────────────────────────────────────────────────
get_output() {
  aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

API_URL=$(get_output "METApiUrl")
USER_POOL_ID=$(get_output "METUserPoolId")
APP_CLIENT_ID=$(get_output "METAppClientId")
IDENTITY_POOL_ID=$(get_output "METIdentityPoolId")
RECEIPTS_BUCKET=$(get_output "METReceiptsBucket")
VEHICLES_TABLE=$(get_output "METVehiclesTable")
TRIPS_TABLE=$(get_output "METTripsTable")
EXPENSES_TABLE=$(get_output "METExpensesTable")

# ── Write met_outputs.json to repo root ───────────────────────────────────────
cat > "${REPO_ROOT}/met_outputs.json" << EOF
{
  "version": "1",
  "api": {
    "aws_region": "${AWS_REGION}",
    "base_url":   "${API_URL}"
  },
  "auth": {
    "aws_region":          "${AWS_REGION}",
    "user_pool_id":        "${USER_POOL_ID}",
    "user_pool_client_id": "${APP_CLIENT_ID}",
    "identity_pool_id":    "${IDENTITY_POOL_ID}"
  },
  "storage": {
    "aws_region":      "${AWS_REGION}",
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
echo "  ✅ met_outputs.json written to repo root"
echo "  API URL:         $API_URL"
echo "  User Pool:       $USER_POOL_ID"
echo "  App Client:      $APP_CLIENT_ID"
echo "  Identity Pool:   $IDENTITY_POOL_ID"
echo "  Receipts Bucket: $RECEIPTS_BUCKET"
echo ""

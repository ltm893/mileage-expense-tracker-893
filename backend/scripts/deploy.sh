#!/bin/bash
# backend/scripts/deploy.sh
# Deploys the Mileage Expense Tracker CDK stack.
# Reads base_outputs.json via BASE_OUTPUTS_PATH env var.
#
# Idempotent — safe to run on every deploy:
#   - Cognito app client: checked by name, created only if missing
#   - API Gateway:        checked by name, created only if missing (imported into CDK)
#   - DynamoDB tables:    CDK-managed with RETAIN policy (data never lost)
#   - S3 receipts bucket: CDK-managed with RETAIN policy (data never lost)
#   - Identity Pool:      CDK-managed (stateless, safe to update)
#
# Usage (standard — base pool from cognito-s3-stack-893):
#   BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json ./scripts/deploy.sh
#
# Usage (override — point at any existing Cognito pool):
#   BASE_OUTPUTS_PATH=/path/to/base_outputs.json \
#   ID_PREFIX=dliv893 \
#   USER_POOL_ID=us-east-1_A4MFXeYS7 \
#   AWS_REGION=us-east-1 \
#     ./scripts/deploy.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${BACKEND_DIR}/.." && pwd)"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   Mileage Expense Tracker — Backend Deploy   ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Resolve ID_PREFIX, AWS_REGION, USER_POOL_ID ──────────────────────────────
# These can come from env var overrides (Option B) or from base_outputs.json.
# Env vars take priority. base_outputs.json is only read if any value is missing.

if [ -n "$ID_PREFIX" ] && [ -n "$AWS_REGION" ] && [ -n "$USER_POOL_ID" ]; then
  # All three overrides provided — no base_outputs.json needed
  echo "  ℹ️  Using env var overrides (no base_outputs.json required)"
else
  # Fall back to base_outputs.json for any missing values
  if [ -z "$BASE_OUTPUTS_PATH" ]; then
    echo "  ❌ BASE_OUTPUTS_PATH is not set."
    echo "     Either provide it, or set ID_PREFIX, USER_POOL_ID, and AWS_REGION directly."
    echo "     Example (standard):"
    echo "       BASE_OUTPUTS_PATH=/path/to/cognito-s3-stack-893/base_outputs.json ./scripts/deploy.sh"
    echo "     Example (override):"
    echo "       ID_PREFIX=dliv893 USER_POOL_ID=us-east-1_A4MFXeYS7 AWS_REGION=us-east-1 ./scripts/deploy.sh"
    exit 1
  fi

  if [ ! -f "$BASE_OUTPUTS_PATH" ]; then
    echo "  ❌ base_outputs.json not found at: $BASE_OUTPUTS_PATH"
    echo "     Deploy the base stack first."
    exit 1
  fi

  PUBLIC_BUCKET=$(grep -E '"public_bucket"' "$BASE_OUTPUTS_PATH" | sed 's/.*"\(.*\)".*/\1/')
  AWS_REGION_FROM_FILE=$(grep -E '"aws_region"' "$BASE_OUTPUTS_PATH" | head -1 | sed 's/.*"\(.*\)".*/\1/')
  USER_POOL_ID_FROM_FILE=$(grep -E '"user_pool_id"' "$BASE_OUTPUTS_PATH" | sed 's/.*"\(.*\)".*/\1/')

  ID_PREFIX="${ID_PREFIX:-${PUBLIC_BUCKET%-public}}"
  AWS_REGION="${AWS_REGION:-${AWS_REGION_FROM_FILE}}"
  USER_POOL_ID="${USER_POOL_ID:-${USER_POOL_ID_FROM_FILE}}"
fi
# Validate that we have everything we need
if [ -z "$ID_PREFIX" ]; then
  echo "  ❌ Could not determine ID_PREFIX."
  echo "     Either set ID_PREFIX env var, or ensure base_outputs.json has a valid storage.public_bucket."
  exit 1
fi

if [ -z "$USER_POOL_ID" ]; then
  echo "  ❌ Could not determine USER_POOL_ID."
  echo "     Either set USER_POOL_ID env var, or ensure base_outputs.json has a valid auth.user_pool_id."
  exit 1
fi

if [ -z "$AWS_REGION" ]; then
  echo "  ❌ Could not determine AWS_REGION."
  echo "     Either set AWS_REGION env var, or ensure base_outputs.json has a valid aws_region."
  exit 1
fi

STACK_NAME="MileageExpenseStack-${ID_PREFIX}"

# Derived resource names — single source of truth
CLIENT_NAME="${ID_PREFIX}-met-client"
API_NAME="${ID_PREFIX}-mileage-expense-api"

echo "  Stack:         $STACK_NAME"
echo "  Region:        $AWS_REGION"
echo "  ID prefix:     $ID_PREFIX"
echo "  User pool:     $USER_POOL_ID"
echo "  Base from:     $BASE_OUTPUTS_PATH"
echo ""

# ── Check / create Cognito app client (idempotent) ────────────────────────────
echo "  Checking Cognito app client '$CLIENT_NAME'..."

EXISTING_CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
  --user-pool-id "$USER_POOL_ID" \
  --region "$AWS_REGION" \
  --query "UserPoolClients[?ClientName=='${CLIENT_NAME}'].ClientId" \
  --output text 2>/dev/null || true)

if [ -n "$EXISTING_CLIENT_ID" ] && [ "$EXISTING_CLIENT_ID" != "None" ]; then
  echo "  ✅ App client exists: $EXISTING_CLIENT_ID"
  MET_CLIENT_ID="$EXISTING_CLIENT_ID"
else
  echo "  Creating app client '$CLIENT_NAME'..."
  MET_CLIENT_ID=$(aws cognito-idp create-user-pool-client \
    --user-pool-id "$USER_POOL_ID" \
    --client-name "$CLIENT_NAME" \
    --no-generate-secret \
    --explicit-auth-flows \
      ALLOW_USER_PASSWORD_AUTH \
      ALLOW_USER_SRP_AUTH \
      ALLOW_REFRESH_TOKEN_AUTH \
    --prevent-user-existence-errors ENABLED \
    --region "$AWS_REGION" \
    --query "UserPoolClient.ClientId" \
    --output text)
  echo "  ✅ App client created: $MET_CLIENT_ID"
fi

# ── Check / create API Gateway (idempotent) ───────────────────────────────────
echo ""
echo "  Checking API Gateway '$API_NAME'..."

EXISTING_API_ID=$(aws apigateway get-rest-apis \
  --region "$AWS_REGION" \
  --query "items[?name=='${API_NAME}'].id" \
  --output text 2>/dev/null || true)

if [ -n "$EXISTING_API_ID" ] && [ "$EXISTING_API_ID" != "None" ]; then
  echo "  ✅ API Gateway exists: $EXISTING_API_ID"
  MET_API_ID="$EXISTING_API_ID"

  # Fetch root resource ID so CDK can import the API without a custom resource
  MET_API_ROOT_ID=$(aws apigateway get-resources \
    --rest-api-id "$MET_API_ID" \
    --region "$AWS_REGION" \
    --query "items[?path=='/'].id" \
    --output text)
  echo "  ✅ Root resource ID:   $MET_API_ROOT_ID"
else
  echo "  ℹ️  API Gateway not found — CDK will create it on first deploy."
  MET_API_ID=""
  MET_API_ROOT_ID=""
fi

# ── Show resource summary and confirm ────────────────────────────────────────
echo ""
echo "  Resources after this deploy:"
echo "    Cognito client:  $MET_CLIENT_ID (preserved)"
if [ -n "$MET_API_ID" ]; then
  echo "    API Gateway:     $MET_API_ID (preserved)"
else
  echo "    API Gateway:     will be created by CDK"
fi
echo "    S3:              ${ID_PREFIX}-met-receipts (retained)"
echo "    DynamoDB:        ${ID_PREFIX}-met-vehicles, ${ID_PREFIX}-met-trips, ${ID_PREFIX}-met-expenses (retained)"
echo ""
read -p "  Proceed? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then echo "  Cancelled."; exit 0; fi

# ── Install deps ──────────────────────────────────────────────────────────────
cd "$BACKEND_DIR"
[ ! -d "node_modules" ] && npm install

# ── Deploy CDK stack ──────────────────────────────────────────────────────────
echo ""
echo "  Deploying CDK stack..."

BASE_OUTPUTS_PATH="$BASE_OUTPUTS_PATH" \
MET_CLIENT_ID="$MET_CLIENT_ID" \
MET_API_ID="$MET_API_ID" \
MET_API_ROOT_ID="$MET_API_ROOT_ID" \
  npx cdk deploy --require-approval never

# ── Re-check API Gateway ID (if CDK just created it) ─────────────────────────
if [ -z "$MET_API_ID" ]; then
  echo ""
  echo "  Resolving new API Gateway ID..."
  MET_API_ID=$(aws apigateway get-rest-apis \
    --region "$AWS_REGION" \
    --query "items[?name=='${API_NAME}'].id" \
    --output text)
  echo "  ✅ API Gateway created: $MET_API_ID"
fi

# ── Capture CloudFormation outputs ───────────────────────────────────────────
get_output() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$AWS_REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" \
    --output text
}

API_URL=$(get_output "METApiUrl")
IDENTITY_POOL_ID=$(get_output "METIdentityPoolId")
RECEIPTS_BUCKET=$(get_output "METReceiptsBucket")
VEHICLES_TABLE=$(get_output "METVehiclesTable")
TRIPS_TABLE=$(get_output "METTripsTable")
EXPENSES_TABLE=$(get_output "METExpensesTable")

# ── Write met_outputs.json ────────────────────────────────────────────────────
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
    "user_pool_client_id": "${MET_CLIENT_ID}",
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
echo ""
echo "  ────────────────────────────────────────────────────"
echo "  API URL:         $API_URL"
echo "  User Pool:       $USER_POOL_ID"
echo "  App Client:      $MET_CLIENT_ID"
echo "  Identity Pool:   $IDENTITY_POOL_ID"
echo "  Receipts Bucket: $RECEIPTS_BUCKET"
echo "  API Gateway ID:  $MET_API_ID"
echo "  ────────────────────────────────────────────────────"
echo ""
echo "  Next: rebuild the iOS app in Xcode if met_outputs.json changed."
echo ""

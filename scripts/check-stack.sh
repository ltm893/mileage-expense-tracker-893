#!/bin/bash
# check-stack.sh — Show current METStack status and all resource IDs

STACK_NAME="METStack"
REGION="us-east-1"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║       Check METStack Status          ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  Stack: $STACK_NAME  |  Region: $REGION"
echo ""

STATUS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$REGION" \
  --query "Stacks[0].StackStatus" \
  --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [[ "$STATUS" == "DOES_NOT_EXIST" || "$STATUS" == "None" ]]; then
  echo "  ❌ Stack '$STACK_NAME' does not exist."
  echo "     Run: ./scripts/deploy.sh"
  echo ""
  exit 0
fi

echo "  Status: $STATUS"
echo ""

get_output() {
  aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" \
    --output text 2>/dev/null
}

echo "  ────────────────────────────────────────────────────"
echo "  API URL:         $(get_output ApiUrl)"
echo "  User Pool ID:    $(get_output UserPoolId)"
echo "  App Client ID:   $(get_output UserPoolClientId)"
echo "  Identity Pool:   $(get_output IdentityPoolId)"
echo "  Receipts Bucket: $(get_output ReceiptsBucket)"
echo "  Vehicles Table:  $(get_output VehiclesTable)"
echo "  Trips Table:     $(get_output TripsTable)"
echo "  Expenses Table:  $(get_output ExpensesTable)"
echo "  ────────────────────────────────────────────────────"
echo ""

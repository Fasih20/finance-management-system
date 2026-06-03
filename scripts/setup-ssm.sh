#!/usr/bin/env bash
# setup-ssm.sh — Populate AWS SSM Parameter Store with real secret values.
# Run this ONCE after `terraform apply` creates the placeholder parameters.
#
# Usage:
#   1. Fill in every value below (remove the "CHANGEME" placeholders)
#   2. chmod +x scripts/setup-ssm.sh
#   3. ./scripts/setup-ssm.sh
#
# Requires: AWS CLI configured with a user that has SSM write access.

set -euo pipefail

REGION="us-east-1"
PREFIX="/finance-app"

put() {
  local key="$1"
  local value="$2"
  echo "  Storing $PREFIX/$key ..."
  aws ssm put-parameter \
    --name "$PREFIX/$key" \
    --value "$value" \
    --type SecureString \
    --overwrite \
    --region "$REGION"
}

echo "==> Populating SSM parameters in $REGION ..."

# ── Clerk ──────────────────────────────────────────────────────────────────
put "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" "pk_test_CHANGEME"
put "CLERK_PUBLISHABLE_KEY"             "pk_test_CHANGEME"
put "CLERK_SECRET_KEY"                  "sk_test_CHANGEME"

# ── Database ────────────────────────────────────────────────────────────────
put "DATABASE_URL" "postgresql://user:password@host/dbname?sslmode=require&channel_binding=require"

# ── Plaid ───────────────────────────────────────────────────────────────────
put "PLAID_CLIENT_TOKEN" "CHANGEME"
put "PLAID_SECRET_TOKEN" "CHANGEME"

# ── LemonSqueezy ────────────────────────────────────────────────────────────
put "LEMONSQUEEZY_STORE_ID"       "CHANGEME"
put "LEMONSQUEEZY_PRODUCT_ID"     "CHANGEME"
put "LEMONSQUEEZY_API_KEY"        "CHANGEME"
put "LEMONSQUEEZY_WEBHOOK_SECRET" "CHANGEME"

# ── AWS Bedrock (AI Insights) ────────────────────────────────────────────────
put "AWS_ACCESS_KEY_ID"     "CHANGEME"
put "AWS_SECRET_ACCESS_KEY" "CHANGEME"

# ── Gemini ──────────────────────────────────────────────────────────────────
put "GEMINI_API_KEY" "CHANGEME"

echo ""
echo "==> Done. All parameters stored in SSM under $PREFIX/"
echo "    ECS will inject them automatically on next container start."

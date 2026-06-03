# setup-ssm.ps1 — Populate AWS SSM Parameter Store with real secret values.
# Run this ONCE after `terraform apply` creates the placeholder parameters.
#
# Usage (Windows PowerShell):
#   1. Fill in every value below (replace the "CHANGEME" text)
#   2. Open PowerShell as normal user (no admin needed)
#   3. cd into the project root
#   4. .\scripts\setup-ssm.ps1
#
# Requires: AWS CLI installed and configured  (aws configure)
# Install AWS CLI on Windows: https://awscli.amazonaws.com/AWSCLIV2.msi

$ErrorActionPreference = "Stop"

$REGION = "us-east-1"
$PREFIX = "/finance-app"

function Put-Param($key, $value) {
    Write-Host "  Storing $PREFIX/$key ..."
    aws ssm put-parameter `
        --name "$PREFIX/$key" `
        --value "$value" `
        --type SecureString `
        --overwrite `
        --region $REGION
}

Write-Host "==> Populating SSM parameters in $REGION ..."

# ── Clerk ─────────────────────────────────────────────────────────────────────
Put-Param "NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" "pk_test_CHANGEME"
Put-Param "CLERK_PUBLISHABLE_KEY"             "pk_test_CHANGEME"
Put-Param "CLERK_SECRET_KEY"                  "sk_test_CHANGEME"

# ── Database ──────────────────────────────────────────────────────────────────
Put-Param "DATABASE_URL" "postgresql://user:password@host/dbname?sslmode=require&channel_binding=require"

# ── Plaid ─────────────────────────────────────────────────────────────────────
Put-Param "PLAID_CLIENT_TOKEN" "CHANGEME"
Put-Param "PLAID_SECRET_TOKEN" "CHANGEME"

# ── LemonSqueezy ──────────────────────────────────────────────────────────────
Put-Param "LEMONSQUEEZY_STORE_ID"       "CHANGEME"
Put-Param "LEMONSQUEEZY_PRODUCT_ID"     "CHANGEME"
Put-Param "LEMONSQUEEZY_API_KEY"        "CHANGEME"
Put-Param "LEMONSQUEEZY_WEBHOOK_SECRET" "CHANGEME"

# ── AWS Bedrock (AI Insights) ─────────────────────────────────────────────────
Put-Param "AWS_ACCESS_KEY_ID"     "CHANGEME"
Put-Param "AWS_SECRET_ACCESS_KEY" "CHANGEME"

# ── Gemini ────────────────────────────────────────────────────────────────────
Put-Param "GEMINI_API_KEY" "CHANGEME"

Write-Host ""
Write-Host "==> Done. All parameters stored in SSM under $PREFIX/"
Write-Host "    ECS will inject them automatically on next container start."

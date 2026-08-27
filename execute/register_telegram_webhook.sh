#!/usr/bin/env bash
set -euo pipefail

TELEGRAM_TOKEN=$(grep -E '^\s*telegram_token' secrets.auto.tfvars | cut -d'"' -f2)
WEBHOOK_SECRET=$(grep -E '^\s*webhook_secret' secrets.auto.tfvars | cut -d'"' -f2)
FUNCTION_URL=$(terraform output -raw retrieval_function_url)

[[ -z "$TELEGRAM_TOKEN" || -z "$WEBHOOK_SECRET" || -z "$FUNCTION_URL" ]] && { echo "token, secret or url is empty"; exit 1; }

curl -sS "https://api.telegram.org/bot$TELEGRAM_TOKEN/setWebhook" \
  -d "url=$FUNCTION_URL" \
  -d "secret_token=$WEBHOOK_SECRET"

#!/usr/bin/env bash
set -euo pipefail

MODEL_ID="eu.anthropic.claude-sonnet-4-5-20250929-v1:0"
CHUNK_SIZE=1000
CHUNK_OVERLAP=150
START_AT="chunking"

STATE_MACHINE_ARN=$(terraform output -raw state_machine_arn)

[[ -z "$STATE_MACHINE_ARN" ]] && { echo "terraform output is empty"; exit 1; }

aws stepfunctions start-execution \
  --state-machine-arn "$STATE_MACHINE_ARN" \
  --input "{\"model_id\":\"$MODEL_ID\",\"start_at\":\"$START_AT\",\"chunk_size\":$CHUNK_SIZE,\"chunk_overlap\":$CHUNK_OVERLAP}"

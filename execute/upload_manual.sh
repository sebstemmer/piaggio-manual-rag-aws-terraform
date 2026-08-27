#!/usr/bin/env bash
set -euo pipefail

BUCKET=$(terraform output -raw bucket_name)
MANUAL_PDF_KEY=$(terraform output -raw manual_pdf_key)

[[ -z "$BUCKET" || -z "$MANUAL_PDF_KEY" ]] && { echo "terraform output is empty"; exit 1; }

FILE="data/manual.pdf"

aws s3 cp "$FILE" "s3://$BUCKET/$MANUAL_PDF_KEY"
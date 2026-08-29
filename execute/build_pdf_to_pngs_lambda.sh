#!/usr/bin/env bash
set -euo pipefail

rm -rf lambdas/build/pdf_to_pngs
mkdir -p lambdas/build/pdf_to_pngs

cp lambdas/code/pdf_to_pngs/pdf_to_pngs.py lambdas/build/pdf_to_pngs/

pip install \
  --platform manylinux2014_aarch64 \
  --python-version 3.14 \
  --only-binary=:all: \
  --target lambdas/build/pdf_to_pngs \
  pillow
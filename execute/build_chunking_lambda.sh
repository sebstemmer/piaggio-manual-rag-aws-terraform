#!/usr/bin/env bash
set -euo pipefail

rm -rf lambdas/build/chunking
mkdir -p lambdas/build/chunking

cp lambdas/code/chunking/chunking.py lambdas/build/chunking/

pip install \
  --platform manylinux2014_aarch64 \
  --python-version 3.14 \
  --only-binary=:all: \
  --target lambdas/build/chunking \
  langchain-text-splitters

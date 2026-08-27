#!/usr/bin/env bash
set -euo pipefail

rm -rf lambdas/build/retrieval
mkdir -p lambdas/build/retrieval

cp lambdas/code/retrieval/*.py lambdas/build/retrieval/

#!/usr/bin/env bash
set -euo pipefail

rm -rf lambdas/build/embed_chunks
mkdir -p lambdas/build/embed_chunks

cp lambdas/code/embed_chunks/*.py lambdas/build/embed_chunks/

#!/usr/bin/env bash
set -euo pipefail

rm -rf lambdas/build/png_to_md
mkdir -p lambdas/build/png_to_md

cp lambdas/code/png_to_md/*.py lambdas/build/png_to_md/
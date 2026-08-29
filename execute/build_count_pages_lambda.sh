#!/usr/bin/env bash
set -euo pipefail

rm -rf lambdas/build/count_pages
mkdir -p lambdas/build/count_pages

cp lambdas/code/count_pages/count_pages.py lambdas/build/count_pages/

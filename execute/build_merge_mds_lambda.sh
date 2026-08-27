#!/usr/bin/env bash
set -euo pipefail

rm -rf lambdas/build/merge_mds
mkdir -p lambdas/build/merge_mds

cp lambdas/code/merge_mds/*.py lambdas/build/merge_mds/

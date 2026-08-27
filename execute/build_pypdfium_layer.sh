#!/usr/bin/env bash
set -euo pipefail

rm -rf lambdas/build/pypdfium

pip install \
  --platform manylinux2014_aarch64 \
  --only-binary=:all: \
  --target lambdas/build/pypdfium/python \
  pypdfium2
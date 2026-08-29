#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d evaluation/.venv ]]; then
  python3 -m venv evaluation/.venv
fi

source evaluation/.venv/bin/activate

pip install -q -r evaluation/requirements.txt

echo "=== check_testset ==="
python3 -m evaluation.tests.check_testset

echo
echo "=== check_chunking ==="
python3 -m evaluation.tests.check_chunking

deactivate

#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d evaluation/.venv ]]; then
  python3 -m venv evaluation/.venv
fi

source evaluation/.venv/bin/activate

pip install -q -r evaluation/requirements.txt

python3 -m evaluation.chunk_size.evaluate_chunk_size

deactivate

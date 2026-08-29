#!/usr/bin/env bash
set -euo pipefail

bash execute/build_count_pages_lambda.sh
bash execute/build_pdf_to_pngs_lambda.sh
bash execute/build_png_to_md_lambda.sh
bash execute/build_merge_mds_lambda.sh
bash execute/build_chunking_lambda.sh
bash execute/build_embed_chunks_lambda.sh
bash execute/build_retrieval_lambda.sh

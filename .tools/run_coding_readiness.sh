#!/usr/bin/env bash
# Author: WaterRun
# Date: 2026-09-23
# File: run_coding_readiness.sh
# Description: Runs contract, evidence and feasibility checks under the shared resource guard.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

if [[ ${YACA_TEST_RESOURCE_GUARD_HELD:-0} != 1 ]]; then
  exec "$SCRIPT_DIR/run_with_resource_guard.sh" bash "$0" "$@"
fi

cd "$REPO_ROOT"

python3.13 test/self/code_comments_test.py
python3.13 .tools/check_code_comments.py

bin/lua55 .tools/validate_design_contracts.lua
bin/lua55 .tools/validate_proof_evidence.lua
bin/lua55 .tools/validate_coding_readiness.lua
bin/lua55 .tools/check_documentation_truth.lua "$REPO_ROOT"
bin/lua55 .tools/proofs/tp003_event_pump.lua
python3 .tools/proofs/tp006_curl_carrier.py
python3 .tools/proofs/tp008_xml_commit.py \
  .develope-docs/contracts/fixtures/context-minimal.xml \
  .develope-docs/contracts/context.rng
bash .tools/proofs/tp010_build.sh
bash .tools/proofs/rp001_resource_overlay.sh

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

bin/lua55 .tools/validate_design_contracts.lua
bin/lua55 .tools/validate_proof_evidence.lua
bin/lua55 .tools/proofs/tp003_event_pump.lua
python3 .tools/proofs/tp006_curl_carrier.py
python3 .tools/proofs/tp008_xml_commit.py \
  .develope-docs/contracts/fixtures/context-minimal.xml \
  .develope-docs/contracts/context.rng
bash .tools/proofs/tp010_build.sh

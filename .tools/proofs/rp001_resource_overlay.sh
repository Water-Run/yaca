#!/usr/bin/env bash
# Author: WaterRun
# Date: 2026-10-09
# File: rp001_resource_overlay.sh
# Description: Builds and checks the pinned luainstaller resource-overlay patch on the host.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

if [[ ${YACA_TEST_RESOURCE_GUARD_HELD:-0} != 1 ]]; then
  exec "$REPO_ROOT/.tools/run_with_resource_guard.sh" bash "$0" "$@"
fi

WORK_DIR=$(mktemp -d -t yaca-rp001-XXXXXX)
BUILD_LOG="$WORK_DIR/build.log"

# Remove the temporary proof checkout after every exit path.
#@param none No arguments; uses WORK_DIR from this proof invocation.
#@return int rm exit status; the EXIT trap does not consume a result value.
#@effect Deletes only the temporary proof directory.
cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

LUAINSTALLER_REVISION=a289a1bed6c6dcf8ad4f11a1d9e28f2f2989adbf
LUAINSTALLER_URL=https://github.com/Water-Run/luainstaller.git
PATCH_PATH="$REPO_ROOT/release/patches/luainstaller-1.5.0-resources.patch"
PATCH_SHA256=25f5816a67a3d65f4a7ef74c9c744493f626b1aa657fb4b6451cd0bfbeb57443
LUA_VERSION=5.5.1
LUA_SHA256=1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
LUA_URL=https://www.lua.org/ftp/lua-5.5.1.tar.gz

# Run a proof command and show its final log lines if it fails.
#@param ... string Command and arguments executed without shell re-parsing.
#@return int Zero when the command succeeds; failures exit the proof.
#@effect Appends command output to BUILD_LOG and exits on failure.
run_logged() {
  if ! "$@" >>"$BUILD_LOG" 2>&1; then
    echo "proof command failed: $*" >&2
    tail -80 "$BUILD_LOG" >&2
    exit 1
  fi
}

# Compare a proof input with its pinned SHA-256 digest.
#@param 1 string Input file path.
#@param 2 string Expected lowercase SHA-256 digest.
#@return int Zero on a matching digest; mismatch exits with status 65.
verify_sha256() {
  local file=$1
  local expected=$2
  local actual
  actual=$(sha256sum "$file" | awk '{print $1}')
  if [[ "$actual" != "$expected" ]]; then
    echo "checksum mismatch: $file" >&2
    echo "expected=$expected actual=$actual" >&2
    exit 65
  fi
}

SOURCE_REPOSITORY=${LUAINSTALLER_SOURCE:-}
if [[ -z "$SOURCE_REPOSITORY" && -d "$REPO_ROOT/../luainstaller/.git" ]]; then
  SOURCE_REPOSITORY="$REPO_ROOT/../luainstaller"
fi
if [[ -z "$SOURCE_REPOSITORY" ]]; then
  run_logged git clone --branch v1.5.0 --depth 1 "$LUAINSTALLER_URL" "$WORK_DIR/repository"
  SOURCE_REPOSITORY="$WORK_DIR/repository"
fi
if ! git -C "$SOURCE_REPOSITORY" cat-file -e "$LUAINSTALLER_REVISION^{commit}" 2>/dev/null; then
  echo "pinned luainstaller commit is unavailable: $LUAINSTALLER_REVISION" >&2
  exit 66
fi

mkdir -p "$WORK_DIR/upstream"
git -C "$SOURCE_REPOSITORY" archive "$LUAINSTALLER_REVISION" \
  | tar -x -C "$WORK_DIR/upstream"

verify_sha256 \
  "$WORK_DIR/upstream/src/init.lua" \
  aea35743cbeee546fb7c5128f43a2326425020e5a780f4284f2865e8bd54df1c
verify_sha256 \
  "$WORK_DIR/upstream/src/manifest.lua" \
  d86f856d0346a5f42a6611532f29f745f4dab10f892bc2cdf25148e134fc3065
verify_sha256 \
  "$WORK_DIR/upstream/src/bundler.lua" \
  b8f7fe1a41499c83da8172b935ca9410a9dda3ea7b2a4e87c3ad315afeaf6a17
verify_sha256 \
  "$WORK_DIR/upstream/src/onefile.lua" \
  67edbb961affcc496ad99a1bcdd342f07e0a2c488bed6de3442b8ac23e989a68
verify_sha256 "$PATCH_PATH" "$PATCH_SHA256"
run_logged patch --batch --forward --fuzz=0 -d "$WORK_DIR/upstream" -p1 -i "$PATCH_PATH"

if [[ -n ${YACA_PROOF_SOURCE_CACHE:-} ]]; then
  cp -- "$YACA_PROOF_SOURCE_CACHE/lua-$LUA_VERSION.tar.gz" "$WORK_DIR/lua.tar.gz"
  echo "source_cache=lua-$LUA_VERSION.tar.gz"
else
  curl --disable --fail --location --silent --show-error \
    --output "$WORK_DIR/lua.tar.gz" "$LUA_URL"
fi
verify_sha256 "$WORK_DIR/lua.tar.gz" "$LUA_SHA256"
tar -xzf "$WORK_DIR/lua.tar.gz" -C "$WORK_DIR"
LUA_SOURCE="$WORK_DIR/lua-$LUA_VERSION"
LUA_PREFIX="$WORK_DIR/lua-prefix"
run_logged make -C "$LUA_SOURCE/src" linux MYCFLAGS="-fPIC -O2"
run_logged make -C "$LUA_SOURCE" install INSTALL_TOP="$LUA_PREFIX"

echo "proof=RP-001"
echo "scope=modern-linux-pinned-luainstaller-resource-overlay"
echo "target_qualification=false"
echo "host=$(uname -srm)"
echo "luainstaller_revision=$LUAINSTALLER_REVISION"
echo "patch_sha256=$PATCH_SHA256"
echo "lua=$LUA_VERSION sha256=$LUA_SHA256"

(
  cd "$WORK_DIR/upstream"
  "$LUA_PREFIX/bin/lua" "$SCRIPT_DIR/rp001_resource_overlay.lua" "$LUA_PREFIX"
)

echo "status=PASS"

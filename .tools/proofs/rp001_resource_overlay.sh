#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

if [[ ${YACA_TEST_RESOURCE_GUARD_HELD:-0} != 1 ]]; then
  exec "$REPO_ROOT/.tools/run_with_resource_guard.sh" bash "$0" "$@"
fi

WORK_DIR=$(mktemp -d -t yaca-rp001-XXXXXX)
BUILD_LOG="$WORK_DIR/build.log"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

LUAINSTALLER_REVISION=97192d100077b31b61dc8f94427e14df1c68a9eb
LUAINSTALLER_URL=https://github.com/Water-Run/luainstaller.git
PATCH_PATH="$REPO_ROOT/release/patches/luainstaller-1.3.0-resources.patch"
PATCH_SHA256=974cf25b51ab644c8af60a7f2524a5670b1fea38e35ad733267ac4775c5d9dff
LUA_VERSION=5.5.1
LUA_SHA256=1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
LUA_URL=https://www.lua.org/ftp/lua-5.5.1.tar.gz

run_logged() {
  if ! "$@" >>"$BUILD_LOG" 2>&1; then
    echo "proof command failed: $*" >&2
    tail -80 "$BUILD_LOG" >&2
    exit 1
  fi
}

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
  run_logged git clone --branch v1.3.0 --depth 1 "$LUAINSTALLER_URL" "$WORK_DIR/repository"
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
  55694d5e1c349362206e24a3ee8670977e5ea40fd51f0a457b221c95a84fce2d
verify_sha256 \
  "$WORK_DIR/upstream/src/manifest.lua" \
  d86f856d0346a5f42a6611532f29f745f4dab10f892bc2cdf25148e134fc3065
verify_sha256 \
  "$WORK_DIR/upstream/src/bundler.lua" \
  502da4a599ee0565d11d6c58455a1834d3333f31f8c247e6ee8260fb1dafcfae
verify_sha256 \
  "$WORK_DIR/upstream/src/onefile.lua" \
  363e9a78d157821be7d6e222a4494c1f65998f5cc920c6f4cfcc0eee01dae610
verify_sha256 "$PATCH_PATH" "$PATCH_SHA256"
run_logged patch --batch --forward --fuzz=0 -d "$WORK_DIR/upstream" -p1 -i "$PATCH_PATH"

curl --disable --fail --location --silent --show-error \
  --output "$WORK_DIR/lua.tar.gz" "$LUA_URL"
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

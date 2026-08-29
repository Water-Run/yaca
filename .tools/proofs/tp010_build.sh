#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
WORK_DIR=$(mktemp -d -t yaca-tp010-XXXXXX)
BUILD_LOG="$WORK_DIR/build.log"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT

LUA_VERSION=5.5.1
LUA_SHA256=1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
LUA_URL=https://www.lua.org/ftp/lua-5.5.1.tar.gz

EXPAT_VERSION=2.8.2
EXPAT_SHA256=ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c
EXPAT_URL=https://github.com/libexpat/libexpat/releases/download/R_2_8_2/expat-2.8.2.tar.gz

LUAEXPAT_VERSION=1.5.2
LUAEXPAT_SHA256=89d83f2141edec31be576425637216928221918fe95dc3854d1b7fd4c627213f
LUAEXPAT_URL=https://github.com/lunarmodules/luaexpat/archive/refs/tags/1.5.2.tar.gz

download_and_verify() {
  local url=$1
  local destination=$2
  local expected=$3
  curl --disable --fail --location --silent --show-error --output "$destination" "$url"
  local actual
  actual=$(sha256sum "$destination" | awk '{print $1}')
  if [[ "$actual" != "$expected" ]]; then
    echo "source checksum mismatch for $url" >&2
    echo "expected=$expected actual=$actual" >&2
    exit 65
  fi
}

run_logged() {
  if ! "$@" >>"$BUILD_LOG" 2>&1; then
    echo "build command failed: $*" >&2
    tail -80 "$BUILD_LOG" >&2
    exit 1
  fi
}

mkdir -p "$WORK_DIR/downloads" "$WORK_DIR/modules"
download_and_verify "$LUA_URL" "$WORK_DIR/downloads/lua.tar.gz" "$LUA_SHA256"
download_and_verify "$EXPAT_URL" "$WORK_DIR/downloads/expat.tar.gz" "$EXPAT_SHA256"
download_and_verify "$LUAEXPAT_URL" "$WORK_DIR/downloads/luaexpat.tar.gz" "$LUAEXPAT_SHA256"

tar -xzf "$WORK_DIR/downloads/lua.tar.gz" -C "$WORK_DIR"
tar -xzf "$WORK_DIR/downloads/expat.tar.gz" -C "$WORK_DIR"
tar -xzf "$WORK_DIR/downloads/luaexpat.tar.gz" -C "$WORK_DIR"

LUA_SOURCE="$WORK_DIR/lua-$LUA_VERSION"
EXPAT_SOURCE="$WORK_DIR/expat-$EXPAT_VERSION"
LUAEXPAT_SOURCE="$WORK_DIR/luaexpat-$LUAEXPAT_VERSION"
EXPAT_BUILD="$WORK_DIR/expat-build"
EXPAT_INSTALL="$WORK_DIR/expat-install"

run_logged cmake \
  -S "$EXPAT_SOURCE" \
  -B "$EXPAT_BUILD" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$EXPAT_INSTALL" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DEXPAT_SHARED_LIBS=OFF \
  -DEXPAT_BUILD_DOCS=OFF \
  -DEXPAT_BUILD_EXAMPLES=OFF \
  -DEXPAT_BUILD_TESTS=OFF \
  -DEXPAT_BUILD_TOOLS=OFF
run_logged cmake --build "$EXPAT_BUILD" --parallel 2
run_logged cmake --install "$EXPAT_BUILD"

run_logged make -C "$LUA_SOURCE/src" linux MYCFLAGS="-fPIC -O2"

EXPAT_STATIC_LIB=$(find "$EXPAT_INSTALL" -type f -name libexpat.a -print -quit)
if [[ -z "$EXPAT_STATIC_LIB" ]]; then
  echo "installed static Expat library not found" >&2
  exit 1
fi

run_logged gcc \
  -std=c99 \
  -O2 \
  -Wall \
  -Wextra \
  -fPIC \
  -shared \
  -I"$LUA_SOURCE/src" \
  -I"$EXPAT_INSTALL/include" \
  "$LUAEXPAT_SOURCE/src/lxplib.c" \
  "$EXPAT_STATIC_LIB" \
  -ldl \
  -lm \
  -o "$WORK_DIR/modules/lxp.so"

LUA_BIN="$LUA_SOURCE/src/lua"
LXP_MODULE="$WORK_DIR/modules/lxp.so"

if ! file "$LUA_BIN" | grep -q "ELF 64-bit"; then
  echo "modern proof Lua is not ELF64" >&2
  exit 1
fi
if ! file "$LXP_MODULE" | grep -q "ELF 64-bit"; then
  echo "modern proof lxp module is not ELF64" >&2
  exit 1
fi
if ldd "$LXP_MODULE" | grep -q "libexpat"; then
  echo "lxp unexpectedly depends on a host libexpat" >&2
  exit 1
fi
if readelf -d "$LXP_MODULE" | grep -Eq "RPATH|RUNPATH"; then
  echo "lxp unexpectedly contains RPATH/RUNPATH" >&2
  exit 1
fi

xmllint --nonet --noout --relaxng \
  "$REPO_ROOT/.develope-docs/contracts/context.rng" \
  "$REPO_ROOT/.develope-docs/contracts/fixtures/context-minimal.xml" \
  >/dev/null 2>&1

echo "proof=TP-010"
echo "scope=modern-linux-pinned-source-build-and-corpus"
echo "host=$(uname -srm)"
echo "compiler=$(gcc --version | sed -n '1p')"
echo "source_lua=$LUA_VERSION sha256=$LUA_SHA256"
echo "source_expat=$EXPAT_VERSION sha256=$EXPAT_SHA256"
echo "source_luaexpat=$LUAEXPAT_VERSION sha256=$LUAEXPAT_SHA256"
echo "abi=lua:ELF64,lxp:ELF64,expat:static,no-rpath"

LUA_CPATH="$WORK_DIR/modules/?.so" \
  "$LUA_BIN" \
  "$SCRIPT_DIR/tp010_xml.lua" \
  "$REPO_ROOT/.develope-docs/contracts/fixtures/context-minimal.xml" \
  "$REPO_ROOT/.develope-docs/contracts/context.rng"

echo "status=PASS"

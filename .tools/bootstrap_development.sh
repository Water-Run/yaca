#!/usr/bin/env bash
# Author: WaterRun
# Date: 2026-10-13
# File: bootstrap_development.sh
# Description: Prepare a relocatable Linux or WSL development environment from pinned public sources and parser requirements under the shared resource guard.

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
if [[ ${YACA_TEST_RESOURCE_GUARD_HELD:-0} != 1 ]]; then
  exec bash "$SCRIPT_DIR/run_with_resource_guard.sh" bash "$0" "$@"
fi
[[ $# == 0 ]] || { echo "usage: bash .tools/bootstrap_development.sh" >&2; exit 64; }
for required in python3.13 cc make cmake curl git tar sha256sum patch xmllint; do
  command -v "$required" >/dev/null || { echo "missing development prerequisite: $required" >&2; exit 69; }
done
WORK_ROOT="$REPO_ROOT/out/development"
CACHE_ROOT="$WORK_ROOT/sources"
mkdir -p "$CACHE_ROOT"
DOWNLOAD_COMMAND=curl
BUILDER_GIT=git
if [[ $(uname -r) == *[Mm]icrosoft* ]] && command -v wslpath >/dev/null; then
  if command -v curl.exe >/dev/null; then DOWNLOAD_COMMAND=curl.exe; fi
  if command -v git.exe >/dev/null; then BUILDER_GIT=git.exe; fi
fi

# Obtain one pinned archive, validating both existing cache bytes and newly downloaded bytes.
#@param 1 string Public HTTPS source URL used only when the cached archive is absent.
#@param 2 string Basename of the source archive in this repository's development cache.
#@param 3 string Expected SHA-256 from the maintained dependency lock.
#@return int Zero after verification; command errors or mismatches terminate bootstrap.
#@effect Downloads missing input with bounded HTTPS retries, using the Windows network tool when available in WSL, and publishes it after digest verification; existing mismatches are preserved and refused.
download_source() {
  local url=$1 name=$2 expected=$3
  local path="$CACHE_ROOT/$name"
  if [[ ! -e "$path" ]]; then
    local staged
    staged=$(mktemp "$CACHE_ROOT/.download-XXXXXX")
    local download_output=$staged
    if [[ "$DOWNLOAD_COMMAND" == curl.exe ]]; then download_output=$(wslpath -w "$staged"); fi
    if ! "$DOWNLOAD_COMMAND" --disable --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
      --connect-timeout 20 --max-time 120 --retry 2 --retry-all-errors --retry-delay 2 --retry-max-time 180 \
      --output "$download_output" "$url"; then
      echo "public source download failed: $name" >&2
      rm -- "$staged"
      return 1
    fi
    if [[ $(sha256sum "$staged" | awk '{print $1}') != "$expected" ]]; then
      echo "source checksum mismatch: $name" >&2
      rm -- "$staged"
      return 65
    fi
    mv -n -- "$staged" "$path"
  fi
  [[ -f "$path" && ! -L "$path" && $(sha256sum "$path" | awk '{print $1}') == "$expected" ]] \
    || { echo "cached source checksum mismatch: $name" >&2; return 65; }
}

download_source https://www.lua.org/ftp/lua-5.5.1.tar.gz lua-5.5.1.tar.gz \
  1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce
download_source https://github.com/libexpat/libexpat/releases/download/R_2_8_2/expat-2.8.2.tar.gz expat-2.8.2.tar.gz \
  ef7d1994f533c9e7343d6c19f31064fc8ebbcbcaa144be3812b4f43052a05f4c
download_source https://github.com/lunarmodules/luaexpat/archive/refs/tags/1.5.2.tar.gz luaexpat-1.5.2.tar.gz \
  89d83f2141edec31be576425637216928221918fe95dc3854d1b7fd4c627213f

tar -xzf "$CACHE_ROOT/lua-5.5.1.tar.gz" -C "$WORK_ROOT"
make -C "$WORK_ROOT/lua-5.5.1" clean > "$WORK_ROOT/lua-build.log" 2>&1
make -C "$WORK_ROOT/lua-5.5.1" -j1 linux >> "$WORK_ROOT/lua-build.log" 2>&1 \
  || { tail -40 "$WORK_ROOT/lua-build.log" >&2; exit 1; }
mkdir -p "$REPO_ROOT/bin"
if [[ ! -e "$REPO_ROOT/bin/lua55" && ! -L "$REPO_ROOT/bin/lua55" ]]; then
  ln -s ../out/development/lua-5.5.1/src/lua "$REPO_ROOT/bin/lua55"
fi
"$REPO_ROOT/bin/lua55" -v 2>&1 | grep -F 'Lua 5.5.1' >/dev/null \
  || { echo "bin/lua55 is not the required Lua 5.5.1 interpreter" >&2; exit 65; }

if [[ ! -e "$WORK_ROOT/python/bin/python3.13" ]]; then
  python3.13 -m venv "$WORK_ROOT/python"
fi
"$WORK_ROOT/python/bin/python3.13" -m pip install --disable-pip-version-check \
  -r "$REPO_ROOT/.tools/comment_check_requirements.txt" > "$WORK_ROOT/parser-install.log" 2>&1 \
  || { tail -40 "$WORK_ROOT/parser-install.log" >&2; exit 1; }

BUILDER_ROOT="$WORK_ROOT/luainstaller"
if [[ ! -e "$BUILDER_ROOT" ]]; then
  BUILDER_DESTINATION=$BUILDER_ROOT
  if [[ "$BUILDER_GIT" == git.exe ]]; then BUILDER_DESTINATION=$(wslpath -w "$BUILDER_ROOT"); fi
  "$BUILDER_GIT" -c core.autocrlf=false clone --branch v1.5.0 --depth 1 --no-checkout \
    https://github.com/Water-Run/luainstaller.git "$BUILDER_DESTINATION"
fi
[[ $(git -C "$BUILDER_ROOT" rev-parse HEAD) == a289a1bed6c6dcf8ad4f11a1d9e28f2f2989adbf ]] \
  || { echo "luainstaller checkout differs from the pinned commit" >&2; exit 65; }

{
  printf '# Author: WaterRun\n# Date: 2026-10-13\n# File: activate.sh\n# Description: Select the generated local development tools and pinned public proof sources.\n'
  printf 'export PATH=%q:"$PATH"\n' "$WORK_ROOT/python/bin"
  printf 'export YACA_PROOF_SOURCE_CACHE=%q\n' "$CACHE_ROOT"
  printf 'export LUAINSTALLER_SOURCE=%q\n' "$BUILDER_ROOT"
} > "$WORK_ROOT/activate.sh"
echo "development bootstrap: PASS"
echo "source out/development/activate.sh, then run the commands in .develope-docs/QUALIFICATION-RUNBOOK.md"

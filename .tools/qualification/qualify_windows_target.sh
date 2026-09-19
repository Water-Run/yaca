#!/usr/bin/env bash
# Windows target qualification driver (run from the Linux build host).
#
# usage: qualify_windows_target.sh SSH_HOST TARGET_ID PACKAGE_ZIP [WORKDIR]
#
# TARGET_ID is win32-x86 or win64-x86_64. The script distributes the zip,
# then drives the on-target clean-machine journey and collects evidence.
# Online segments need YACA_CONFIG_INI pointing at a private configuration
# file; without it only the offline qualification runs.
#
# Prerequisites on the target: an ssh server with cmd reachable, unzip
# (Cygwin) or PowerShell Expand-Archive (Win7+), and no other yaca process.
set -euo pipefail

SSH_HOST=$1
TARGET_ID=$2
PACKAGE_ZIP=$3
WORKDIR=${4:-C:\\yaca-qual}

[[ "$TARGET_ID" == win32-x86 || "$TARGET_ID" == win64-x86_64 ]] || {
  echo "target must be win32-x86 or win64-x86_64" >&2; exit 64; }
[[ -f "$PACKAGE_ZIP" ]] || { echo "package zip is missing" >&2; exit 64; }

EVIDENCE=${EVIDENCE_DIR:-qual-$TARGET_ID-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$EVIDENCE"
sha256sum "$PACKAGE_ZIP" | tee "$EVIDENCE/package-sha256.txt"

remote() { ssh -o BatchMode=yes "$SSH_HOST" "$@"; }

echo "[1/7] distributing package"
if [[ "$TARGET_ID" == win32-x86 ]]; then
  scp -q "$PACKAGE_ZIP" "$SSH_HOST":/tmp/yaca-qual.zip
  remote 'cd /tmp && rm -rf yaca-qual && mkdir yaca-qual && cd yaca-qual
    && unzip -q /tmp/yaca-qual.zip -d inst' \
    | tee "$EVIDENCE/01-extract.log"
  LIST_CMD='cd /tmp/yaca-qual && find inst -type f | sed "s|^inst/||" | sort'
  RUN_CMD='/tmp/yaca-qual/inst/yaca.exe'
else
  scp -O -q "$PACKAGE_ZIP" "$SSH_HOST":C:/Users/Administrator/yaca-qual.zip
  remote 'Remove-Item -Recurse -Force C:\yaca-qual -ErrorAction SilentlyContinue;
    New-Item -ItemType Directory -Force C:\yaca-qual\inst | Out-Null;
    Expand-Archive -Path C:\Users\Administrator\yaca-qual.zip -DestinationPath C:\yaca-qual\inst' \
    | tee "$EVIDENCE/01-extract.log"
  LIST_CMD='Get-ChildItem -Recurse -File C:\yaca-qual\inst | ForEach-Object { $_.FullName.Substring(21).Replace("\\","/") } | Sort-Object'
  RUN_CMD='C:\yaca-qual\inst\yaca.exe'
fi

echo "[2/7] exporting the extracted file list for the zero-surface audit"
remote "$LIST_CMD" | tr -d '\r' | sed '/^$/d' > "$EVIDENCE/02-file-list.txt"

echo "[3/7] version and offline stage-1 self-test"
remote "$RUN_CMD --version" | tr -d '\r' | tee "$EVIDENCE/03-version.log"
if [[ "$TARGET_ID" == win32-x86 ]]; then
  remote "cd /tmp/yaca-qual && winpty ./inst/yaca.exe --self-test --through-stage 1" \
    | tr -d '\000' | tee "$EVIDENCE/04-stage1.log"
else
  remote "$RUN_CMD --self-test --through-stage 1" \
    | tr -d '\r' | tee "$EVIDENCE/04-stage1.log"
fi
grep -q "outcome=passed\|outcome=partial" "$EVIDENCE/04-stage1.log" \
  || { echo "stage 1 did not pass on the target" >&2; exit 1; }

if [[ -n ${YACA_CONFIG_INI:-} ]]; then
  echo "[4/7] placing the private configuration and running stages 2/3"
  if [[ "$TARGET_ID" == win32-x86 ]]; then
    remote 'mkdir -p /tmp/yaca-qual/inst/__yaca__'
    scp -q "$YACA_CONFIG_INI" "$SSH_HOST":/tmp/yaca-qual/inst/__yaca__/config.ini
    remote "$RUN_CMD --self-test --through-stage 3 --i-accept-online-self-test" \
      | tr -d '\000' | tee "$EVIDENCE/05-stage23.log"
  else
    base64 -w0 "$YACA_CONFIG_INI" | remote 'New-Item -ItemType Directory -Force C:\yaca-qual\inst\__yaca__ | Out-Null; $b=($input -join "").Trim(); [IO.File]::WriteAllBytes("C:\yaca-qual\inst\__yaca__\config.ini",[Convert]::FromBase64String($b))'
    remote "$RUN_CMD --self-test --through-stage 3 --i-accept-online-self-test" \
      | tr -d '\r' | tee "$EVIDENCE/05-stage23.log"
  fi
  grep -q "completed-stage=3" "$EVIDENCE/05-stage23.log" \
    || { echo "online stages did not complete on the target" >&2; exit 1; }
else
  echo "[4/7] skipped: no YACA_CONFIG_INI for the online segment"
fi

echo "[5/7] upgrade rehearsal: re-extract over the install, data must survive"
if [[ "$TARGET_ID" == win32-x86 ]]; then
  remote 'cd /tmp/yaca-qual && unzip -qo /tmp/yaca-qual.zip -d inst && ls inst/__yaca__' \
    | tee "$EVIDENCE/06-upgrade.log"
else
  remote 'Expand-Archive -Path C:\Users\Administrator\yaca-qual.zip -DestinationPath C:\yaca-qual\inst -Force; Test-Path C:\yaca-qual\inst\__yaca__' \
    | tee "$EVIDENCE/06-upgrade.log"
fi

echo "[6/7] uninstall and residue check"
if [[ "$TARGET_ID" == win32-x86 ]]; then
  remote 'rm -rf /tmp/yaca-qual && ls /tmp/yaca-qual' | tee "$EVIDENCE/07-uninstall.log" \
    || true
else
  remote 'Remove-Item -Recurse -Force C:\yaca-qual; Test-Path C:\yaca-qual' \
    | tee "$EVIDENCE/07-uninstall.log"
fi

echo "[7/7] evidence collected in $EVIDENCE"
echo "Run the zero-surface audit and the interactive journeys next:"
echo "  bin/lua55 -e '... verify(manifest, file-list entries, $TARGET_ID)'"
echo "  python journey.py <log> $SSH_HOST '<run chat with approvals>'"

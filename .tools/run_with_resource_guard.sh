#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 COMMAND [ARGUMENT ...]" >&2
  exit 64
}

refuse() {
  echo "test resource preflight: REFUSED: $*" >&2
  exit 75
}

[[ $# -gt 0 ]] || usage

PROC_ROOT=${YACA_TEST_PROC_ROOT:-/proc}
CGROUP_ROOT=${YACA_TEST_CGROUP_ROOT:-/sys/fs/cgroup}
MINIMUM_AVAILABLE_MIB=${YACA_TEST_MIN_AVAILABLE_MIB:-2048}
MAXIMUM_LOAD_PER_CPU=${YACA_TEST_MAX_LOAD_PER_CPU:-2.0}
MAXIMUM_MEMORY_FULL_AVG10=${YACA_TEST_MAX_MEMORY_FULL_AVG10:-5.0}

[[ "$MINIMUM_AVAILABLE_MIB" =~ ^[0-9]+$ \
  && "$MINIMUM_AVAILABLE_MIB" -ge 256 \
  && "$MINIMUM_AVAILABLE_MIB" -le 1048576 ]] \
  || refuse "YACA_TEST_MIN_AVAILABLE_MIB is invalid"
[[ "$MAXIMUM_LOAD_PER_CPU" =~ ^[0-9]+([.][0-9]+)?$ ]] \
  || refuse "YACA_TEST_MAX_LOAD_PER_CPU is invalid"
[[ "$MAXIMUM_MEMORY_FULL_AVG10" =~ ^[0-9]+([.][0-9]+)?$ ]] \
  || refuse "YACA_TEST_MAX_MEMORY_FULL_AVG10 is invalid"

if [[ ${YACA_TEST_RESOURCE_GUARD_HELD:-0} != 1 ]]; then
  for required_command in awk flock getconf id mkdir stat tr; do
    command -v "$required_command" >/dev/null 2>&1 \
      || refuse "$required_command is required by the resource guard"
  done
  USER_ID=$(id -u 2>/dev/null) \
    || refuse "current user identity is unavailable"
  LOCK_ROOT=${XDG_RUNTIME_DIR:-}
  if [[ -n "$LOCK_ROOT" && -d "$LOCK_ROOT" ]]; then
    LOCK_ROOT_OWNER=$(stat -Lc '%u' "$LOCK_ROOT" 2>/dev/null || true)
    LOCK_ROOT_MODE=$(stat -Lc '%a' "$LOCK_ROOT" 2>/dev/null || true)
    if [[ "$LOCK_ROOT_OWNER" != "$USER_ID" || "$LOCK_ROOT_MODE" != 700 ]]; then
      LOCK_ROOT=
    fi
  else
    LOCK_ROOT=
  fi
  if [[ -z "$LOCK_ROOT" ]]; then
    LOCK_ROOT=/tmp/yaca-$USER_ID-test-resource
    umask 077
    if [[ ! -e "$LOCK_ROOT" ]]; then
      mkdir -m 700 -- "$LOCK_ROOT" 2>/dev/null || true
    fi
    LOCK_ROOT_OWNER=$(stat -Lc '%u' "$LOCK_ROOT" 2>/dev/null || true)
    LOCK_ROOT_MODE=$(stat -Lc '%a' "$LOCK_ROOT" 2>/dev/null || true)
    [[ -d "$LOCK_ROOT" \
      && "$LOCK_ROOT_OWNER" == "$USER_ID" \
      && "$LOCK_ROOT_MODE" == 700 ]] \
      || refuse "a private resource lock directory is unavailable"
  fi
  LOCK_PATH=${YACA_TEST_RESOURCE_LOCK_PATH:-$LOCK_ROOT/yaca-$USER_ID-heavy-test.lock}
  umask 077
  exec 9>"$LOCK_PATH" \
    || refuse "resource lock cannot be opened: $LOCK_PATH"
  flock -n 9 \
    || refuse "another guarded yaca test or proof is already running"
  export YACA_TEST_RESOURCE_GUARD_HELD=1
fi

MEMINFO="$PROC_ROOT/meminfo"
LOADAVG="$PROC_ROOT/loadavg"
[[ -r "$MEMINFO" ]] || refuse "memory availability cannot be read"
[[ -r "$LOADAVG" ]] || refuse "system load cannot be read"

read_meminfo_kib() {
  local name=$1
  awk -v key="$name:" '$1 == key { print $2; exit }' "$MEMINFO"
}

MEMORY_AVAILABLE_KIB=$(read_meminfo_kib MemAvailable)
MEMORY_TOTAL_KIB=$(read_meminfo_kib MemTotal)
SWAP_FREE_KIB=$(read_meminfo_kib SwapFree)
SWAP_TOTAL_KIB=$(read_meminfo_kib SwapTotal)
[[ "$MEMORY_AVAILABLE_KIB" =~ ^[0-9]+$ \
  && "$MEMORY_TOTAL_KIB" =~ ^[0-9]+$ \
  && "$SWAP_FREE_KIB" =~ ^[0-9]+$ \
  && "$SWAP_TOTAL_KIB" =~ ^[0-9]+$ ]] \
  || refuse "memory counters are malformed"

EFFECTIVE_AVAILABLE_KIB=$MEMORY_AVAILABLE_KIB
AVAILABILITY_SOURCE=host

apply_cgroup_limit() {
  local maximum_path=$1
  local current_path=$2
  local maximum current headroom_kib
  [[ -r "$maximum_path" && -r "$current_path" ]] || return 0
  maximum=$(tr -d '[:space:]' <"$maximum_path")
  current=$(tr -d '[:space:]' <"$current_path")
  [[ "$maximum" == max ]] && return 0
  [[ "$maximum" =~ ^[0-9]+$ && "$current" =~ ^[0-9]+$ ]] \
    || refuse "cgroup memory counters are malformed"
  if (( current >= maximum )); then
    headroom_kib=0
  else
    headroom_kib=$(( (maximum - current) / 1024 ))
  fi
  if (( headroom_kib < EFFECTIVE_AVAILABLE_KIB )); then
    EFFECTIVE_AVAILABLE_KIB=$headroom_kib
    AVAILABILITY_SOURCE=cgroup
  fi
}

apply_cgroup_limit \
  "$CGROUP_ROOT/memory.max" \
  "$CGROUP_ROOT/memory.current"
apply_cgroup_limit \
  "$CGROUP_ROOT/memory/memory.limit_in_bytes" \
  "$CGROUP_ROOT/memory/memory.usage_in_bytes"

MINIMUM_AVAILABLE_KIB=$(( MINIMUM_AVAILABLE_MIB * 1024 ))
if (( EFFECTIVE_AVAILABLE_KIB < MINIMUM_AVAILABLE_KIB )); then
  refuse "available memory is below ${MINIMUM_AVAILABLE_MIB} MiB (${AVAILABILITY_SOURCE}=$(( EFFECTIVE_AVAILABLE_KIB / 1024 )) MiB)"
fi

PROCESSOR_COUNT=${YACA_TEST_PROCESSOR_COUNT:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)}
[[ "$PROCESSOR_COUNT" =~ ^[0-9]+$ && "$PROCESSOR_COUNT" -ge 1 ]] \
  || refuse "online processor count is unavailable"
LOAD_ONE=$(awk 'NR == 1 { print $1 }' "$LOADAVG")
[[ "$LOAD_ONE" =~ ^[0-9]+([.][0-9]+)?$ ]] \
  || refuse "one-minute load average is malformed"
awk -v observed="$LOAD_ONE" -v cpus="$PROCESSOR_COUNT" \
  -v per_cpu="$MAXIMUM_LOAD_PER_CPU" \
  'BEGIN { exit(observed <= cpus * per_cpu ? 0 : 1) }' \
  || refuse "one-minute load $LOAD_ONE exceeds ${MAXIMUM_LOAD_PER_CPU} per CPU"

MEMORY_FULL_AVG10=unavailable
PRESSURE_PATH="$PROC_ROOT/pressure/memory"
if [[ -r "$PRESSURE_PATH" ]]; then
  MEMORY_FULL_AVG10=$(awk '
    $1 == "full" {
      for (field_number = 2; field_number <= NF; field_number++) {
        if ($field_number ~ /^avg10=/) {
          sub(/^avg10=/, "", $field_number)
          print $field_number
          exit
        }
      }
    }
  ' "$PRESSURE_PATH")
  [[ "$MEMORY_FULL_AVG10" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    || refuse "memory pressure counters are malformed"
  awk -v pressure="$MEMORY_FULL_AVG10" \
    -v maximum="$MAXIMUM_MEMORY_FULL_AVG10" \
    'BEGIN { exit(pressure <= maximum ? 0 : 1) }' \
    || refuse "memory full pressure avg10=$MEMORY_FULL_AVG10 exceeds $MAXIMUM_MEMORY_FULL_AVG10"
fi

echo "test resource preflight: PASS available_mib=$(( EFFECTIVE_AVAILABLE_KIB / 1024 )) source=$AVAILABILITY_SOURCE swap_free_mib=$(( SWAP_FREE_KIB / 1024 )) swap_total_mib=$(( SWAP_TOTAL_KIB / 1024 )) load_1m=$LOAD_ONE cpus=$PROCESSOR_COUNT memory_full_avg10=$MEMORY_FULL_AVG10"

exec "$@"

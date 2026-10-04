#!/usr/bin/env bash
# Run only on a disposable lab VM: generate-cpu.sh [seconds] [workers].
set -euo pipefail

duration=${1-420}
workers=${2-2}
if (( $# > 2 )) || [[ ! "$duration" =~ ^[1-9][0-9]{0,3}$ ]] ||
  [[ ! "$workers" =~ ^[1-9][0-9]?$ ]] || (( duration > 1800 || workers > 64 )); then
  echo "Usage: $0 [seconds: 1-1800] [workers: 1-64]" >&2
  exit 2
fi

pids=()
timer=""
cleanup() {
  local pid
  # Only stop the processes started by this invocation; never use killall.
  for pid in "${pids[@]}" "$timer"; do
    if [[ -n "$pid" ]]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for (( i = 0; i < workers; i++ )); do
  yes > /dev/null &
  pids+=("$!")
done
printf 'CPU load started for %s seconds with %s workers. It will stop automatically.\n' "$duration" "$workers"
sleep "$duration" &
timer=$!
wait "$timer"
timer=""
echo "CPU load finished."

#!/usr/bin/env bash
# Launch the three isolated HLS validations and retain each exit status.
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
names=(
  '2026-11-18_PV分离累加阶段'
  '2026-11-18_PV静态行状态映射'
  '2026-11-18_PV五组交错调度'
)

run_one() {
  local name="$1"
  cd "$root/$name" || return 90
  mkdir -p logs
  printf 'start=%s\n' "$(date --iso-8601=seconds)" > logs/runner.meta
  bash ./validate_candidate.sh > logs/runner.log 2>&1
  local status=$?
  printf '%s\n' "$status" > logs/validation.exitcode
  printf 'end=%s\nexit_code=%s\n' "$(date --iso-8601=seconds)" "$status" >> logs/runner.meta
  return "$status"
}

pids=()
for name in "${names[@]}"; do
  run_one "$name" &
  pids+=("$!")
done

failed=0
for pid in "${pids[@]}"; do
  wait "$pid" || failed=1
done
printf 'end=%s\nfailed=%s\n' "$(date --iso-8601=seconds)" "$failed" > "$root/run_all.done"
exit "$failed"

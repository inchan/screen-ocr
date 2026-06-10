#!/usr/bin/env bash
# Reproduces the orphaned-recognizer-children leak: start the persistent worker the way the
# app does, kill it the way the app does (SIGTERM via Process.terminate) and the hard way
# (SIGKILL), and count which of its recognizer-pool children survive.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="$ROOT/.venv-ocr/bin/python"

count_descendants() { # all live pythons whose ancestor chain includes $1
  local root="$1"
  ps -axo pid,ppid,command | awk -v root="$root" '
    $3 ~ /python/ { pid[$1] = $2 }
    END {
      for (p in pid) {
        anc = pid[p]
        while (anc in pid) { if (anc == root) { n++; break }; anc = pid[anc] }
        if (anc == root) continue
      }
      # simpler: count pythons whose direct or transitive parent is root
      n = 0
      for (p in pid) {
        anc = p
        while (anc != "" && anc != "0" && anc != "1") {
          anc = pid[anc]
          if (anc == root) { n++; break }
        }
      }
      print n
    }'
}

run_case() {
  local signal_name="$1"
  echo "=== case: kill -$signal_name worker ==="
  PYTHONPATH="$ROOT/sidecar" "$PY" -u -m screen_ocr_sidecar.worker \
    >/tmp/orphan-test-stdout.log 2>/tmp/orphan-test-stderr.log &
  local worker_pid=$!

  # Wait for the ready line (model load + pool spawn).
  for _ in $(seq 1 120); do
    grep -q '"event": "ready"' /tmp/orphan-test-stdout.log 2>/dev/null && break
    sleep 1
  done

  local before
  before="$(count_descendants "$worker_pid")"
  echo "descendants before kill: $before"

  kill "-$signal_name" "$worker_pid" 2>/dev/null
  sleep 6  # give any cleanup/watchdog time to run

  local leftover
  leftover="$(ps -axo pid,command | grep -c "[p]ython.*multiprocessing")"
  echo "leftover spawn children after kill -$signal_name: $leftover"

  # Cleanup any survivors so repeated runs stay honest.
  pkill -9 -f "multiprocessing.spawn" 2>/dev/null
  pkill -9 -f "screen_ocr_sidecar.worker" 2>/dev/null
  sleep 1
}

run_case TERM
run_case KILL

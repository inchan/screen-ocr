#!/usr/bin/env bash
# Reproduces the "Python quit unexpectedly" dialog on app quit: drive the worker through the
# same shutdown path the menubar Quit uses (stdin EOF -> pool terminate -> child exit) three
# times, then assert no recognizer child crashed (no new Python .ips crash reports) and no
# process outlived the worker.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PY="$ROOT/.venv-ocr/bin/python"
REPORTS="$HOME/Library/Logs/DiagnosticReports"

before_count="$(ls "$REPORTS" 2>/dev/null | grep -c '^Python-')"

for cycle in 1 2 3; do
  echo "=== quit cycle $cycle ==="
  mkfifo /tmp/quit-test-stdin.$$ 2>/dev/null
  PYTHONPATH="$ROOT/sidecar" "$PY" -u -m screen_ocr_sidecar.worker \
    </tmp/quit-test-stdin.$$ >/tmp/quit-test-stdout.log 2>/tmp/quit-test-stderr.log &
  worker_pid=$!
  exec 9>/tmp/quit-test-stdin.$$   # hold the write end open like the app does

  for _ in $(seq 1 120); do
    grep -q '"event": "ready"' /tmp/quit-test-stdout.log 2>/dev/null && break
    sleep 1
  done

  exec 9>&-                        # menubar quit: the app dies, stdin write end closes
  worker_alive="yes"
  for _ in $(seq 1 15); do
    if ! kill -0 "$worker_pid" 2>/dev/null; then worker_alive="no"; break; fi
    sleep 1
  done

  sleep 6                          # crash reporter + child watchdog (2s poll) settle time
  leftover="$(ps -axo command | grep -c "[p]ython.*spawn_main")"
  echo "worker still alive: $worker_alive, leftover spawn children: $leftover"
  rm -f /tmp/quit-test-stdin.$$
done

# Leave no strays behind for the next experiment.
pkill -9 -f "multiprocessing.spawn" 2>/dev/null
pkill -9 -f "screen_ocr_sidecar.worker" 2>/dev/null

sleep 5
after_count="$(ls "$REPORTS" 2>/dev/null | grep -c '^Python-')"
echo "new python crash reports: $((after_count - before_count))"

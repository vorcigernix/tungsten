#!/usr/bin/env bash
# Browser memory stability soak test.
#
# Launches Tungsten, drives its real tab UI with keyboard shortcuts, and checks
# that retained RSS after close/reopen cycles stays within a configurable
# budget. This is not a full Instruments leak run; it is a repeatable regression
# guard for obvious tab lifecycle leaks.
#
# Defaults: 10 tabs, 20 measured cycles after a warm-up cycle. Override with:
# TUNGSTEN_MEMORY_TABS, TUNGSTEN_MEMORY_CYCLES,
# TUNGSTEN_MEMORY_MAX_RETAINED_MB, TUNGSTEN_MEMORY_MAX_RETAINED_PCT, and
# TUNGSTEN_MEMORY_MAX_RETAINED_SLOPE_MB.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${TUNGSTEN_DERIVED_DATA:-/tmp/TungstenDerivedData}"
CONFIGURATION="${TUNGSTEN_MEMORY_CONFIGURATION:-Release}"
APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/Tungsten.app"
APP_BIN="${APP}/Contents/MacOS/Tungsten"
LOG="$(mktemp -t tungsten-memory-stability.XXXXXX.log)"

cleanup() {
  if [[ -n "${PID:-}" ]]; then
    terminate_app >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

terminate_app() {
  local expected_signal=0
  local status=0

  if [[ -z "${PID:-}" ]]; then
    return 0
  fi

  if kill -0 "$PID" 2>/dev/null; then
    osascript -e 'tell application id "dev.tungsten.browser" to quit' >/dev/null 2>&1 || {
      kill "$PID" 2>/dev/null || true
      expected_signal=1
    }

    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$PID" 2>/dev/null || break
      sleep 0.2
    done

    if kill -0 "$PID" 2>/dev/null; then
      kill -9 "$PID" 2>/dev/null || true
      expected_signal=1
    fi
  fi

  set +e
  wait "$PID"
  status=$?
  set -e
  PID=""

  if [[ $status -eq 0 ]]; then
    return 0
  fi

  if [[ $expected_signal -eq 1 && ( $status -eq 137 || $status -eq 143 ) ]]; then
    return 0
  fi

  echo "Tungsten exited unexpectedly during memory stability teardown (status ${status})."
  echo "--- launch log (last 80 lines) ---"
  tail -n 80 "$LOG" || true
  return 1
}

if python3 - <<'PY'
import json
import urllib.request

try:
    urllib.request.urlopen("http://127.0.0.1:9222/json/version", timeout=0.5).read()
except Exception:
    raise SystemExit(1)
raise SystemExit(0)
PY
then
  echo "CEF DevTools is already reachable on 127.0.0.1:9222."
  echo "Quit any running Tungsten instance before running this stability test."
  exit 1
fi

if [[ ! -x "$APP_BIN" ]]; then
  echo "${CONFIGURATION} build not found; building..."
  if [[ "$CONFIGURATION" == "Release" ]]; then
    "${ROOT_DIR}/scripts/build-release.sh" -quiet
  else
    "${ROOT_DIR}/scripts/build-debug.sh" -quiet
  fi
fi

TUNGSTEN_PERF_LOG=1 "$APP_BIN" >"$LOG" 2>&1 &
PID=$!

sleep 1.5
if ! kill -0 "$PID" 2>/dev/null; then
  echo "Tungsten exited before memory stability test could start."
  echo "--- log ---"
  cat "$LOG"
  exit 1
fi

TUNGSTEN_APP_PID="$PID" python3 "${ROOT_DIR}/Tests/browser_memory_stability.py"
RC=$?

if [[ $RC -eq 0 ]] && ! kill -0 "$PID" 2>/dev/null; then
  echo "Tungsten exited during memory stability test."
  RC=1
fi

if ! terminate_app; then
  RC=1
fi

if [[ $RC -eq 0 ]]; then
  TABS="${TUNGSTEN_MEMORY_TABS:-10}"
  CYCLES="${TUNGSTEN_MEMORY_CYCLES:-20}"
  EXPECTED_NAVIGATIONS=$(( (CYCLES + 1) * TABS ))
  EXPECTED_TAB_CREATES=$(( (CYCLES + 1) * (TABS > 1 ? TABS - 1 : 0) ))
  ACTUAL_NAVIGATIONS="$(grep -c 'tab.navigateSelected.start' "$LOG" || true)"
  ACTUAL_TAB_CREATES="$(grep -c 'tab.create' "$LOG" || true)"

  if (( ACTUAL_NAVIGATIONS < EXPECTED_NAVIGATIONS )); then
    echo "Expected at least ${EXPECTED_NAVIGATIONS} Tungsten address navigations, saw ${ACTUAL_NAVIGATIONS}."
    RC=1
  fi

  if (( ACTUAL_TAB_CREATES < EXPECTED_TAB_CREATES )); then
    echo "Expected at least ${EXPECTED_TAB_CREATES} Tungsten tab creations, saw ${ACTUAL_TAB_CREATES}."
    RC=1
  fi
fi

if [[ $RC -ne 0 ]]; then
  echo "--- launch log (last 80 lines) ---"
  tail -n 80 "$LOG" || true
fi

exit $RC

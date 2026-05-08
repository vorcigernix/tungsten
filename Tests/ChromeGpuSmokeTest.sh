#!/usr/bin/env bash
# chrome://gpu smoke test.
#
# Builds a Release Tungsten if needed, launches it headlessly enough that CEF
# initializes (no first-run UI is shown beyond the initial WindowGroup), then
# connects to the embedded DevTools endpoint and asserts that the Graphics
# Feature Status section reports hardware acceleration for the features that
# Tier 1 of our perf work targets.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${TUNGSTEN_DERIVED_DATA:-/tmp/TungstenDerivedData}"
APP="${DERIVED_DATA}/Build/Products/Release/Tungsten.app"
APP_BIN="${APP}/Contents/MacOS/Tungsten"
LOG="$(mktemp -t tungsten-gpu-smoke.XXXXXX.log)"

cleanup() {
  if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    # CEF needs a moment to tear down its helper processes
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$PID" 2>/dev/null || break
      sleep 0.2
    done
    kill -9 "$PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ ! -x "$APP_BIN" ]]; then
  echo "Release build not found; building..."
  "${ROOT_DIR}/scripts/build-release.sh" -quiet
fi

# Launch detached from the controlling terminal so signals reach only this
# process tree, redirect to log so chatty CEF init lines don't pollute the
# test output.
"$APP_BIN" >"$LOG" 2>&1 &
PID=$!

# Sanity: the process must still be alive after the dyld load phase.
sleep 1.5
if ! kill -0 "$PID" 2>/dev/null; then
  echo "Tungsten exited before DevTools came up."
  echo "--- log ---"
  cat "$LOG"
  exit 1
fi

python3 "${ROOT_DIR}/Tests/chrome_gpu_smoke.py"
RC=$?

if [[ $RC -ne 0 ]]; then
  echo "--- launch log (last 40 lines) ---"
  tail -n 40 "$LOG" || true
fi

exit $RC

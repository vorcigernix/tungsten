#!/usr/bin/env python3
"""
Browser memory stability soak test.

The shell wrapper launches Tungsten. This script drives the real app UI with
keyboard shortcuts:

1. Open N local file-backed pages in app tabs.
2. Close them.
3. Reopen the closed tabs.
4. Close them again.

After each phase it samples RSS for Tungsten and its CEF helper process tree.
The test catches large retained-memory regressions and slow steady growth after
realistic tab churn. It intentionally does not assert that RSS returns to the
exact baseline because Chromium keeps caches and renderer infrastructure alive
by design.
"""

import os
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

try:
    sys.stdout.reconfigure(line_buffering=True)
except AttributeError:
    pass

DEFAULT_TABS = 10
DEFAULT_CYCLES = 20
DEFAULT_ACTION_DELAY_SECONDS = 0.25
DEFAULT_SETTLE_SECONDS = 2.0
DEFAULT_MAX_RETAINED_MB = 250.0
DEFAULT_MAX_RETAINED_PCT = 25.0
DEFAULT_MAX_RETAINED_SLOPE_MB = 8.0


@dataclass
class MemorySample:
    label: str
    rss_kb: int
    process_count: int

    @property
    def rss_mb(self):
        return self.rss_kb / 1024.0


def env_int(name, fallback):
    raw = os.environ.get(name)
    if raw is None:
        return fallback
    try:
        value = int(raw)
    except ValueError:
        raise SystemExit(f"{name} must be an integer, got {raw!r}")
    if value <= 0:
        raise SystemExit(f"{name} must be positive, got {value}")
    return value


def env_float(name, fallback):
    raw = os.environ.get(name)
    if raw is None:
        return fallback
    try:
        value = float(raw)
    except ValueError:
        raise SystemExit(f"{name} must be a number, got {raw!r}")
    if value < 0:
        raise SystemExit(f"{name} must be non-negative, got {value}")
    return value


def process_rows():
    out = subprocess.check_output(
        ["ps", "-axo", "pid=,ppid=,rss=,command="],
        text=True,
    )
    rows = []
    for line in out.splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) < 4:
            continue
        try:
            pid = int(parts[0])
            ppid = int(parts[1])
            rss = int(parts[2])
        except ValueError:
            continue
        rows.append((pid, ppid, rss, parts[3]))
    return rows


def tungsten_process_ids(root_pid):
    rows = process_rows()
    by_parent = {}
    by_pid = {}
    for pid, ppid, rss, command in rows:
        by_pid[pid] = (pid, ppid, rss, command)
        by_parent.setdefault(ppid, []).append(pid)

    if root_pid not in by_pid:
        raise RuntimeError(f"Tungsten process {root_pid} is not running")

    wanted = set()
    stack = [root_pid]
    while stack:
        pid = stack.pop()
        if pid in wanted:
            continue
        wanted.add(pid)
        stack.extend(by_parent.get(pid, []))

    # CEF helpers are normally descendants, but include same-bundle helpers as
    # a fallback in case macOS reparents them during teardown.
    for pid, _, _, command in rows:
        if "/Tungsten Helper.app/Contents/MacOS/Tungsten Helper" in command:
            wanted.add(pid)

    return wanted, by_pid


def sample_memory(root_pid, label):
    pids, by_pid = tungsten_process_ids(root_pid)
    rss = sum(by_pid[pid][2] for pid in pids if pid in by_pid)
    return MemorySample(label=label, rss_kb=rss, process_count=len(pids))


def print_sample(sample):
    print(f"{sample.label:<22} {sample.rss_mb:8.1f} MB  processes={sample.process_count}")


def retained_slope_mb_per_cycle(samples):
    if len(samples) < 3:
        return 0.0

    xs = list(range(len(samples)))
    ys = [sample.rss_mb for sample in samples]
    x_mean = sum(xs) / len(xs)
    y_mean = sum(ys) / len(ys)
    denominator = sum((x - x_mean) ** 2 for x in xs)
    if denominator == 0:
        return 0.0
    numerator = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys))
    return numerator / denominator


def applescript_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def run_osascript(script, timeout=10):
    result = subprocess.run(
        ["osascript", "-e", script],
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    if result.returncode == 0:
        return

    stderr = result.stderr.strip()
    stdout = result.stdout.strip()
    detail = stderr or stdout or f"osascript exited {result.returncode}"
    raise RuntimeError(detail)


def ensure_ui_automation_available(root_pid):
    script = f"""
tell application "System Events"
  set appProcess to first application process whose unix id is {root_pid}
  set frontmost of appProcess to true
  keystroke "l" using {{command down}}
end tell
"""
    try:
        run_osascript(script)
    except RuntimeError as error:
        raise RuntimeError(
            "UI automation failed. Grant Accessibility permission to the "
            "terminal running this test, then rerun it. Underlying error: "
            f"{error}"
        )


def write_payload_pages(directory, count):
    urls = []
    for index in range(count):
        path = directory / f"stability-page-{index}.html"
        path.write_text(payload_html(index), encoding="utf-8")
        urls.append(path.resolve().as_uri())
    return urls


def payload_html(index):
    return f"""<!doctype html>
<meta charset="utf-8">
<title>Tungsten stability {index}</title>
<style>
body {{ font: 14px -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px; }}
.row {{ padding: 2px 0; border-bottom: 1px solid #ddd; }}
</style>
<h1>Stability page {index}</h1>
<canvas id="c" width="1200" height="800"></canvas>
<main id="rows"></main>
<script>
const retained = [];
for (let i = 0; i < 2200; i++) retained.push(`{index}-${{i}}-${{'x'.repeat(2048)}}`);
const rows = document.getElementById('rows');
for (let i = 0; i < 700; i++) {{
  const row = document.createElement('div');
  row.className = 'row';
  row.textContent = `Row ${{i}} ` + retained[i % retained.length];
  rows.appendChild(row);
}}
const ctx = document.getElementById('c').getContext('2d');
for (let i = 0; i < 900; i++) {{
  ctx.fillStyle = `hsl(${{(i * 17) % 360}} 70% 55%)`;
  ctx.fillRect((i * 37) % 1200, (i * 29) % 800, 72, 44);
}}
window.__TUNGSTEN_STABILITY_READY = true;
</script>
"""


def navigate_current_tab(root_pid, url, delay):
    script = f"""
tell application "System Events"
  set appProcess to first application process whose unix id is {root_pid}
  set frontmost of appProcess to true
  keystroke "l" using {{command down}}
  delay 0.05
  set the clipboard to {applescript_string(url)}
  keystroke "v" using {{command down}}
  key code 36
end tell
"""
    run_osascript(script)
    time.sleep(delay)


def open_pages(root_pid, urls, delay):
    for index, url in enumerate(urls):
        if index > 0:
            run_osascript(f"""
tell application "System Events"
  set appProcess to first application process whose unix id is {root_pid}
  set frontmost of appProcess to true
  keystroke "t" using {{command down}}
end tell
""")
            time.sleep(delay)
        navigate_current_tab(root_pid, url, delay)


def close_tabs(root_pid, count, delay):
    script = f"""
tell application "System Events"
  set appProcess to first application process whose unix id is {root_pid}
  set frontmost of appProcess to true
  repeat {count} times
    keystroke "w" using {{command down}}
    delay {delay}
  end repeat
end tell
"""
    run_osascript(script, timeout=max(10, count * (delay + 0.2)))


def reopen_closed_tabs(root_pid, count, delay):
    script = f"""
tell application "System Events"
  set appProcess to first application process whose unix id is {root_pid}
  set frontmost of appProcess to true
  repeat {count} times
    keystroke "t" using {{command down, shift down}}
    delay {delay}
  end repeat
end tell
"""
    run_osascript(script, timeout=max(10, count * (delay + 0.2)))


def churn(root_pid, urls, cycle, action_delay, settle_seconds):
    open_pages(root_pid, urls, action_delay)
    time.sleep(settle_seconds)
    open_sample = sample_memory(root_pid, f"cycle {cycle} open")

    close_tabs(root_pid, len(urls), action_delay)
    time.sleep(settle_seconds)
    close_sample = sample_memory(root_pid, f"cycle {cycle} close")

    reopen_closed_tabs(root_pid, len(urls), action_delay)
    time.sleep(settle_seconds)
    reopen_sample = sample_memory(root_pid, f"cycle {cycle} reopen")

    close_tabs(root_pid, len(urls), action_delay)
    time.sleep(settle_seconds)
    final_close_sample = sample_memory(root_pid, f"cycle {cycle} final")

    return open_sample, close_sample, reopen_sample, final_close_sample


def main():
    raw_pid = os.environ.get("TUNGSTEN_APP_PID")
    if not raw_pid:
        print("FAIL  TUNGSTEN_APP_PID is required")
        return 1

    root_pid = int(raw_pid)
    tabs = env_int("TUNGSTEN_MEMORY_TABS", DEFAULT_TABS)
    cycles = env_int("TUNGSTEN_MEMORY_CYCLES", DEFAULT_CYCLES)
    action_delay = env_float("TUNGSTEN_MEMORY_ACTION_DELAY_SECONDS", DEFAULT_ACTION_DELAY_SECONDS)
    settle_seconds = env_float("TUNGSTEN_MEMORY_SETTLE_SECONDS", DEFAULT_SETTLE_SECONDS)
    max_retained_mb = env_float("TUNGSTEN_MEMORY_MAX_RETAINED_MB", DEFAULT_MAX_RETAINED_MB)
    max_retained_pct = env_float("TUNGSTEN_MEMORY_MAX_RETAINED_PCT", DEFAULT_MAX_RETAINED_PCT)
    max_retained_slope_mb = env_float(
        "TUNGSTEN_MEMORY_MAX_RETAINED_SLOPE_MB",
        DEFAULT_MAX_RETAINED_SLOPE_MB
    )

    with tempfile.TemporaryDirectory(prefix="tungsten-memory-pages.") as tmp:
        urls = write_payload_pages(Path(tmp), tabs)

        print(f"Running memory stability test: tabs={tabs}, cycles={cycles}, pid={root_pid}")
        ensure_ui_automation_available(root_pid)
        print_sample(sample_memory(root_pid, "initial"))

        warm_samples = churn(root_pid, urls, 0, action_delay, settle_seconds)
        for sample in warm_samples:
            print_sample(sample)
        baseline = warm_samples[-1]
        retained_samples = [baseline]

        final = baseline
        peak_open = max(warm_samples, key=lambda sample: sample.rss_kb)
        for cycle in range(1, cycles + 1):
            samples = churn(root_pid, urls, cycle, action_delay, settle_seconds)
            for sample in samples:
                print_sample(sample)
            final = samples[-1]
            retained_samples.append(final)
            peak_open = max([peak_open, *samples], key=lambda sample: sample.rss_kb)

    retained_growth_mb = final.rss_mb - baseline.rss_mb
    retained_slope_mb = retained_slope_mb_per_cycle(retained_samples)
    allowed_growth_mb = max(max_retained_mb, baseline.rss_mb * (max_retained_pct / 100.0))

    print(f"Peak phase RSS:     {peak_open.rss_mb:.1f} MB")
    print(f"Retained growth:    {retained_growth_mb:.1f} MB")
    print(f"Retained trend:     {retained_slope_mb:.2f} MB/cycle")
    print(f"Allowed retention:  {allowed_growth_mb:.1f} MB")
    print(f"Allowed trend:      {max_retained_slope_mb:.2f} MB/cycle")

    if retained_growth_mb > allowed_growth_mb:
        print("FAIL  retained RSS grew beyond the configured memory budget")
        print("      adjust TUNGSTEN_MEMORY_MAX_RETAINED_MB/PCT only after validating with Instruments")
        return 1

    if retained_slope_mb > max_retained_slope_mb:
        print("FAIL  retained RSS is trending upward across close/reopen cycles")
        print("      adjust TUNGSTEN_MEMORY_MAX_RETAINED_SLOPE_MB only after validating with Instruments")
        return 1

    print("BrowserMemoryStabilityTests passed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except RuntimeError as error:
        print(f"FAIL  {error}")
        sys.exit(1)

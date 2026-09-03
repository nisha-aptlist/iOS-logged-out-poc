#!/usr/bin/env python3
"""Decide whether a UI test run actually passed.

Three separate things made a naive read of `xcodebuild` output untrustworthy on
this machine, all observed rather than assumed:

1. It emits SEVERAL "Executed N tests, with M failures" lines per run, and they
   can disagree. One run logged four passing test cases while every summary
   line read "Executed 2 tests". The LAST line is the authoritative one.
2. A run was seen reporting a suite PASSED having executed ZERO tests. So the
   count is asserted against a floor: a suite that silently runs a subset is
   worse than no suite, because it launders confidence.
3. The exit code lies. A run where every test passed still ended
   "** TEST FAILED **", because diagnostics collection cannot find `simctl`
   while `xcode-select -p` points at CommandLineTools.

A fourth reason was claimed here and has been WITHDRAWN, because it was
probably this same class of error one level up. `xcresulttool` appeared to
fail intermittently with "item missing for id" on bundles from runs that
succeeded — but a second reader got 10/10 clean reads on an uncontended
bundle, and every one of my failures happened while a concurrent `make uitest`
was doing `rm -rf` on the same fixed `BUNDLE_PATH` mid-read. That produces
exactly that error. The bundle is probably fine; my measurement was not.

The log is still what this script reads, because `>` truncation makes a
collision obvious rather than subtle, and reasons 1 to 3 above stand on their
own. Both paths are now unique per run, so a future reader can cross-check the
two sources instead of trusting either.
"""
import re
import sys

expected = int(sys.argv[1]) if len(sys.argv) > 1 else 5
log_path = sys.argv[2] if len(sys.argv) > 2 else ".build/uitest.log"

try:
    log = open(log_path, errors="replace").read()
except OSError:
    print(f"FAIL: no log at {log_path} — the run never started.")
    sys.exit(1)

runs = re.findall(r"Executed (\d+) tests?, with (\d+) failure", log)
if not runs:
    print("FAIL: no test summary in the log at all. Tail:")
    print("\n".join(log.splitlines()[-20:]))
    sys.exit(1)

if len({r for r in runs}) > 1:
    print(f"note: summary lines disagree {runs}; taking the last as authoritative")

total, failed = int(runs[-1][0]), int(runs[-1][1])
print(f"executed={total} failed={failed} (expected {expected} / 0)")

if total != expected:
    print(f"FAIL: expected {expected} tests, ran {total}.")
    print("A suite that silently runs fewer tests than it has is worse than no suite.")
    for line in re.findall(r"Test Case '.*' (?:passed|failed).*", log):
        print("  ", line)
    sys.exit(1)

if failed != 0:
    print(f"FAIL: {failed} failing:")
    for line in re.findall(r"Test Case '.*' failed.*", log):
        print("  ", line)
    for line in re.findall(r".*\.swift:\d+: error:.*", log):
        print("  ", line.strip())
    sys.exit(1)

print(f"UI TESTS OK: {total}/{total}")

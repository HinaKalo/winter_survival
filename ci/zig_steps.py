#!/usr/bin/env python3
"""Run `zig build`, then `zig build test --summary all`, and optionally the headless probe,
in the cwd (the project root, winter_survival).

  zig_steps.py --zig ZIG --log-dir DIR [--probe]

Logs go to --log-dir (build.log, unit.log, and with --probe: probe.log + probe.xml).
With --probe, `zig build probe -Dbackend=headless` runs the probe (audio on) and its PROBE lines are
converted to JUnit by probe_junit.py. Exits non-zero on any failure (infrastructure errors too).
"""
import argparse
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_junit  # noqa: E402

PROBE_ARGS = ["build", "probe", "-Dbackend=headless"]
STEP_TIMEOUT_S = 1800
TIMEOUT_RC = 124  # same convention as coreutils `timeout`


def _emit(text):
    """Echo text to stdout as UTF-8 where a binary stdout exists (replaced characters are tolerated)."""
    buf = getattr(sys.stdout, "buffer", None)
    if buf is not None:
        buf.write(text.encode("utf-8", "replace"))
    else:
        sys.stdout.write(text)
    sys.stdout.flush()


def step(zig, args, log, timeout=STEP_TIMEOUT_S):
    """Run `zig args...`, tee the output to `log`. Always writes the log, even on timeout or spawn failure.

    Returns the exit code; a timeout returns TIMEOUT_RC, a spawn failure returns 127.
    """
    print(">>> zig " + " ".join(args), flush=True)
    try:
        p = subprocess.run([zig] + args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        out = p.stdout.decode("utf-8", "replace")
        rc = p.returncode
    except subprocess.TimeoutExpired as e:
        partial = e.stdout or b""
        out = partial.decode("utf-8", "replace") if isinstance(partial, bytes) else str(partial)
        out += "\nTIMEOUT after %d s\n" % timeout
        rc = TIMEOUT_RC
    except OSError as e:
        out = "ERROR: cannot run %s: %s\n" % (zig, e)
        rc = 127
    with open(log, "w", encoding="utf-8") as f:
        f.write(out)
    _emit(out)
    return rc


def run_probe(zig, log_dir, timeout=STEP_TIMEOUT_S):
    """Run the headless probe, then convert its log to probe.xml. Returns 0 only if both succeed.

    probe.log and probe.xml are written even when the probe times out or cannot start; an incomplete log
    becomes a failing "probe output" testcase in probe.xml.
    """
    log = os.path.join(log_dir, "probe.log")
    xml = os.path.join(log_dir, "probe.xml")
    rc = step(zig, PROBE_ARGS, log, timeout)
    conv = probe_junit.convert(log, xml)
    if rc != 0:
        print("FAIL: zig build probe exited %d" % rc, file=sys.stderr)
    if conv != 0:
        print("FAIL: probe run incomplete or unusable (see %s)" % xml, file=sys.stderr)
    return 0 if rc == 0 and conv == 0 else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zig", required=True)
    ap.add_argument("--log-dir", required=True)
    ap.add_argument("--probe", action="store_true", help="also run `zig build probe -Dbackend=headless`")
    a = ap.parse_args()
    if not os.path.isfile(a.zig):
        print("ERROR: zig not found: %s" % a.zig, file=sys.stderr)
        return 2
    if not os.path.isfile("build.zig"):
        print("ERROR: build.zig not in cwd; run from the project root (winter_survival)", file=sys.stderr)
        return 2
    os.makedirs(a.log_dir, exist_ok=True)
    rc = step(a.zig, ["build"], os.path.join(a.log_dir, "build.log"))
    if rc != 0:
        print("FAIL: zig build exited %d" % rc, file=sys.stderr)
        return 1
    rc = step(a.zig, ["build", "test", "--summary", "all"], os.path.join(a.log_dir, "unit.log"))
    if rc != 0:
        print("FAIL: zig build test exited %d" % rc, file=sys.stderr)
        return 1
    if a.probe and run_probe(a.zig, a.log_dir) != 0:
        return 1
    print("OK: build and unit tests passed" + (", probe passed" if a.probe else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())

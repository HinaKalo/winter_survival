#!/usr/bin/env python3
"""Windows-side steps of the verify pipeline (stdlib only), run from the project root.

  verify_steps.py --zig ZIG --log-dir DIR [--profile quick|full] [--probes LIST] [--balance-days N]

Runs, collecting failures instead of stopping at the first one:
  zig build test; zig build luatest -Dbackend=headless (if build.zig has the step);
  one `zig build probe -Dbackend=headless -Dprobe=FILE` per selected probe (-> probe_<name>.log/.xml via
  probe_junit); `zig build balance` (full profile, only if build.zig has the step).
Each plain step writes <step>.log and <step>.xml (one JUnit testcase). Exit 1 if anything failed.
Before every verdict (pass or fail), copies the balance report and fixtures into the log dir via
collect_outputs: out/balance/report.json -> balance/report.json, tests/fixtures/*.sav and
tests/fixtures/manifest.lua -> fixtures/ (missing sources are skipped).
"""
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_junit  # noqa: E402
import zig_steps  # noqa: E402

QUICK_SKIP = {"soak_heap.lua"}  # 30 s memory soak; full profile only
DEFAULT_PROBES = "tests/probe/*.lua"


def has_step(build_zig_text, name):
    return re.search(r'\.step\(\s*"%s"' % re.escape(name), build_zig_text) is not None


def select_probes(spec, profile, root="."):
    """Expand a glob/list spec (separated by newlines, commas or spaces) into sorted probe paths
    (forward slashes, relative to root). The quick profile drops QUICK_SKIP."""
    pats = [p for p in re.split(r"[\s,]+", spec or "") if p] or [DEFAULT_PROBES]
    found = []
    for p in pats:
        hits = sorted(glob.glob(os.path.join(root, p)))
        if not hits:
            if any(c in p for c in "*?["):
                raise ValueError("probe pattern matches no files: %s" % p)
            hits = [os.path.join(root, p)]  # explicit file: let the step fail loudly if missing
        for h in hits:
            rel = os.path.relpath(h, root).replace(os.sep, "/")
            if rel not in found:
                found.append(rel)
    if profile == "quick":
        found = [f for f in found if os.path.basename(f) not in QUICK_SKIP]
    if not found:
        raise ValueError("no probes selected (spec=%r, profile=%s)" % (spec or DEFAULT_PROBES, profile))
    return found


def collect_outputs(root, log_dir):
    """Copy the balance report and fixtures from root into log_dir (byte-for-byte, missing sources
    skipped). Returns the copied paths relative to log_dir (forward slashes, sorted)."""
    fx = os.path.join(root, "tests", "fixtures")
    pairs = [(os.path.join(root, "out", "balance", "report.json"), "balance/report.json")]
    for src in sorted(glob.glob(os.path.join(glob.escape(fx), "*.sav"))):
        pairs.append((src, "fixtures/" + os.path.basename(src)))
    pairs.append((os.path.join(fx, "manifest.lua"), "fixtures/manifest.lua"))
    copied = []
    for src, rel in pairs:
        if not os.path.isfile(src):
            continue
        dst = os.path.join(log_dir, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)
        copied.append(rel)
    return sorted(copied)


def _collect_and_report(log_dir):
    got = collect_outputs(".", log_dir)
    print("collected: %s" % (", ".join(got) or "(none)"), flush=True)


def write_step_junit(path, suite, name, seconds, rc, log_tail):
    root = ET.Element("testsuites")
    s = ET.SubElement(root, "testsuite", name=suite, tests="1", failures="1" if rc else "0",
                      errors="0", skipped="0", time="%.2f" % seconds)
    tc = ET.SubElement(s, "testcase", classname=suite, name=name, time="%.2f" % seconds)
    if rc:
        f = ET.SubElement(tc, "failure", message="%s exited %d" % (name, rc))
        f.text = probe_junit._xml_safe(log_tail[-4000:])
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def run_plain(zig, args, log_dir, key, suite, name):
    log = os.path.join(log_dir, key + ".log")
    t0 = time.time()
    rc = zig_steps.step(zig, args, log)
    el = time.time() - t0
    try:
        tail = open(log, encoding="utf-8", errors="replace").read()
    except OSError:
        tail = ""
    write_step_junit(os.path.join(log_dir, key + ".xml"), suite, name, el, rc, tail)
    return rc


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--zig", required=True)
    ap.add_argument("--log-dir", required=True)
    ap.add_argument("--profile", choices=("quick", "full"), default="full")
    ap.add_argument("--probes", default="")
    ap.add_argument("--probes-file", help="read the probe list from this file (overrides --probes)")
    ap.add_argument("--balance-days", default="30")
    a = ap.parse_args(argv)
    if not os.path.isfile(a.zig):
        print("ERROR: zig not found: %s" % a.zig, file=sys.stderr)
        return 2
    if not os.path.isfile("build.zig"):
        print("ERROR: build.zig not in cwd", file=sys.stderr)
        return 2
    os.makedirs(a.log_dir, exist_ok=True)
    if a.probes_file and os.path.isfile(a.probes_file):
        a.probes = open(a.probes_file, encoding="utf-8-sig").read()
    bz = open("build.zig", encoding="utf-8").read()
    failures = []

    if run_plain(a.zig, ["build", "test", "--summary", "all"], a.log_dir, "unit", "zig-unit", "zig build test"):
        failures.append("zig build test")
    if has_step(bz, "luatest"):
        if run_plain(a.zig, ["build", "luatest", "-Dbackend=headless"], a.log_dir, "luatest", "luatest",
                     "zig build luatest"):
            failures.append("luatest")
    else:
        print("NOTE: build.zig has no luatest step, skipped")

    try:
        probes = select_probes(a.probes, a.profile)
    except ValueError as e:
        print("VERIFY FAILED: probe selection: %s" % e)
        write_step_junit(os.path.join(a.log_dir, "probe_selection.xml"), "probe_selection",
                         "select probes", 0.0, 1, str(e))
        _collect_and_report(a.log_dir)
        return 1
    print("probes (%s): %s" % (a.profile, ", ".join(probes) or "(none)"), flush=True)
    for p in probes:
        key = "probe_" + os.path.splitext(os.path.basename(p))[0]
        log = os.path.join(a.log_dir, key + ".log")
        rc = zig_steps.step(a.zig, ["build", "probe", "-Dbackend=headless", "-Dprobe=" + p], log)
        conv = probe_junit.convert(log, os.path.join(a.log_dir, key + ".xml"), suite=key)
        if rc != 0 or conv != 0:
            failures.append("probe " + p)

    if a.profile == "full" and has_step(bz, "balance"):
        bargs = ["build", "balance", "-Dbackend=headless"]
        if re.search(r'\.option\([^)]*"days"', bz):  # pass the day count only if the step takes it
            bargs.append("-Ddays=" + str(a.balance_days))
        if run_plain(a.zig, bargs, a.log_dir, "balance", "balance", "zig build balance"):
            failures.append("balance")

    _collect_and_report(a.log_dir)
    if failures:
        print("VERIFY FAILED: " + "; ".join(failures))
        return 1
    print("VERIFY OK (%d probes)" % len(probes))
    return 0


if __name__ == "__main__":
    sys.exit(main())

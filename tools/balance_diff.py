#!/usr/bin/env python3
"""Compare a balance report with a baseline (P0-PLAN §1.3).

  balance_diff.py BASELINE REPORT [--exact]

Default: compare the "balance summary" = report without any `checksum` field and without
determinism.a/.b (the run checksums); determinism.ok must be true in REPORT.
--exact: byte-for-byte comparison (P0-2 phase A, P0-4 C7 move).
Exit 0 if equal, 1 if different (prints the differing paths), 2 on usage/IO errors.
Typical REPORT: /tmp/claude-1000/ci-verify-<name>/windows/balance/report.json
"""
import json
import sys


def summary(obj):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if k == "checksum":
                continue
            out[k] = summary(v)
        return out
    if isinstance(obj, list):
        return [summary(v) for v in obj]
    return obj


def strip(report):
    s = summary(report)
    det = s.get("determinism")
    if isinstance(det, dict):
        s["determinism"] = {"ok": det.get("ok")}
    return s


def diff_paths(a, b, path="$"):
    if type(a) is not type(b):
        return [path]
    if isinstance(a, dict):
        out = []
        for k in sorted(set(a) | set(b)):
            if k not in a or k not in b:
                out.append("%s.%s" % (path, k))
            else:
                out += diff_paths(a[k], b[k], "%s.%s" % (path, k))
        return out
    if isinstance(a, list):
        if len(a) != len(b):
            return [path + "[len]"]
        out = []
        for i, (x, y) in enumerate(zip(a, b)):
            out += diff_paths(x, y, "%s[%d]" % (path, i))
        return out
    return [] if a == b else [path]


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    exact = "--exact" in argv
    args = [a for a in argv if a != "--exact"]
    if len(args) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        raw = [open(p, "rb").read() for p in args]
        rep = [json.loads(r.decode("utf-8")) for r in raw]
    except (OSError, ValueError) as e:
        print("balance_diff: %s" % e, file=sys.stderr)
        return 2
    if exact:
        if raw[0] == raw[1]:
            print("balance_diff: identical (exact)")
            return 0
        print("balance_diff: DIFFERENT (exact): " + ", ".join(diff_paths(rep[0], rep[1]) or ["(whitespace/format)"]))
        return 1
    if not (isinstance(rep[1].get("determinism"), dict) and rep[1]["determinism"].get("ok") is True):
        print("balance_diff: determinism.ok is not true in %s" % args[1])
        return 1
    d = diff_paths(strip(rep[0]), strip(rep[1]))
    if d:
        print("balance_diff: DIFFERENT (summary): " + ", ".join(d))
        return 1
    print("balance_diff: summary identical")
    return 0


if __name__ == "__main__":
    sys.exit(main())

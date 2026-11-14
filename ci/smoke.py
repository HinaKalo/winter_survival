#!/usr/bin/env python3
"""Cross-platform smoke test for the Delve starter game (same file on Linux and Windows).

Launches the exe with ISO_AUTOQUIT=<seconds>, captures stdout+stderr to a log, takes a
screenshot at --shot-at seconds (archived for human review, not analysed), checks exit code 0
and that the log has no panic/error/leak. Prints PASS/FAIL lines; exit 1 on any failure.
Linux screenshot: ImageMagick `import -window root` (needs DISPLAY, e.g. under xvfb-run).
Windows screenshot: window named by --title via ctypes + PIL.ImageGrab (falls back to full screen).
Python 3.10+ ; stdlib + Pillow only.
"""
import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET


DEFAULT_TITLE = "Thirty Below"
BAD_LOG_RE = re.compile(r"panic|error\(|lua error|leak|segmentation fault|unreachable", re.I)
# Known harmless lines (regexes, case-insensitive); a line matching any is ignored by the log check.
LOG_WHITELIST = [
    r"\bDPI\b",
]


# ---------------------------------------------------------------- pure helpers (unit-testable)
def scan_log(text, whitelist=None, bad_re=BAD_LOG_RE):
    """Return the list of offending log lines (matching bad_re and not whitelisted)."""
    wl = [re.compile(p, re.I) for p in (LOG_WHITELIST if whitelist is None else whitelist)]
    bad = []
    for line in text.splitlines():
        if bad_re.search(line) and not any(w.search(line) for w in wl):
            bad.append(line)
    return bad


def window_bbox(rect):
    """Convert a Win32 RECT (l, t, r, b) into a usable bbox, or None if degenerate
    (minimized windows report tiny / off-screen rects)."""
    l, t, r, b = rect
    if r - l < 16 or b - t < 16 or r <= -30000 or b <= -30000:  # -32000 = minimized window
        return None
    return (l, t, r, b)


def parse_env_pairs(pairs):
    """['A=1', 'B=x=y'] -> {'A': '1', 'B': 'x=y'}; raises ValueError on a malformed pair."""
    out = {}
    for p in pairs or []:
        k, sep, v = p.partition("=")
        if not sep or not k.strip():
            raise ValueError("bad env pair %r (expected KEY=VAL)" % p)
        out[k.strip()] = v
    return out


def safe_name(name):
    """File-system safe shot name."""
    n = re.sub(r"[^A-Za-z0-9_.-]+", "_", name.strip()).strip("._")
    return n or "shot"


def parse_shots(text):
    """Parse a shots file. One shot per line: `name|KEY=VAL KEY2=VAL2|extra game args`.
    Blank lines and lines starting with # are ignored; the env and args fields are optional.
    Returns a list of dicts {name, env, args}. Raises ValueError on a malformed line or duplicate name."""
    shots, seen = [], set()
    for i, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|", 2)
        name = safe_name(parts[0])
        if not parts[0].strip():
            raise ValueError("line %d: empty shot name" % i)
        if name.lower() in seen:
            raise ValueError("line %d: duplicate shot name %r" % (i, name))
        seen.add(name.lower())
        env_field = parts[1] if len(parts) > 1 else ""
        args_field = parts[2] if len(parts) > 2 else ""
        try:
            env = parse_env_pairs(shlex.split(env_field))
        except ValueError as e:
            raise ValueError("line %d: %s" % (i, e))
        shots.append({"name": name, "env": env, "args": shlex.split(args_field)})
    return shots


def write_settings(save_dir, lang):
    """Pre-write settings.sav so the game starts in `lang` (same format as core/save.lua)."""
    os.makedirs(save_dir, exist_ok=True)
    with open(os.path.join(save_dir, "settings.sav"), "w", encoding="utf-8", newline="\n") as f:
        f.write('return { version = 1, lang = "%s" }\n' % lang)


# ---------------------------------------------------------------- screenshot back ends
def _find_window_rect_win32(title):
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.windll.user32
    try:
        user32.SetProcessDPIAware()  # physical pixels so the rect matches ImageGrab
    except Exception:  # noqa: BLE001
        pass
    user32.FindWindowW.restype = wintypes.HWND
    user32.FindWindowW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR]
    hwnd = user32.FindWindowW(None, title)
    if not hwnd:
        return None
    rect = wintypes.RECT()
    if not user32.GetWindowRect(hwnd, ctypes.byref(rect)):
        return None
    return window_bbox((rect.left, rect.top, rect.right, rect.bottom))


def _is_blank(img):
    """True if every channel is (near) black - what PrintWindow returns when it cannot capture."""
    return all(hi < 8 for _, hi in img.convert("RGB").getextrema())


def _printwindow_capture_win32(hwnd):
    """Render the window's client area via PrintWindow(PW_RENDERFULLCONTENT): works even when the
    window is covered by other windows (e.g. a remote-desktop viewer). Returns a PIL image or None."""
    import ctypes
    from ctypes import wintypes
    from PIL import Image
    user32, gdi32 = ctypes.windll.user32, ctypes.windll.gdi32
    user32.GetDC.restype = wintypes.HDC
    user32.GetDC.argtypes = [wintypes.HWND]
    user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
    user32.PrintWindow.argtypes = [wintypes.HWND, wintypes.HDC, wintypes.UINT]
    gdi32.CreateCompatibleDC.restype = wintypes.HDC
    gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
    gdi32.CreateCompatibleBitmap.restype = wintypes.HBITMAP
    gdi32.CreateCompatibleBitmap.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int]
    gdi32.SelectObject.restype = wintypes.HGDIOBJ
    gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
    gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]
    gdi32.DeleteDC.argtypes = [wintypes.HDC]

    class BITMAPINFOHEADER(ctypes.Structure):
        _fields_ = [("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG), ("biHeight", wintypes.LONG),
                    ("biPlanes", wintypes.WORD), ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                    ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", wintypes.LONG),
                    ("biYPelsPerMeter", wintypes.LONG), ("biClrUsed", wintypes.DWORD), ("biClrImportant", wintypes.DWORD)]

    gdi32.GetDIBits.argtypes = [wintypes.HDC, wintypes.HBITMAP, wintypes.UINT, wintypes.UINT,
                                ctypes.c_void_p, ctypes.c_void_p, wintypes.UINT]
    rc = wintypes.RECT()
    if not user32.GetClientRect(hwnd, ctypes.byref(rc)):
        return None
    w, h = rc.right - rc.left, rc.bottom - rc.top
    if w < 16 or h < 16:
        return None
    hdc = user32.GetDC(hwnd)
    mdc = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    old = gdi32.SelectObject(mdc, bmp)
    try:
        PW_CLIENTONLY, PW_RENDERFULLCONTENT = 0x1, 0x2
        if not user32.PrintWindow(hwnd, mdc, PW_CLIENTONLY | PW_RENDERFULLCONTENT):
            return None
        bih = BITMAPINFOHEADER()
        bih.biSize = ctypes.sizeof(BITMAPINFOHEADER)
        bih.biWidth, bih.biHeight = w, -h  # negative height = top-down rows
        bih.biPlanes, bih.biBitCount, bih.biCompression = 1, 32, 0  # BI_RGB
        buf = ctypes.create_string_buffer(w * h * 4)
        if gdi32.GetDIBits(mdc, bmp, 0, h, buf, ctypes.byref(bih), 0) != h:  # DIB_RGB_COLORS
            return None
        return Image.frombuffer("RGB", (w, h), buf.raw, "raw", "BGRX", 0, 1)
    finally:
        gdi32.SelectObject(mdc, old)
        gdi32.DeleteObject(bmp)
        gdi32.DeleteDC(mdc)
        user32.ReleaseDC(hwnd, hdc)


def _topmost_grab_win32(hwnd, bbox):
    """Fallback: temporarily make the window topmost so screen pixels in bbox are really ours."""
    import ctypes
    import time
    from ctypes import wintypes
    from PIL import ImageGrab
    user32 = ctypes.windll.user32
    user32.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int,
                                    ctypes.c_int, ctypes.c_int, wintypes.UINT]
    HWND_TOPMOST, HWND_NOTOPMOST = wintypes.HWND(-1), wintypes.HWND(-2)
    flags = 0x0001 | 0x0002 | 0x0040  # SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW
    user32.SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, flags)
    try:
        time.sleep(0.5)  # let the compositor present a frame on top
        try:
            return ImageGrab.grab(bbox=bbox, all_screens=True)
        except TypeError:  # old Pillow without all_screens
            return ImageGrab.grab(bbox=bbox)
    finally:
        user32.SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, flags)


def take_screenshot(path, title=DEFAULT_TITLE):
    """Take a screenshot to `path` (Windows: window titled `title`). Returns None on success or an error string."""
    d = os.path.dirname(os.path.abspath(path))
    if not os.path.isdir(d):
        os.makedirs(d)
    if sys.platform == "win32":
        try:
            import ctypes
            from ctypes import wintypes
            from PIL import ImageGrab
            bbox = _find_window_rect_win32(title)  # also sets DPI awareness
            user32 = ctypes.windll.user32
            user32.FindWindowW.restype = wintypes.HWND
            user32.FindWindowW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR]
            hwnd = user32.FindWindowW(None, title)
            img, method = None, None
            if hwnd:
                img = _printwindow_capture_win32(hwnd)
                method = "PrintWindow"
                if img is None or _is_blank(img):
                    if bbox is not None:
                        img, method = _topmost_grab_win32(hwnd, bbox), "topmost+ImageGrab"
            if img is None:
                print("smoke: window %r not found, grabbing full screen" % title)
                try:
                    img = ImageGrab.grab(all_screens=True)
                except TypeError:
                    img = ImageGrab.grab()
                method = "full screen"
            print("smoke: screenshot via %s, size %dx%d" % (method, img.size[0], img.size[1]))
            img.save(path)
            return None
        except Exception as e:  # noqa: BLE001
            return "screenshot failed: %r" % (e,)
    try:
        r = subprocess.run(["import", "-window", "root", path], stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, timeout=30)
        if r.returncode != 0:
            return "import exited %d: %s" % (r.returncode, r.stdout.decode("utf-8", "replace")[:500])
        return None
    except Exception as e:  # noqa: BLE001
        return "screenshot failed: %r" % (e,)


# ---------------------------------------------------------------- main run
def run_game(exe, cwd, seconds, shot_at, shot, log, timeout, title=DEFAULT_TITLE, extra_env=None, game_args=None):
    """Returns (launch_failure_or_None, exit_code_or_None, screenshot_error_or_None, elapsed)."""
    env = dict(os.environ)
    env.update(extra_env or {})
    env["ISO_AUTOQUIT"] = str(seconds)
    t0 = time.time()
    shot_err = "screenshot not attempted (process did not run long enough)"
    d = os.path.dirname(os.path.abspath(log))
    if not os.path.isdir(d):
        os.makedirs(d)
    with open(log, "wb") as lf:
        try:
            proc = subprocess.Popen([exe] + list(game_args or []), cwd=cwd, env=env, stdout=lf, stderr=subprocess.STDOUT)
        except (OSError, ValueError) as e:
            return "cannot launch %s: %s" % (exe, e), None, "game did not start", time.time() - t0
        shot_done = False
        while True:
            rc = proc.poll()
            el = time.time() - t0
            if rc is not None:
                break
            if not shot_done and el >= shot_at:
                shot_err = take_screenshot(shot, title)
                shot_done = True
                continue
            if el >= timeout:
                proc.kill()
                proc.wait()
                return ("timeout: still running after %ds (killed)" % timeout, None, shot_err, time.time() - t0)
            time.sleep(0.1)
    fail = None if rc == 0 else "exit code %d (expected 0)" % rc
    return fail, rc, shot_err, time.time() - t0


def build_parser():
    ap = argparse.ArgumentParser(description="Smoke-test the game exe: launch, log scan, screenshot.")
    ap.add_argument("--exe", required=True)
    ap.add_argument("--cwd", default=".")
    ap.add_argument("--title", default=DEFAULT_TITLE,
                    help="window title to screenshot on Windows (default: %(default)r)")
    ap.add_argument("--seconds", type=float, default=6)
    ap.add_argument("--shot-at", type=float, default=3)
    ap.add_argument("--shot", help="screenshot path (single mode)")
    ap.add_argument("--log", help="game log path (single mode)")
    ap.add_argument("--timeout", type=float, default=60)
    ap.add_argument("--env", action="append", default=[], metavar="KEY=VAL",
                    help="extra environment variable for the game (repeatable)")
    ap.add_argument("--save-dir", help="pass --save-dir DIR to the game (isolated saves)")
    ap.add_argument("--lang", help="pre-write DIR/settings.sav with this language (needs --save-dir, "
                                   "or a temp dir is used)")
    ap.add_argument("--args", default="", help="extra game arguments, shell-style string")
    ap.add_argument("--shots-file", help="batch mode: file with lines `name|KEY=VAL ...|extra args`; "
                                         "needs --out-dir (writes <name>.png and <name>.log there)")
    ap.add_argument("--out-dir", help="batch mode output directory")
    ap.add_argument("--junit", help="batch mode: write a JUnit XML with one testcase per shot")
    ap.add_argument("--default-lang", default="zh", help="batch mode language when a shot has no WS_LANG")
    return ap


def smoke_one(a, shot, log, env, game_args, save_dir, lang):
    """Run one smoke pass; returns (list of (name, err) results, log_text)."""
    if lang:
        if not save_dir:
            save_dir = tempfile.mkdtemp(prefix="smoke-saves-")
        write_settings(save_dir, lang)
    gargs = list(game_args)
    if save_dir:
        gargs = ["--save-dir", save_dir] + gargs
    if os.path.exists(shot):
        os.remove(shot)
    extra = {}  # only passed when used, so the legacy call shape (and test doubles for it) stays valid
    if env:
        extra["extra_env"] = env
    if gargs:
        extra["game_args"] = gargs
    launch_fail, rc, shot_err, el = run_game(a.exe, a.cwd, a.seconds, a.shot_at, shot, log, a.timeout,
                                             title=a.title, **extra)
    log_text = ""
    if os.path.isfile(log):
        with open(log, "r", encoding="utf-8", errors="replace") as f:
            log_text = f.read()
    bad = scan_log(log_text)
    results = [
        ("launch & exit code == 0", launch_fail),
        ("no error/panic/leak in log", None if not bad else "%d suspicious line(s):\n%s" % (len(bad), "\n".join(bad[:30]))),
        ("screenshot taken", shot_err or (None if os.path.isfile(shot) and os.path.getsize(shot) > 0 else "screenshot file missing")),
    ]
    return results, log_text, el


def report(results, log_text):
    failed = 0
    for name, err in results:
        print("%s %s" % ("FAIL" if err else "PASS", name))
        if err:
            failed += 1
            print("    " + err.replace("\n", "\n    ")[:1500])
    if failed:
        print("--- log tail ---\n" + log_text[-3000:])
    return failed


_XML_BAD = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\ufffe\uffff]")


def _xml_safe(s):
    return _XML_BAD.sub("", s)


def write_shots_junit(path, cases):
    """cases: list of (name, seconds, error_or_None)."""
    fails = sum(1 for c in cases if c[2])
    root = ET.Element("testsuites")
    suite = ET.SubElement(root, "testsuite", name="shots", tests=str(len(cases)), failures=str(fails),
                          errors="0", skipped="0", time="%.2f" % sum(c[1] for c in cases))
    for name, secs, err in cases:
        tc = ET.SubElement(suite, "testcase", classname="shots", name=name, time="%.2f" % secs)
        if err:
            f = ET.SubElement(tc, "failure", message=_xml_safe(err.splitlines()[0][:200]) if err.strip() else "failed")
            f.text = _xml_safe(err[:4000])
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def run_batch(a):
    try:
        with open(a.shots_file, "r", encoding="utf-8") as f:
            shots = parse_shots(f.read())
    except (OSError, ValueError) as e:
        print("FAIL shots file: %s" % e)
        return 2
    if not a.out_dir:
        print("FAIL --shots-file needs --out-dir")
        return 2
    os.makedirs(a.out_dir, exist_ok=True)
    base_env = parse_env_pairs(a.env)
    base_args = shlex.split(a.args)
    saves_root = tempfile.mkdtemp(prefix="smoke-saves-")
    cases, failed = [], 0
    for s in shots:
        name = s["name"]
        print("=== shot %s env=%s args=%s" % (name, s["env"], s["args"]), flush=True)
        env = dict(base_env)
        env.update(s["env"])
        lang = env.get("WS_LANG") or a.default_lang
        save_dir = os.path.join(saves_root, name)
        shot = os.path.join(a.out_dir, name + ".png")
        log = os.path.join(a.out_dir, name + ".log")
        try:
            results, log_text, el = smoke_one(a, shot, log, env, base_args + s["args"], save_dir, lang)
        except Exception as e:  # noqa: BLE001 - one bad shot must not hide the others
            results, log_text, el = [("smoke run", "exception: %r" % (e,))], "", 0.0
        n = report(results, log_text)
        failed += 1 if n else 0
        err = "\n".join("%s: %s" % (nm, er) for nm, er in results if er) or None
        cases.append((name, el, err))
    if a.junit:
        write_shots_junit(a.junit, cases)
    shutil.rmtree(saves_root, ignore_errors=True)
    print("shots: %d run, %d failed" % (len(cases), failed))
    return 1 if failed else 0


def main(argv=None):
    ap = build_parser()
    a = ap.parse_args(argv)
    if a.shots_file:
        return run_batch(a)
    if not a.shot or not a.log:
        ap.error("--shot and --log are required (unless --shots-file is used)")
    try:
        env = parse_env_pairs(a.env)
    except ValueError as e:
        ap.error(str(e))
    results, log_text, _ = smoke_one(a, a.shot, a.log, env, shlex.split(a.args), a.save_dir, a.lang)
    return 1 if report(results, log_text) else 0


if __name__ == "__main__":
    sys.exit(main())

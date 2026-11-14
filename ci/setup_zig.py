#!/usr/bin/env python3
"""Install Zig 0.16.0 into --dest (idempotent, stdlib only, Windows + Linux).

  setup_zig.py --dest <dir>

Skips if <dest>/zig[.exe] already reports version 0.16.0. Otherwise downloads to a temp file,
verifies sha256, extracts (zip or tar.xz), strips the archive's top-level directory and
renames it atomically to <dest>. Any failure prints "ERROR: ..." to stderr and exits non-zero.
"""
import argparse
import hashlib
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

VERSION = "0.16.0"
BASE = "https://ziglang.org/download/%s/" % VERSION
# (os, arch) -> (file name, sha256)
PACKAGES = {
    ("windows", "x86_64"): ("zig-x86_64-windows-%s.zip" % VERSION,
                            "68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e"),
    ("linux", "x86_64"): ("zig-x86_64-linux-%s.tar.xz" % VERSION,
                          "70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00"),
}


class SetupError(Exception):
    pass


def select_package(plat=None, machine=None):
    """Return (url, filename, sha256) for the given sys.platform / platform.machine()."""
    plat = sys.platform if plat is None else plat
    machine = platform.machine() if machine is None else machine
    os_name = "windows" if plat.startswith("win") else "linux" if plat.startswith("linux") else plat
    arch = {"amd64": "x86_64", "x86_64": "x86_64", "x64": "x86_64"}.get(machine.lower(), machine.lower())
    try:
        name, sha = PACKAGES[(os_name, arch)]
    except KeyError:
        raise SetupError("unsupported platform %s/%s (supported: %s)" % (
            os_name, arch, ", ".join("%s/%s" % k for k in PACKAGES)))
    return BASE + name, name, sha


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def verify(path, expected):
    got = sha256_of(path)
    if got != expected:
        raise SetupError("sha256 mismatch for %s: expected %s, got %s" % (os.path.basename(path), expected, got))


def download(url, dest, attempts=3):
    last = None
    for i in range(attempts):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "winter_survival-ci-setup"})
            with urllib.request.urlopen(req, timeout=60) as r, open(dest, "wb") as f:
                shutil.copyfileobj(r, f)
            return
        except Exception as e:  # noqa: BLE001
            last = e
            print("download attempt %d/%d failed: %s" % (i + 1, attempts, e), file=sys.stderr)
    raise SetupError("download failed: %s (%s)" % (url, last))


def _safe_target(root, name):
    target = os.path.realpath(os.path.join(root, name))
    if not (target == os.path.realpath(root) or target.startswith(os.path.realpath(root) + os.sep)):
        raise SetupError("unsafe path in archive: %s" % name)


def extract(archive, out_dir):
    """Extract .zip / .tar.xz into out_dir, rejecting path traversal."""
    if archive.endswith(".zip"):
        with zipfile.ZipFile(archive) as z:
            for n in z.namelist():
                _safe_target(out_dir, n)
            z.extractall(out_dir)
    else:
        with tarfile.open(archive, "r:*") as t:
            for m in t.getmembers():
                _safe_target(out_dir, m.name)
            t.extractall(out_dir)


def strip_top(out_dir):
    """Return the single top-level directory inside out_dir (the one to rename to dest)."""
    entries = os.listdir(out_dir)
    if len(entries) != 1 or not os.path.isdir(os.path.join(out_dir, entries[0])):
        raise SetupError("expected exactly one top-level directory in archive, got: %s" % entries)
    return os.path.join(out_dir, entries[0])


def zig_exe(dest):
    return os.path.join(dest, "zig.exe" if sys.platform == "win32" else "zig")


def zig_version(dest):
    exe = zig_exe(dest)
    if not os.path.isfile(exe):
        return None
    try:
        r = subprocess.run([exe, "version"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60)
        return r.stdout.decode().strip() if r.returncode == 0 else None
    except Exception:  # noqa: BLE001
        return None


def install_from_archive(archive, dest, tmp_parent):
    """Extract archive, strip top dir, atomically place at dest. Returns nothing."""
    work = tempfile.mkdtemp(prefix=".extract.", dir=tmp_parent)
    try:
        extract(archive, work)
        top = strip_top(work)
        if os.path.isdir(dest):
            shutil.rmtree(dest)
        os.rename(top, dest)  # same filesystem -> atomic
    finally:
        shutil.rmtree(work, ignore_errors=True)


def ensure_zig(dest, url=None, sha=None):
    if zig_version(dest) == VERSION:
        print("zig %s already present at %s (skip)" % (VERSION, dest))
        return
    if url is None:
        url, _, sha = select_package()
    parent = os.path.dirname(os.path.abspath(dest))
    os.makedirs(parent, exist_ok=True)
    tmpdir = tempfile.mkdtemp(prefix=".dl.", dir=parent)
    try:
        arc = os.path.join(tmpdir, url.rsplit("/", 1)[1])
        print("downloading %s" % url)
        download(url, arc)
        verify(arc, sha)
        install_from_archive(arc, os.path.abspath(dest), tmpdir)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    got = zig_version(dest)
    if got != VERSION:
        raise SetupError("installed zig at %s reports version %r, expected %s" % (dest, got, VERSION))
    print("installed zig %s to %s" % (VERSION, dest))


# lua.org is unreachable for zig's HTTP client on our networks (no system-proxy support),
# so zlua's lazy Lua 5.4.8 dependency is pre-seeded into the zig global cache from a mirror.
LUA_URL = "https://sources.buildroot.net/lua/lua-5.4.8.tar.gz"
LUA_SHA256 = "4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae"
LUA_ZIG_HASH = "N-V-__8AAKEzFAAA695b9LXBhUSVK5MAV_VKSm1mEj3Acbze"


def ensure_lua(dest):
    cache = os.environ.get("ZIG_GLOBAL_CACHE_DIR")
    if not cache:
        raise SetupError("--lua-mirror needs ZIG_GLOBAL_CACHE_DIR to be set (same value as the build step)")
    pdir = os.path.join(cache, "p")
    # zig 0.16 keeps fetched packages as p/<hash>.tar.gz (older: p/<hash>/)
    if os.path.isdir(pdir) and any(n == LUA_ZIG_HASH or n.startswith(LUA_ZIG_HASH + ".") for n in os.listdir(pdir)):
        print("lua 5.4.8 already in zig cache (skip)")
        return
    os.makedirs(cache, exist_ok=True)
    tmpdir = tempfile.mkdtemp(prefix=".lua.", dir=cache)
    try:
        arc = os.path.join(tmpdir, "lua-5.4.8.tar.gz")
        print("downloading %s" % LUA_URL)
        download(LUA_URL, arc)
        verify(arc, LUA_SHA256)
        # zig 0.16 `zig fetch` refuses to run outside a project: give it a throwaway one.
        proj = os.path.join(tmpdir, "proj")
        os.makedirs(proj)
        with open(os.path.join(proj, "build.zig"), "w") as f:
            f.write("pub fn build(_: *@import(\"std\").Build) void {}\n")
        r = subprocess.run([zig_exe(dest), "fetch", arc], cwd=proj,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=600)
        got = r.stdout.decode().strip()
        if r.returncode != 0 or got != LUA_ZIG_HASH:
            raise SetupError("zig fetch lua failed (rc=%d, hash=%r, expected %s): %s"
                             % (r.returncode, got, LUA_ZIG_HASH, r.stderr.decode().strip()))
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)
    print("seeded lua 5.4.8 into zig cache as %s" % LUA_ZIG_HASH)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--dest", required=True)
    ap.add_argument("--lua-mirror", action="store_true",
                    help="pre-seed zlua's Lua 5.4.8 tarball from a mirror into ZIG_GLOBAL_CACHE_DIR")
    a = ap.parse_args(argv)
    try:
        ensure_zig(a.dest)
        if a.lua_mirror:
            ensure_lua(a.dest)
    except SetupError as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    print("zig path: %s" % zig_exe(a.dest))
    print("zig version: %s" % zig_version(a.dest))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Generate a new Delve game project from this starter (Python 3.10+, stdlib only).

Usage (from anywhere; the starter root is the parent of tools/):
  python3 tools/new_game.py NAME [--dest DIR] [--title TITLE] [--delve DIR] [--git]

NAME must match [a-z][a-z0-9_]{0,31} (Zig package name rules). DIR defaults to
<starter parent>/<NAME with _ replaced by ->. The Delve framework is located via --delve, or else via the
`.delve` dependency path in the starter's build.zig.zon; `.path` in the new project is rewritten relative to DIR.
"""
import argparse
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import zlib
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

NAME_RE = re.compile(r"[a-z][a-z0-9_]{0,31}")
# DEST basename: substituted into Groovy strings and sh/bat lines in ci/ and into the README.
DIR_NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
# Top-level directories of the starter that are never copied.
EXCLUDED_TOP_DIRS = {"out", "reports"}
# Names excluded at any depth.
EXCLUDED_ANY_DEPTH = {".git", ".zig-cache", "zig-out", "zig-pkg", "__pycache__"}
EXCLUDED_SUFFIXES = (".pyc",)
# Starter-relative POSIX paths that are never copied.
EXCLUDED_RELPATHS = {"docs/STARTER-PLAN.md"}
# Files with these extensions are never text-replaced.
BINARY_EXTS = {".png", ".wav", ".ogg", ".jpg", ".gif"}
# Starter tokens. Assembled from parts so this file does not contain the literal tokens it rewrites
# (this file is copied into generated projects, where the leftover check must still pass).
TOK_PKG = "delve" + "_starter"  # build.zig.zon .name (rewritten with its leading dot)
TOK_EXE = "starter" + "-game"  # exe name in build.zig, ci files, README
TOK_TITLE = "Delve" + " Starter"  # window title, ci smoke title, README
TOK_DIR = "delve" + "-starter"  # directory basename in README/CI
# Tokens that must not survive generation (unless the NAME/TITLE/DIR itself contains them).
FORBIDDEN_TOKENS = (TOK_PKG, TOK_EXE, TOK_TITLE, TOK_DIR)

FINGERPRINT_RE = re.compile(r"(\.fingerprint\s*=\s*)0x[0-9a-fA-F]+(\s*,)")
DELVE_PATH_RE = re.compile(r'(\.delve\s*=\s*\.\{\s*\.path\s*=\s*")([^"]*)(")')


class NewGameError(Exception):
    """A clean, user-facing error. exit_code is the process exit status."""

    exit_code = 1


class UsageError(NewGameError):
    """Invalid arguments (exit 2)."""

    exit_code = 2


@dataclass
class GameResult:
    dest: Path
    name: str
    title: str
    fingerprint: str
    delve_path: str
    framework: Path
    git_initialized: bool


def validate_name(name: str) -> None:
    if not NAME_RE.fullmatch(name):
        raise UsageError(
            f"invalid NAME {name!r}: must match [a-z][a-z0-9_]{{0,31}} (lowercase letters, digits, underscore)"
        )


def validate_title(title: str) -> None:
    if not title.strip():
        raise UsageError("TITLE must not be empty")
    if any(c in title for c in '"\\') or any(ord(c) < 32 or ord(c) == 127 for c in title):
        raise UsageError("TITLE must not contain quotes, backslashes or control characters")


def validate_dest_name(basename: str) -> None:
    if not DIR_NAME_RE.fullmatch(basename):
        raise UsageError(
            f"invalid DEST directory name {basename!r}: must match [A-Za-z0-9][A-Za-z0-9._-]{{0,63}} "
            "(letters, digits, '.', '_', '-'; starts with a letter or digit)"
        )


def default_title(name: str) -> str:
    return name.replace("_", " ").title()


def default_dest(root: Path, name: str) -> Path:
    return root.parent / name.replace("_", "-")


def make_fingerprint(name: str) -> int:
    """Zig 0.16 requires the upper 32 bits to equal crc32(name); the lower 32 bits are random, never 0 or 0xffffffff."""
    r = secrets.randbelow(0xFFFFFFFE) + 1
    return (zlib.crc32(name.encode()) << 32) | r


def _is_within(path: Path, parent: Path) -> bool:
    return path == parent or parent in path.parents


def _make_ignore(root: Path):
    def ignore(src: str, names: list[str]) -> set[str]:
        src_path = Path(src)
        at_top = src_path == root
        skipped = set()
        for n in names:
            if n in EXCLUDED_ANY_DEPTH or n.endswith(EXCLUDED_SUFFIXES):
                skipped.add(n)
            elif at_top and n in EXCLUDED_TOP_DIRS and (src_path / n).is_dir():
                skipped.add(n)
            elif (src_path / n).relative_to(root).as_posix() in EXCLUDED_RELPATHS:
                skipped.add(n)
        return skipped

    return ignore


def _iter_text_files(tree: Path):
    """Yield (path, text) for regular text files; skips binary extensions, symlinks, NUL bytes and non-UTF-8."""
    for dirpath, _dirnames, filenames in os.walk(tree):
        for fn in filenames:
            p = Path(dirpath) / fn
            if p.suffix.lower() in BINARY_EXTS or p.is_symlink():
                continue
            data = p.read_bytes()
            if b"\x00" in data:
                continue
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                continue
            yield p, text


def _replace_tokens(tree: Path, mapping: dict[str, str]) -> None:
    # Single pass, so a replacement value is never re-scanned for tokens.
    pattern = re.compile("|".join(re.escape(t) for t in sorted(mapping, key=len, reverse=True)))
    for p, text in _iter_text_files(tree):
        new = pattern.sub(lambda m: mapping[m.group(0)], text)
        if new != text:
            p.write_bytes(new.encode("utf-8"))


def _verify_no_leftovers(tree: Path, allowed: list[str]) -> None:
    checks = [t for t in FORBIDDEN_TOKENS if not any(t in a for a in allowed)]
    for p, text in _iter_text_files(tree):
        for t in checks:
            if t in text:
                raise NewGameError(f"leftover '{t}' in {p.relative_to(tree).as_posix()} after generation")


def _relpath(framework: Path, dest: Path) -> str:
    try:
        rel = os.path.relpath(framework, dest).replace(os.sep, "/")
    except ValueError as e:
        raise NewGameError(f"cannot express {framework} relative to {dest}: {e}") from e
    # rel is written into a Zig string literal in build.zig.zon, so it must not break the literal.
    if any(c in rel for c in '"\\') or any(ord(c) < 32 or ord(c) == 127 for c in rel):
        raise NewGameError(
            f"relative path to the delve framework {rel!r} contains a quote, backslash or control character; "
            "move the framework or the project to a path without them"
        )
    return rel


def locate_framework(root: Path, delve: str | None) -> Path:
    if delve is not None:
        framework = Path(delve).expanduser().resolve()
    else:
        zon = (root / "build.zig.zon").read_text(encoding="utf-8")
        m = DELVE_PATH_RE.search(zon)
        if not m:
            raise NewGameError("cannot find the .delve dependency path in build.zig.zon; pass --delve DIR")
        framework = (root / m.group(2)).resolve()
    if not (framework / "build.zig").is_file():
        raise NewGameError(f"delve framework not found at {framework} (no build.zig there); pass --delve DIR")
    return framework


def _rewrite_zon(zon_path: Path, fingerprint: int, rel_delve: str) -> None:
    text = zon_path.read_text(encoding="utf-8")
    text, n_fp = FINGERPRINT_RE.subn(lambda m: f"{m.group(1)}0x{fingerprint:016x}{m.group(2)}", text, count=1)
    if n_fp == 0:
        raise NewGameError("cannot find .fingerprint in build.zig.zon")
    text, n_path = DELVE_PATH_RE.subn(lambda m: f"{m.group(1)}{rel_delve}{m.group(3)}", text, count=1)
    if n_path == 0:
        raise NewGameError("cannot find the .delve dependency path in build.zig.zon")
    zon_path.write_text(text, encoding="utf-8")


def _git(args: list[str], cwd: Path) -> str:
    try:
        r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    except OSError as e:
        raise NewGameError(f"cannot run git: {e}") from e
    if r.returncode != 0:
        detail = (r.stderr or r.stdout).strip()
        hint = ""
        if "user.name" in detail or "user.email" in detail or "tell me who you are" in detail:
            hint = " (git user.name/user.email is not set; configure it and rerun)"
        raise NewGameError(f"git {' '.join(args)} failed: {detail}{hint}")
    return r.stdout


def _starter_sha(root: Path) -> str:
    try:
        r = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=root, capture_output=True, text=True)
    except OSError:
        return "unknown"
    sha = r.stdout.strip() if r.returncode == 0 else ""
    return sha or "unknown"


def _git_init_commit(dest: Path, name: str, starter_sha: str) -> None:
    _git(["init", "-q", "-b", "main"], dest)
    _git(["add", "-A"], dest)
    _git(["commit", "-q", "-m", f"Initial {name} from {TOK_DIR} {starter_sha}"], dest)


def _missing_ancestors(dest: Path) -> list[Path]:
    """Directories above `dest` (dest excluded) that do not exist yet, outermost first."""
    missing = []
    for parent in dest.parents:
        if parent.exists():
            break
        missing.append(parent)
    missing.reverse()
    return missing


def _create_ancestors(dest: Path, created: list[Path]) -> None:
    """Create the missing ancestors of `dest` one by one, appending to `created` only those this call made.

    A directory that appears concurrently (FileExistsError, now a directory) belongs to someone else: not recorded.
    """
    for p in _missing_ancestors(dest):
        try:
            os.mkdir(p)
        except FileExistsError:
            if not p.is_dir():
                raise
        else:
            created.append(p)


def _current_umask() -> int:
    mask = os.umask(0)
    try:
        return mask
    finally:
        os.umask(mask)


def _commit(staging: Path, dest: Path, preexisting: bool) -> None:
    """Move the finished tree from `staging` to `dest`. Never deletes or overwrites anything in `dest`."""
    if not preexisting:
        # Fails (and leaves dest alone) if dest appeared meanwhile with content.
        try:
            os.rename(staging, dest)
        except OSError as e:
            raise NewGameError(f"cannot move the generated project to {dest}: {e}") from e
        return
    if any(dest.iterdir()):
        raise NewGameError(f"{dest} is no longer empty; refusing to overwrite it")
    moved: list[str] = []
    try:
        for entry in sorted(os.listdir(staging)):
            target = dest / entry
            # Residual window: something created at `target` between this check and the rename could still be
            # replaced on POSIX (a file) - unavoidable with rename; the check catches everything earlier.
            if os.path.lexists(target):
                raise NewGameError(f"{target} appeared during generation; refusing to overwrite it")
            os.rename(staging / entry, target)
            moved.append(entry)
        os.rmdir(staging)
    except BaseException as exc:
        stuck: list[str] = []
        for entry in reversed(moved):  # only the names this run moved
            try:
                os.rename(dest / entry, staging / entry)
            except OSError:
                stuck.append(entry)  # never delete anything inside DEST; report it instead
        if stuck and isinstance(exc, Exception):
            raise NewGameError(
                f"{exc}\nCould not move these generated entries back out of {dest}; remove them by hand: "
                + ", ".join(sorted(stuck))
            ) from exc
        raise


def _cleanup(staging: Path | None, created_dirs: list[Path]) -> None:
    """Remove only what this run is certain to own: the staging directory, then the ancestors it created
    (deepest first, with rmdir, which refuses non-empty directories so foreign content survives)."""
    if staging is not None:
        shutil.rmtree(staging, ignore_errors=True)
    for d in reversed(created_dirs):
        try:
            os.rmdir(d)
        except OSError:
            pass


def create_game(
    root: Path,
    name: str,
    dest: str | None = None,
    title: str | None = None,
    delve: str | None = None,
    git: bool = False,
) -> GameResult:
    """Generate a game project from the starter at `root`. Raises NewGameError (or a subclass) on failure.

    `.path` in build.zig.zon is always rewritten relative to DEST, so non-sibling destinations work.

    Cleanup guarantee: a failed run never deletes anything it did not create, even if other processes write into
    the directories concurrently. All arguments are validated before the filesystem is touched. Missing ancestors
    of DEST are created one by one with mkdir and only those actually created are recorded. The project is
    generated in a private staging directory (`.new_game-*`, next to DEST) and then renamed to DEST (or, for a
    pre-existing empty DEST, its top-level entries are moved in by name; DEST's children are never enumerated for
    deletion). On failure the staging directory is removed, then the recorded ancestors are removed deepest-first
    with rmdir, which leaves any non-empty directory in place. Residual case: if someone writes into an ancestor
    this run created, that ancestor (and their content) is left in place. A pre-existing DEST is never removed.
    A failing `--git` step runs after the commit and keeps the generated files (the error says so).
    """
    root = Path(root).resolve()
    validate_name(name)
    title = default_title(name) if title is None else title
    validate_title(title)

    dest_path = (Path(dest).expanduser() if dest else default_dest(root, name)).resolve()
    basename = dest_path.name
    if not basename:
        raise UsageError(f"cannot derive a project directory name from {dest_path}")
    validate_dest_name(basename)
    if _is_within(dest_path, root):
        raise UsageError(f"DEST {dest_path} must not be inside the starter tree {root}")
    preexisting = dest_path.exists()
    if preexisting:
        if not dest_path.is_dir():
            raise NewGameError(f"{dest_path} exists and is not a directory")
        if any(dest_path.iterdir()):
            raise NewGameError(f"{dest_path} exists and is not empty; refusing to overwrite it")

    framework = locate_framework(root, delve)
    fingerprint = make_fingerprint(name)
    delve_path = _relpath(framework, dest_path)

    created_dirs: list[Path] = []
    staging: Path | None = None
    try:
        _create_ancestors(dest_path, created_dirs)
        staging = Path(tempfile.mkdtemp(prefix=".new_game-", dir=dest_path.parent))
        shutil.copytree(root, staging, ignore=_make_ignore(root), dirs_exist_ok=True)
        if not preexisting:
            # mkdtemp makes the directory 0700 and copytree's copystat then copies the starter root's mode; the
            # final DEST should get what a plain mkdir would have given, so set it after the copy.
            os.chmod(staging, 0o777 & ~_current_umask())
        _replace_tokens(
            staging,
            {
                "." + TOK_PKG: "." + name,
                TOK_EXE: name,
                TOK_TITLE: title,
                TOK_DIR: basename,
            },
        )
        _rewrite_zon(staging / "build.zig.zon", fingerprint, delve_path)
        _verify_no_leftovers(staging, [name, title, basename])
        _commit(staging, dest_path, preexisting)
        staging = None  # consumed by the commit
    except BaseException:
        _cleanup(staging, created_dirs)
        raise
    if git:
        try:
            _git_init_commit(dest_path, name, _starter_sha(root))
        except NewGameError as e:
            raise NewGameError(
                f"{e}\nThe project was generated and kept in {dest_path}; fix git there and commit manually."
            ) from e

    return GameResult(
        dest=dest_path,
        name=name,
        title=title,
        fingerprint=f"0x{fingerprint:016x}",
        delve_path=delve_path,
        framework=framework,
        git_initialized=git,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="new_game.py",
        description="Generate a new Delve game project from this starter.",
    )
    parser.add_argument("name", help="package/exe name: [a-z][a-z0-9_]{0,31}")
    parser.add_argument("--dest", metavar="DIR", help="target directory (default: <starter parent>/NAME-with-dashes)")
    parser.add_argument("--title", metavar="TITLE", help="window/README title (default: NAME title-cased)")
    parser.add_argument("--delve", metavar="DIR", help="delve-framework checkout (default: from build.zig.zon)")
    parser.add_argument("--git", action="store_true", help="git init and make an initial commit in DIR")
    args = parser.parse_args(argv)

    try:
        result = create_game(
            ROOT,
            args.name,
            dest=args.dest,
            title=args.title,
            delve=args.delve,
            git=args.git,
        )
    except NewGameError as e:
        print(f"error: {e}", file=sys.stderr)
        return e.exit_code
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    print(f"Created game project: {result.dest}")
    print(f"  name:        {result.name}")
    print(f"  title:       {result.title}")
    print(f"  fingerprint: {result.fingerprint}")
    print(f"  delve path:  {result.delve_path} (framework: {result.framework})")
    print(f"  git:         {'initialized with initial commit' if result.git_initialized else 'not initialized'}")
    print("Next steps:")
    print(f"  cd {result.dest} && mise exec -- zig build run")
    return 0


if __name__ == "__main__":
    sys.exit(main())

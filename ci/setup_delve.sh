#!/usr/bin/env bash
# Idempotent: clone/fetch delve-framework to <dest>, force-checkout <rev>, re-apply the local quakemap patch.
# Usage: setup_delve.sh <dest> <rev> [repo-url]
set -euo pipefail
DEST="${1:?usage: setup_delve.sh <dest> <rev> [repo-url]}"
REV="${2:?usage: setup_delve.sh <dest> <rev> [repo-url]}"
REPO="${3:-${DELVE_REPO:-git://127.0.0.1/delve-framework}}"

command -v git >/dev/null || { echo "ERROR: git not found" >&2; exit 1; }
if [ ! -d "$DEST/.git" ]; then
  mkdir -p "$DEST"
  git -C "$DEST" init -q
  git -C "$DEST" remote add origin "$REPO"
fi
git -C "$DEST" remote set-url origin "$REPO"
if ! timeout 300 git -C "$DEST" fetch --quiet origin; then
  echo "ERROR: cannot fetch $REPO (is the git daemon running?)" >&2
  exit 1
fi
if ! git -C "$DEST" cat-file -e "$REV^{commit}" 2>/dev/null; then
  echo "ERROR: revision $REV not found in $REPO" >&2
  exit 1
fi
git -C "$DEST" checkout --force --quiet "$REV"
git -C "$DEST" clean -fdxq

# Local patch (not committed upstream): zig 0.16 renamed GeneralPurposeAllocator -> DebugAllocator.
# sed is idempotent: once patched there is nothing left to match.
QM="$DEST/src/framework/utils/quakemap.zig"
[ -f "$QM" ] || { echo "ERROR: $QM not found" >&2; exit 1; }
sed -i 's/GeneralPurposeAllocator(/DebugAllocator(/g' "$QM"

echo "delve HEAD: $(git -C "$DEST" rev-parse HEAD)"
git -C "$DEST" diff --stat

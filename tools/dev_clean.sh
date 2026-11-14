#!/usr/bin/env bash
# Reclaim disk on the dev box (shared with the Jenkins controller: below 1 GiB free Jenkins takes the
# built-in node offline and every CI run hangs in the queue).
#
#   tools/dev_clean.sh            caches + old temp + old CI refs (safe: everything is regenerable)
#   tools/dev_clean.sh --worktrees  also remove worktrees whose branch is merged into main and that have
#                                 no uncommitted changes (the branch itself is kept)
#   tools/dev_clean.sh --dry-run    print what would be removed
#
# Removes: .zig-cache of worktrees idle for 24 h (any worktree incl. main when > 1.5 GiB),
# /tmp/claude-<uid>/ci-verify-* older than 2 days, Claude session temp dirs older than 2 days,
# refs/ci/* older than 7 days. Never touches tracked files, branches or the current worktree's work.
set -euo pipefail

DRY="" WT=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --worktrees) WT=1 ;;
    -h|--help) sed -n 2,13p "$0"; exit 0 ;;
    *) echo "dev_clean: unknown option $a" >&2; exit 2 ;;
  esac
done

run() { if [ -n "$DRY" ]; then echo "would: $*"; else "$@"; fi; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN="$(git -C "$HERE" worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
TMPROOT="/tmp/claude-$(id -u)"
before="$(df -BM --output=avail / | tail -1 | tr -dc 0-9)"

# 1. worktrees of merged branches (opt-in)
if [ -n "$WT" ]; then
  git -C "$MAIN" worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r w; do
    [ "$w" = "$MAIN" ] && continue
    [ "$w" = "$(pwd -P)" ] && continue
    b="$(git -C "$w" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [ -n "$b" ] && [ "$b" != "HEAD" ] || continue
    if git -C "$MAIN" merge-base --is-ancestor "$b" main && [ -z "$(git -C "$w" status --short)" ]; then
      echo "dev_clean: worktree $w ($b, merged, clean)"
      run git -C "$MAIN" worktree remove "$w"
    fi
  done
  run git -C "$MAIN" worktree prune
fi

# 2. zig caches
git -C "$MAIN" worktree list --porcelain | awk '/^worktree /{print $2}' | while read -r w; do
  c="$w/.zig-cache"
  [ -d "$c" ] || continue
  kb="$(du -xsk "$c" | cut -f1)"
  if [ "$kb" -le 1572864 ]; then
    # keep the cache of the main checkout and of worktrees touched in the last 24 h (index = last
    # checkout/commit/add); only big caches are always cleared
    [ "$w" = "$MAIN" ] && continue
    idx="$(git -C "$w" rev-parse --git-path index)"
    case "$idx" in /*) ;; *) idx="$w/$idx" ;; esac
    [ -n "$(find "$idx" -mmin -1440 2>/dev/null)" ] && continue
  fi
  echo "dev_clean: $(du -xsh "$c" | cut -f1) $c"
  run rm -rf "$c"
done

# 3. old temp
if [ -d "$TMPROOT" ]; then
  find "$TMPROOT" -maxdepth 1 -type d -name 'ci-verify-*' -mtime +2 -print | while read -r d; do
    run rm -rf "$d"
  done
  find "$TMPROOT" -mindepth 2 -maxdepth 2 -type d -path "$TMPROOT/-*" -mtime +2 -print | while read -r d; do
    echo "dev_clean: $(du -xsh "$d" | cut -f1) $d"
    run rm -rf "$d"
  done
fi

# 4. old CI snapshot refs
if [ -z "$DRY" ]; then (cd "$MAIN" && "$HERE/ci_verify.sh" --gc 7); fi

after="$(df -BM --output=avail / | tail -1 | tr -dc 0-9)"
echo "dev_clean: free ${before}M -> ${after}M"

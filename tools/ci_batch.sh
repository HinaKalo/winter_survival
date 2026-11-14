#!/usr/bin/env bash
# Batch merge gate: merge several finished branches onto main in a throwaway worktree and verify them
# with ONE Jenkins run instead of one run per branch (the Windows runner is serial).
#
#   tools/ci_batch.sh --name TAG [--profile quick|full] [--probes LIST] [--max-wait S] BRANCH...
#
# Creates branch integ/TAG = main + each BRANCH (merge --no-ff, in the order given) in
# ../<repo>-integ-TAG, runs tools/ci_verify.sh there and removes the worktree afterwards.
# On a merge conflict it stops and leaves the worktree for manual resolution.
# Success: `git merge --ff-only integ/TAG` on main lands the whole batch (after review).
set -euo pipefail

NAME="" PROFILE="quick" PROBES="" MAXWAIT="14000" BRANCHES=()
die() { echo "ci_batch: $*" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:?}"; shift 2 ;;
    --profile) PROFILE="${2:?}"; shift 2 ;;
    --probes) PROBES="${2:?}"; shift 2 ;;
    --max-wait) MAXWAIT="${2:?}"; shift 2 ;;
    -h|--help) sed -n 2,11p "$0"; exit 0 ;;
    -*) die "unknown option $1" ;;
    *) BRANCHES+=("$1"); shift ;;
  esac
done
[ -n "$NAME" ] || die "--name is required"
[ ${#BRANCHES[@]} -gt 0 ] || die "give at least one branch"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN="$(git -C "$HERE" worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
WT="$(dirname "$MAIN")/$(basename "$MAIN")-integ-$NAME"
BR="integ/$NAME"

git -C "$MAIN" show-ref --quiet "refs/heads/$BR" && die "branch $BR exists (delete it or pick another --name)"
git -C "$MAIN" worktree add -q -b "$BR" "$WT" main
for b in "${BRANCHES[@]}"; do
  echo "ci_batch: merging $b"
  if ! git -C "$WT" merge -q --no-ff "$b" -m "integ/$NAME: merge $b"; then
    die "conflict merging $b; resolve in $WT, commit, then run tools/ci_verify.sh there"
  fi
done

args=(--name "batch-$NAME" --profile "$PROFILE" --max-wait "$MAXWAIT")
[ -n "$PROBES" ] && args+=(--probes "$PROBES")
rc=0
(cd "$WT" && "$HERE/ci_verify.sh" "${args[@]}") || rc=$?
git -C "$MAIN" worktree remove --force "$WT"
if [ $rc -eq 0 ]; then
  echo "ci_batch: PASS - land with: git -C $MAIN merge --ff-only $BR"
else
  echo "ci_batch: FAIL (rc=$rc) - branch $BR kept for inspection"
fi
exit $rc

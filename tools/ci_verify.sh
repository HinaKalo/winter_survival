#!/usr/bin/env bash
# Snapshot the current worktree, run it through the Jenkins job winter_survival-verify (Windows GPU),
# download JUnit/logs/screenshots and print a compact summary. Exit 0 only if the build SUCCEEDED.
#
#   tools/ci_verify.sh --name TAG [--profile quick|full] [--shots FILE] [--probes LIST] [--out DIR]
#                      [--balance-days N] [--max-wait SECONDS]
#   tools/ci_verify.sh --gc [DAYS]          delete refs/ci/* older than DAYS (default 7)
#
# The snapshot (tracked + untracked files, .gitignore honoured) is committed with a temporary index and
# stored as refs/ci/TAG in the shared repo; the branch, index and working files are never touched.
# --shots FILE: one screenshot per line `name|KEY=VAL KEY2=VAL2|extra game args` (see docs/CI-PLAN.md section 7).
set -euo pipefail

JOB="${CI_VERIFY_JOB:-winter_survival-verify}"
JENKINS_URL="${JENKINS_URL:-http://localhost:8080}"
CLI_JAR="${HOME}/.config/jenkins/jenkins-cli.jar"
AUTH_FILE="${HOME}/.config/jenkins/ci_auth"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAME="" PROFILE="full" SHOTS_FILE="" PROBES="" OUT="" DAYS="30" MAXWAIT="3000" GC=""
die() { echo "ci_verify: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:?}"; shift 2 ;;
    --profile) PROFILE="${2:?}"; shift 2 ;;
    --shots) SHOTS_FILE="${2:?}"; shift 2 ;;
    --probes) PROBES="${2:?}"; shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    --balance-days) DAYS="${2:?}"; shift 2 ;;
    --max-wait) MAXWAIT="${2:?}"; shift 2 ;;
    --gc) GC="7"; if [ $# -gt 1 ] && [[ "$2" =~ ^[0-9]+$ ]]; then GC="$2"; shift; fi; shift ;;
    -h|--help) sed -n 2,12p "$0"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

# make --shots absolute before any cd
if [ -n "$SHOTS_FILE" ]; then
  case "$SHOTS_FILE" in /*) ;; *) SHOTS_FILE="$PWD/$SHOTS_FILE" ;; esac
fi

GIT_COMMON="$(git rev-parse --git-common-dir)"
GIT_COMMON="$(cd "$GIT_COMMON" && pwd)"

if [ -n "$GC" ]; then
  now="$(date +%s)"; n=0
  while read -r ref ts; do
    if [ $((now - ts)) -gt $((GC * 86400)) ]; then
      git --git-dir="$GIT_COMMON" update-ref -d "$ref"; n=$((n + 1))
    fi
  done < <(git --git-dir="$GIT_COMMON" for-each-ref --format='%(refname) %(committerdate:unix)' refs/ci/)
  echo "ci_verify: deleted $n refs/ci/* older than $GC day(s)"
  exit 0
fi

[ -n "$NAME" ] || die "--name TAG is required"
[[ "$NAME" =~ ^[A-Za-z0-9._-]+$ ]] || die "--name may only contain letters, digits, . _ -"
case "$PROFILE" in quick|full) ;; *) die "--profile must be quick or full" ;; esac
[ -f "$CLI_JAR" ] && [ -f "$AUTH_FILE" ] || die "jenkins-cli.jar / ci_auth missing under ~/.config/jenkins"
[ -z "$SHOTS_FILE" ] || [ -f "$SHOTS_FILE" ] || die "shots file not found: $SHOTS_FILE"
[ -n "$OUT" ] || OUT="/tmp/claude-1000/ci-verify-$NAME"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"

# ---- snapshot (no effect on branch / index / working tree)
TOP="$(git rev-parse --show-toplevel)"
cd "$TOP"
TMPD="$(mktemp -d)"
CFG="$TMPD/curl.cfg"
trap 'rm -rf "$TMPD"' EXIT
export GIT_INDEX_FILE="$TMPD/index"
git read-tree HEAD
git add -A
TREE="$(git write-tree)"
SHA="$(git commit-tree "$TREE" -p HEAD -m "ci snapshot $NAME" -m "from $(git rev-parse --abbrev-ref HEAD) $(git rev-parse --short HEAD)")"
unset GIT_INDEX_FILE
git --git-dir="$GIT_COMMON" update-ref "refs/ci/$NAME" "$SHA"
echo "ci_verify: snapshot $SHA -> refs/ci/$NAME (profile=$PROFILE)"

# ---- trigger + wait
cli() { java -jar "$CLI_JAR" -s "$JENKINS_URL/" -auth "@$AUTH_FILE" "$@"; }
SHOTS_TEXT=""; [ -z "$SHOTS_FILE" ] || SHOTS_TEXT="$(cat "$SHOTS_FILE")"
T0="$(date +%s)"
set +e
timeout "$MAXWAIT" java -jar "$CLI_JAR" -s "$JENKINS_URL/" -auth "@$AUTH_FILE" build "$JOB" \
  -p "REF=refs/ci/$NAME" -p "PROFILE=$PROFILE" -p "SHOTS=$SHOTS_TEXT" -p "PROBES=$PROBES" \
  -p "BALANCE_DAYS=$DAYS" -f -v > "$OUT/console.log" 2>&1
RC=$?
set -e
T1="$(date +%s)"
if [ "$RC" -eq 124 ]; then
  echo "ci_verify: gave up waiting after ${MAXWAIT}s (Windows agent busy/offline?); build keeps running in Jenkins"
fi
BUILD="$(grep -aoE "Started $JOB #[0-9]+" "$OUT/console.log" | head -1 | grep -oE '[0-9]+$' || true)"
RESULT="$(grep -aoE 'Finished: [A-Z_]+' "$OUT/console.log" | tail -1 | sed 's/Finished: //' || true)"
[ -n "$RESULT" ] || RESULT="UNKNOWN(cli rc=$RC)"

# ---- artifacts (credentials go through a 0600 curl config, never argv)
if [ -n "$BUILD" ]; then
  ( umask 077; printf 'user = "%s"\n' "$(cat "$AUTH_FILE")" > "$CFG" )
  ZIP="$TMPD/archive.zip"
  if curl -sf --config "$CFG" -o "$ZIP" "$JENKINS_URL/job/$JOB/$BUILD/artifact/*zip*/archive.zip"; then
    if ! python3 -I - "$ZIP" "$OUT" <<'PY'
import sys, zipfile, os
zp, out = sys.argv[1:3]
with zipfile.ZipFile(zp) as z:
    for m in z.infolist():
        if m.is_dir():
            continue
        parts = m.filename.split("/")
        # archive/winter_survival/reports/<linux|windows>/... -> OUT/<linux|windows>/...
        if "reports" in parts:
            parts = parts[parts.index("reports") + 1:]
        else:
            parts = parts[1:]
        dest = os.path.normpath(os.path.join(out, *parts))
        if not dest.startswith(out + os.sep):
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with z.open(m) as src, open(dest, "wb") as dst:
            dst.write(src.read())
PY
    then
      echo "ci_verify: WARNING: could not unpack the artifact archive for build #$BUILD (continuing to summary)" >&2
    fi
  else
    echo "ci_verify: no artifacts downloaded for build #$BUILD"
  fi
fi

# ---- summary
echo "================ ci_verify summary ================"
echo "build: ${BUILD:+#$BUILD} result: $RESULT  ref: refs/ci/$NAME  wall: $((T1 - T0))s (queue+run)"
echo "out:   $OUT   (console: $OUT/console.log)"
python3 -I "$HERE/ci_verify_summary.py" "$OUT"
[ "$RESULT" = "SUCCESS" ]

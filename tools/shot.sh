#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <out.png> [--lang zh|en|ko] [--script path.lua] [--at seconds]" >&2
  exit 2
fi

OUT="$1"
shift

LANG_CODE=""
SCRIPT_PATH=""
SHOT_AT="3"

while [ $# -gt 0 ]; do
  case "$1" in
    --lang)
      LANG_CODE="${2:?missing lang}"
      shift 2
      ;;
    --script)
      SCRIPT_PATH="${2:?missing script}"
      shift 2
      ;;
    --at)
      SHOT_AT="${2:?missing at}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p "$(dirname "$OUT")" .zig-cache

SAVES_FILE="saves/settings.sav"
BACKUP_FILE=""
HAD_SAVES=0
WRAPPER=""

cleanup() {
  if [ "$HAD_SAVES" -eq 1 ] && [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
    mkdir -p saves
    cp -f "$BACKUP_FILE" "$SAVES_FILE"
    rm -f "$BACKUP_FILE"
  elif [ "$HAD_SAVES" -eq 0 ] && [ -n "$LANG_CODE" ]; then
    rm -f "$SAVES_FILE"
  fi
  if [ -n "$WRAPPER" ] && [ -f "$WRAPPER" ]; then
    rm -f "$WRAPPER"
  fi
}
trap cleanup EXIT INT TERM

if [ -n "$LANG_CODE" ]; then
  mkdir -p saves
  if [ -f "$SAVES_FILE" ]; then
    HAD_SAVES=1
    BACKUP_FILE="$(mktemp .zig-cache/settings.sav.bak.XXXXXX)"
    cp -f "$SAVES_FILE" "$BACKUP_FILE"
  fi
  cat > "$SAVES_FILE" <<EOF
return {
  version = 1,
  lang = "$LANG_CODE",
}
EOF
fi

if command -v mise >/dev/null 2>&1; then
  mise exec -- zig build
else
  zig build
fi

EXE="./zig-out/bin/winter_survival"
if [ -n "$SCRIPT_PATH" ]; then
  WRAPPER="$(mktemp .zig-cache/shot_exe.XXXXXX.sh)"
  cat > "$WRAPPER" <<EOF
#!/usr/bin/env bash
exec "$ROOT_DIR/zig-out/bin/winter_survival" --no-audio --script "$SCRIPT_PATH" "\$@"
EOF
  chmod +x "$WRAPPER"
  EXE="$WRAPPER"
fi

SECS="$(python3 -c "print(max(4.0, float('$SHOT_AT') + 1.5))")"
xvfb-run -a -s "-screen 0 1280x720x24" \
  python3 ci/smoke.py \
    --exe "$EXE" \
    --cwd "$ROOT_DIR" \
    --shot "$OUT" \
    --shot-at "$SHOT_AT" \
    --seconds "$SECS" \
    --log ".zig-cache/shot.log"

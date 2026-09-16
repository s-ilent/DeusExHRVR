#!/usr/bin/env bash
# Linux/Proton uninstaller for DeusExHRVR. Mirrors uninstall.ps1.
#
# Usage:
#   ./uninstall.sh <game-dir> [options]
#
# Options:
#   --prefix DIR     Wine/Proton prefix for the registry cleanup step
#                    (env fallback: PROTON_PREFIX, WINEPREFIX, UMU_PREFIX)
#   --wine BIN       Wine binary used for `wine reg delete` (env: WINE)
#   --proton DIR     Proton installation dir; its bundled wine is used
#   --umu            Prefer umu-run for the registry step
#   --no-registry    Skip registry cleanup entirely
#   -h, --help       This help
#
# Restores original files + graphics registry settings from the backup manifest
# created by install.sh. Diagnostic logs and the backup itself are preserved.
set -euo pipefail

usage() { sed -n '2,21p' "$0"; }

GAME_DIR=""
PREFIX_ARG=""
WINE_ARG=""
PROTON_ARG=""
USE_UMU=0
NO_REGISTRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)      PREFIX_ARG="$2"; shift 2 ;;
    --wine)        WINE_ARG="$2"; shift 2 ;;
    --proton)      PROTON_ARG="$2"; shift 2 ;;
    --umu)         USE_UMU=1; shift ;;
    --no-registry) NO_REGISTRY=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    --*)           echo "Unknown option: $1" >&2; exit 1 ;;
    *) if [ -z "$GAME_DIR" ]; then GAME_DIR="$1"; shift
       else echo "Unexpected argument: $1" >&2; exit 1; fi ;;
  esac
done

if [ -z "$GAME_DIR" ]; then
  echo "Usage: $0 <game-directory> [--prefix DIR] [--wine BIN] [--proton DIR] [--umu] [--no-registry]" >&2
  exit 1
fi

GAME_DIR=$(cd "$GAME_DIR" && pwd)

if pgrep -x DXHRDC >/dev/null 2>&1; then
  echo "Error: close Deus Ex before restoring." >&2
  exit 1
fi

BACKUP_ROOT="$GAME_DIR/DeusExHRVR-backup"
MANIFEST="$BACKUP_ROOT/install.json"

if [ ! -f "$MANIFEST" ]; then
  echo "Error: no backup manifest at $MANIFEST (was install.sh run?)" >&2
  exit 1
fi

# Read the manifest with python3 (always available) or jq.
if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 required to read the backup manifest." >&2
  exit 1
fi

# Sanity-check the manifest gameRoot matches.
MANIFEST_ROOT=$(python3 -c "import json,sys; print(json.load(open('$MANIFEST'))['gameRoot'])" 2>/dev/null || echo "")
if [ "$MANIFEST_ROOT" != "$GAME_DIR" ]; then
  echo "Error: backup belongs to another game directory ($MANIFEST_ROOT)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Registry machinery (Proton-aware) — mirrors install.sh
# ---------------------------------------------------------------------------

PFX="${PREFIX_ARG:-${PROTON_PREFIX:-${WINEPREFIX:-${UMU_PREFIX:-$HOME/.wine}}}}"
USER_REG="$PFX/user.reg"

proton_dir_wine() {
  local d="$1"
  if [ -x "$d/files/bin/wine" ]; then echo "$d/files/bin/wine"
  elif [ -x "$d/dist/bin/wine" ]; then echo "$d/dist/bin/wine"
  fi
}

autodetect_proton_wine() {
  local roots=(
    "$HOME/.steam/steam/steamapps/common"
    "$HOME/.local/share/Steam/steamapps/common"
    "$HOME/.steam/root/steamapps/common"
    "$HOME/.steam/debian-installation/steamapps/common"
    "$HOME/.steam/steam/compatibilitytools.d"
    "$HOME/.local/share/Steam/compatibilitytools.d"
    "$HOME/.local/share/umu"
  )
  local root d
  {
    for root in "${roots[@]}"; do
      [ -d "$root" ] || continue
      for d in "$root"/Proton* "$root"/GE-Proton* "$root"/UMU-Proton* "$root"/umu-proton*; do
        [ -d "$d" ] || continue
        proton_dir_wine "$d"
      done
    done
  } | sort -V | tail -n 1
}

REG_METHOD=""
REG_WINE=""
REG_UMU=""

if [ "$NO_REGISTRY" -eq 0 ]; then
  if [ -n "$WINE_ARG" ] && [ -x "$WINE_ARG" ]; then
    REG_METHOD="wine"; REG_WINE="$WINE_ARG"
  elif [ -n "${WINE:-}" ] && command -v "$WINE" >/dev/null 2>&1; then
    REG_METHOD="wine"; REG_WINE="$WINE"
  fi
  if [ -z "$REG_METHOD" ] && [ "$USE_UMU" -eq 1 ] && command -v umu-run >/dev/null 2>&1; then
    REG_METHOD="umu"; REG_UMU="umu-run"
  fi
  if [ -z "$REG_METHOD" ] && [ -n "$PROTON_ARG" ]; then
    w=$(proton_dir_wine "$PROTON_ARG" || true)
    if [ -n "$w" ]; then REG_METHOD="wine"; REG_WINE="$w"; fi
  fi
  if [ -z "$REG_METHOD" ] && [ -n "${UMU_PROTON:-}" ]; then
    w=$(proton_dir_wine "$UMU_PROTON" || true)
    if [ -n "$w" ]; then REG_METHOD="wine"; REG_WINE="$w"; fi
  fi
  if [ -z "$REG_METHOD" ]; then
    w=$(autodetect_proton_wine || true)
    if [ -n "$w" ]; then REG_METHOD="wine"; REG_WINE="$w"; fi
  fi
  if [ -z "$REG_METHOD" ]; then
    for candidate in wine wine64; do
      if command -v "$candidate" >/dev/null 2>&1; then
        REG_METHOD="wine"; REG_WINE="$candidate"; break
      fi
    done
  fi
  if [ -z "$REG_METHOD" ] && command -v umu-run >/dev/null 2>&1; then
    REG_METHOD="umu"; REG_UMU="umu-run"
  fi
  if [ -z "$REG_METHOD" ] && [ -f "$USER_REG" ] && command -v python3 >/dev/null 2>&1; then
    REG_METHOD="userreg"
  fi
fi

# Section-aware value deletion in user.reg (raw-space and \x20 forms).
user_reg_del() {
  python3 - "$USER_REG" "$1" <<'PYEOF'
import re, sys
path, name = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8", errors="surrogateescape", newline="") as f:
    lines = f.read().split("\n")
sec_re = re.compile(r"^\[Software\\\\Eidos\\\\Deus(?:\\x20| )Ex:(?:\\x20| )HRDC\\\\Graphics\]$")
val_re = re.compile('^"' + re.escape(name) + '"=dword:')
idx = None
for i, l in enumerate(lines):
    if sec_re.match(l):
        idx = i
        break
if idx is None:
    sys.exit(0)
head, rest, insec = lines[:idx], [], True
for l in lines[idx:]:
    if l == lines[idx]:
        rest.append(l)
        continue
    if l.startswith("["):
        insec = False
    if insec and val_re.match(l):
        continue
    rest.append(l)
with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
    f.write("\n".join(head + rest))
PYEOF
}

reg_del_value() {
  # $1 = value name. Removes it from HKCU\Software\Eidos\Deus Ex: HRDC\Graphics.
  local key='HKCU\Software\Eidos\Deus Ex: HRDC\Graphics'
  case "$REG_METHOD" in
    wine)
      WINEPREFIX="$PFX" "$REG_WINE" reg delete "$key" /v "$1" /f >/dev/null 2>&1 || true ;;
    umu)
      UMU_PREFIX="$PFX" "$REG_UMU" "$PFX/drive_c/windows/system32/reg.exe" DELETE "$key" /v "$1" /f >/dev/null 2>&1 || true ;;
    userreg)
      user_reg_del "$1" ;;
    *)
      return 1 ;;
  esac
}

ALLOWED_REGEX='^(d3d11\.dll|atidxx32\.dll|atiadlxy\.dll|DeusExHRVR/DeusExHRVRHost\.exe)$'

# Restore files: if it existed before, copy back; if not, remove.
python3 -c "
import json, sys
m = json.load(open('$MANIFEST'))
for f in m['files']:
    print(f\"{f['path']}\t{str(f['existed']).lower()}\")
" | while IFS=$'\t' read -r path existed; do
  if ! [[ "$path" =~ $ALLOWED_REGEX ]]; then
    echo "Error: unexpected file in backup manifest: $path" >&2
    exit 1
  fi
  target="$GAME_DIR/$path"
  if [ "$existed" = "true" ]; then
    cp -f "$BACKUP_ROOT/$path" "$target"
  elif [ -f "$target" ]; then
    rm -f "$target"
  fi
done

# Registry settings the installer wrote. The manifest doesn't track
# pre-existing settings on Linux (Wine prefix registry inspection is fragile),
# so we just remove the four values the installer sets. If they existed before
# install, they're now gone — re-set them manually if you need the original
# values (they were DX11/stereo/VSync/AA settings, typically defaulted in-game).
if [ "$NO_REGISTRY" -eq 1 ]; then
  echo "Registry cleanup skipped (--no-registry)."
elif [ -n "$REG_METHOD" ]; then
  del_reg_value() { reg_del_value "$1"; }
  del_reg_value EnableDirectX11
  del_reg_value StereoMode
  del_reg_value EnableVSync
  del_reg_value AntiAliasingMode
  echo "Installer graphics settings removed (method: $REG_METHOD, prefix: $PFX)."
else
  echo "No wine/umu-run/Proton installation found and no user.reg at $USER_REG."
  echo "Registry values left in place — remove them manually if desired:"
  echo "  HKCU\\Software\\Eidos\\Deus Ex: HRDC\\Graphics  (EnableDirectX11, StereoMode, EnableVSync, AntiAliasingMode)"
fi

echo "Restored original files and removed installer graphics settings."
echo "Diagnostic logs and backup are preserved in $BACKUP_ROOT"

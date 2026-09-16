#!/usr/bin/env bash
# Linux/Proton installer for DeusExHRVR. Mirrors install.ps1.
#
# Usage:
#   ./install.sh <game-dir> [options]
#
# Options:
#   --prefix DIR     Wine/Proton prefix for the graphics registry step
#                    (env fallback: PROTON_PREFIX, WINEPREFIX, UMU_PREFIX)
#   --wine BIN       Wine binary used for `wine reg add` (env: WINE)
#   --proton DIR     Proton installation dir; its bundled wine is used
#   --umu            Prefer umu-run for the registry step
#   --no-registry    Skip registry writes entirely
#   -h, --help       This help
#
# Registry notes: the mod DLL now applies the VR-critical settings itself on
# every launch (EnableDirectX11=1, StereoMode=1, EnableVSync=0 — it enforces
# them in-process and re-persists them if the game rewrites them). This
# installer still pre-seeds them (plus AntiAliasingMode=0) as a belt-and-
# braces step for the very first boot, but a missing registry step is no
# longer fatal.
#
# Validates the DXHRDC.exe by PE header (TimeDateStamp + SizeOfImage), matching
# the C++ hook validation. Accepts both Steam and GOG builds of DC 2.0.66.0.
set -euo pipefail

usage() { sed -n '2,24p' "$0"; }

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
EXE="$GAME_DIR/DXHRDC.exe"

if [ ! -f "$EXE" ]; then
  echo "Error: DXHRDC.exe not found in $GAME_DIR" >&2
  exit 1
fi

if pgrep -x DXHRDC >/dev/null 2>&1; then
  echo "Error: close Deus Ex before installation." >&2
  exit 1
fi

# Validate EXE by PE header. e_lfanew at offset 0x3c (4 bytes LE), then
# TimeDateStamp at e_lfanew+8 (4 bytes LE) and SizeOfImage at e_lfanew+80
# (4 bytes LE). Matches install.ps1 + the C++ hook validation exactly.
read_pe_uint32() {
  # $1 = byte offset. Reads 4 LE bytes from $EXE as unsigned int.
  od -An -tu4 -j "$1" -N 4 "$EXE" | tr -d ' '
}

E_LFANEW=$(read_pe_uint32 60)
TIMESTAMP=$(read_pe_uint32 $((E_LFANEW + 8)))
SIZE_OF_IMAGE=$(read_pe_uint32 $((E_LFANEW + 80)))

# printf them as hex for the error message
TS_HEX=$(printf '0x%08x' "$TIMESTAMP")
SOI_HEX=$(printf '0x%08x' "$SIZE_OF_IMAGE")

if [ "$TIMESTAMP" -ne 1384384788 ] || [ "$SIZE_OF_IMAGE" -ne 29704192 ]; then
  # 1384384788 = 0x52840914, 29704192 = 0x01c54000
  echo "Error: unsupported DXHRDC.exe build (TimeDateStamp=$TS_HEX, SizeOfImage=$SOI_HEX)." >&2
  echo "This mod supports Director's Cut 2.0.66.0 (Steam and GOG)." >&2
  exit 1
fi

PAYLOAD="$PWD/dist"
FILES=("d3d11.dll" "atidxx32.dll" "atiadlxy.dll" "DeusExHRVR/DeusExHRVRHost.exe")
for f in "${FILES[@]}"; do
  if [ ! -f "$PAYLOAD/$f" ]; then
    echo "Error: missing payload: $f (expected in $PAYLOAD)" >&2
    exit 1
  fi
done

BACKUP_ROOT="$GAME_DIR/DeusExHRVR-backup"
MANIFEST="$BACKUP_ROOT/install.json"

# ---------------------------------------------------------------------------
# Registry machinery (Proton-aware)
# ---------------------------------------------------------------------------

# The prefix: --prefix > PROTON_PREFIX > WINEPREFIX > UMU_PREFIX > ~/.wine.
PFX="${PREFIX_ARG:-${PROTON_PREFIX:-${WINEPREFIX:-${UMU_PREFIX:-$HOME/.wine}}}}"
USER_REG="$PFX/user.reg"

# Resolve a Proton dir's bundled wine (layout differs across Proton versions).
proton_dir_wine() {
  local d="$1"
  if [ -x "$d/files/bin/wine" ]; then echo "$d/files/bin/wine"
  elif [ -x "$d/dist/bin/wine" ]; then echo "$d/dist/bin/wine"
  fi
}

# Newest Proton-bundled wine found in the common Steam/Proton-GE/umu locations.
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
  # 1) explicit wine (--wine / $WINE)
  if [ -n "$WINE_ARG" ] && [ -x "$WINE_ARG" ]; then
    REG_METHOD="wine"; REG_WINE="$WINE_ARG"
  elif [ -n "${WINE:-}" ] && command -v "$WINE" >/dev/null 2>&1; then
    REG_METHOD="wine"; REG_WINE="$WINE"
  fi
  # 2) umu-run when explicitly requested
  if [ -z "$REG_METHOD" ] && [ "$USE_UMU" -eq 1 ] && command -v umu-run >/dev/null 2>&1; then
    REG_METHOD="umu"; REG_UMU="umu-run"
  fi
  # 3) --proton / $UMU_PROTON bundled wine
  if [ -z "$REG_METHOD" ] && [ -n "$PROTON_ARG" ]; then
    w=$(proton_dir_wine "$PROTON_ARG" || true)
    if [ -n "$w" ]; then REG_METHOD="wine"; REG_WINE="$w"; fi
  fi
  if [ -z "$REG_METHOD" ] && [ -n "${UMU_PROTON:-}" ]; then
    w=$(proton_dir_wine "$UMU_PROTON" || true)
    if [ -n "$w" ]; then REG_METHOD="wine"; REG_WINE="$w"; fi
  fi
  # 4) auto-detected Steam/GE/umu Proton installs
  if [ -z "$REG_METHOD" ]; then
    w=$(autodetect_proton_wine || true)
    if [ -n "$w" ]; then REG_METHOD="wine"; REG_WINE="$w"; fi
  fi
  # 5) system wine
  if [ -z "$REG_METHOD" ]; then
    for candidate in wine wine64; do
      if command -v "$candidate" >/dev/null 2>&1; then
        REG_METHOD="wine"; REG_WINE="$candidate"; break
      fi
    done
  fi
  # 6) umu-run without an explicit request
  if [ -z "$REG_METHOD" ] && command -v umu-run >/dev/null 2>&1; then
    REG_METHOD="umu"; REG_UMU="umu-run"
  fi
  # 7) direct user.reg edit
  if [ -z "$REG_METHOD" ] && [ -f "$USER_REG" ] && command -v python3 >/dev/null 2>&1; then
    REG_METHOD="userreg"
  fi
fi

# Section-aware user.reg edit. Wine escapes spaces in section names as \x20
# in some versions and keeps them raw in others; both forms are handled.
user_reg_set() {
  python3 - "$USER_REG" "$1" "$2" <<'PYEOF'
import re, sys
path, name, val = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r", encoding="utf-8", errors="surrogateescape", newline="") as f:
    lines = f.read().split("\n")
sec_re = re.compile(r"^\[Software\\\\Eidos\\\\Deus(?:\\x20| )Ex:(?:\\x20| )HRDC\\\\Graphics\]$")
val_re = re.compile('^"' + re.escape(name) + '"=dword:')
vline  = '"%s"=dword:%s' % (name, val)
idx = None
for i, l in enumerate(lines):
    if sec_re.match(l):
        idx = i
        break
if idx is None:
    if lines and lines[-1].strip() != "":
        lines.append("")
    lines.append("[Software\\\\Eidos\\\\Deus Ex: HRDC\\\\Graphics]")
    lines.append(vline)
else:
    head = lines[:idx + 1]
    # Drop any existing value lines between this header and the next one,
    # then insert the new value directly under the section header.
    rest, insec = [], True
    for l in lines[idx + 1:]:
        if l.startswith("["):
            insec = False
        if insec and val_re.match(l):
            continue
        rest.append(l)
    lines = head + [vline] + rest
with open(path, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
    f.write("\n".join(lines))
PYEOF
}

reg_set_dword() {
  # $1 = value name, $2 = dword value. Sets under
  # HKCU\Software\Eidos\Deus Ex: HRDC\Graphics.
  local key='HKCU\Software\Eidos\Deus Ex: HRDC\Graphics'
  case "$REG_METHOD" in
    wine)
      WINEPREFIX="$PFX" "$REG_WINE" reg add "$key" /v "$1" /t REG_DWORD /d "$2" /f >/dev/null 2>&1 || true ;;
    umu)
      UMU_PREFIX="$PFX" "$REG_UMU" "$PFX/drive_c/windows/system32/reg.exe" ADD "$key" /v "$1" /t REG_DWORD /d "$2" /f >/dev/null 2>&1 || true ;;
    userreg)
      user_reg_set "$1" "$(printf '%08x' "$2")" ;;
    *)
      return 1 ;;
  esac
}

if [ ! -f "$MANIFEST" ]; then
  mkdir -p "$BACKUP_ROOT"
  # Back up existing files + record whether they existed.
  ENTRIES='['
  for f in "${FILES[@]}"; do
    target="$GAME_DIR/$f"
    existed=false
    if [ -f "$target" ]; then
      mkdir -p "$(dirname "$BACKUP_ROOT/$f")"
      cp -f "$target" "$BACKUP_ROOT/$f"
      existed=true
    fi
    ENTRIES="$ENTRIES{\"path\":\"$f\",\"existed\":$existed},"
  done
  ENTRIES="${ENTRIES%,}]"
  printf '{"version":1,"gameRoot":"%s","files":%s}\n' "$GAME_DIR" "$ENTRIES" > "$MANIFEST"
fi

# Install the payload files.
for f in "${FILES[@]}"; do
  target="$GAME_DIR/$f"
  mkdir -p "$(dirname "$target")"
  cp -f "$PAYLOAD/$f" "$target"
done

# Sync the mod-owned payload folder (host + compiled shaders + table.csv).
if [ -d "$PAYLOAD/DeusExHRVR" ]; then
  mkdir -p "$GAME_DIR/DeusExHRVR"
  cp -a "$PAYLOAD/DeusExHRVR/." "$GAME_DIR/DeusExHRVR/"
fi

# Pre-seed the graphics registry keys (DX11 + stereo, VSync + AA off).
if [ "$NO_REGISTRY" -eq 1 ]; then
  echo "Registry step skipped (--no-registry). The mod DLL applies EnableDirectX11/StereoMode/EnableVSync itself on launch."
elif [ -n "$REG_METHOD" ]; then
  REG_LABEL="$REG_METHOD"
  [ "$REG_METHOD" = "wine" ] && REG_LABEL="wine ($REG_WINE)"
  [ "$REG_METHOD" = "umu" ] && REG_LABEL="umu-run (prefix: $PFX)"
  [ "$REG_METHOD" = "userreg" ] && REG_LABEL="direct user.reg edit ($USER_REG)"
  set_reg_dword EnableDirectX11 1
  set_reg_dword StereoMode 1
  set_reg_dword EnableVSync 0
  set_reg_dword AntiAliasingMode 0
  echo "Graphics registry pre-seeded via $REG_LABEL (prefix: $PFX)."
  echo "The mod DLL re-applies and enforces EnableDirectX11/StereoMode/EnableVSync on every launch."
else
  echo "No wine/umu-run/Proton installation found and no user.reg at $USER_REG."
  echo "Registry not pre-seeded — that is OK: the mod DLL applies EnableDirectX11/StereoMode/EnableVSync itself on launch."
fi

echo "Installed native stereo bridge. Original files/settings are in $BACKUP_ROOT"

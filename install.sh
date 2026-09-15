#!/usr/bin/env bash
# Linux/Proton installer for DeusExHRVR. Mirrors install.ps1.
#
# Usage:
#   ./install.sh /path/to/your/Deus\ Ex\ Human\ Revolution\ Director\'s\ Cut
#
# Validates the DXHRDC.exe by PE header (TimeDateStamp + SizeOfImage), matching
# the C++ hook validation. Accepts both Steam and GOG builds of DC 2.0.66.0.
#
# Under Proton, the game's "registry" is the Wine prefix's user.reg. We set the
# graphics keys via `wine reg add` when a Wine binary is available, falling
# back to direct user.reg editing if not. The registry path mirrors the
# PowerShell installer: HKCU\Software\Eidos\Deus Ex: HRDC\Graphics
#   EnableDirectX11=1, StereoMode=1, EnableVSync=0, AntiAliasingMode=0
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <game-directory>" >&2
  exit 1
fi

GAME_DIR=$(cd "$1" && pwd)
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

# Locate the Wine prefix + a Wine binary for registry writes.
# PROTON_PREFIX / WINEPREFIX point at the prefix; PROTONPATH / wine on PATH
# give us a binary. Under Steam Play, Steam sets these when launching the game;
# for manual runs the user typically has WINEPREFIX set.
WINE_PREFIX="${PROTON_PREFIX:-${WINEPREFIX:-$HOME/.wine}}"
WINE_BIN=""
for candidate in "${WINE:-}" wine wine64; do
  if command -v "$candidate" >/dev/null 2>&1; then WINE_BIN="$candidate"; break; fi
done

set_reg_dword() {
  # $1 = value name, $2 = dword value. Sets under
  # HKCU\Software\Eidos\Deus Ex: HRDC\Graphics.
  local key='HKCU\Software\Eidos\Deus Ex: HRDC\Graphics'
  if [ -n "$WINE_BIN" ]; then
    WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg add "$key" /v "$1" /t REG_DWORD /d "$2" /f >/dev/null 2>&1 || true
  else
    # Fallback: edit user.reg directly. The section header uses Wine's
    # escaped form (spaces -> \\x20). Append the value under the section.
    local user_reg="$WINE_PREFIX/user.reg"
    if [ -f "$user_reg" ]; then
      local sect='[Software\\Eidos\\Deus Ex: HRDC\\Graphics]'
      # Ensure section exists, then set the value (reg file format).
      if ! grep -qF "$sect" "$user_reg"; then
        printf '\n%s\n' "$sect" >> "$user_reg"
      fi
      # Remove any existing entry for this value name, then append.
      sed -i "/^\"$1\"=dword:/d" "$user_reg"
      printf '"%s"=dword:%08x\n' "$1" "$2" >> "$user_reg"
    fi
  fi
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

# Set graphics registry keys (DX11 + stereo, VSync + AA off).
set_reg_dword EnableDirectX11 1
set_reg_dword StereoMode 1
set_reg_dword EnableVSync 0
set_reg_dword AntiAliasingMode 0

echo "Installed native stereo bridge. Original files/settings are in $BACKUP_ROOT"

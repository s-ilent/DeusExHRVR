#!/usr/bin/env bash
# Linux/Proton uninstaller for DeusExHRVR. Mirrors uninstall.ps1.
#
# Usage:
#   ./uninstall.sh /path/to/your/Deus\ Ex\ Human\ Revolution\ Director\'s\ Cut
#
# Restores original files + graphics registry settings from the backup manifest
# created by install.sh. Diagnostic logs and the backup itself are preserved.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <game-directory>" >&2
  exit 1
fi

if pgrep -x DXHRDC >/dev/null 2>&1; then
  echo "Error: close Deus Ex before restoring." >&2
  exit 1
fi

GAME_DIR=$(cd "$1" && pwd)
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

WINE_PREFIX="${PROTON_PREFIX:-${WINEPREFIX:-$HOME/.wine}}"
WINE_BIN=""
for candidate in "${WINE:-}" wine wine64; do
  if command -v "$candidate" >/dev/null 2>&1; then WINE_BIN="$candidate"; break; fi
done

del_reg_value() {
  # $1 = value name. Removes it from HKCU\Software\Eidos\Deus Ex: HRDC\Graphics.
  local key='HKCU\Software\Eidos\Deus Ex: HRDC\Graphics'
  if [ -n "$WINE_BIN" ]; then
    WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg delete "$key" /v "$1" /f >/dev/null 2>&1 || true
  else
    local user_reg="$WINE_PREFIX/user.reg"
    if [ -f "$user_reg" ]; then
      sed -i "/^\"$1\"=dword:/d" "$user_reg"
    fi
  fi
}
set_reg_dword() {
  local key='HKCU\Software\Eidos\Deus Ex: HRDC\Graphics'
  if [ -n "$WINE_BIN" ]; then
    WINEPREFIX="$WINE_PREFIX" "$WINE_BIN" reg add "$key" /v "$1" /t REG_DWORD /d "$2" /f >/dev/null 2>&1 || true
  else
    local user_reg="$WINE_PREFIX/user.reg"
    if [ -f "$user_reg" ]; then
      local sect='[Software\\Eidos\\Deus Ex: HRDC\\Graphics]'
      grep -qF "$sect" "$user_reg" || printf '\n%s\n' "$sect" >> "$user_reg"
      sed -i "/^\"$1\"=dword:/d" "$user_reg"
      printf '"%s"=dword:%08x\n' "$1" "$2" >> "$user_reg"
    fi
  fi
}

ALLOWED=("d3d11.dll" "atidxx32.dll" "atiadlxy.dll" "DeusExHRVR/DeusExHRVRHost.exe")
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
del_reg_value EnableDirectX11
del_reg_value StereoMode
del_reg_value EnableVSync
del_reg_value AntiAliasingMode

echo "Restored original files and removed installer graphics settings."
echo "Diagnostic logs and backup are preserved in $BACKUP_ROOT"

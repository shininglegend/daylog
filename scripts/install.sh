#!/bin/bash
# Replaces /Applications/DayLog.app with build/DayLog.app and relaunches it.
# Run after ./build.sh. Data and keychain items live outside the app bundle,
# and permission grants survive as long as the signing identity is unchanged.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/DayLog.app"
DEST="/Applications/DayLog.app"

[[ -d "$SRC" ]] || { echo "no build at $SRC; run ./build.sh first" >&2; exit 1; }

# Refuse to install a build whose signature would invalidate existing grants.
if [[ -d "$DEST" ]]; then
  new_req="$(codesign -d -r- "$SRC" 2>&1 | grep designated || true)"
  old_req="$(codesign -d -r- "$DEST" 2>&1 | grep designated || true)"
  if [[ "$new_req" != "$old_req" ]]; then
    echo "WARNING: the new build is signed differently from the installed one." >&2
    echo "         Accessibility/Automation grants and keychain access will need re-approval." >&2
    read -r -p "Install anyway? [y/N] " answer
    [[ "$answer" == [yY] ]] || exit 1
  fi
fi

if pgrep -xq DayLog; then
  echo "==> Quitting DayLog"
  osascript -e 'tell application id "local.daylog" to quit' || true
  for _ in {1..20}; do pgrep -xq DayLog || break; sleep 0.25; done
  pgrep -xq DayLog && { echo "DayLog didn't quit; quit it from the menu bar and retry" >&2; exit 1; }
fi

echo "==> Installing to $DEST"
rm -rf "$DEST"
ditto "$SRC" "$DEST"

echo "==> Launching"
open "$DEST"

#!/bin/bash
# Fails if DayLog's own binaries link Network.framework or reference
# URLSession / CFSocket / nw_ symbols. Usage: check-no-network.sh path/to/DayLog.app
set -euo pipefail
APP="${1:?usage: $0 path/to/DayLog.app}"

BINARIES=("$APP/Contents/MacOS/DayLog")
while IFS= read -r fw; do
  name="$(basename "$fw" .framework)"
  BINARIES+=("$fw/Versions/Current/$name")
done < <(find "$APP/Contents/Frameworks" -maxdepth 1 -name '*.framework' 2>/dev/null)

fail=0
for bin in "${BINARIES[@]}"; do
  [[ -f "$bin" ]] || { echo "missing binary: $bin" >&2; exit 1; }
  if otool -L "$bin" | grep -qi 'Network.framework'; then
    echo "FAIL: $bin links Network.framework" >&2; fail=1
  fi
  hits="$(nm -u "$bin" | grep -E 'NSURLSession|URLSession|CFSocket|_nw_' || true)"
  if [[ -n "$hits" ]]; then
    echo "FAIL: $bin references network symbols:" >&2
    echo "$hits" >&2
    fail=1
  fi
  [[ $fail -eq 0 ]] && echo "ok: $(basename "$bin")"
done
exit $fail

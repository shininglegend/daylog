#!/bin/bash
# Build, test, sign, and verify DayLog.app.
# Usage: ./build.sh "<code signing identity>"   (use "-" for ad-hoc, development only)
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 \"<code signing identity>\"   (\"-\" = ad-hoc)" >&2
  echo "available identities:" >&2
  security find-identity -p codesigning >&2 || true
  exit 64
fi
IDENTITY="$1"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
APP="$BUILD_DIR/DayLog.app"

if [[ "$IDENTITY" == "-" ]]; then
  echo "WARNING: ad-hoc signing. macOS permission grants (Accessibility, Automation)" >&2
  echo "         will NOT survive rebuilds. See README → Signing." >&2
fi

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }

cd "$ROOT"
echo "==> Generating Xcode project"
xcodegen generate --quiet

echo "==> Running unit tests"
xcodebuild test \
  -project DayLog.xcodeproj -scheme DayLog \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$DERIVED" \
  -quiet

echo "==> Building Release"
xcodebuild build \
  -project DayLog.xcodeproj -scheme DayLog -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual \
  OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
  -quiet

rm -rf "$APP"
ditto "$DERIVED/Build/Products/Release/DayLog.app" "$APP"

echo "==> No-network check"
"$ROOT/scripts/check-no-network.sh" "$APP"

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "com.apple.security.automation.apple-events" \
  || { echo "missing apple-events entitlement" >&2; exit 1; }
codesign -dv "$APP" 2>&1 | grep -q "flags=.*runtime" \
  || { echo "hardened runtime not enabled" >&2; exit 1; }

echo "==> Built $APP"

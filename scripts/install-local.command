#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
APP_NAME="CodexQuota.app"
BUILD_DIR="${ROOT_DIR}/build/DerivedData"
BUILT_APP="${BUILD_DIR}/Build/Products/Release/${APP_NAME}"
INSTALL_DIR="${HOME}/Applications"
INSTALLED_APP="${INSTALL_DIR}/${APP_NAME}"

cd "${ROOT_DIR}"

echo "Codex Quota local installer"
echo

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Xcode is required. Install Xcode from the Mac App Store first."
  exit 1
fi

if [[ "$(xcode-select -p)" != *"/Xcode.app/"* ]]; then
  echo "Your active developer directory is not full Xcode."
  echo "Run this once, then re-run this installer:"
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

echo "Building Release app..."
xcodebuild \
  -quiet \
  -project CodexQuota.xcodeproj \
  -scheme CodexQuota \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "Signing app locally..."
codesign --force --sign - --entitlements CodexQuotaWidget/CodexQuotaWidget.entitlements "${BUILT_APP}/Contents/PlugIns/CodexQuotaWidget.appex"
codesign --force --sign - --entitlements CodexQuota/CodexQuota.entitlements "${BUILT_APP}"
codesign --verify --deep --strict --verbose=2 "${BUILT_APP}" >/dev/null

echo "Installing to ${INSTALLED_APP}..."
mkdir -p "${INSTALL_DIR}"
pkill -x CodexQuota 2>/dev/null || true
rm -rf "${INSTALLED_APP}"
ditto "${BUILT_APP}" "${INSTALLED_APP}"

echo "Opening Codex Quota..."
open "${INSTALLED_APP}"

echo
echo "Done."
echo "Next steps:"
echo "1. Wait 30-60 seconds for the menu bar app to read local Codex logs."
echo "2. Right-click the desktop and choose Edit Widgets."
echo "3. Search for Codex Quota or Codex 额度, then add the widget."
echo
read -k 1 "?Press any key to close..."

#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
APP_NAME="CodexQuota.app"
BUILD_DIR="${ROOT_DIR}/build/DerivedData"
BUILT_APP="${BUILD_DIR}/Build/Products/Release/${APP_NAME}"
INSTALL_DIR="${HOME}/Applications"
INSTALLED_APP="${INSTALL_DIR}/${APP_NAME}"
LEGACY_APP="/Applications/${APP_NAME}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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
pkill -x CodexQuotaWidget 2>/dev/null || true

if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -u "${BUILT_APP}" 2>/dev/null || true
  for trashed_app in "${HOME}"/.Trash/CodexQuota*.app(N); do
    "${LSREGISTER}" -u "${trashed_app}" 2>/dev/null || true
  done
fi

if [[ -d "${LEGACY_APP}" && "${LEGACY_APP}" != "${INSTALLED_APP}" ]]; then
  echo "Removing legacy install at ${LEGACY_APP}..."
  if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -u "${LEGACY_APP}" 2>/dev/null || true
  fi
  if ! rm -rf "${LEGACY_APP}" 2>/dev/null; then
    echo "Could not remove ${LEGACY_APP}."
    echo "If widgets still load an old version, run:"
    echo "  sudo rm -rf '${LEGACY_APP}'"
  fi
fi
rm -rf "${INSTALLED_APP}"
ditto "${BUILT_APP}" "${INSTALLED_APP}"

if [[ -x "${LSREGISTER}" ]]; then
  echo "Refreshing app and widget registration..."
  "${LSREGISTER}" -f "${INSTALLED_APP}" 2>/dev/null || true
fi

killall chronod 2>/dev/null || true

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

#!/bin/zsh
set -e

echo "Codex Quota needs Xcode first-launch components to build the macOS Widget."
echo "macOS may ask for your administrator password below."
echo
sudo xcodebuild -runFirstLaunch
echo
echo "Xcode first-launch setup finished. You can close this Terminal window."
read -k 1 "?Press any key to close..."

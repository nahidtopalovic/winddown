#!/bin/bash
# Builds the SPM executable and assembles Winddown.app. Ad-hoc signed so
# UserNotifications and launch-at-login work locally.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP=build/Winddown.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Winddown "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run:    open $APP"
echo "Install: cp -R $APP /Applications/"

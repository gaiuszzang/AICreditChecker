#!/bin/bash
# AICreditChecker.app 번들 생성 (메뉴바 전용, Dock 아이콘 없음)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/AICreditChecker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AICreditChecker "$APP/Contents/MacOS/AICreditChecker"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AICreditChecker</string>
    <key>CFBundleDisplayName</key><string>AI Credit Checker</string>
    <key>CFBundleIdentifier</key><string>dev.local.AICreditChecker</string>
    <key>CFBundleExecutable</key><string>AICreditChecker</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>ko</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built: $APP"
echo "설치: cp -R $APP /Applications/ && open /Applications/AICreditChecker.app"

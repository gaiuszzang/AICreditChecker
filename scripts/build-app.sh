#!/bin/bash
# AICreditChecker.app 번들 생성 (메뉴바 전용, Dock 아이콘 없음)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "오류: macOS에서 실행해야 합니다." >&2
    exit 1
fi

if ! xcrun --find swift >/dev/null 2>&1; then
    echo "오류: Xcode 또는 Command Line Tools가 필요합니다. xcode-select --install 을 실행하세요." >&2
    exit 1
fi

echo "현재 Mac 아키텍처($(uname -m))용 릴리스 빌드 중…"
swift build -c release --product AICreditChecker
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/AICreditChecker.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AICreditChecker" "$APP/Contents/MacOS/AICreditChecker"

# 원본 PNG에서 Retina를 포함한 macOS 아이콘 크기 생성
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AICreditChecker</string>
    <key>CFBundleDisplayName</key><string>AI Credit Checker</string>
    <key>CFBundleIdentifier</key><string>dev.local.AICreditChecker</string>
    <key>CFBundleExecutable</key><string>AICreditChecker</string>
    <key>CFBundleIconFile</key><string>AppIcon.icns</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>ko</string>
</dict>
</plist>
PLIST

plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
echo "실행: open $APP"
echo "설치: cp -R $APP /Applications/ && open /Applications/AICreditChecker.app"

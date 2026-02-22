#!/bin/zsh

# ClothIQ Quick Deploy Script
# 빌드 → 설치 → 실행을 한 번에 수행

set -e  # 에러 발생 시 중단

PROJECT_DIR="/Users/cauca/Projects/ClothIQ-ClaudeCode/ClothIQ"
DEVICE_ID="00008027-001A65243499802E"
BUNDLE_ID="com.eunyeon.ClothIQ"

echo "📦 [1/4] Building ClothIQ..."
cd "$PROJECT_DIR"
xcodebuild -project ClothIQ.xcodeproj \
  -scheme ClothIQ \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  build 2>&1 | grep -E "(BUILD|error|warning)" | tail -20

if [ $? -eq 0 ]; then
    echo "✅ Build succeeded"
else
    echo "❌ Build failed"
    exit 1
fi

# Build output 경로 찾기
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "ClothIQ.app" -path "*/Debug-iphoneos/ClothIQ.app" | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Cannot find ClothIQ.app"
    exit 1
fi

echo "📲 [2/4] Installing to device..."
xcrun devicectl device install app \
  --device "$DEVICE_ID" \
  "$APP_PATH"

if [ $? -eq 0 ]; then
    echo "✅ Installation succeeded"
else
    echo "❌ Installation failed"
    exit 1
fi

echo "🚀 [3/4] Launching app..."
xcrun devicectl device process launch \
  --device "$DEVICE_ID" \
  "$BUNDLE_ID"

if [ $? -eq 0 ]; then
    echo "✅ App launched"
else
    echo "❌ Launch failed"
    exit 1
fi

echo "📋 [4/4] Streaming logs..."
echo "Press Ctrl+C to stop"
log stream --device "$DEVICE_ID" \
  --predicate 'subsystem == "com.eunyeon.ClothIQ"' \
  --level info

#!/bin/zsh

# ClothIQ Automated Test Script
# 빌드 → 배포 → 테스트 시나리오 실행 → 결과 검증

set -e

PROJECT_ROOT="/Users/cauca/Projects/ClothIQ-ClaudeCode"
DEVICE_ID="00008027-001A65243499802E"
BUNDLE_ID="com.eunyeon.ClothIQ"
TEST_DATA_DIR="$PROJECT_ROOT/TestData"
RESULT_DIR="$PROJECT_ROOT/TestResults"

# 결과 디렉토리 생성
mkdir -p "$RESULT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULT_FILE="$RESULT_DIR/test_result_$TIMESTAMP.txt"

echo "🧪 [ClothIQ Automated Test]" | tee "$RESULT_FILE"
echo "Timestamp: $TIMESTAMP" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# Step 1: 빌드
echo "📦 Step 1: Building..." | tee -a "$RESULT_FILE"
cd "$PROJECT_ROOT/ClothIQ"
BUILD_OUTPUT=$(xcodebuild -project ClothIQ.xcodeproj \
  -scheme ClothIQ \
  -configuration Debug \
  -destination "platform=iOS,id=$DEVICE_ID" \
  build 2>&1)

if echo "$BUILD_OUTPUT" | grep -q "BUILD SUCCEEDED"; then
    echo "✅ Build: PASS" | tee -a "$RESULT_FILE"
else
    echo "❌ Build: FAIL" | tee -a "$RESULT_FILE"
    echo "$BUILD_OUTPUT" | grep -E "error:" | tee -a "$RESULT_FILE"
    exit 1
fi

# Step 2: 설치
echo "📲 Step 2: Installing..." | tee -a "$RESULT_FILE"
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "ClothIQ.app" -path "*/Debug-iphoneos/ClothIQ.app" | head -1)
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ Install: PASS" | tee -a "$RESULT_FILE"
else
    echo "❌ Install: FAIL" | tee -a "$RESULT_FILE"
    exit 1
fi

# Step 3: 실행
echo "🚀 Step 3: Launching app..." | tee -a "$RESULT_FILE"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" > /dev/null 2>&1
sleep 3  # 앱 초기화 대기

if [ $? -eq 0 ]; then
    echo "✅ Launch: PASS" | tee -a "$RESULT_FILE"
else
    echo "❌ Launch: FAIL" | tee -a "$RESULT_FILE"
    exit 1
fi

# Step 4: 로그 수집 시작
echo "📋 Step 4: Collecting logs..." | tee -a "$RESULT_FILE"
LOG_FILE="$RESULT_DIR/test_log_$TIMESTAMP.txt"

# 백그라운드에서 로그 스트리밍 시작
log stream --device "$DEVICE_ID" \
  --predicate 'subsystem == "com.eunyeon.ClothIQ"' \
  --level info > "$LOG_FILE" 2>&1 &
LOG_PID=$!

# Step 5: 테스트 시나리오 실행 대기
echo "⏳ Waiting for user to perform test scenario..." | tee -a "$RESULT_FILE"
echo "   1. Open clothing library" | tee -a "$RESULT_FILE"
echo "   2. Select an item (shorts)" | tee -a "$RESULT_FILE"
echo "   3. Tap '재측정' button" | tee -a "$RESULT_FILE"
echo "   4. Complete measurement" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"
echo "Press ENTER when test is complete..."
read

# 로그 수집 종료
kill $LOG_PID 2>/dev/null
sleep 1

# Step 6: 결과 분석
echo "🔍 Step 6: Analyzing results..." | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"

# 의류 분류 확인
CLASSIFICATION=$(grep "ClothingType" "$LOG_FILE" | tail -1)
if echo "$CLASSIFICATION" | grep -q "shorts"; then
    echo "✅ Classification: PASS (shorts)" | tee -a "$RESULT_FILE"
else
    echo "❌ Classification: FAIL" | tee -a "$RESULT_FILE"
    echo "   Found: $CLASSIFICATION" | tee -a "$RESULT_FILE"
fi

# 신뢰도 확인
CONFIDENCE=$(grep "confidence" "$LOG_FILE" | grep -E "[0-9]+\.[0-9]+" | tail -1)
if echo "$CONFIDENCE" | grep -qE "0\.[7-9][0-9]|0\.8[0-9]"; then
    echo "✅ Confidence: PASS (>70%)" | tee -a "$RESULT_FILE"
    echo "   Value: $CONFIDENCE" | tee -a "$RESULT_FILE"
else
    echo "⚠️  Confidence: CHECK" | tee -a "$RESULT_FILE"
    echo "   Value: $CONFIDENCE" | tee -a "$RESULT_FILE"
fi

# 좌표 방향 확인
COORDS=$(grep -E "start.*end" "$LOG_FILE" | grep -E "y.*y" | tail -1)
if [ -n "$COORDS" ]; then
    echo "✅ Coordinates: FOUND" | tee -a "$RESULT_FILE"
    echo "   $COORDS" | tee -a "$RESULT_FILE"
else
    echo "⚠️  Coordinates: NOT FOUND" | tee -a "$RESULT_FILE"
fi

echo "" | tee -a "$RESULT_FILE"
echo "📊 Test Summary:" | tee -a "$RESULT_FILE"
echo "   Build: ✅" | tee -a "$RESULT_FILE"
echo "   Install: ✅" | tee -a "$RESULT_FILE"
echo "   Launch: ✅" | tee -a "$RESULT_FILE"
echo "   Classification: $(grep -q '✅ Classification' "$RESULT_FILE" && echo '✅' || echo '❌')" | tee -a "$RESULT_FILE"
echo "   Confidence: $(grep -q '✅ Confidence' "$RESULT_FILE" && echo '✅' || echo '⚠️')" | tee -a "$RESULT_FILE"
echo "" | tee -a "$RESULT_FILE"
echo "Full logs saved to: $LOG_FILE"
echo "Test results saved to: $RESULT_FILE"

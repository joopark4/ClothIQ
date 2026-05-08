#!/bin/bash

###############################################################################
# ClothIQ Build Validator (Evaluator)
#
# Generator-Evaluator 패턴의 Evaluator 역할.
# 코드 변경 후 빌드 성공 여부와 경고/에러를 자동 검증합니다.
#
# 사용법:
#   ./scripts/validate_build.sh              # 전체 빌드 검증
#   ./scripts/validate_build.sh --quick      # 증분 빌드 (clean 없이)
#   ./scripts/validate_build.sh --warnings   # 경고만 분석 (빌드 스킵)
#
# 종료 코드:
#   0 - 빌드 성공, 새 경고 없음
#   1 - 빌드 실패
#   2 - 빌드 성공, 새 경고 발생
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/ClothIQ/ClothIQ.xcodeproj"
SCHEME="ClothIQ"
DERIVED_DATA="${CLOTHIQ_DERIVED_DATA:-/private/tmp/ClothIQDerivedData-Codex}"
BUILD_LOG="$PROJECT_ROOT/tmp_crash_logs/last_build.log"
WARNING_BASELINE="$PROJECT_ROOT/tmp_crash_logs/warning_baseline.txt"

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_step()    { echo -e "${CYAN}[STEP]${NC} $1"; }
log_pass()    { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail()    { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }

normalize_warning_lines() {
    sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]+ [^ ]+\[[^]]+\] //' \
        | grep -v "Metadata extraction skipped. No AppIntents.framework dependency found." \
        || true
}

# 임시 디렉토리 보장
mkdir -p "$PROJECT_ROOT/tmp_crash_logs"

# --- 옵션 파싱 ---
QUICK_MODE=false
WARNINGS_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --quick)    QUICK_MODE=true ;;
        --warnings) WARNINGS_ONLY=true ;;
        --help|-h)
            echo "사용법: $0 [--quick] [--warnings]"
            echo "  --quick      증분 빌드 (clean 없이)"
            echo "  --warnings   기존 빌드 로그에서 경고만 분석"
            exit 0
            ;;
    esac
done

# --- 경고 분석 함수 ---
analyze_warnings() {
    local log_file="$1"

    if [ ! -f "$log_file" ]; then
        log_fail "빌드 로그를 찾을 수 없습니다: $log_file"
        return 1
    fi

    local warnings
    warnings=$(
        (grep "warning:" "$log_file" 2>/dev/null || true) \
            | normalize_warning_lines \
            | wc -l \
            | tr -d ' '
    )
    warnings=${warnings:-0}
    local errors
    errors=$(grep -c "error:" "$log_file" 2>/dev/null || true)
    errors=${errors:-0}

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  빌드 검증 결과"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  에러:   ${errors}개"
    echo -e "  경고:   ${warnings}개"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # 에러 상세
    if [ "$errors" -gt 0 ]; then
        echo ""
        log_fail "컴파일 에러 목록:"
        grep "error:" "$log_file" | head -20 | while IFS= read -r line; do
            echo "  $line"
        done
    fi

    # 새 경고 감지 (baseline 대비)
    local current_warnings_file
    current_warnings_file=$(mktemp)
    (grep "warning:" "$log_file" 2>/dev/null || true) | normalize_warning_lines | sort > "$current_warnings_file"

    if [ -f "$WARNING_BASELINE" ]; then
        local normalized_baseline_file
        normalized_baseline_file=$(mktemp)
        normalize_warning_lines < "$WARNING_BASELINE" | sort > "$normalized_baseline_file"

        local new_warnings
        new_warnings=$(comm -13 "$normalized_baseline_file" "$current_warnings_file" | wc -l | tr -d ' ')
        if [ "$new_warnings" -gt 0 ]; then
            echo ""
            log_warn "새로 추가된 경고 ${new_warnings}개:"
            comm -13 "$normalized_baseline_file" "$current_warnings_file" | head -10 | while IFS= read -r line; do
                echo "  $line"
            done
            rm -f "$current_warnings_file" "$normalized_baseline_file"
            return 2
        else
            sort -u "$normalized_baseline_file" "$current_warnings_file" > "$WARNING_BASELINE"
            log_pass "새 경고 없음 (baseline 대비)"
        fi
        rm -f "$normalized_baseline_file"
    else
        # baseline이 없으면 현재를 baseline으로 저장
        cp "$current_warnings_file" "$WARNING_BASELINE"
        log_info "경고 baseline 생성됨 (${warnings}개 경고 기록)"
    fi

    rm -f "$current_warnings_file"
    return 0
}

# --- 경고 전용 모드 ---
if [ "$WARNINGS_ONLY" = true ]; then
    log_step "기존 빌드 로그 경고 분석"
    analyze_warnings "$BUILD_LOG"
    exit $?
fi

# --- 빌드 실행 ---
BUILD_CMD="build"
if [ "$QUICK_MODE" = false ]; then
    BUILD_CMD="clean build"
fi

log_step "xcodebuild ${BUILD_CMD} 시작..."
echo ""

BUILD_START=$(date +%s)

set +e
xcodebuild \
	    -project "$PROJECT_PATH" \
	    -scheme "$SCHEME" \
	    -sdk iphoneos \
	    -configuration Debug \
	    -derivedDataPath "$DERIVED_DATA" \
	    -allowProvisioningUpdates \
	    CODE_SIGNING_ALLOWED=NO \
	    $BUILD_CMD > "$BUILD_LOG" 2>&1
XCODEBUILD_STATUS=$?
set -e

grep -E "^(Build |Compiling|Linking|error:|warning:|\*\*)| error: | warning: " "$BUILD_LOG" || true

BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))

# 빌드 성공 여부 확인
if grep -q "BUILD SUCCEEDED" "$BUILD_LOG" 2>/dev/null; then
    echo ""
    log_pass "빌드 성공 (${BUILD_DURATION}초)"
elif grep -q "BUILD FAILED" "$BUILD_LOG" 2>/dev/null; then
    echo ""
    log_fail "빌드 실패 (${BUILD_DURATION}초)"
    analyze_warnings "$BUILD_LOG"
    exit 1
else
    echo ""
    log_fail "빌드 결과를 확인할 수 없습니다"
    exit 1
fi

# --- 경고 분석 ---
analyze_warnings "$BUILD_LOG"
WARN_RESULT=$?

echo ""
if [ $WARN_RESULT -eq 0 ]; then
    log_pass "검증 완료: 빌드 성공, 새 경고 없음"
elif [ $WARN_RESULT -eq 2 ]; then
    log_warn "검증 완료: 빌드 성공, 새 경고 발생"
fi

exit $WARN_RESULT

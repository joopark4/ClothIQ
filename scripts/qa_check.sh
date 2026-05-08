#!/bin/bash

###############################################################################
# ClothIQ QA Evaluator
#
# Generator-Evaluator 패턴의 독립 Evaluator.
# 코드 품질, 아키텍처 일관성, 잠재적 문제를 자동 검출합니다.
#
# 사용법:
#   ./scripts/qa_check.sh                # 전체 QA 검사
#   ./scripts/qa_check.sh --changed      # git 변경 파일만 검사
#   ./scripts/qa_check.sh --report       # 결과를 파일로 저장
#
# 종료 코드:
#   0 - 모든 검사 통과
#   1 - 심각한 문제 발견
#   2 - 경고 수준 문제 발견
###############################################################################

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$PROJECT_ROOT/ClothIQ/ClothIQ"
REPORT_FILE="$PROJECT_ROOT/tmp_crash_logs/qa_report.txt"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0
WARNINGS=0
PASSED=0

CHECK_CHANGED_ONLY=false
SAVE_REPORT=false

for arg in "$@"; do
    case "$arg" in
        --changed)  CHECK_CHANGED_ONLY=true ;;
        --report)   SAVE_REPORT=true ;;
        --help|-h)
            echo "Usage: $0 [--changed] [--report]"
            exit 0
            ;;
    esac
done

# --- 대상 파일 목록 (임시 파일 사용) ---
TARGET_LIST=$(mktemp)
trap "rm -f $TARGET_LIST" EXIT

if [ "$CHECK_CHANGED_ONLY" = true ]; then
    {
        git -C "$PROJECT_ROOT" diff --name-only HEAD 2>/dev/null
        git -C "$PROJECT_ROOT" diff --cached --name-only 2>/dev/null
        git -C "$PROJECT_ROOT" ls-files --others --exclude-standard 2>/dev/null
    } | grep '\.swift$' | sort -u | while read -r f; do
        [ -f "$PROJECT_ROOT/$f" ] && echo "$PROJECT_ROOT/$f"
    done > "$TARGET_LIST"
else
    find "$SOURCE_DIR" -name "*.swift" -type f > "$TARGET_LIST"
fi

# --- 출력 ---
print_header() { echo -e "\n${BOLD}--- $1 ---${NC}"; }
check_pass()   { echo -e "  ${GREEN}✓${NC} $1"; PASSED=$((PASSED + 1)); }
check_warn()   { echo -e "  ${YELLOW}△${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
check_fail()   { echo -e "  ${RED}✗${NC} $1"; ERRORS=$((ERRORS + 1)); }

# =========================================================================
# 1. 대형 파일 감지
# =========================================================================
check_large_files() {
    print_header "대형 파일 감지 (>500줄)"
    local found=0
    while IFS= read -r file; do
        local lines
        lines=$(wc -l < "$file" | tr -d ' ')
        local name
        name="${file##*/}"
        if [ "$lines" -gt 800 ]; then
            check_fail "${name}: ${lines}줄 (800줄 초과 - 분할 권장)"
            found=1
        elif [ "$lines" -gt 500 ]; then
            check_warn "${name}: ${lines}줄 (500줄 초과)"
            found=1
        fi
    done < "$TARGET_LIST"
    [ "$found" -eq 0 ] && check_pass "대형 파일 없음"
}

# =========================================================================
# 2. 강제 언래핑 감지
# =========================================================================
check_force_unwrap() {
    print_header "강제 언래핑 사용 감지"
    local total=0
    while IFS= read -r file; do
        local name="${file##*/}"
        local cnt
        cnt=$(grep -c '![^=/ ]' "$file" 2>/dev/null || true)
        cnt=$(echo "$cnt" | tr -d '[:space:]')
        if [ "$cnt" -gt 5 ] 2>/dev/null; then
            check_warn "${name}: 강제 언래핑 ${cnt}개소 (과다 사용)"
            total=$((total + 1))
        fi
    done < "$TARGET_LIST"
    [ "$total" -eq 0 ] && check_pass "과다 강제 언래핑 없음"
}

# =========================================================================
# 3. 아키텍처 레이어 위반 감지
# =========================================================================
check_architecture_violations() {
    print_header "아키텍처 레이어 위반 감지"
    local violations=0

    # Domain 레이어에서 UI import
    while IFS= read -r file; do
        if grep -q "^import SwiftUI\|^import UIKit" "$file" 2>/dev/null; then
            local name="${file##*/}"
            check_fail "Domain 위반: ${name} - UI 프레임워크 import"
            violations=$((violations + 1))
        fi
    done < <(find "$SOURCE_DIR" -path "*/Domain/*.swift" -type f 2>/dev/null)

    # Data/Services에서 SwiftUI import
    while IFS= read -r file; do
        if grep -q "^import SwiftUI" "$file" 2>/dev/null; then
            local name="${file##*/}"
            check_warn "서비스 레이어: ${name} - SwiftUI import"
            violations=$((violations + 1))
        fi
    done < <(find "$SOURCE_DIR" -path "*/Data/Services/*.swift" -type f 2>/dev/null)

    [ "$violations" -eq 0 ] && check_pass "아키텍처 레이어 위반 없음"
}

# =========================================================================
# 4. TODO/FIXME/HACK 잔존 확인
# =========================================================================
check_todo_markers() {
    print_header "TODO/FIXME/HACK 잔존 확인"
    local todo_count=0
    local fixme_count=0
    local hack_count=0

    while IFS= read -r file; do
        local t f h
        t=$(grep -c "// TODO" "$file" 2>/dev/null || true)
        f=$(grep -c "// FIXME" "$file" 2>/dev/null || true)
        h=$(grep -c "// HACK" "$file" 2>/dev/null || true)
        todo_count=$((todo_count + ${t:-0}))
        fixme_count=$((fixme_count + ${f:-0}))
        hack_count=$((hack_count + ${h:-0}))
    done < "$TARGET_LIST"

    [ "$hack_count" -gt 0 ] && check_fail "HACK 주석 ${hack_count}개 잔존"
    [ "$fixme_count" -gt 0 ] && check_warn "FIXME 주석 ${fixme_count}개 잔존"
    [ "$todo_count" -gt 0 ] && check_warn "TODO 주석 ${todo_count}개 잔존"
    [ "$hack_count" -eq 0 ] && [ "$fixme_count" -eq 0 ] && [ "$todo_count" -eq 0 ] && check_pass "잔존 마커 없음"
}

# =========================================================================
# 5. print/debugPrint 잔존 확인
# =========================================================================
check_debug_prints() {
    print_header "디버그 print 잔존 확인"
    local total=0
    while IFS= read -r file; do
        local name="${file##*/}"
        # Debug/Settings/Log/Test 파일 제외
        case "$name" in
            *[Dd]ebug*|*[Ss]etting*|*[Ll]og*|*[Tt]est*) continue ;;
        esac
        local cnt
        cnt=$(grep -cE '^\s*(print|debugPrint|NSLog)\(' "$file" 2>/dev/null || true)
        cnt=$(echo "$cnt" | tr -d '[:space:]')
        if [ "${cnt:-0}" -gt 3 ] 2>/dev/null; then
            check_warn "${name}: print문 ${cnt}개 (프로덕션 코드)"
            total=$((total + 1))
        fi
    done < "$TARGET_LIST"
    [ "$total" -eq 0 ] && check_pass "과다 디버그 print 없음"
}

# =========================================================================
# 6. SwiftData 모델 일관성
# =========================================================================
check_swiftdata_models() {
    print_header "SwiftData 모델 일관성"
    local models_dir="$SOURCE_DIR/Core/Data/SwiftData/Models"
    if [ ! -d "$models_dir" ]; then
        check_warn "SwiftData 모델 디렉토리 없음"
        return
    fi
    local model_count=0
    local annotated=0
    while IFS= read -r file; do
        model_count=$((model_count + 1))
        grep -q "@Model" "$file" 2>/dev/null && annotated=$((annotated + 1))
    done < <(find "$models_dir" -name "*.swift" -type f)

    if [ "$annotated" -eq "$model_count" ]; then
        check_pass "모든 모델에 @Model 매크로 적용 (${model_count}개)"
    else
        check_warn "일부 모델에 @Model 누락 (${annotated}/${model_count})"
    fi
}

# =========================================================================
# 7. 측정 방식 분기 일관성
# =========================================================================
check_measurement_consistency() {
    print_header "측정 방식 분기 일관성"
    local method_files
    method_files=$(grep -rl "measurementMethodRaw\|measurementMethod" "$SOURCE_DIR" --include="*.swift" 2>/dev/null | wc -l | tr -d ' ')
    [ "${method_files:-0}" -gt 0 ] && check_pass "측정 방식 분기 코드 존재 (${method_files}개 파일)"

    local cal_files
    cal_files=$(grep -rl "calibrat" "$SOURCE_DIR" --include="*.swift" 2>/dev/null | wc -l | tr -d ' ')
    [ "${cal_files:-0}" -gt 0 ] && check_pass "교정(calibration) 관련 코드 존재 (${cal_files}개 파일)"
}

# =========================================================================
# 8. Swift 문법 기본 검사 (중괄호 균형)
# =========================================================================
check_swift_syntax() {
    print_header "Swift 문법 기본 검사"
    local imbalanced=0
    while IFS= read -r file; do
        local name="${file##*/}"
        local opens closes
        opens=$(grep -o '{' "$file" 2>/dev/null | wc -l | tr -d ' ')
        closes=$(grep -o '}' "$file" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$opens" -ne "$closes" ]; then
            check_fail "${name}: 중괄호 불균형 ({${opens} }${closes})"
            imbalanced=$((imbalanced + 1))
        fi
    done < "$TARGET_LIST"
    [ "$imbalanced" -eq 0 ] && check_pass "중괄호 균형 정상"
}

# =========================================================================
# 실행
# =========================================================================
echo ""
echo -e "${BOLD}=========================================${NC}"
echo -e "${BOLD}  ClothIQ QA Evaluator${NC}"
echo -e "${BOLD}=========================================${NC}"

if [ "$CHECK_CHANGED_ONLY" = true ]; then
    echo -e "${BLUE}Mode: changed files only${NC}"
else
    echo -e "${BLUE}Mode: full scan${NC}"
fi

check_large_files
check_force_unwrap
check_architecture_violations
check_todo_markers
check_debug_prints
check_swiftdata_models
check_measurement_consistency
check_swift_syntax

# --- 결과 ---
echo ""
echo -e "${BOLD}=========================================${NC}"
echo -e "  ${GREEN}PASS:${NC} ${PASSED}  ${YELLOW}WARN:${NC} ${WARNINGS}  ${RED}FAIL:${NC} ${ERRORS}"
echo -e "${BOLD}=========================================${NC}"

if [ "$SAVE_REPORT" = true ]; then
    mkdir -p "$(dirname "$REPORT_FILE")"
    echo "QA Report - $(date '+%Y-%m-%d %H:%M:%S') | PASS:${PASSED} WARN:${WARNINGS} FAIL:${ERRORS}" > "$REPORT_FILE"
    echo -e "${BLUE}Report: $REPORT_FILE${NC}"
fi

if [ "$ERRORS" -gt 0 ]; then
    exit 1
elif [ "$WARNINGS" -gt 0 ]; then
    exit 2
else
    exit 0
fi

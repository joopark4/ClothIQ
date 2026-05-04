#!/bin/bash

#########################################################################################
# ClothIQ 실제 기기 학습 데이터 스냅샷 수집 스크립트
#
# 수행 작업:
# 1. 실제 기기 앱 컨테이너에서 Documents/MLTrainingData 복사
# 2. Documents 전체와 Library/Application Support 복사
# 3. SwiftData default.store에서 복구 가능한 측정 라벨 생성
# 4. 앱 수집 라벨과 복구 라벨 병합
# 5. 병합 결과 readiness 또는 completion audit 실행
#########################################################################################

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

BUNDLE_ID="com.eunyeon.ClothIQ"
DEVICE_ID=""
OUTPUT_DIR="$PROJECT_ROOT/tmp/training-snapshot-$(date +%Y%m%d-%H%M%S)"
MIN_KEYPOINTS=2
PULL_RETRIES=3
RUN_AUDIT=true
COMPLETION_AUDIT=false
COLLECTION_PLAN_PATH=""
CAPTURE_CHECKLIST_PATH=""
PYTHON_BIN="${PYTHON_BIN:-python3}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

usage() {
    cat <<EOF
사용법:
  scripts/pull_training_snapshot.sh --device-id <device-id> [옵션]

옵션:
  --device-id <id>             devicectl 기기 Identifier 또는 이름
  --bundle-id <id>             앱 bundle identifier (기본값: com.eunyeon.ClothIQ)
  --output-dir <path>          스냅샷 출력 디렉토리
  --min-keypoints <count>      SwiftData 복구 샘플 최소 키포인트 수 (기본값: 2)
  --pull-retries <count>       기기 복사 재시도 횟수 (기본값: 3)
  --completion-audit           readiness 대신 완료 감사 실행
  --collection-plan <path>     완료 감사 수집 계획 Markdown 출력
  --capture-checklist <path>   완료 감사 한국어 촬영 체크리스트 Markdown 출력
  --skip-audit                 pull/복구/병합만 수행
  --help                       도움말 표시

출력 구조:
  <output-dir>/ml_training_data/labels.json
  <output-dir>/documents/
  <output-dir>/application_support/default.store
  <output-dir>/recovered/labels.json
  <output-dir>/merged/labels.json
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device-id)
            DEVICE_ID="$2"
            shift 2
            ;;
        --bundle-id)
            BUNDLE_ID="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --min-keypoints)
            MIN_KEYPOINTS="$2"
            shift 2
            ;;
        --pull-retries)
            PULL_RETRIES="$2"
            shift 2
            ;;
        --completion-audit)
            COMPLETION_AUDIT=true
            shift
            ;;
        --collection-plan)
            COMPLETION_AUDIT=true
            COLLECTION_PLAN_PATH="$2"
            shift 2
            ;;
        --capture-checklist)
            COMPLETION_AUDIT=true
            CAPTURE_CHECKLIST_PATH="$2"
            shift 2
            ;;
        --skip-audit)
            RUN_AUDIT=false
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "알 수 없는 옵션: $1"
            usage
            exit 1
            ;;
    esac
done

if [ -z "$DEVICE_ID" ]; then
    log_error "--device-id가 필요합니다."
    usage
    exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
    log_error "xcrun을 찾을 수 없습니다."
    exit 1
fi

copy_from_device() {
    local source_path="$1"
    local destination_path="$2"
    local required="$3"

    mkdir -p "$destination_path"
    local attempt=1

    while [ "$attempt" -le "$PULL_RETRIES" ]; do
        if [ "$attempt" -gt 1 ]; then
            log_warning "복사 재시도: $source_path ($attempt/$PULL_RETRIES)"
            sleep 2
        fi

        log_info "기기에서 복사: $source_path -> $destination_path"
        if xcrun devicectl device copy from \
            --device "$DEVICE_ID" \
            --domain-type appDataContainer \
            --domain-identifier "$BUNDLE_ID" \
            --source "$source_path" \
            --destination "$destination_path" \
            --remove-existing-content true; then
            log_success "복사 완료: $source_path"
            return 0
        fi

        attempt=$((attempt + 1))
    done

    if [ "$required" = true ]; then
        log_error "필수 데이터 복사 실패: $source_path"
        exit 1
    fi

    log_warning "선택 데이터 복사 실패: $source_path"
    return 1
}

ML_DATA_DIR="$OUTPUT_DIR/ml_training_data"
DOCUMENTS_DIR="$OUTPUT_DIR/documents"
APP_SUPPORT_DIR="$OUTPUT_DIR/application_support"
RECOVERED_DIR="$OUTPUT_DIR/recovered"
MERGED_DIR="$OUTPUT_DIR/merged"

mkdir -p "$OUTPUT_DIR"

log_info "스냅샷 출력: $OUTPUT_DIR"
copy_from_device "Documents/MLTrainingData" "$ML_DATA_DIR" true
copy_from_device "Documents" "$DOCUMENTS_DIR" false
copy_from_device "Library/Application Support" "$APP_SUPPORT_DIR" false

MERGE_INPUT="$ML_DATA_DIR"

if [ -f "$APP_SUPPORT_DIR/default.store" ] && [ -d "$DOCUMENTS_DIR" ]; then
    log_info "SwiftData 저장소에서 학습 라벨 복구 중..."
    "$PYTHON_BIN" "$SCRIPT_DIR/extract_training_data_from_swiftdata.py" \
        --store "$APP_SUPPORT_DIR/default.store" \
        --documents-dir "$DOCUMENTS_DIR" \
        --output-dir "$RECOVERED_DIR" \
        --merge-labels "$ML_DATA_DIR/labels.json" \
        --min-keypoints "$MIN_KEYPOINTS"
    MERGE_INPUT="$RECOVERED_DIR"
else
    log_warning "SwiftData 복구를 건너뜁니다. default.store 또는 Documents가 없습니다."
fi

log_info "학습 라벨 병합 중..."
"$PYTHON_BIN" "$SCRIPT_DIR/merge_training_data.py" \
    --input "$MERGE_INPUT" \
    --output-dir "$MERGED_DIR"

if [ "$RUN_AUDIT" = true ]; then
    if [ "$COMPLETION_AUDIT" = true ]; then
        audit_args=(
            --data-path "$MERGED_DIR"
            --completion-audit
            --skip-export
        )
        if [ -n "$COLLECTION_PLAN_PATH" ]; then
            audit_args+=(--collection-plan "$COLLECTION_PLAN_PATH")
        fi
        if [ -n "$CAPTURE_CHECKLIST_PATH" ]; then
            audit_args+=(--capture-checklist "$CAPTURE_CHECKLIST_PATH")
        fi
    else
        audit_args=(
            --data-path "$MERGED_DIR"
            --readiness-only
            --skip-export
        )
    fi

    log_info "병합 데이터 감사 실행 중..."
    bash "$SCRIPT_DIR/ml_training_workflow.sh" "${audit_args[@]}"
fi

log_success "스냅샷 준비 완료: $MERGED_DIR"

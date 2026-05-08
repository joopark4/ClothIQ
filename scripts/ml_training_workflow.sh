#!/bin/bash

#########################################################################################
# ClothIQ ML 학습 워크플로우 스크립트
#
# 이 스크립트는 다음 작업을 수행합니다:
# 1. 학습 데이터 내보내기 (iOS 앱에서 수집된 데이터)
# 2. 데이터 통계 확인
# 3. 모델 학습 (Python/TensorFlow 또는 CreateML)
# 4. 학습된 모델을 .mlmodelc로 컴파일하고 iOS 프로젝트/Documents에 복사
# 5. 성능 보고서 생성
#
# 사용법:
#   ./ml_training_workflow.sh [옵션]
#
# 옵션:
#   --method [python|createml]  학습 방법 선택 (기본값: python)
#   --epochs [숫자]             학습 에폭 수 (기본값: 100)
#   --batch-size [숫자]         배치 크기 (기본값: 32)
#   --data-path [경로]          학습 데이터 경로 직접 지정
#   --pull-device-data          연결된 실제 기기에서 MLTrainingData 복사
#   --device-id [id]            devicectl 기기 Identifier
#   --bundle-id [id]            앱 bundle identifier (기본값: com.eunyeon.ClothIQ)
#   --pulled-data-path [경로]   기기 데이터 복사 대상 경로
#   --pull-retries [숫자]       기기 데이터 복사 재시도 횟수 (기본값: 3)
#   --clothing-type [rawValue]  특정 의류 타입만 학습
#   --per-type                  고유 촬영 샘플이 충분한 의류 타입별 모델을 각각 학습
#   --min-type-samples [숫자]   타입별 학습 최소 고유 원본 촬영 수 (기본값: 20)
#   --min-corrected-samples [숫자] 타입별 사용자 보정 고유 원본 촬영 수 (기본값: 3)
#   --readiness-only            학습 없이 타입별 준비 상태만 확인
#   --completion-audit          실제 원본 데이터/모델 산출물 기준으로 학습 완료 여부 감사
#   --collection-plan [경로]    완료 감사 기반 촬영/보정 부족분 계획 Markdown 작성
#   --capture-checklist [경로]  완료 감사 기반 한국어 촬영 체크리스트 Markdown 작성
#   --export-only              데이터 내보내기만 수행
#   --skip-export              내보내기 건너뛰기
#
# 산출물:
#   - models/ClothingKeypointDetector.mlpackage
#   - models/ClothingKeypointDetector.mlmodelc
#   - ClothIQ/ClothIQ/Resources/CoreML/ClothingKeypointDetector.mlmodelc
#   - Documents/MLTrainingData/Models/ClothingKeypointDetector.mlmodelc
#########################################################################################

set -e  # 오류 발생 시 즉시 종료

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 기본 설정
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IOS_PROJECT="$PROJECT_ROOT/ClothIQ/ClothIQ"
DOCUMENTS_PATH="$HOME/Library/Developer/CoreSimulator/Devices"
MODELS_DIR="$PROJECT_ROOT/models"
BUNDLE_MODELS_DIR="$IOS_PROJECT/Resources/CoreML"
MODEL_NAME="ClothingKeypointDetector"
TRAINING_METHOD="python"
TRAINING_DATA_PATH_OVERRIDE=""
PULL_DEVICE_DATA=false
DEVICE_ID=""
BUNDLE_ID="com.eunyeon.ClothIQ"
PULLED_DATA_PATH="$PROJECT_ROOT/tmp/device-training-data"
PULL_RETRIES=3
EPOCHS=100
BATCH_SIZE=32
CLOTHING_TYPE=""
PER_TYPE=false
MIN_TYPE_SAMPLES=20
MIN_CORRECTED_SAMPLES=3
READINESS_ONLY=false
COMPLETION_AUDIT=false
COLLECTION_PLAN_PATH=""
CAPTURE_CHECKLIST_PATH=""
EXPORT_ONLY=false
SKIP_EXPORT=false
PYTHON_BIN=""

# 로그 파일
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/ml_training_$(date +%Y%m%d_%H%M%S).log"

# 로깅 함수
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

resolve_python_bin() {
    if [ -n "${ML_PYTHON_BIN:-}" ]; then
        echo "$ML_PYTHON_BIN"
    elif [ -x "$PROJECT_ROOT/.venv-ml/bin/python" ]; then
        echo "$PROJECT_ROOT/.venv-ml/bin/python"
    elif [ -x "$PROJECT_ROOT/venv/bin/python" ]; then
        echo "$PROJECT_ROOT/venv/bin/python"
    else
        echo "python3"
    fi
}

# 헤더 출력
print_header() {
    echo ""
    echo "=========================================="
    echo "    ClothIQ ML 학습 워크플로우"
    echo "=========================================="
    echo ""
}

# 옵션 파싱
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --method)
                TRAINING_METHOD="$2"
                shift 2
                ;;
            --epochs)
                EPOCHS="$2"
                shift 2
                ;;
            --batch-size)
                BATCH_SIZE="$2"
                shift 2
                ;;
            --data-path)
                TRAINING_DATA_PATH_OVERRIDE="$2"
                shift 2
                ;;
            --pull-device-data)
                PULL_DEVICE_DATA=true
                shift
                ;;
            --device-id)
                DEVICE_ID="$2"
                shift 2
                ;;
            --bundle-id)
                BUNDLE_ID="$2"
                shift 2
                ;;
            --pulled-data-path)
                PULLED_DATA_PATH="$2"
                shift 2
                ;;
            --pull-retries)
                PULL_RETRIES="$2"
                shift 2
                ;;
            --clothing-type)
                CLOTHING_TYPE="$2"
                shift 2
                ;;
            --per-type)
                PER_TYPE=true
                shift
                ;;
            --min-type-samples)
                MIN_TYPE_SAMPLES="$2"
                shift 2
                ;;
            --min-corrected-samples)
                MIN_CORRECTED_SAMPLES="$2"
                shift 2
                ;;
            --readiness-only)
                READINESS_ONLY=true
                shift
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
            --export-only)
                EXPORT_ONLY=true
                shift
                ;;
            --skip-export)
                SKIP_EXPORT=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "알 수 없는 옵션: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 도움말 표시
show_help() {
    cat << EOF
사용법: $0 [옵션]

옵션:
    --method [python|createml]  학습 방법 선택 (기본값: python)
    --epochs [숫자]             학습 에폭 수 (기본값: 100)
    --batch-size [숫자]         배치 크기 (기본값: 32)
    --data-path [경로]          학습 데이터 경로 직접 지정
    --pull-device-data          연결된 실제 기기에서 Documents/MLTrainingData 복사
    --device-id [id]            devicectl 기기 Identifier
    --bundle-id [id]            앱 bundle identifier (기본값: com.eunyeon.ClothIQ)
    --pulled-data-path [경로]   기기 데이터 복사 대상 경로
    --pull-retries [숫자]       기기 데이터 복사 재시도 횟수 (기본값: 3)
    --clothing-type [rawValue]  특정 의류 타입만 학습
    --per-type                  고유 촬영 샘플이 충분한 의류 타입별 모델을 각각 학습
    --min-type-samples [숫자]   타입별 학습 최소 고유 원본 촬영 수 (기본값: 20)
    --min-corrected-samples [숫자] 타입별 사용자 보정 고유 원본 촬영 수 (기본값: 3)
    --readiness-only            학습 없이 타입별 준비 상태만 확인
    --completion-audit          실제 원본 데이터/모델 산출물 기준으로 학습 완료 여부 감사
    --collection-plan [경로]    완료 감사 기반 촬영/보정 부족분 계획 Markdown 작성
    --capture-checklist [경로]  완료 감사 기반 한국어 촬영 체크리스트 Markdown 작성
    --export-only              데이터 내보내기만 수행
    --skip-export              내보내기 건너뛰기
    --help                     이 도움말 표시

예시:
    $0                          # 기본 설정으로 전체 워크플로우 실행
    $0 --per-type                # 의류 타입별 모델 전체 학습
    $0 --data-path ./tmp/device-training-data --per-type
    $0 --pull-device-data --device-id <id> --readiness-only
    $0 --data-path ./tmp/device-training-data --completion-audit
    $0 --data-path ./tmp/device-training-data --collection-plan tmp/ml-training-collection-plan.md
    $0 --clothing-type shorts    # 반바지 전용 모델 학습
    $0 --method createml        # CreateML 사용
    $0 --export-only           # 데이터 내보내기만
    $0 --epochs 50 --batch-size 16  # 커스텀 학습 파라미터
EOF
}

# 시뮬레이터 데이터 경로 찾기
pull_device_training_data() {
    if [ -z "$DEVICE_ID" ]; then
        log_error "--pull-device-data 사용 시 --device-id가 필요합니다."
        log_info "연결된 기기는 다음 명령으로 확인할 수 있습니다: xcrun devicectl list devices"
        exit 1
    fi

    if ! command -v xcrun >/dev/null 2>&1; then
        log_error "xcrun을 찾을 수 없습니다. 실제 기기 데이터 복사는 Xcode가 설치된 Mac에서 실행해야 합니다."
        exit 1
    fi

    mkdir -p "$PULLED_DATA_PATH"
    log_info "기기 학습 데이터 복사 중..."
    log_info "  - device: $DEVICE_ID"
    log_info "  - bundle: $BUNDLE_ID"
    log_info "  - destination: $PULLED_DATA_PATH"

    local attempt=1
    while [ "$attempt" -le "$PULL_RETRIES" ]; do
        if [ "$attempt" -gt 1 ]; then
            log_warning "기기 학습 데이터 복사 재시도: $attempt/$PULL_RETRIES"
            sleep 2
        fi

        if xcrun devicectl device copy from \
            --device "$DEVICE_ID" \
            --domain-type appDataContainer \
            --domain-identifier "$BUNDLE_ID" \
            --source Documents/MLTrainingData \
            --destination "$PULLED_DATA_PATH" \
            --remove-existing-content true; then
            TRAINING_DATA_PATH_OVERRIDE="$PULLED_DATA_PATH"
            log_success "기기 학습 데이터 복사 완료: $PULLED_DATA_PATH"
            return
        fi

        attempt=$((attempt + 1))
    done

    log_error "기기 학습 데이터 복사 실패"
    exit 1
}

find_training_data() {
    log_info "학습 데이터 찾는 중..."

    if [ -n "$TRAINING_DATA_PATH_OVERRIDE" ]; then
        if [ ! -d "$TRAINING_DATA_PATH_OVERRIDE" ]; then
            log_error "지정한 학습 데이터 경로가 디렉토리가 아닙니다: $TRAINING_DATA_PATH_OVERRIDE"
            exit 1
        fi

        if [ ! -f "$TRAINING_DATA_PATH_OVERRIDE/labels.json" ]; then
            log_error "지정한 학습 데이터 경로에 labels.json이 없습니다: $TRAINING_DATA_PATH_OVERRIDE"
            exit 1
        fi

        TRAINING_DATA_PATH="$TRAINING_DATA_PATH_OVERRIDE"
        log_success "지정된 학습 데이터 사용: $TRAINING_DATA_PATH"
        return
    fi

    # 시뮬레이터 데이터 디렉토리 검색
    local data_dirs=$(find "$DOCUMENTS_PATH" -name "MLTrainingData" -type d 2>/dev/null | head -1)

    if [ -z "$data_dirs" ]; then
        # 실제 디바이스 또는 로컬 개발 경로 확인
        if [ -d "$IOS_PROJECT/Documents/MLTrainingData" ]; then
            data_dirs="$IOS_PROJECT/Documents/MLTrainingData"
        else
            log_error "학습 데이터를 찾을 수 없습니다"
            log_info "iOS 앱에서 먼저 학습 데이터를 수집해주세요"
            exit 1
        fi
    fi

    TRAINING_DATA_PATH="$data_dirs"
    log_success "학습 데이터 발견: $TRAINING_DATA_PATH"
}

# 데이터 통계 확인
check_data_statistics() {
    log_info "데이터 통계 확인 중..."

    if [ -f "$TRAINING_DATA_PATH/labels.json" ]; then
        local sample_summary=$("$PYTHON_BIN" -c "
import base64
import hashlib
import json
with open('$TRAINING_DATA_PATH/labels.json', 'r') as f:
    data = json.load(f)
augmented = sum(1 for d in data if d.get('isAugmented') is True or d.get('sourceSampleID'))
corrected_original = 0
unique_original = set()
unique_corrected_original = set()
for d in data:
    if d.get('isAugmented') is True or d.get('sourceSampleID'):
        continue
    image_data = d.get('imageData')
    if not isinstance(image_data, str) or not image_data:
        continue
    try:
        image_hash = hashlib.sha256(base64.b64decode(image_data, validate=True)).hexdigest()
    except Exception:
        continue
    unique_original.add(image_hash)
    if d.get('isUserCorrected', False):
        corrected_original += 1
        unique_corrected_original.add(image_hash)
print(len(data))
print(augmented)
print(corrected_original)
print(len(unique_original))
print(len(unique_corrected_original))
" 2>/dev/null)
        local sample_count=$(echo "$sample_summary" | sed -n '1p')
        local augmented_count=$(echo "$sample_summary" | sed -n '2p')
        local user_corrected_original=$(echo "$sample_summary" | sed -n '3p')
        local unique_original_count=$(echo "$sample_summary" | sed -n '4p')
        local unique_corrected_original_count=$(echo "$sample_summary" | sed -n '5p')

        log_info "📊 데이터 통계:"
        log_info "  - 총 샘플 수: $sample_count"
        log_info "  - 고유 원본 촬영 샘플: $unique_original_count"
        log_info "  - 고유 사용자 수정 원본 샘플: $unique_corrected_original_count"
        if [ "$augmented_count" -gt 0 ]; then
            log_info "  - 증강 샘플: $augmented_count"
            log_info "  - 사용자 수정 원본 샘플: $user_corrected_original"
        else
            log_info "  - 사용자 수정 샘플: $user_corrected_original"
        fi

        if [ "$sample_count" -lt 100 ]; then
            log_warning "샘플 수가 100개 미만입니다. 더 많은 데이터 수집을 권장합니다."
        fi
    else
        log_error "labels.json 파일을 찾을 수 없습니다"
        exit 1
    fi
}

# 데이터 내보내기
export_training_data() {
    if [ "$SKIP_EXPORT" = true ]; then
        log_info "데이터 내보내기 건너뛰기"
        return
    fi

    log_info "학습 데이터 내보내기 중..."

    # 백업 생성
    local backup_dir="$PROJECT_ROOT/data_backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    cp -r "$TRAINING_DATA_PATH" "$backup_dir/"
    log_success "백업 생성됨: $backup_dir"

    # CreateML 형식으로 변환 (필요한 경우)
    if [ "$TRAINING_METHOD" = "createml" ]; then
        log_info "CreateML 형식으로 변환 중..."
        # TODO: CreateML 형식 변환 로직 추가
    fi
}

# Python/TensorFlow로 학습
train_with_python() {
    local model_name="${1:-$MODEL_NAME}"
    local clothing_type="${2:-}"

    log_info "Python/TensorFlow로 모델 학습 시작: $model_name"
    if [ -n "$clothing_type" ]; then
        log_info "  - 의류 타입 필터: $clothing_type"
    fi

    # 가상환경 활성화 (있는 경우)
    if [ -d "$PROJECT_ROOT/venv" ] && [ "$PYTHON_BIN" = "python3" ]; then
        source "$PROJECT_ROOT/venv/bin/activate"
    fi

    # 필요한 패키지 확인
    log_info "필수 패키지 확인 중..."
    "$PYTHON_BIN" -m pip install --quiet tensorflow coremltools pillow numpy scikit-learn

    local extra_args=(
        --model-name "$model_name"
        --min-real-samples "$MIN_TYPE_SAMPLES"
        --min-corrected-samples "$MIN_CORRECTED_SAMPLES"
    )
    if [ -n "$clothing_type" ]; then
        extra_args+=(--clothing-type "$clothing_type")
    fi

    "$PYTHON_BIN" "$SCRIPT_DIR/train_keypoint_model.py" \
        --data-path "$TRAINING_DATA_PATH" \
        --output-path "$MODELS_DIR" \
        --epochs "$EPOCHS" \
        --batch-size "$BATCH_SIZE" \
        "${extra_args[@]}" \
        2>&1 | tee -a "$LOG_FILE"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_success "모델 학습 완료!"
    else
        log_error "모델 학습 실패"
        exit 1
    fi
}

# CreateML로 학습
train_with_createml() {
    log_info "CreateML로 모델 학습 시작..."

    # macOS 확인
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "CreateML은 macOS에서만 사용 가능합니다"
        exit 1
    fi

    # Swift 스크립트 실행
    swift "$SCRIPT_DIR/train_createml.swift" \
        "$TRAINING_DATA_PATH" \
        "$MODELS_DIR" \
        2>&1 | tee -a "$LOG_FILE"

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_success "모델 학습 완료!"
    else
        log_error "모델 학습 실패"
        exit 1
    fi
}

# 모델을 iOS 프로젝트에 복사
compile_model() {
    local model_name="${1:-$MODEL_NAME}"

    log_info "Core ML 모델 컴파일 중: $model_name"

    local source_model="$MODELS_DIR/$model_name.mlpackage"
    local compiled_model="$MODELS_DIR/$model_name.mlmodelc"

    local source_is_package=1
    if [ ! -d "$source_model" ]; then
        source_model="$MODELS_DIR/$model_name.mlmodel"
        source_is_package=0
        if [ ! -f "$source_model" ]; then
            log_error "원본 모델 파일을 찾을 수 없습니다: $MODELS_DIR/$model_name.mlpackage 또는 $MODELS_DIR/$model_name.mlmodel"
            exit 1
        fi
    fi

    if ! command -v xcrun >/dev/null 2>&1; then
        log_error "xcrun을 찾을 수 없습니다. .mlmodelc 컴파일은 Xcode가 설치된 Mac에서 실행해야 합니다."
        exit 1
    fi

    local source_for_compile="$source_model"
    local compile_temp_dir=""
    if [ "$source_is_package" -eq 1 ]; then
        compile_temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/clothiq-coreml-compile.XXXXXX")"
        cp -R "$source_model" "$compile_temp_dir/"
        source_for_compile="$compile_temp_dir/$(basename "$source_model")"
        chmod -R u+rwX,go+rX "$source_for_compile"
    fi

    rm -rf "$compiled_model"
    xcrun coremlcompiler compile "$source_for_compile" "$MODELS_DIR" 2>&1 | tee -a "$LOG_FILE"
    local compile_status=${PIPESTATUS[0]}

    if [ -n "$compile_temp_dir" ]; then
        rm -rf "$compile_temp_dir"
    fi

    if [ "$compile_status" -ne 0 ]; then
        log_error "Core ML 모델 컴파일 실패: $source_model"
        exit 1
    fi

    if [ ! -d "$compiled_model" ]; then
        log_error "컴파일된 모델을 찾을 수 없습니다: $compiled_model"
        exit 1
    fi

    log_success "컴파일된 모델 생성 완료: $compiled_model"
}

deploy_model() {
    local model_name="${1:-$MODEL_NAME}"

    log_info "학습된 모델을 iOS 프로젝트에 배포 중: $model_name"

    local compiled_model="$MODELS_DIR/$model_name.mlmodelc"

    if [ ! -d "$compiled_model" ]; then
        log_error "컴파일된 모델 디렉토리를 찾을 수 없습니다: $compiled_model"
        exit 1
    fi

    # iOS 앱 번들에 포함할 CoreML 디렉토리에 복사
    mkdir -p "$BUNDLE_MODELS_DIR"
    rm -rf "$BUNDLE_MODELS_DIR/$model_name.mlmodelc"
    cp -R "$compiled_model" "$BUNDLE_MODELS_DIR/"
    log_success "번들 모델 배포 완료: $BUNDLE_MODELS_DIR/$model_name.mlmodelc"

    # 현재 학습 데이터가 있는 앱 Documents 경로에도 복사해서 시뮬레이터 재빌드 없이 검증 가능하게 함
    local documents_model_dir="$TRAINING_DATA_PATH/Models"
    mkdir -p "$documents_model_dir"
    rm -rf "$documents_model_dir/$model_name.mlmodelc"
    cp -R "$compiled_model" "$documents_model_dir/"
    log_success "Documents 모델 배포 완료: $documents_model_dir/$model_name.mlmodelc"

    # 모델 정보 파일도 복사
    if [ -f "$MODELS_DIR/model_info.json" ]; then
        cp "$MODELS_DIR/model_info.json" "$BUNDLE_MODELS_DIR/"
        cp "$MODELS_DIR/model_info.json" "$documents_model_dir/"
    fi
}

# 성능 보고서 생성
generate_report() {
    local model_name="${1:-$MODEL_NAME}"

    log_info "성능 보고서 생성 중: $model_name"

    local report_file="$LOG_DIR/training_report_$(date +%Y%m%d_%H%M%S).md"

    cat > "$report_file" << EOF
# ClothIQ ML 학습 보고서

**생성 일시**: $(date)
**학습 방법**: $TRAINING_METHOD
**모델 이름**: $model_name
**에폭 수**: $EPOCHS
**배치 크기**: $BATCH_SIZE

## 데이터 통계

EOF

    # 데이터 통계 추가
    if [ -f "$MODELS_DIR/model_info.json" ]; then
        "$PYTHON_BIN" -c "
import json
with open('$MODELS_DIR/model_info.json', 'r') as f:
    info = json.load(f)
    print('- **모델 버전**: ' + info.get('version', 'N/A'))
    print('- **학습 샘플 수**: ' + str(info.get('training_samples', 'N/A')))
    print('- **최종 손실**: ' + str(info.get('final_loss', 'N/A')))
    print('- **최종 MAE**: ' + str(info.get('final_mae', 'N/A')))
" >> "$report_file"
    fi

    echo "" >> "$report_file"
    echo "## 로그 파일" >> "$report_file"
    echo "" >> "$report_file"
    echo "전체 로그: \`$LOG_FILE\`" >> "$report_file"

    log_success "보고서 생성 완료: $report_file"
}

list_trainable_clothing_types() {
    "$PYTHON_BIN" - "$TRAINING_DATA_PATH/labels.json" "$MIN_TYPE_SAMPLES" "$MIN_CORRECTED_SAMPLES" << 'PY'
import base64
import hashlib
import json
import sys

labels_path = sys.argv[1]
minimum = int(sys.argv[2])
corrected_minimum = int(sys.argv[3])

with open(labels_path, 'r') as f:
    samples = json.load(f)

def is_usable(sample):
    if not sample.get('clothingType'):
        return False
    if not sample.get('keypoints'):
        return False
    image_data = sample.get('imageData')
    if not isinstance(image_data, str) or not image_data:
        return False
    try:
        base64.b64decode(image_data, validate=True)
    except Exception:
        return False
    return True

def is_augmented(sample):
    return sample.get('isAugmented') is True or bool(sample.get('sourceSampleID'))

def image_hash(sample):
    image_data = sample.get('imageData')
    try:
        return hashlib.sha256(base64.b64decode(image_data, validate=True)).hexdigest()
    except Exception:
        return None

hashes_by_type = {}
corrected_hashes_by_type = {}
for sample in samples:
    if not is_usable(sample) or is_augmented(sample):
        continue
    clothing_type = sample.get('clothingType')
    hash_value = image_hash(sample)
    if hash_value is None:
        continue
    hashes_by_type.setdefault(clothing_type, set()).add(hash_value)
    if sample.get('isUserCorrected') is True:
        corrected_hashes_by_type.setdefault(clothing_type, set()).add(hash_value)

for clothing_type, hashes in sorted(hashes_by_type.items()):
    corrected_hashes = corrected_hashes_by_type.get(clothing_type, set())
    if len(hashes) >= minimum and len(corrected_hashes) >= corrected_minimum:
        print(clothing_type)
PY
}

print_type_readiness() {
    log_info "타입별 학습 준비 상태:"
    "$PYTHON_BIN" - "$TRAINING_DATA_PATH/labels.json" "$MIN_TYPE_SAMPLES" "$MIN_CORRECTED_SAMPLES" << 'PY' | while IFS= read -r line; do
import base64
import hashlib
import json
import sys
from collections import Counter

labels_path = sys.argv[1]
minimum = int(sys.argv[2])
corrected_minimum = int(sys.argv[3])
prior_minimum = corrected_minimum

with open(labels_path, 'r') as f:
    samples = json.load(f)

def usability_error(sample):
    if not sample.get('clothingType'):
        return "clothingType 누락"
    if not sample.get('keypoints'):
        return "keypoints 누락"
    image_data = sample.get('imageData')
    if not isinstance(image_data, str) or not image_data:
        return "imageData 누락"
    try:
        base64.b64decode(image_data, validate=True)
    except Exception:
        return "imageData 디코딩 실패"
    return None

def image_hash(sample):
    image_data = sample.get('imageData')
    try:
        return hashlib.sha256(base64.b64decode(image_data, validate=True)).hexdigest()
    except Exception:
        return None

label_counts = Counter()
counts = Counter()
corrected = Counter()
corrected_original = Counter()
augmented = Counter()
original_hashes = {}
corrected_original_hashes = {}
invalid_reasons = Counter()
original_prior_keypoint_counts = {}

expected_keypoints = {
    "short_sleeve": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "long_sleeve": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve", "right_sleeve"},
    "shirt": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "polo": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "jacket": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve", "right_sleeve"},
    "coat": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "vest": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center"},
    "cardigan": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "hoodie": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "dress": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "waist_left", "waist_right", "hip_left", "hip_right"},
    "jumpsuit": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "waist_left", "waist_right", "hip_left", "hip_right", "crotch"},
    "shorts": {"waist_left", "waist_right", "hem_center", "hem_left", "hem_right", "crotch"},
    "pants": {"waist_left", "waist_right", "hem_center", "hem_left", "hem_right", "crotch", "hip_left", "hip_right"},
    "jeans": {"waist_left", "waist_right", "hem_center", "hem_left", "hem_right", "crotch", "hip_left", "hip_right"},
    "skirt": {"waist_left", "waist_right", "hem_center", "hem_left", "hem_right"},
    "leggings": {"waist_left", "waist_right", "hem_center", "hem_left", "hem_right", "hip_left", "hip_right"},
}

def visible_labels(sample):
    labels = []
    for label in sample.get('keypoints') or []:
        if label.get('visibility', 0) < 0.5:
            continue
        identifier = label.get('identifier')
        x = label.get('x')
        y = label.get('y')
        if not identifier or not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
            continue
        if 0 <= x <= 1 and 0 <= y <= 1:
            labels.append(label)
    return labels

def has_keypoint_bounds(labels):
    xs = [label['x'] for label in labels]
    ys = [label['y'] for label in labels]
    return max(xs) - min(xs) > 0.01 and max(ys) - min(ys) > 0.01

def is_augmented(sample):
    return sample.get('isAugmented') is True or bool(sample.get('sourceSampleID'))

for sample in samples:
    clothing_type = sample.get('clothingType')
    if clothing_type:
        label_counts[clothing_type] += 1

    labels = visible_labels(sample)
    sample_is_augmented = is_augmented(sample)
    hash_value = image_hash(sample) if clothing_type and not sample_is_augmented else None
    if clothing_type and hash_value and not sample_is_augmented and len(labels) >= 4 and has_keypoint_bounds(labels):
        expected = expected_keypoints.get(clothing_type, set())
        per_type = original_prior_keypoint_counts.setdefault(clothing_type, {})
        for label in labels:
            identifier = label.get('identifier')
            if identifier in expected:
                per_type.setdefault(identifier, set()).add(hash_value)

    error = usability_error(sample)
    if error:
        invalid_reasons[error] += 1
        continue

    counts[clothing_type] += 1
    if sample_is_augmented:
        augmented[clothing_type] += 1
    elif hash_value:
        original_hashes.setdefault(clothing_type, set()).add(hash_value)
    if sample.get('isUserCorrected', False):
        corrected[clothing_type] += 1
        if not sample_is_augmented:
            corrected_original[clothing_type] += 1
            if hash_value:
                corrected_original_hashes.setdefault(clothing_type, set()).add(hash_value)

if invalid_reasons:
    reason_text = ", ".join(f"{reason} {count}개" for reason, count in sorted(invalid_reasons.items()))
    print(f"- 무효 샘플: {sum(invalid_reasons.values())}개 ({reason_text})")

if not label_counts:
    print("- 수집된 타입 없음")

for clothing_type in sorted(label_counts):
    label_count = label_counts[clothing_type]
    total_count = counts[clothing_type]
    augmented_count = augmented[clothing_type]
    original_record_count = total_count - augmented_count
    original_count = len(original_hashes.get(clothing_type, set()))
    corrected_count = corrected[clothing_type]
    corrected_original_record_count = corrected_original[clothing_type]
    corrected_original_count = len(corrected_original_hashes.get(clothing_type, set()))
    model_needed = max(0, minimum - original_count)
    model_corrected_needed = max(0, corrected_minimum - corrected_original_count)
    prior_needed = max(0, prior_minimum - corrected_original_count)
    expected = expected_keypoints.get(clothing_type, set())
    complete_prior_keypoints = sum(
        1
        for identifier in expected
        if len(original_prior_keypoint_counts.get(clothing_type, {}).get(identifier, set())) >= prior_minimum
    )
    if model_needed == 0 and model_corrected_needed == 0:
        model_status = "모델 학습 가능(고유 원본 기준)"
    else:
        missing_parts = []
        if model_needed > 0:
            missing_parts.append(f"고유 원본 {model_needed}개")
        if model_corrected_needed > 0:
            missing_parts.append(f"고유 사용자 보정 원본 {model_corrected_needed}개")
        missing_text = ", ".join(missing_parts)
        if augmented_count > 0:
            model_status = f"모델 학습까지 {missing_text} 추가 필요 (증강 포함 유효 {total_count}개)"
        else:
            model_status = f"모델 학습까지 {missing_text} 추가 필요"
    if not expected:
        app_prior_status = "앱 prior 원본 기준 없음"
    elif complete_prior_keypoints >= len(expected):
        app_prior_status = f"앱 prior 원본 완료 ({complete_prior_keypoints}/{len(expected)})"
    elif complete_prior_keypoints > 0:
        app_prior_status = f"앱 prior 원본 일부 적용 ({complete_prior_keypoints}/{len(expected)})"
    else:
        app_prior_status = f"앱 prior 원본 부족 (0/{len(expected)})"
    if prior_needed == 0:
        prior_status = "사용자 보정 원본 prior 가능"
    else:
        prior_status = f"사용자 보정 원본 prior까지 {prior_needed}개 추가 필요"
    if augmented_count > 0:
        valid_status = f"유효 레코드 {total_count}개(원본 레코드 {original_record_count}개, 고유 원본 {original_count}개, 증강 {augmented_count}개)"
        corrected_status = f"고유 사용자 수정 원본 {corrected_original_count}개(원본 레코드 {corrected_original_record_count}개, 증강 포함 {corrected_count}개)"
    else:
        valid_status = f"유효 레코드 {total_count}개(고유 원본 {original_count}개)"
        corrected_status = f"고유 사용자 수정 원본 {corrected_original_count}개(원본 레코드 {corrected_original_record_count}개)"
    print(f"- {clothing_type}: 라벨 {label_count}개, {valid_status}, {corrected_status} / {app_prior_status} / {prior_status} / {model_status}")
PY
        log_info "  $line"
    done
}

run_completion_audit() {
    local audit_args=(
        --data-path "$TRAINING_DATA_PATH"
        --min-real-samples "$MIN_TYPE_SAMPLES"
        --min-corrected-samples "$MIN_CORRECTED_SAMPLES"
    )

    if [ -n "$CLOTHING_TYPE" ]; then
        audit_args+=(--required-types "$CLOTHING_TYPE")
    fi
    if [ -n "$COLLECTION_PLAN_PATH" ]; then
        audit_args+=(--write-plan "$COLLECTION_PLAN_PATH")
    fi
    if [ -n "$CAPTURE_CHECKLIST_PATH" ]; then
        audit_args+=(--write-capture-checklist "$CAPTURE_CHECKLIST_PATH")
    fi

    log_info "학습 완료 감사 실행 중..."
    "$PYTHON_BIN" "$SCRIPT_DIR/audit_ml_training_completion.py" "${audit_args[@]}" 2>&1 | tee -a "$LOG_FILE"
    local audit_status=${PIPESTATUS[0]}
    if [ "$audit_status" -eq 0 ]; then
        log_success "학습 완료 감사 통과"
    else
        log_error "학습 완료 감사 실패"
    fi
    return "$audit_status"
}

train_compile_deploy() {
    local model_name="$1"
    local clothing_type="${2:-}"

    if [ "$TRAINING_METHOD" = "python" ]; then
        train_with_python "$model_name" "$clothing_type"
    elif [ "$TRAINING_METHOD" = "createml" ]; then
        if [ -n "$clothing_type" ]; then
            log_error "CreateML 타입별 학습은 현재 스크립트에서 지원하지 않습니다. --method python을 사용하세요."
            exit 1
        fi
        train_with_createml
    else
        log_error "지원하지 않는 학습 방법: $TRAINING_METHOD"
        exit 1
    fi

    compile_model "$model_name"
    deploy_model "$model_name"
    generate_report "$model_name"
}

# 메인 실행 함수
main() {
    print_header

    # 옵션 파싱
    parse_arguments "$@"
    PYTHON_BIN="$(resolve_python_bin)"

    log_info "설정:"
    log_info "  - 학습 방법: $TRAINING_METHOD"
    log_info "  - Python: $PYTHON_BIN"
    log_info "  - 에폭 수: $EPOCHS"
    log_info "  - 배치 크기: $BATCH_SIZE"
    if [ "$PULL_DEVICE_DATA" = true ]; then
        log_info "  - 실제 기기 데이터 복사: 활성화"
        log_info "  - 기기 ID: $DEVICE_ID"
        log_info "  - Bundle ID: $BUNDLE_ID"
        log_info "  - 복사 대상: $PULLED_DATA_PATH"
        log_info "  - 복사 재시도: $PULL_RETRIES"
    fi
    if [ -n "$TRAINING_DATA_PATH_OVERRIDE" ]; then
        log_info "  - 학습 데이터 경로: $TRAINING_DATA_PATH_OVERRIDE"
    fi
    if [ "$PER_TYPE" = true ]; then
        log_info "  - 타입별 학습: 활성화 (최소 원본 샘플: $MIN_TYPE_SAMPLES, 사용자 보정 원본: $MIN_CORRECTED_SAMPLES)"
    elif [ -n "$CLOTHING_TYPE" ]; then
        log_info "  - 의류 타입 필터: $CLOTHING_TYPE"
    fi
    if [ "$READINESS_ONLY" = true ]; then
        log_info "  - 준비 상태만 확인: 활성화"
    fi
    if [ "$COMPLETION_AUDIT" = true ]; then
        log_info "  - 완료 감사: 활성화"
    fi
    if [ -n "$COLLECTION_PLAN_PATH" ]; then
        log_info "  - 수집 계획 출력: $COLLECTION_PLAN_PATH"
    fi
    echo ""

    if [ "$PULL_DEVICE_DATA" = true ]; then
        pull_device_training_data
    fi

    # 학습 데이터 찾기
    find_training_data

    # 데이터 통계 확인
    check_data_statistics

    # 타입별 준비 상태 확인
    print_type_readiness

    if [ "$COMPLETION_AUDIT" = true ]; then
        run_completion_audit
        exit $?
    fi

    if [ "$READINESS_ONLY" = true ]; then
        log_success "학습 준비 상태 확인 완료"
        exit 0
    fi

    # 데이터 내보내기
    export_training_data

    if [ "$EXPORT_ONLY" = true ]; then
        log_success "데이터 내보내기 완료!"
        exit 0
    fi

    # 모델 디렉토리 생성
    mkdir -p "$MODELS_DIR"

    if [ "$PER_TYPE" = true ]; then
        if [ "$TRAINING_METHOD" != "python" ]; then
            log_error "--per-type는 현재 --method python에서만 지원합니다."
            exit 1
        fi

        local trainable_types
        trainable_types=$(list_trainable_clothing_types)
        if [ -z "$trainable_types" ]; then
            log_error "최소 원본 샘플 수($MIN_TYPE_SAMPLES)와 사용자 보정 원본 수($MIN_CORRECTED_SAMPLES)를 만족하는 의류 타입이 없습니다."
            exit 1
        fi

        log_info "타입별 학습 대상:"
        for clothing_type in $trainable_types; do
            log_info "  - $clothing_type"
        done

        for clothing_type in $trainable_types; do
            train_compile_deploy "${MODEL_NAME}_${clothing_type}" "$clothing_type"
        done
    else
        local model_name="$MODEL_NAME"
        if [ -n "$CLOTHING_TYPE" ]; then
            model_name="${MODEL_NAME}_${CLOTHING_TYPE}"
        fi
        train_compile_deploy "$model_name" "$CLOTHING_TYPE"
    fi

    echo ""
    log_success "🎉 ML 학습 워크플로우 완료!"
    log_info "다음 단계:"
    log_info "  1. Xcode에서 프로젝트를 열어 새 모델 확인"
    log_info "  2. 앱을 빌드하고 테스트"
    log_info "  3. 필요시 추가 데이터 수집 후 재학습"
}

# 스크립트 실행
main "$@"

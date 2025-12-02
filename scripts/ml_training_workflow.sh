#!/bin/bash

#########################################################################################
# ClothIQ ML 학습 워크플로우 스크립트
#
# 이 스크립트는 다음 작업을 수행합니다:
# 1. 학습 데이터 내보내기 (iOS 앱에서 수집된 데이터)
# 2. 데이터 통계 확인
# 3. 모델 학습 (Python/TensorFlow 또는 CreateML)
# 4. 학습된 모델 iOS 프로젝트에 복사
# 5. 성능 보고서 생성
#
# 사용법:
#   ./ml_training_workflow.sh [옵션]
#
# 옵션:
#   --method [python|createml]  학습 방법 선택 (기본값: python)
#   --epochs [숫자]             학습 에폭 수 (기본값: 100)
#   --batch-size [숫자]         배치 크기 (기본값: 32)
#   --export-only              데이터 내보내기만 수행
#   --skip-export              내보내기 건너뛰기
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
TRAINING_METHOD="python"
EPOCHS=100
BATCH_SIZE=32
EXPORT_ONLY=false
SKIP_EXPORT=false

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
    --export-only              데이터 내보내기만 수행
    --skip-export              내보내기 건너뛰기
    --help                     이 도움말 표시

예시:
    $0                          # 기본 설정으로 전체 워크플로우 실행
    $0 --method createml        # CreateML 사용
    $0 --export-only           # 데이터 내보내기만
    $0 --epochs 50 --batch-size 16  # 커스텀 학습 파라미터
EOF
}

# 시뮬레이터 데이터 경로 찾기
find_training_data() {
    log_info "학습 데이터 찾는 중..."

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
        local sample_count=$(python3 -c "
import json
with open('$TRAINING_DATA_PATH/labels.json', 'r') as f:
    data = json.load(f)
    print(len(data))
" 2>/dev/null)

        local user_corrected=$(python3 -c "
import json
with open('$TRAINING_DATA_PATH/labels.json', 'r') as f:
    data = json.load(f)
    corrected = sum(1 for d in data if d.get('isUserCorrected', False))
    print(corrected)
" 2>/dev/null)

        log_info "📊 데이터 통계:"
        log_info "  - 총 샘플 수: $sample_count"
        log_info "  - 사용자 수정 샘플: $user_corrected"

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
    log_info "Python/TensorFlow로 모델 학습 시작..."

    # 가상환경 활성화 (있는 경우)
    if [ -d "$PROJECT_ROOT/venv" ]; then
        source "$PROJECT_ROOT/venv/bin/activate"
    fi

    # 필요한 패키지 확인
    log_info "필수 패키지 확인 중..."
    python3 -m pip install --quiet tensorflow coremltools pillow numpy pandas scikit-learn

    # 학습 실행
    python3 "$SCRIPT_DIR/train_keypoint_model.py" \
        --data-path "$TRAINING_DATA_PATH" \
        --output-path "$MODELS_DIR" \
        --epochs "$EPOCHS" \
        --batch-size "$BATCH_SIZE" \
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
deploy_model() {
    log_info "학습된 모델을 iOS 프로젝트에 배포 중..."

    local model_file=""
    if [ "$TRAINING_METHOD" = "python" ]; then
        model_file="$MODELS_DIR/ClothingKeypointDetector.mlmodel"
    else
        model_file="$MODELS_DIR/ClothingKeypointDetector.mlmodel"
    fi

    if [ ! -f "$model_file" ]; then
        log_error "모델 파일을 찾을 수 없습니다: $model_file"
        exit 1
    fi

    # iOS 프로젝트의 CoreML 디렉토리에 복사
    local target_dir="$IOS_PROJECT/Resources/CoreML"
    mkdir -p "$target_dir"

    cp "$model_file" "$target_dir/"
    log_success "모델 배포 완료: $target_dir/"

    # 모델 정보 파일도 복사
    if [ -f "$MODELS_DIR/model_info.json" ]; then
        cp "$MODELS_DIR/model_info.json" "$target_dir/"
    fi
}

# 성능 보고서 생성
generate_report() {
    log_info "성능 보고서 생성 중..."

    local report_file="$LOG_DIR/training_report_$(date +%Y%m%d_%H%M%S).md"

    cat > "$report_file" << EOF
# ClothIQ ML 학습 보고서

**생성 일시**: $(date)
**학습 방법**: $TRAINING_METHOD
**에폭 수**: $EPOCHS
**배치 크기**: $BATCH_SIZE

## 데이터 통계

EOF

    # 데이터 통계 추가
    if [ -f "$MODELS_DIR/model_info.json" ]; then
        python3 -c "
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

# 메인 실행 함수
main() {
    print_header

    # 옵션 파싱
    parse_arguments "$@"

    log_info "설정:"
    log_info "  - 학습 방법: $TRAINING_METHOD"
    log_info "  - 에폭 수: $EPOCHS"
    log_info "  - 배치 크기: $BATCH_SIZE"
    echo ""

    # 학습 데이터 찾기
    find_training_data

    # 데이터 통계 확인
    check_data_statistics

    # 데이터 내보내기
    export_training_data

    if [ "$EXPORT_ONLY" = true ]; then
        log_success "데이터 내보내기 완료!"
        exit 0
    fi

    # 모델 디렉토리 생성
    mkdir -p "$MODELS_DIR"

    # 학습 수행
    if [ "$TRAINING_METHOD" = "python" ]; then
        train_with_python
    elif [ "$TRAINING_METHOD" = "createml" ]; then
        train_with_createml
    else
        log_error "지원하지 않는 학습 방법: $TRAINING_METHOD"
        exit 1
    fi

    # 모델 배포
    deploy_model

    # 보고서 생성
    generate_report

    echo ""
    log_success "🎉 ML 학습 워크플로우 완료!"
    log_info "다음 단계:"
    log_info "  1. Xcode에서 프로젝트를 열어 새 모델 확인"
    log_info "  2. 앱을 빌드하고 테스트"
    log_info "  3. 필요시 추가 데이터 수집 후 재학습"
}

# 스크립트 실행
main "$@"
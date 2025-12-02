#!/bin/bash

#########################################################################################
# ClothIQ ML 데이터 수집 테스트 스크립트
#
# 이 스크립트는 ML 학습 데이터 수집 기능을 테스트합니다.
#
# 사용법:
#   ./test_data_collection.sh [옵션]
#
# 옵션:
#   check     - 현재 수집된 데이터 확인
#   monitor   - 실시간 모니터링 (1초마다 갱신)
#   validate  - 데이터 무결성 검증
#   report    - 상세 리포트 생성
#########################################################################################

set -e

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 경로 설정
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 시뮬레이터 데이터 경로 찾기
find_data_path() {
    # 시뮬레이터 Documents 경로 찾기
    local simulator_path="$HOME/Library/Developer/CoreSimulator/Devices"

    # 가장 최근에 수정된 시뮬레이터 찾기
    local device_id=$(ls -t "$simulator_path" | head -1)

    if [ -z "$device_id" ]; then
        echo "❌ 시뮬레이터를 찾을 수 없습니다"
        exit 1
    fi

    # MLTrainingData 디렉토리 경로
    DATA_PATH="$simulator_path/$device_id/data/Containers/Data/Application"

    # 실제 앱 컨테이너 찾기 (가장 최근 수정된 것)
    for app_dir in $(ls -t "$DATA_PATH" 2>/dev/null | head -5); do
        local test_path="$DATA_PATH/$app_dir/Documents/MLTrainingData"
        if [ -d "$test_path" ]; then
            DATA_PATH="$test_path"
            return 0
        fi
    done

    # 못 찾으면 로컬 테스트 경로 사용
    DATA_PATH="$PROJECT_ROOT/test_data/MLTrainingData"
    mkdir -p "$DATA_PATH"
    echo "⚠️ 시뮬레이터 데이터를 찾을 수 없어 테스트 경로 사용: $DATA_PATH"
}

# 헤더 출력
print_header() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}    ClothIQ ML 데이터 수집 테스트${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
}

# 데이터 확인
check_data() {
    print_header
    echo -e "${BLUE}[데이터 확인]${NC}"
    echo ""

    if [ ! -d "$DATA_PATH" ]; then
        echo -e "${RED}❌ 데이터 디렉토리가 존재하지 않습니다${NC}"
        echo "   경로: $DATA_PATH"
        exit 1
    fi

    echo -e "${GREEN}✅ 데이터 경로:${NC} $DATA_PATH"
    echo ""

    # labels.json 확인
    if [ -f "$DATA_PATH/labels.json" ]; then
        local sample_count=$(python3 -c "
import json
try:
    with open('$DATA_PATH/labels.json', 'r') as f:
        data = json.load(f)
        print(len(data))
except:
    print(0)
" 2>/dev/null)

        local file_size=$(du -h "$DATA_PATH/labels.json" | cut -f1)

        echo -e "${GREEN}📄 labels.json${NC}"
        echo "   - 샘플 수: $sample_count개"
        echo "   - 파일 크기: $file_size"

        # 최근 5개 샘플 정보
        if [ "$sample_count" -gt 0 ]; then
            echo ""
            echo -e "${BLUE}최근 수집된 샘플 (최대 5개):${NC}"
            python3 -c "
import json
from datetime import datetime

with open('$DATA_PATH/labels.json', 'r') as f:
    data = json.load(f)

# 최근 5개만
for i, sample in enumerate(data[-5:], 1):
    timestamp = sample.get('timestamp', 'Unknown')
    clothing_type = sample.get('clothingType', 'Unknown')
    is_corrected = sample.get('isUserCorrected', False)
    confidence = sample.get('confidence', 0)
    keypoints_count = len(sample.get('keypoints', []))

    corrected_mark = '✅' if is_corrected else '  '
    print(f'   {i}. [{corrected_mark}] {clothing_type}')
    print(f'      - 시간: {timestamp}')
    print(f'      - 키포인트: {keypoints_count}개')
    print(f'      - 신뢰도: {confidence:.1%}')
    print()
" 2>/dev/null || echo "   파싱 오류"
        fi
    else
        echo -e "${YELLOW}⚠️ labels.json 파일이 없습니다${NC}"
    fi

    # images 디렉토리 확인
    echo ""
    if [ -d "$DATA_PATH/images" ]; then
        local image_count=$(ls "$DATA_PATH/images" 2>/dev/null | wc -l | tr -d ' ')
        local dir_size=$(du -sh "$DATA_PATH/images" 2>/dev/null | cut -f1)

        echo -e "${GREEN}📁 images/${NC}"
        echo "   - 이미지 수: $image_count개"
        echo "   - 전체 크기: $dir_size"
    else
        echo -e "${YELLOW}⚠️ images 디렉토리가 없습니다${NC}"
    fi

    # CreateML 데이터 확인
    echo ""
    if [ -f "$DATA_PATH/createml_data.json" ]; then
        local createml_size=$(du -h "$DATA_PATH/createml_data.json" | cut -f1)
        echo -e "${GREEN}🤖 createml_data.json${NC}"
        echo "   - 파일 크기: $createml_size"
        echo "   - 상태: CreateML 형식으로 내보내기 완료"
    else
        echo -e "${YELLOW}⚠️ CreateML 데이터가 아직 생성되지 않았습니다${NC}"
    fi
}

# 실시간 모니터링
monitor_data() {
    print_header
    echo -e "${BLUE}[실시간 모니터링 모드]${NC}"
    echo "종료하려면 Ctrl+C를 누르세요"
    echo ""

    while true; do
        clear
        print_header
        echo -e "${BLUE}[실시간 모니터링]${NC} $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""

        if [ -f "$DATA_PATH/labels.json" ]; then
            python3 -c "
import json
import os
from datetime import datetime

labels_path = '$DATA_PATH/labels.json'
images_path = '$DATA_PATH/images'

# Labels 파일 읽기
try:
    with open(labels_path, 'r') as f:
        data = json.load(f)

    total = len(data)
    user_corrected = sum(1 for d in data if d.get('isUserCorrected', False))
    avg_confidence = sum(d.get('confidence', 0) for d in data) / max(total, 1)

    # 의류 타입별 통계
    clothing_types = {}
    for d in data:
        ctype = d.get('clothingType', 'Unknown')
        clothing_types[ctype] = clothing_types.get(ctype, 0) + 1

    print(f'📊 데이터 통계:')
    print(f'   총 샘플: {total}개')
    print(f'   사용자 수정: {user_corrected}개 ({user_corrected/max(total,1)*100:.1f}%)')
    print(f'   평균 신뢰도: {avg_confidence:.1%}')
    print()

    print('👕 의류 타입별:')
    for ctype, count in clothing_types.items():
        print(f'   - {ctype}: {count}개')
    print()

    # 최근 샘플
    if data:
        latest = data[-1]
        print('🆕 최근 수집:')
        print(f'   타입: {latest.get(\"clothingType\", \"Unknown\")}')
        print(f'   시간: {latest.get(\"timestamp\", \"Unknown\")}')
        print(f'   수정: {\"예\" if latest.get(\"isUserCorrected\", False) else \"아니오\"}')

    # 이미지 디렉토리 크기
    if os.path.exists(images_path):
        image_count = len(os.listdir(images_path))
        print()
        print(f'🖼 이미지: {image_count}개')

except Exception as e:
    print(f'오류: {e}')
" 2>/dev/null || echo "데이터 읽기 오류"
        else
            echo "데이터 파일이 없습니다"
        fi

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        sleep 1
    done
}

# 데이터 검증
validate_data() {
    print_header
    echo -e "${BLUE}[데이터 무결성 검증]${NC}"
    echo ""

    local has_error=false

    # 1. JSON 파일 검증
    echo "1. JSON 파일 검증..."
    if [ -f "$DATA_PATH/labels.json" ]; then
        python3 -c "
import json
try:
    with open('$DATA_PATH/labels.json', 'r') as f:
        data = json.load(f)
    print('   ✅ JSON 파싱 성공')

    # 필수 필드 확인
    errors = []
    for i, sample in enumerate(data):
        if 'id' not in sample:
            errors.append(f'샘플 {i}: id 필드 누락')
        if 'clothingType' not in sample:
            errors.append(f'샘플 {i}: clothingType 필드 누락')
        if 'keypoints' not in sample:
            errors.append(f'샘플 {i}: keypoints 필드 누락')

    if errors:
        print('   ❌ 필수 필드 누락:')
        for err in errors[:5]:  # 최대 5개만 표시
            print(f'      - {err}')
    else:
        print('   ✅ 모든 필수 필드 존재')

except json.JSONDecodeError as e:
    print(f'   ❌ JSON 파싱 실패: {e}')
except Exception as e:
    print(f'   ❌ 오류: {e}')
" || has_error=true
    else
        echo "   ❌ labels.json 파일 없음"
        has_error=true
    fi

    echo ""

    # 2. 이미지 파일 검증
    echo "2. 이미지 파일 검증..."
    if [ -d "$DATA_PATH/images" ]; then
        local image_count=$(ls "$DATA_PATH/images" 2>/dev/null | wc -l | tr -d ' ')
        echo "   📁 이미지 수: $image_count개"

        # 손상된 이미지 확인
        local corrupted=0
        for img in "$DATA_PATH/images"/*.jpg "$DATA_PATH/images"/*.png; do
            if [ -f "$img" ]; then
                if ! file "$img" | grep -q "image" 2>/dev/null; then
                    ((corrupted++))
                fi
            fi
        done

        if [ $corrupted -gt 0 ]; then
            echo "   ❌ 손상된 이미지: $corrupted개"
            has_error=true
        else
            echo "   ✅ 모든 이미지 정상"
        fi
    else
        echo "   ⚠️ images 디렉토리 없음"
    fi

    echo ""

    # 3. 데이터 일관성 검증
    echo "3. 데이터 일관성 검증..."
    python3 -c "
import json
import os

labels_path = '$DATA_PATH/labels.json'
images_path = '$DATA_PATH/images'

try:
    with open(labels_path, 'r') as f:
        data = json.load(f)

    # 중복 ID 확인
    ids = [d.get('id') for d in data if 'id' in d]
    if len(ids) != len(set(ids)):
        print('   ❌ 중복된 ID 발견')
    else:
        print('   ✅ ID 중복 없음')

    # 키포인트 유효성 확인
    invalid_keypoints = 0
    for sample in data:
        for kp in sample.get('keypoints', []):
            x = kp.get('x', 0)
            y = kp.get('y', 0)
            if not (0 <= x <= 1 and 0 <= y <= 1):
                invalid_keypoints += 1
                break

    if invalid_keypoints > 0:
        print(f'   ❌ 유효하지 않은 키포인트: {invalid_keypoints}개 샘플')
    else:
        print('   ✅ 모든 키포인트 좌표 정상 (0.0~1.0)')

except Exception as e:
    print(f'   ❌ 검증 실패: {e}')
" || has_error=true

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "$has_error" = true ]; then
        echo -e "${RED}⚠️ 일부 검증 항목에서 문제가 발견되었습니다${NC}"
    else
        echo -e "${GREEN}✅ 모든 검증 항목 통과${NC}"
    fi
}

# 상세 리포트 생성
generate_report() {
    print_header
    echo -e "${BLUE}[상세 리포트 생성]${NC}"
    echo ""

    local report_file="$PROJECT_ROOT/ml_data_report_$(date +%Y%m%d_%H%M%S).md"

    {
        echo "# ClothIQ ML 데이터 수집 리포트"
        echo ""
        echo "생성 시간: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "## 데이터 경로"
        echo "\`\`\`"
        echo "$DATA_PATH"
        echo "\`\`\`"
        echo ""

        if [ -f "$DATA_PATH/labels.json" ]; then
            python3 -c "
import json
import os
from datetime import datetime

labels_path = '$DATA_PATH/labels.json'

with open(labels_path, 'r') as f:
    data = json.load(f)

total = len(data)
user_corrected = sum(1 for d in data if d.get('isUserCorrected', False))
avg_confidence = sum(d.get('confidence', 0) for d in data) / max(total, 1)

print('## 통계 요약')
print()
print(f'- **총 샘플 수**: {total}개')
print(f'- **사용자 수정 샘플**: {user_corrected}개 ({user_corrected/max(total,1)*100:.1f}%)')
print(f'- **평균 신뢰도**: {avg_confidence:.1%}')
print()

# 의류 타입별 분포
clothing_types = {}
for d in data:
    ctype = d.get('clothingType', 'Unknown')
    clothing_types[ctype] = clothing_types.get(ctype, 0) + 1

print('## 의류 타입별 분포')
print()
print('| 의류 타입 | 샘플 수 | 비율 |')
print('|-----------|---------|------|')
for ctype, count in sorted(clothing_types.items(), key=lambda x: x[1], reverse=True):
    ratio = count / max(total, 1) * 100
    print(f'| {ctype} | {count} | {ratio:.1f}% |')
print()

# 시간대별 수집 패턴
print('## 수집 패턴')
print()
if data:
    first_timestamp = data[0].get('timestamp', '')
    last_timestamp = data[-1].get('timestamp', '')
    print(f'- **첫 수집**: {first_timestamp}')
    print(f'- **마지막 수집**: {last_timestamp}')
    print(f'- **수집 기간**: 계산 필요')
print()

# 키포인트 통계
total_keypoints = sum(len(d.get('keypoints', [])) for d in data)
avg_keypoints = total_keypoints / max(total, 1)
print('## 키포인트 통계')
print()
print(f'- **총 키포인트**: {total_keypoints}개')
print(f'- **평균 키포인트/샘플**: {avg_keypoints:.1f}개')
print()

# 최근 10개 샘플
print('## 최근 수집 샘플 (최대 10개)')
print()
print('| # | 의류 타입 | 시간 | 수정 | 신뢰도 | 키포인트 |')
print('|---|-----------|------|------|--------|----------|')
for i, sample in enumerate(data[-10:], 1):
    ctype = sample.get('clothingType', 'Unknown')
    timestamp = sample.get('timestamp', 'Unknown')[:10]  # 날짜만
    corrected = '✅' if sample.get('isUserCorrected', False) else '❌'
    confidence = sample.get('confidence', 0)
    kp_count = len(sample.get('keypoints', []))
    print(f'| {i} | {ctype} | {timestamp} | {corrected} | {confidence:.1%} | {kp_count} |')
"
        else
            echo "## 오류"
            echo "데이터 파일을 찾을 수 없습니다."
        fi
    } > "$report_file"

    echo -e "${GREEN}✅ 리포트 생성 완료:${NC} $report_file"
    echo ""

    # 리포트 미리보기
    echo "리포트 미리보기 (처음 20줄):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    head -20 "$report_file"
    echo "..."
}

# 메인 함수
main() {
    # 데이터 경로 찾기
    find_data_path

    case "${1:-check}" in
        check)
            check_data
            ;;
        monitor)
            monitor_data
            ;;
        validate)
            validate_data
            ;;
        report)
            generate_report
            ;;
        *)
            echo "사용법: $0 [check|monitor|validate|report]"
            echo ""
            echo "  check    - 현재 수집된 데이터 확인"
            echo "  monitor  - 실시간 모니터링"
            echo "  validate - 데이터 무결성 검증"
            echo "  report   - 상세 리포트 생성"
            exit 1
            ;;
    esac
}

# 실행
main "$@"
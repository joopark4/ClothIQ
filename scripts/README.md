# iOS Device Development Tools

연결된 iOS 디바이스에서 앱을 빌드, 배포, 디버깅하는 자동화 도구입니다.

## 빠른 시작

```bash
# 1. 설정 파일 생성
cp ios_device_config.template ios_device_config.sh

# 2. 설정 파일 편집 (프로젝트 경로, 스킴, 번들 ID)
nano ios_device_config.sh

# 3. 디바이스 연결 확인
./ios_device_tools.sh list-devices

# 4. 빌드 + 배포 + 로그
./ios_device_tools.sh full-deploy
```

## 주요 명령어

| 명령어 | 설명 |
|--------|------|
| `list-devices` | 연결된 디바이스 목록 |
| `build` | 프로젝트 빌드 |
| `install` | 앱 설치 |
| `launch` | 앱 실행 |
| `logs` | 실시간 로그 스트리밍 |
| `stop` | 앱 종료 |
| `full-deploy` | 빌드→설치→실행→로그 (권장) |
| `monitor` | 프로세스 모니터링 |
| `crash-logs` | 크래시 로그 수집 |
| `profile` | 성능 프로파일링 |

## 상세 가이드

전체 사용 가이드는 **[DOC/IOS_DEVICE_GUIDE.md](../DOC/IOS_DEVICE_GUIDE.md)** 를 참조하세요.

## 다른 프로젝트에 적용하기

1. `ios_device_tools.sh`와 `ios_device_config.template`을 복사
2. 설정 파일 생성 및 편집
3. 프로젝트 정보 입력 (프로젝트 경로, 스킴, 번들 ID)
4. `./ios_device_tools.sh full-deploy` 실행

자세한 내용은 [DOC/IOS_DEVICE_GUIDE.md](../DOC/IOS_DEVICE_GUIDE.md)의 "다른 프로젝트에 적용하기" 섹션을 참조하세요.

## 파일 설명

- **ios_device_tools.sh**: 메인 스크립트 (실행 파일)
- **ios_device_config.template**: 설정 파일 템플릿
- **ios_device_config.sh**: 프로젝트별 설정 (생성 필요, .gitignore에 추가 권장)

## 요구사항

- macOS (Sonoma 이상)
- Xcode 15.0+
- 연결된 iOS 디바이스

## 라이선스

MIT License - 자유롭게 수정 및 재배포 가능

---

# ClothIQ 자동화 스크립트 (추가)

ClothIQ 개발 워크플로우를 더욱 간소화하는 추가 자동화 스크립트입니다.

## 추가 스크립트 목록

### 0. ML 학습/수집 워크플로우

실제 촬영 데이터로 의류 타입별 키포인트 모델을 학습하고 Core ML 모델을 앱에 배포하는 흐름입니다. 현재 타입별 학습/배포는 실제 촬영 원본과 사용자 보정 원본이 기준을 충족할 때까지 보류합니다.

촬영 데이터 저장 위치와 수동 데이터 형식은 `DOC/ML_DATA_COLLECTION_GUIDE.md`를 먼저 확인하세요.

앱 컨테이너 기준 핵심 저장 위치:

- 촬영 원본: `Documents/clothing_images/*.jpg`
- 깊이맵: `Documents/depth_maps/*.png`
- 의류/측정 저장소: `Library/Application Support/default.store`
- ML 학습 라벨: `Documents/MLTrainingData/labels.json`
- 학습 모델 배포: `Documents/MLTrainingData/Models/*.mlmodelc`

수동으로 외부 데이터를 넣을 때는 `tmp/manual-training-data/labels.json` 형태로 두고 `--data-path tmp/manual-training-data`를 지정합니다.

**환경 준비/검증**:
```bash
cd ..
scripts/setup_ml_training_env.sh --verify-only --smoke-conversion
```

처음 설정하거나 `.venv-ml`이 없는 경우:
```bash
cd ..
scripts/setup_ml_training_env.sh
```

**기기 데이터 준비 상태 확인**:
```bash
cd ..
bash scripts/ml_training_workflow.sh \
  --pull-device-data \
  --device-id <device-id> \
  --pulled-data-path tmp/latest-device-training-data \
  --readiness-only \
  --skip-export
```

**기기 스냅샷 전체 추출 + SwiftData 복구 + 병합**:
```bash
cd ..
bash scripts/pull_training_snapshot.sh \
  --device-id <device-id> \
  --output-dir tmp/latest-training-snapshot \
  --completion-audit \
  --collection-plan tmp/ml-training-collection-plan-current-audit.md \
  --capture-checklist tmp/ml-training-required-capture-checklist.md
```

이 명령은 `Documents/MLTrainingData`, `Documents`, `Library/Application Support`를 함께 복사하고 `default.store`에서 복구 가능한 측정 라벨을 병합합니다. 앱에서 촬영/보정한 뒤에는 이 명령을 우선 사용하세요.

**현재 보류 상태와 재개 순서**:

실제 촬영 데이터 수집에는 시간이 걸리므로, 타입별 ML 학습/배포는 촬영 데이터가 기준을 충족할 때까지 보류합니다.

새로 촬영한 뒤에는 아래 순서로 이어서 진행합니다.

1. 기기 스냅샷 추출
2. 완료 감사 실행
3. 타입별 학습 실행
4. `ClothingKeypointDetector_<type>.mlmodelc` 컴파일
5. `Documents/MLTrainingData/Models/*.mlmodelc` 배포

**완료 감사 및 수집 계획 생성**:
```bash
cd ..
bash scripts/ml_training_workflow.sh \
  --data-path tmp/latest-training-snapshot/merged \
  --completion-audit \
  --collection-plan tmp/ml-training-collection-plan-current.md \
  --capture-checklist tmp/ml-training-required-capture-checklist.md \
  --skip-export
```

**여러 기기 데이터 병합**:
```bash
cd ..
python3 scripts/merge_training_data.py \
  --input tmp/latest-device-training-data-ipad \
  --input tmp/latest-device-training-data-iphone \
  --output-dir tmp/latest-device-training-data-merged
```

**타입별 학습/컴파일/배포**:
```bash
cd ..
bash scripts/ml_training_workflow.sh \
  --data-path tmp/latest-training-snapshot/merged \
  --per-type \
  --skip-export
```

학습 완료 기준은 16개 의류 타입 전체에 대해 타입별 고유 실제 원본 촬영 20개 이상, 고유 사용자 보정 원본 촬영 3개 이상, 필수 키포인트 coverage 충족, 컴파일된 `ClothingKeypointDetector_<type>.mlmodelc` 생성입니다. 증강 샘플과 같은 이미지의 중복 라벨 레코드는 완료 기준의 실제 원본 촬영 수로 계산하지 않습니다.

현재 감사 기준으로는 총 라벨 17개, 고유 실제 촬영 원본 16장, 고유 사용자 보정 원본 1장만 있어 타입별 학습 기준을 충족하지 못합니다. 새 촬영/보정 데이터가 들어오기 전에는 `--per-type` 학습이 모델 생성을 중단하는 것이 정상입니다.

### 1. `quick_deploy.sh` - 빠른 빌드 및 배포

빌드 → 설치 → 실행 → 로그 스트리밍을 한 번에 수행합니다.

**사용법**:
```bash
cd scripts
./quick_deploy.sh
```

**실행 내용**:
1. 📦 프로젝트 빌드
2. 📲 디바이스에 앱 설치
3. 🚀 앱 실행
4. 📋 실시간 로그 스트리밍 (Ctrl+C로 종료)

---

### 2. `collect_logs.sh` - 로그 수집

디바이스에서 최근 5분간의 로그를 파일로 저장합니다.

**사용법**:
```bash
cd scripts
./collect_logs.sh
```

**출력**:
- `Reference/device_log_YYYYMMDD_HHMMSS.txt`

**내용**:
- ClothIQ 앱의 모든 진단 로그
- 자동으로 주요 키워드(ClothingType, 측정, confidence, 좌표) 필터링하여 표시

---

### 3. `automated_test.sh` - 자동화 테스트

빌드부터 테스트 결과 분석까지 전체 워크플로우를 자동화합니다.

**사용법**:
```bash
cd scripts
./automated_test.sh
```

**실행 순서**:
1. 📦 빌드
2. 📲 설치
3. 🚀 실행
4. 📋 로그 수집 시작
5. ⏳ 사용자 테스트 대기
   - 의류 라이브러리 열기
   - 아이템 선택 (반바지)
   - "재측정" 버튼 탭
   - 측정 완료
   - **ENTER 키 입력**
6. 🔍 결과 자동 분석
   - 의류 분류 검증
   - 신뢰도 검증
   - 좌표 검증

**출력**:
- `TestResults/test_result_YYYYMMDD_HHMMSS.txt` - 테스트 결과 요약
- `TestResults/test_log_YYYYMMDD_HHMMSS.txt` - 전체 로그

**결과 예시**:
```
🧪 [ClothIQ Automated Test]
Timestamp: 20251106_230000

📦 Step 1: Building...
✅ Build: PASS

📲 Step 2: Installing...
✅ Install: PASS

🚀 Step 3: Launching app...
✅ Launch: PASS

🔍 Step 6: Analyzing results...
✅ Classification: PASS (shorts)
✅ Confidence: PASS (>70%)
   Value: 0.846
✅ Coordinates: FOUND
   start=(0.59, 0.85) end=(0.56, 0.12)

📊 Test Summary:
   Build: ✅
   Install: ✅
   Launch: ✅
   Classification: ✅
   Confidence: ✅
```

---

## 환경 변수 설정 (선택)

`~/.zshrc` 또는 `~/.bash_profile`에 다음을 추가하면 더 편리하게 사용할 수 있습니다:

```bash
# ClothIQ 개발 환경 변수
export CLOTHIQ_DEVICE_ID="<device-id>"
export CLOTHIQ_BUNDLE_ID="<bundle-id>"
export CLOTHIQ_PROJECT_DIR="<repo>/ClothIQ"

# 단축 명령어 (aliases)
alias ciq-deploy='cd <repo>/scripts && ./quick_deploy.sh'
alias ciq-logs='cd <repo>/scripts && ./collect_logs.sh'
alias ciq-test='cd <repo>/scripts && ./automated_test.sh'
```

설정 후:
```bash
source ~/.zshrc
ciq-deploy  # 원클릭 배포!
```

---

## 상세 개발 워크플로우

전체 개발 워크플로우는 루트 [README.md](../README.md), 진행 상황은 [ClothIQ/PROGRESS.md](../ClothIQ/PROGRESS.md), iOS 디바이스 가이드는 [DOC/IOS_DEVICE_GUIDE.md](../DOC/IOS_DEVICE_GUIDE.md)를 참조하세요.

**마지막 업데이트**: 2026년 5월 8일

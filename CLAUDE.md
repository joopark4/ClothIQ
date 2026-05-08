# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

- 소통과 진행사항 등 내용은 모두 한글로 진행합니다.

## 프로젝트 개요

ClothIQ는 LiDAR 기반 AR 측정과 사진 기반 후처리 측정을 결합한 iOS 앱입니다.
의류 이미지를 촬영하고, 측정값/앵커/메타데이터를 SwiftData + 파일 시스템에 저장해 라이브러리에서 관리합니다.

- iOS Deployment Target: `26.0`
- 대상 기기: iPad Pro (LiDAR 필수)
- 외부 SPM 의존성 없음 (Apple 프레임워크만 사용)

## 빌드 및 실행

### Xcode에서 열기

```bash
cd ClothIQ && open ClothIQ.xcodeproj
```

### CLI 빌드 (xcodebuild)

```bash
xcodebuild -project ClothIQ/ClothIQ.xcodeproj \
  -scheme ClothIQ \
  -sdk iphoneos \
  -configuration Debug \
  -derivedDataPath ./DerivedData \
  -allowProvisioningUpdates \
  clean build
```

### 디바이스 배포 스크립트

```bash
# 디바이스 설정 (최초 1회)
cd scripts && cp ios_device_config.template ios_device_config.sh
# ios_device_config.sh에 프로젝트 경로, 번들 ID, 서명 설정 입력

# 주요 명령
./ios_device_tools.sh list-devices      # 연결된 디바이스 확인
./ios_device_tools.sh full-deploy       # 빌드 → 설치 → 실행 → 로그 스트리밍
./ios_device_tools.sh build             # 빌드만
./ios_device_tools.sh logs              # 실시간 로그
./ios_device_tools.sh crash-logs        # 크래시 로그 수집
```

### 테스트

테스트 타겟(`ClothIQTests`, `ClothIQUITests`)이 존재하며, 사진 측정 좌표계/ML 키포인트/배경 제거 회귀 테스트를 포함합니다.

```bash
xcodebuild test -project ClothIQ/ClothIQ.xcodeproj \
  -scheme ClothIQ \
  -destination 'platform=iOS Simulator,name=iPad Pro'
```

## 아키텍처

**Clean Architecture + MVVM** 패턴을 사용합니다.

```
ClothIQ/ClothIQ/
├── App/                    # 앱 진입점 (ClothIQApp, ModelContainer 설정)
├── Core/                   # 공유 레이어
│   ├── Data/               #   SwiftData 모델, 파일 시스템 관리
│   ├── Domain/Enums/       #   ClothingType, MeasurementType, MeasurementUnit
│   ├── UI/                 #   재사용 UI 컴포넌트
│   ├── Extensions/         #   UIImage 등 확장
│   └── Utilities/          #   Constants, DeviceCapability, MeasurementSettings 등
└── Features/               # 기능 모듈
    ├── Measurement/        #   AR 카메라 실측
    ├── ClothingLibrary/    #   의류 라이브러리 + 사진 측정
    ├── ImageProcessing/    #   이미지 캡처/크롭/배경 제거
    └── Settings/           #   설정 + 디버그 패널
```

각 Feature 모듈 내부 구조:

```
Features/[FeatureName]/
├── Domain/         # 엔티티, 프로토콜, 유스케이스
├── Data/Services/  # 서비스 구현체
└── Presentation/
    ├── ViewModels/ # @Observable ViewModel
    ├── Views/      # SwiftUI View
    └── Components/ # 재사용 UI 컴포넌트
```

### 주요 데이터 흐름

1. **AR 측정 플로우**: `MeasurementView` → `MeasurementViewModel` → `ARMeasurementService` (LiDAR 포인트 추출) → `MultiSamplingProcessor` (15프레임 샘플링) → `MeasurementCalculator` (거리 계산) → 미리보기 → SwiftData 저장
2. **사진 측정 플로우**: `PhotoMeasurementView` → `PhotoMeasurementViewModel` → `PhotoMeasurementCalculator` (이미지 좌표 기반 거리 계산)
3. **이미지 처리**: `ObjectCaptureService` → `ForegroundSegmentationService` (Vision 전경 마스크) → 크롭/배경 제거 → `ImageFileManager` (로컬 저장)

### SwiftData 모델 관계

- `ClothingItemModel` — 의류 아이템 (이미지, 메타데이터)
- `MeasurementModel` — 측정값 (정규화 좌표, `measurementMethodRaw`: `ar`/`photo`)
- `TagModel` — 태그
- `CalibrationProfile` / `CalibrationFactor` — 교정 프로파일

### 핵심 설계 규칙

- AR 측정 좌표는 **정규화**하여 저장 (기기 해상도 독립)
- AR 캡처 값은 상세 화면에서 photo 교정을 재적용하지 않음 (`measurementMethodRaw`로 분기)
- 서비스는 프로토콜 기반 추상화 (`ARMeasurementServiceProtocol` 등)

## 기술 스택

SwiftUI, SwiftData, ARKit + RealityKit, Vision + Core ML, Combine, Accelerate

## 개발 워크플로우 (Harness Design)

이 프로젝트에서 복잡한 작업을 수행할 때는 다음 패턴을 따릅니다.

### Generator-Evaluator 루프

코드를 변경(Generate)한 뒤 반드시 검증(Evaluate)합니다. **자기 자신의 코드를 스스로 평가하지 말 것** — 독립적인 검증 도구를 사용합니다.

```bash
# 1. 코드 변경 후 빌드 검증 (Evaluator)
./scripts/validate_build.sh --quick    # 증분 빌드 + 경고 분석

# 2. 코드 품질 QA (독립 Evaluator)
./scripts/qa_check.sh --changed        # 변경 파일만 검사
./scripts/qa_check.sh                  # 전체 검사
```

검증 실패 시: 에러를 분석하고 코드를 수정한 뒤 다시 검증합니다. 이 루프를 빌드 성공 + QA 통과까지 반복합니다.

### Sprint Contract 패턴

대규모 기능을 구현할 때는 한 번에 전부 구현하지 않고, 스프린트 단위로 나눕니다.

1. **계획(Plan)**: 구현할 기능의 범위와 검증 방법을 먼저 정의
2. **구현(Generate)**: 한 번에 한 기능씩 구현
3. **검증(Evaluate)**: 각 스프린트 후 빌드 검증 + QA 검사 실행
4. **반복**: 검증 통과 후 다음 스프린트로 진행

### 검증 스크립트 사용법

| 스크립트 | 용도 | 사용 시점 |
| --- | --- | --- |
| `scripts/validate_build.sh` | 빌드 성공 + 경고 분석 | 코드 변경 후 |
| `scripts/validate_build.sh --quick` | 증분 빌드 (빠른 검증) | 소규모 변경 후 |
| `scripts/qa_check.sh --changed` | 변경 파일만 QA | 커밋 전 |
| `scripts/qa_check.sh` | 전체 QA | 스프린트 완료 시 |

### 컨텍스트 관리 원칙

- 긴 작업 시 중간 결과를 파일에 기록 (PROGRESS.md 등)하여 컨텍스트 유실 방지
- 각 스프린트의 완료 상태를 명확히 기록
- 이전 작업의 결정 사항과 이유를 코드 커밋 메시지에 남기기

## 알려진 이슈

- 실제 촬영/수동 보정 데이터가 부족해 타입별 ML 학습/배포는 보류 상태
- LiDAR 미지원 기기에서 핵심 기능 제한
- AR 측정 정확도는 조명/거리/의류 평탄도에 영향받음

## 문서 인덱스

| 문서 | 위치 |
| --- | --- |
| 진행 상황 | `ClothIQ/PROGRESS.md` |
| 권한 설정 | `ClothIQ/ClothIQ/App/README_PERMISSIONS.md` |
| 스크립트 사용법 | `scripts/README.md` |
| 디바이스 배포 가이드 | `DOC/IOS_DEVICE_GUIDE.md` |
| 라이브 디버그/임계값 | `DOC/LIVE_DEBUG_ANALYSIS.md` |
| Core ML 통합 | `DOC/CORE_ML_INTEGRATION_GUIDE.md` |
| ML 데이터 수집 | `DOC/ML_DATA_COLLECTION_GUIDE.md` |
| 이슈 기록 | `ISSUE/` |
| 상세 운영 가이드 | `DOC/` |

## 개인정보/보안 문서 작성 원칙

- 문서에 개인 이름, 이메일, 전화번호, 기기 UDID, 팀 식별자, 개발팀 ID, 프로비저닝 식별자를 기록하지 않습니다.
- 사용자 홈을 포함한 절대 경로를 기록하지 않습니다.
- 문서에는 상대 경로와 `<repo>`, `<device-id>`, `<bundle-id>` 같은 일반화된 placeholder를 사용합니다.
- `tmp/`, `logs/`, `.codex/`, `scripts/__pycache__/`, 기기 스냅샷, 학습 라벨 원본, 모델 산출물은 커밋하지 않습니다.

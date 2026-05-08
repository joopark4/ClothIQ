# ClothIQ

ClothIQ는 LiDAR 기반 AR 측정과 사진 기반 후처리 측정을 결합한 iOS 의류 측정 앱입니다. 의류를 촬영하고, 측정값/앵커/키포인트/촬영 메타데이터를 SwiftData와 앱 컨테이너 파일 시스템에 저장해 라이브러리에서 관리합니다.

- 저장소 루트: 현재 작업 디렉터리
- 앱 프로젝트: `ClothIQ/ClothIQ.xcodeproj`
- 스킴: `ClothIQ`
- 현재 작업 브랜치: `RD`
- 현재 PR: `RD -> main` (`#5`)

## 현재 구현 상태 (2026-05-08 기준)

### 측정 플로우

- AR 카메라 측정
  - 의류 타입 선택
  - 측정 항목 선택
  - 선택 항목 기준 앵커 측정
  - `적용` / `다시 찍기` 흐름
  - 촬영 이미지, depth map, 측정 메타데이터 저장
- 사진 측정
  - 저장된 촬영 이미지 기반 앵커 편집
  - 회전/크롭/표시 영역을 고려한 좌표 변환
  - 기존 측정값 오버레이 표시
  - ML 모드 ON/OFF 전환
  - 사용자 보정 앵커를 학습 데이터로 수집
- 제거된 흐름
  - 의도와 달랐던 "라인을 따라 길이 측정" 방식은 사용하지 않음
  - 선택된 측정 항목과 키포인트 매핑이 없는 경우 임의 fallback으로 첫 라인을 쓰지 않음

### 의류 타입/키포인트

- `ClothingType.allCases` 기준 16개 의류 타입을 감사 대상으로 사용
- 상의/하의/원피스류별 측정 라인과 키포인트 매핑 분리
- `shorts`, `pants`, `skirt`, `leggings`, `dress`, `jumpsuit` 등 하의/복합 타입의 허리, 엉덩이, 밑단, 가랑이, 어깨, 목선 계열 키포인트를 타입별로 처리
- 타입별 prior와 학습 모델 로딩 경로를 분리

### 이미지 처리

- Vision/Depth 기반 배경 제거
- 객체 중심 크롭
- 배경 잔여 픽셀 완화를 위한 마스크 후처리
- Photos 저장 연동

### ML 학습/배포 상태

- 앱 내 학습 데이터 수집, 통계, 상세 부족분 표시 지원
- 기기 스냅샷 추출, SwiftData 복구, 라벨 병합, 완료 감사 스크립트 제공
- 타입별 `.mlmodelc` 로딩 경로 구현
  - 앱 번들
  - 앱 번들 `CoreML`
  - 앱 번들 `Resources/CoreML`
  - `Documents/MLTrainingData/Models`
- 현재 타입별 ML 학습/배포는 보류 상태
  - 실제 촬영 원본과 사용자 보정 원본이 기준에 부족함
  - 기준 미달 데이터로 모델을 만들지 않도록 학습 게이트가 차단

## 현재 ML 완료 기준

타입별 모델 학습/배포 완료로 보려면 아래 조건을 모두 만족해야 합니다.

- 16개 의류 타입 전체 감사
- 각 타입별 고유 실제 촬영 원본 20장 이상
- 각 타입별 고유 사용자 보정 원본 3장 이상
- 타입별 필수 키포인트 coverage 충족
- `ClothingKeypointDetector_<type>.mlmodelc` 컴파일 및 배포

마지막 감사 기준으로는 총 라벨 17개, 고유 실제 촬영 원본 16장, 고유 사용자 보정 원본 1장만 있어 학습/배포를 진행하지 않았습니다.

새 촬영 데이터가 준비되면 다음 순서로 재개합니다.

1. 기기 스냅샷 추출
2. 완료 감사
3. 타입별 학습
4. `.mlmodelc` 컴파일
5. 앱 번들 또는 `Documents/MLTrainingData/Models` 배포

## 기술 스택

- SwiftUI
- SwiftData
- ARKit + RealityKit
- Vision + Core ML
- Combine
- Accelerate

외부 SPM 의존성 없이 Apple 프레임워크 중심으로 구성합니다.

## 시스템 요구사항

- iOS Deployment Target: `26.0`
- Xcode: iOS 26 SDK를 포함한 버전
- 개발/검증 대상: iPad Pro 계열 LiDAR 지원 기기
- LiDAR 미지원 기기에서는 핵심 AR 측정 기능 제한

## 프로젝트 규모

- Swift 파일 수: `127` (`ClothIQ/ClothIQ` 기준)
- 앱 소스 라인 수: `39,343` (`ClothIQ/ClothIQ` 기준)
- 주요 모듈
  - `ClothIQ/ClothIQ/Features/Measurement`
  - `ClothIQ/ClothIQ/Features/ClothingLibrary`
  - `ClothIQ/ClothIQ/Features/ImageProcessing`
  - `ClothIQ/ClothIQ/Features/Settings`

## 빠른 실행

### Xcode

```bash
cd ClothIQ
open ClothIQ.xcodeproj
```

### CLI 빌드 검증

```bash
./scripts/validate_build.sh --quick
./scripts/qa_check.sh --changed
```

### CLI 디바이스 배포

```bash
cd scripts
cp ios_device_config.template ios_device_config.sh
# ios_device_config.sh에 프로젝트 경로, 번들 ID, 서명 설정 입력

./ios_device_tools.sh list-devices
./ios_device_tools.sh full-deploy
```

## ML 데이터 재개 명령

새 촬영/보정 데이터가 생긴 뒤 아래 명령으로 최신 상태를 다시 감사합니다.

```bash
bash scripts/pull_training_snapshot.sh \
  --device-id <device-id> \
  --output-dir tmp/latest-training-snapshot \
  --completion-audit \
  --collection-plan tmp/ml-training-collection-plan-current-audit.md \
  --capture-checklist tmp/ml-training-required-capture-checklist.md
```

감사가 통과한 타입은 타입별 학습으로 진행합니다.

```bash
bash scripts/ml_training_workflow.sh \
  --data-path tmp/latest-training-snapshot/merged \
  --per-type \
  --skip-export
```

## 문서

- 진행 상황: `ClothIQ/PROGRESS.md`
- 권한 설정: `ClothIQ/ClothIQ/App/README_PERMISSIONS.md`
- 스크립트 사용법: `scripts/README.md`
- 이슈 기록: `ISSUE/`
- 상세 운영 가이드: `DOC/` (로컬 문서 디렉터리)

## 개인정보/보안 원칙

- 문서에 개인 이름, 이메일, 전화번호, 기기 UDID, 개발팀 ID, 프로비저닝 식별자를 기록하지 않습니다.
- 문서에는 사용자 홈을 포함한 절대 경로 대신 상대 경로 또는 `<repo>`, `<device-id>`, `<bundle-id>` placeholder를 사용합니다.
- `tmp/`, `logs/`, `.codex/`, `scripts/__pycache__/`, 기기 스냅샷, 학습 라벨 원본, 모델 산출물은 커밋하지 않습니다.

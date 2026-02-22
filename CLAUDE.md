# ClothIQ - 프로젝트 운영 문서

> 최종 업데이트: 2026-02-22

## 프로젝트 개요

ClothIQ는 LiDAR 기반 AR 측정과 사진 기반 후처리 측정을 결합한 iOS 앱입니다.  
의류 이미지를 촬영하고, 측정값/앵커/메타데이터를 SwiftData + 파일 시스템에 저장해 라이브러리에서 관리합니다.

## 현재 구현 상태

| 구분 | 상태 |
| --- | --- |
| Phase 1 (MVP) | ✅ 완료 |
| Phase 2 (고도화) | 🚧 진행 중 |
| AR 카메라 실측 플로우 | ✅ 동작 |
| 촬영 후 미리보기 + 저장/취소 | ✅ 동작 |
| iPad 실기기 배포/실행 | ✅ 확인 |

### 최신 빌드 기준

- 빌드: `xcodebuild` 성공 (`2026-02-22`)
- iOS Deployment Target: `26.0`
- 앱 소스 Swift 파일 수: `99` (`ClothIQ/ClothIQ` 기준)
- 앱 소스 라인 수: `34,319` (`ClothIQ/ClothIQ` 기준)

## 카메라 측정 화면 구현 현황

### 1) 카메라 내 선택 플로우

- 의류 타입 선택: `InCameraMeasurementPicker`
- 측정 항목 선택: 의류 타입별 필수 항목 칩 UI
- 재선택 시 동작:
  - 기존 진행 포인트 초기화
  - 동일 항목 재측정 가능
  - 완료된 동일 항목은 덮어쓰기 저장

관련 파일:
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/Components/InCameraMeasurementPicker.swift`
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/Views/MeasurementView.swift`
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/ViewModels/MeasurementViewModel+MeasurementManagement.swift`

### 2) 앵커 2점 측정 + 적용/취소

- 탭 기반 2점 앵커 측정
- 다중 샘플링(15프레임) 후 포인트 확정
- `적용` 버튼으로 현재 측정 항목 확정
- `다시 찍기` 버튼으로 현재 포인트 취소/초기화
- 최근 수정:
  - `pendingMeasurement` 기반 적용 로직 보강
  - 거리 계산이 이미 끝난 상태에서 포인트 배열이 비어도 저장 가능
  - 불필요한 "30cm 미만" 차단 팝업 경로 제거 (현재 플로우에서는 비정상 값만 차단)

관련 파일:
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/ViewModels/MeasurementViewModel+MeasurementManagement.swift`
- `ClothIQ/ClothIQ/Features/Measurement/Data/Services/MeasurementCalculator.swift`

### 3) 촬영 후 미리보기

- 촬영 버튼 누르면 미리보기 전체화면 표시
- 미리보기에 다음 내용 표시:
  - 촬영 이미지
  - 앵커/측정선
  - 측정 항목명 + 값 라벨
  - 저장/취소 버튼
- 최근 수정:
  - 미리보기 표시 타이밍 레이스 완화 (로딩 placeholder 추가)
  - 이미지 오버레이 높이 고정으로 비정상 레이아웃 방지

관련 파일:
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/Views/MeasurementView.swift`
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/Views/MeasurementPreviewView.swift`

### 4) 저장 데이터 일관성

- AR 측정 저장 시 좌표를 정규화하여 `MeasurementModel`에 저장
- `measurementMethodRaw`(`ar`/`photo`) 저장
- 최근 수정:
  - AR 캡처 값은 상세 화면에서 photo 교정을 재적용하지 않도록 처리
  - 카메라 화면 측정값과 저장 후 표시값 불일치 문제 완화

관련 파일:
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/ViewModels/MeasurementViewModel+DataPersistence.swift`
- `ClothIQ/ClothIQ/Core/Data/SwiftData/Models/MeasurementModel.swift`
- `ClothIQ/ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/PhotoMeasurementViewModel.swift`
- `ClothIQ/ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/BatchAutoMeasurementViewModel.swift`

## 핵심 컴포넌트

### 측정(AR)

- `ARMeasurementService`: LiDAR 기반 포인트 추출/샘플링
- `DepthDataProcessor`: depth map 처리
- `MeasurementCalculator`: 거리 계산/검증
- `MultiSamplingProcessor`: 다중 샘플링
- `KalmanFilter`, `MeasurementFilter`: 노이즈 안정화

### 이미지 처리

- `ObjectCaptureService`: 캡처/크롭/배경 제거 파이프라인
- `ForegroundSegmentationService`: 전경 마스크 생성
- `PhotoLibraryService`: Photos 저장
- `ImageFileManager`: 로컬 이미지 파일 저장

### 모델/저장

- `ClothingItemModel`, `MeasurementModel`, `TagModel` (SwiftData)
- 메타데이터:
  - 이미지 원본/처리 크기
  - crop rect
  - 카메라 intrinsics/resolution
  - 측정 포인트 좌표(정규화)

### UI/워크플로우

- `MeasurementView` + `ARViewContainer`
- `MeasurementOverlayView`, `MeasurementPointView`
- `MeasurementPreviewView`
- `ClothingLibraryView`, `ClothingDetailView`, `PhotoMeasurementView`

## 개발/실행

### Xcode

```bash
cd ClothIQ
open ClothIQ.xcodeproj
```

### CLI 디바이스 배포

```bash
cd scripts
./ios_device_tools.sh list-devices
./ios_device_tools.sh full-deploy
```

## 알려진 이슈/주의사항

- 빌드는 성공하지만 `VisionMLService.swift`에서 `Sendable` 관련 경고가 남아 있습니다.
- AR 측정 정확도는 조명/거리/의류 평탄도에 영향을 받습니다.
- LiDAR 미지원 기기에서는 핵심 기능 사용이 제한됩니다.

## 문서 인덱스

- 진행 상황: `ClothIQ/PROGRESS.md`
- 디바이스 배포/로그: `DOC/IOS_DEVICE_GUIDE.md`
- 라이브 디버그/임계값: `DOC/LIVE_DEBUG_ANALYSIS.md`
- Core ML 통합: `DOC/CORE_ML_INTEGRATION_GUIDE.md`
- ML 데이터 수집: `DOC/ML_DATA_COLLECTION_GUIDE.md`
- ML 빠른 참조: `DOC/ML_DATA_COLLECTION_QUICK_REFERENCE.md`
- ML 테스트: `DOC/ML_DATA_COLLECTION_TEST_GUIDE.md`

## 개인정보/보안 문서 작성 원칙

- 개인 이름, 이메일, 전화번호, 기기 UDID, 팀 식별자, 프로비저닝 식별자 기록 금지
- 절대 경로(예: 사용자 홈 디렉터리 포함 경로) 기록 금지
- 문서에는 상대 경로와 일반화된 예시만 사용

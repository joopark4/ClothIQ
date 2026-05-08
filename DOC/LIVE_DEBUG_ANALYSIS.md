# 라이브 디버깅 시스템 현황 (현재 구현 기준)

최종 업데이트: 2026-05-08

이 문서는 ClothIQ의 라이브 디버깅 관련 컴포넌트 구현 상태와 실제 연결 상태를 코드 기준으로 정리합니다.

## 1) 구현 상태 요약

### 구현 완료된 컴포넌트

- `ClothIQ/Features/Measurement/Presentation/Components/LiveDebugOverlay.swift`
- `ClothIQ/Features/Measurement/Presentation/Components/DebugMetricsPanel.swift`
- `ClothIQ/Features/Measurement/Presentation/Components/DebugSettingsPanel.swift`
- `ClothIQ/Features/Measurement/Presentation/Components/DepthVisualizationView.swift`
- `ClothIQ/Core/Utilities/MeasurementSettings.swift`

### 현재 연결 상태

- 디버그 컴포넌트 자체는 구현되어 있음
- `MeasurementView`에 `LiveDebugOverlay`를 기본 마운트하는 코드 경로는 현재 없음
- 즉, 런타임 조정 엔진(`MeasurementSettings`)은 동작하지만, 디버그 오버레이 UI는 필요 시 연결해서 사용해야 함

## 2) 런타임 조정 가능한 파라미터

`MeasurementSettings.shared` 기준:

- `minConfidence`
- `lowConfidenceWarning`
- `veryLowConfidence`
- `minDepthCoverage`
- `midDepthCoverage`
- `optimalMinDistance`
- `optimalMaxDistance`
- `planeSampleCount`
- `planeErrorTolerance`
- `useCalibration`
- `isDebugMode`

특징:

- `@Published` 기반으로 실시간 반영
- UserDefaults 저장/복원 지원
- 교정 프로파일(`CalibrationProfile`) 적용 가능

## 3) 디버그 패널이 표시하는 메트릭

`DebugMetricsPanel` 기준:

- 환경 점수 (`environmentScore`)
- 깊이 품질 (`depthQuality`)
- 카메라 거리 (`cameraDistance`)
- 감지 포인트 수 (`detectedPointsCount`)
- 현재 측정값 (`currentMeasurement`)

색상 규칙:

- 점수 계열: Green/Yellow/Red
- 거리 계열: `MeasurementSettings`의 최적 거리 범위 기준

## 4) 현 구조에서의 활용 방법

### A. 코드 레벨 임시 활성화

`MeasurementView`의 카메라 ZStack에 아래 오버레이를 추가해 사용할 수 있습니다.

```swift
LiveDebugOverlay(
    environmentScore: viewModel.environmentScore,
    depthQuality: 0.0,
    cameraDistance: nil,
    detectedPointsCount: viewModel.measurementPoints.count,
    currentMeasurement: nil
)
```

그리고 디버그 모드를 켭니다.

```swift
MeasurementSettings.shared.isDebugMode = true
```

### B. 설정값 튜닝

`DebugSettingsPanel`을 통해 슬라이더로 임계값을 조정하고, 측정 품질 변화(오탐/미탐/성공률)를 비교합니다.

## 5) 현재 운영 관점의 체크포인트

1. 기본 측정 정확도는 교정 프로파일 영향이 큼
2. 디버그 UI가 비활성일 때도 `MeasurementSettings` 값은 측정 로직에 영향
3. 릴리즈 빌드에서 디버그 노출 정책 분리 필요
4. 사진 측정/ML 키포인트 위치 문제는 별도 좌표 변환 및 타입별 keypoint 매핑 수정으로 대응됨
5. 타입별 ML 모델 학습/배포는 촬영 데이터 기준 충족 전까지 보류

## 6) 권장 개선 항목

1. `MeasurementView`에 디버그 오버레이 조건부 마운트 옵션 추가
2. 디버그 모드 ON/OFF를 설정 화면에서 직접 제어
3. `depthQuality`, `cameraDistance` 계산 소스 연결(현재는 호출부에서 값 주입 필요)
4. 임계값 프리셋(실내/야외/근거리) 저장 기능 추가
5. ML 모델 배포 후 모델 결과와 휴리스틱 fallback 결과를 같은 디버그 패널에서 비교

## 7) 관련 파일

- `ClothIQ/Core/Utilities/MeasurementSettings.swift`
- `ClothIQ/Features/Measurement/Presentation/Components/LiveDebugOverlay.swift`
- `ClothIQ/Features/Measurement/Presentation/Components/DebugMetricsPanel.swift`
- `ClothIQ/Features/Measurement/Presentation/Components/DebugSettingsPanel.swift`
- `ClothIQ/Features/Measurement/Presentation/Views/MeasurementView.swift`

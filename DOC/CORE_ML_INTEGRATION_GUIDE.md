# Core ML / Vision 통합 가이드 (현재 구현 기준)

최종 업데이트: 2026-05-08

이 문서는 ClothIQ의 ML/컴퓨터비전 통합 상태를 "현재 코드 기준"으로 정리합니다.

## 1) 구현 범위 요약

현재 앱은 키포인트 감지에서 다음 3개 경로를 하이브리드로 사용합니다.

1. Vision 기반 윤곽/Saliency
2. 휴리스틱 키포인트 감지 (`ClothingKeypointDetector`)
3. 타입별 Core ML 모델 로더(`VisionMLModelLoader`)와 `VisionMLService`를 통한 병합

핵심 포인트:

- ML 모드 ON/OFF 토글 지원 (`PhotoMeasurementViewModel.isMLModeEnabled`)
- ML 모드에서 자동 감지 결과를 학습 데이터로 수집
- 사용자 수동 보정 데이터도 별도 플래그로 수집
- CreateML 내보내기 제공
- 컴파일된 타입별 `.mlmodelc`가 있으면 로드하고, 없으면 Vision/휴리스틱/타입별 prior로 fallback
- 현재 타입별 학습/배포는 실제 촬영 데이터 부족으로 보류

## 2) 핵심 파일 맵

### ML/비전 서비스

- `ClothIQ/Features/Measurement/Data/Services/VisionMLService.swift`
- `ClothIQ/Features/Measurement/Data/Services/VisionMLModelLoader.swift`
- `ClothIQ/Features/Measurement/Data/Services/ClothingKeypointDetector.swift`
- `ClothIQ/Features/Measurement/Data/Services/AutoMeasurementService.swift`
- `ClothIQ/Features/Measurement/Data/Services/MLTrainingDataCollector.swift`
- `ClothIQ/Features/Measurement/Data/Services/MLTrainingModels.swift`
- `ClothIQ/Features/Measurement/Data/Services/ClothingTypeMeasurementPrior.swift`
- `ClothIQ/Features/Measurement/Data/Services/ClothingTypeLearnedMeasurementPrior.swift`

### 사진 측정 연동

- `ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/PhotoMeasurementViewModel.swift`
- `ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/PhotoMeasurementViewModel+Keypoint.swift`
- `ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/PhotoMeasurementViewModel+Actions.swift`
- `ClothIQ/Features/ClothingLibrary/Presentation/Views/PhotoMeasurementView.swift`

### 설정/통계/내보내기 UI

- `ClothIQ/Features/Settings/Presentation/Views/MLTrainingSettingsView.swift`
- `ClothIQ/Features/Settings/Presentation/Views/MLTrainingStatisticsView.swift`
- `ClothIQ/Features/Settings/Presentation/Views/MLTrainingExportView.swift`
- `ClothIQ/Features/Settings/Presentation/Views/DataCollectionDebugView.swift` (DEBUG)

## 3) 실제 동작 플로우

### A. Photo 측정에서 키포인트 감지

`PhotoMeasurementViewModel.detectKeypoints()` 기준:

- ML 모드 OFF
  - 윤곽선 감지
  - 특징점 추출
  - 휴리스틱 키포인트 생성

- ML 모드 ON
  - `VisionMLService.detectKeypointsHybrid(...)`
  - 컴파일된 타입별 모델이 있으면 모델 결과 사용
  - 모델이 없으면 Vision/Saliency + 휴리스틱 + 타입별 prior 병합
  - 평균 신뢰도(`mlConfidence`) 업데이트

### B. 학습 데이터 수집

ML 모드에서 자동 감지 시 `collectTrainingData()`가 호출됩니다.

저장 내용(`TrainingSample`):

- 이미지(Base64)
- 의류 타입
- 키포인트 라벨(정규화 좌표)
- 사용자 수정 여부
- 신뢰도
- 수집 시각

저장 경로:

- `Documents/MLTrainingData/labels.json`
- `Documents/MLTrainingData/images/*` (내보내기 시 생성)

촬영 원본과 앱 측정 정보는 별도 위치에 저장됩니다.

- 원본 촬영 이미지: `Documents/clothing_images/*.jpg`
- 깊이맵: `Documents/depth_maps/*.png`
- SwiftData 측정 저장소: `Library/Application Support/default.store`
- 학습 모델 배포 위치: `Documents/MLTrainingData/Models/*.mlmodelc`

### C. 타입별 모델 로딩

`VisionMLModelLoader`는 아래 순서로 컴파일된 모델을 찾습니다.

1. 앱 번들 루트
2. 앱 번들 `CoreML`
3. 앱 번들 `Resources/CoreML`
4. `Documents/MLTrainingData/Models`

모델 이름은 타입별로 `ClothingKeypointDetector_<type>.mlmodelc` 형식을 사용합니다. 컴파일되지 않은 `.mlmodel` 원본만 있으면 iOS 런타임 로딩 대상이 아니므로, Mac에서 `.mlmodelc`로 컴파일한 뒤 배포해야 합니다.

## 4) 현재 구현의 제한/주의사항

- 타입별 `.mlmodelc` 로딩 경로는 구현되어 있으나, 현재 실제 촬영 데이터가 부족해 배포된 타입별 모델은 없습니다.
- CreateML/Python 학습 자동화는 별도 워크플로우(`scripts/train_*`, `scripts/ml_training_workflow.sh`)를 사용합니다.
- 수집 데이터 품질은 사용자 보정 비율에 크게 의존합니다.
- 기준 미달 데이터로 모델을 만들면 측정 품질이 저하될 수 있으므로, 타입별 학습 게이트가 최소 고유 원본/보정 원본 기준을 확인합니다.

## 5) 운영 체크리스트

### 앱에서 확인

1. `설정 > ML 학습 설정`
2. `학습 데이터 수집` ON
3. 필요 시 `사용자 수정 데이터만 수집` ON
4. 사진 측정 화면에서 ML 모드 ON
5. 키포인트 자동 감지/수정 후 저장

### 터미널에서 확인

```bash
bash scripts/pull_training_snapshot.sh \
  --device-id <device-id> \
  --output-dir tmp/latest-training-snapshot \
  --completion-audit \
  --collection-plan tmp/ml-training-collection-plan-current-audit.md \
  --capture-checklist tmp/ml-training-required-capture-checklist.md

bash scripts/ml_training_workflow.sh \
  --data-path tmp/latest-training-snapshot/merged \
  --completion-audit \
  --capture-checklist tmp/ml-training-required-capture-checklist.md \
  --skip-export
```

## 6) 데이터 품질 권장 기준

- 타입별 고유 실제 원본 촬영: 20장 이상
- 타입별 고유 사용자 보정 원본 촬영: 3장 이상
- 평균 신뢰도: 0.70+
- 16개 의류 타입 편중 방지

## 7) 트러블슈팅

### 감지 결과가 비어있음

확인 순서:

1. 해당 아이템에 depth map 존재 여부
2. 의류 타입(`item.type`)이 유효한 enum인지
3. ML 모드 OFF로 휴리스틱 결과 먼저 검증

### 데이터가 수집되지 않음

1. `MLTrainingSettingsView`의 `학습 데이터 수집` 토글 확인
2. `사용자 수정 데이터만 수집` ON 상태인지 확인
3. Xcode 콘솔에서 `[MLTraining]` 로그 확인

### 내보내기 실패

- 최소 샘플 수 부족(기본 100)인지 확인
- 앱 Documents 접근 권한/용량 상태 확인

## 8) 다음 개선 우선순위(문서 기준)

1. 실제 촬영/수동 보정 데이터 수집
2. 완료 감사 통과 타입부터 타입별 `.mlmodelc` 생성
3. 모델 배포 후 Vision/휴리스틱 fallback 대비 정확도 회귀 측정

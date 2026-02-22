# Core ML / Vision 통합 가이드 (현재 구현 기준)

최종 업데이트: 2026-02-22

이 문서는 ClothIQ의 ML/컴퓨터비전 통합 상태를 "현재 코드 기준"으로 정리합니다.

## 1) 구현 범위 요약

현재 앱은 키포인트 감지에서 다음 3개 경로를 하이브리드로 사용합니다.

1. Vision 기반 윤곽/Saliency
2. 휴리스틱 키포인트 감지 (`ClothingKeypointDetector`)
3. ML 서비스 파이프라인 (`VisionMLService`)를 통한 병합

핵심 포인트:

- ML 모드 ON/OFF 토글 지원 (`PhotoMeasurementViewModel.isMLModeEnabled`)
- ML 모드에서 자동 감지 결과를 학습 데이터로 수집
- 사용자 수동 보정 데이터도 별도 플래그로 수집
- CreateML 내보내기 제공

## 2) 핵심 파일 맵

### ML/비전 서비스

- `ClothIQ/Features/Measurement/Data/Services/VisionMLService.swift`
- `ClothIQ/Features/Measurement/Data/Services/ClothingKeypointDetector.swift`
- `ClothIQ/Features/Measurement/Data/Services/AutoMeasurementService.swift`
- `ClothIQ/Features/Measurement/Data/Services/MLTrainingDataCollector.swift`

### 사진 측정 연동

- `ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/PhotoMeasurementViewModel.swift`
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
  - ML + Saliency + 휴리스틱 병합
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
- `Documents/MLTrainingData/images/*`

## 4) 현재 구현의 제한/주의사항

- `VisionMLService.loadCustomModel()`은 현재 `nil` 반환
  - 즉, 커스텀 `.mlmodel` 직접 추론보다 Vision/휴리스틱 하이브리드가 중심입니다.
- CreateML 내보내기는 구현되어 있으나, 실제 모델 학습 자동화는 별도 워크플로우(`scripts/train_*`)를 사용해야 합니다.
- 수집 데이터 품질은 사용자 보정 비율에 크게 의존합니다.

## 5) 운영 체크리스트

### 앱에서 확인

1. `설정 > ML 학습 설정`
2. `학습 데이터 수집` ON
3. 필요 시 `사용자 수정 데이터만 수집` ON
4. 사진 측정 화면에서 ML 모드 ON
5. 키포인트 자동 감지/수정 후 저장

### 터미널에서 확인

```bash
cd scripts
./test_data_collection.sh check
./test_data_collection.sh validate
./test_data_collection.sh report
```

## 6) 데이터 품질 권장 기준

- 총 샘플: 100개 이상(최소), 1,000개 이상(권장)
- 사용자 수정 샘플 비율: 20%+
- 평균 신뢰도: 0.70+
- 의류 타입 편중 방지(반팔/긴팔/하의/치마 분산)

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

1. 커스텀 Core ML 모델 로드 경로 활성화
2. 하이브리드 병합 가중치/정책 설정화
3. 학습 파이프라인 자동 검증 리포트 고도화

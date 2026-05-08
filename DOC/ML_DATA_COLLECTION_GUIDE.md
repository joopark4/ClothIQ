# ML 학습 데이터 수집 가이드 (현재 구현 기준)

최종 업데이트: 2026-05-08

이 문서는 ClothIQ 앱에서 키포인트 학습 데이터를 수집/검증/내보내기 하는 실무 절차를 설명합니다.

## 1) 수집 기능 위치

앱 경로:

- `설정 > ML 학습 설정`

화면 파일:

- `ClothIQ/Features/Settings/Presentation/Views/MLTrainingSettingsView.swift`
- `ClothIQ/Features/Settings/Presentation/Views/MLTrainingStatisticsView.swift`
- `ClothIQ/Features/Settings/Presentation/Views/MLTrainingExportView.swift`

저장 서비스:

- `ClothIQ/Features/Measurement/Data/Services/MLTrainingDataCollector.swift`

## 2) 동작 원리

`PhotoMeasurementViewModel` 기준:

1. ML 모드 ON에서 키포인트 자동 감지 수행
2. 자동 감지 결과를 학습 샘플로 수집
3. 사용자가 앵커를 수정하면 `isUserCorrected` 샘플로 추가 수집

샘플 저장 필드:

- 이미지(Base64)
- 의류 타입
- 키포인트 배열(정규화 좌표)
- 사용자 수정 여부
- 신뢰도
- 타임스탬프

## 3) 수집 전 체크

- `설정 > ML 학습 설정`에서
  - `학습 데이터 수집` ON
  - 필요 시 `사용자 수정 데이터만 수집` ON
- 사진 측정 화면에서 ML 모드 활성화
- 이미지/의류 타입/키포인트 감지가 정상 동작하는지 확인

## 4) 권장 수집 방식

### 기본 수집

1. 의류 촬영/저장
2. `사진 측정` 진입
3. ML 모드 ON
4. 자동 키포인트 감지
5. 항목 저장

### 고품질 수집

1. 기본 수집 진행
2. 오차가 큰 포인트를 수동 수정
3. 수정 후 저장
4. `isUserCorrected` 비율 증가 확인

## 5) 데이터 저장 위치

앱 안에서 촬영/보정하면 사용자가 직접 파일을 고를 필요 없이 앱 컨테이너에 자동 저장됩니다.

### 앱 컨테이너 기준 경로

- 원본 촬영 이미지: `Documents/clothing_images/*.jpg`
- 깊이맵: `Documents/depth_maps/*.png`
- 의류/측정 SwiftData 저장소: `Library/Application Support/default.store`
- ML 학습용 라벨: `Documents/MLTrainingData/labels.json`
- ML 학습 내보내기 이미지: `Documents/MLTrainingData/images/`
- CreateML/Python 내보내기: `Documents/MLTrainingData/createml_data.json`
- 배포된 학습 모델: `Documents/MLTrainingData/Models/*.mlmodelc`

### 실제 학습에 필요한 핵심 파일

`Documents/MLTrainingData/labels.json`이 1차 학습 데이터입니다. 각 샘플은 이미지를 Base64 `imageData`로 포함하므로, 앱에서 수집된 원본 학습 데이터는 `labels.json`만으로도 감사와 병합이 가능합니다.

`Documents/MLTrainingData/images/`는 `exportForCreateML()` 또는 외부 내보내기 과정에서 생성되는 보조 이미지 디렉토리입니다. 앱에서 촬영만 했다고 항상 이미지 파일이 따로 쌓이는 구조가 아닙니다.

## 6) 현재 학습 완료 기준

타입별 모델 학습/배포 완료로 보려면 아래 조건을 모두 만족해야 합니다.

- `ClothingType.allCases` 전체 타입에 대해 고유 실제 원본 촬영 20장 이상
- 각 타입별 고유 사용자 보정 원본 촬영 3장 이상
- 타입별 필수 키포인트 coverage 충족
- `ClothingKeypointDetector_<type>.mlmodelc` 컴파일 및 배포 완료

증강 샘플과 같은 촬영 이미지의 중복 라벨 레코드는 실제 원본 촬영 수로 계산하지 않습니다.

### 현재 보류 상태

현재는 타입별 실제 촬영/수동 보정 데이터가 기준에 부족하므로 학습/배포를 보류합니다.

- 최신 감사 기준 총 라벨: 17개
- 고유 실제 촬영 원본: 16장
- 고유 사용자 보정 원본: 1장
- 타입별 학습 기준 충족 타입: 없음

기준 미달 상태에서 `.mlmodelc`를 생성하면 측정 품질이 나빠질 수 있으므로, `--per-type` 학습은 충분한 타입만 통과하도록 차단되어 있습니다.

## 7) 터미널 점검 명령

```bash
# 연결된 실제 기기에서 전체 스냅샷 추출, SwiftData 복구, 병합, 감사
bash scripts/pull_training_snapshot.sh \
  --device-id <device-id> \
  --output-dir tmp/latest-training-snapshot \
  --completion-audit \
  --collection-plan tmp/ml-training-collection-plan-current-audit.md \
  --capture-checklist tmp/ml-training-required-capture-checklist.md

# 완료 감사 및 수집 계획 생성
bash scripts/ml_training_workflow.sh \
  --data-path tmp/latest-training-snapshot/merged \
  --completion-audit \
  --collection-plan tmp/ml-training-collection-plan-current-audit.md \
  --capture-checklist tmp/ml-training-required-capture-checklist.md \
  --skip-export

# 기준을 충족한 타입별 모델 학습/컴파일/배포
bash scripts/ml_training_workflow.sh \
  --data-path tmp/latest-training-snapshot/merged \
  --per-type \
  --skip-export
```

## 8) 수동 데이터 입력 위치

앱 밖에서 별도 수집/정리한 데이터를 사용할 때는 repo 안에 다음 형태로 둡니다.

```text
tmp/manual-training-data/
└── labels.json
```

`labels.json`은 `TrainingSample` 배열이며 최소 필드는 다음과 같습니다.

```json
[
  {
    "id": "UUID",
    "imageData": "base64-encoded-jpeg",
    "clothingType": "short_sleeve",
    "keypoints": [
      {
        "identifier": "left_shoulder",
        "x": 0.25,
        "y": 0.75,
        "visibility": 1.0
      }
    ],
    "timestamp": "2026-05-04T00:00:00Z",
    "isUserCorrected": true,
    "confidence": 0.9
  }
]
```

좌표는 Vision 학습 좌표계 기준의 정규화 좌표입니다. `x`는 좌측 0, 우측 1이고 `y`는 하단 0, 상단 1입니다. 앱에서 직접 촬영/보정하면 이 변환을 앱이 처리하므로 수동 작성보다 앱 수집을 우선합니다.

## 9) 품질 기준 (운영 권장)

- 타입별 고유 원본 촬영: 20+
- 타입별 고유 사용자 보정 원본 촬영: 3+
- 평균 신뢰도: 0.70+
- 의류 타입 편중 최소화
- 한 이미지에는 한 벌만 촬영
- 의류 전체, 목선, 어깨, 소매, 허리, 밑단이 가려지지 않게 촬영

## 10) 내보내기

### 앱 내 내보내기

- `학습 데이터 내보내기`
- `CreateML 형식으로 내보내기`

### 프로그램적 내보내기

- `MLTrainingDataCollector.exportForCreateML()`
- `MLTrainingDataCollector.exportForCreateMLAsync()`

## 11) 자주 발생하는 문제

### 데이터가 안 쌓임

확인:

1. `학습 데이터 수집` ON 여부
2. `사용자 수정 데이터만 수집` ON 여부
3. ML 모드 ON 여부
4. 콘솔 `[MLTraining]` 로그 여부

### validate 실패

- `labels.json` 형식 오류
- 이미지 파일 유실/손상
- 샘플 필수 필드 누락

해결:

- `bash scripts/ml_training_workflow.sh --data-path <data-path> --completion-audit --skip-export` 결과의 항목별 오류부터 수정

### CreateML 내보내기 실패

- 최소 샘플 수 부족(기본 100)
- 저장 공간 부족
- Documents 접근 오류

## 12) 관련 코드

- `ClothIQ/Features/Measurement/Data/Services/MLTrainingDataCollector.swift`
- `ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/PhotoMeasurementViewModel.swift`
- `ClothIQ/Features/Settings/Presentation/Views/MLTrainingSettingsView.swift`
- `scripts/ml_training_workflow.sh`
- `scripts/audit_ml_training_completion.py`
- `scripts/merge_training_data.py`
- `scripts/pull_training_snapshot.sh`
- `scripts/extract_training_data_from_swiftdata.py`

# ML 업데이트 계획 (로컬 학습 기반)

## 1. 촬영 & 자동 측정 (앱 실행)
- AR 촬영 → `AutoMeasurementService` 가 윤곽선/Depth를 기반으로 측정 포인트와 값을 계산.
- `MeasurementViewModel` 이 결과를 SwiftData 에 저장하고 상세 화면에서 표시.

## 2. 사용자 보정 & 로그 기록
- 사진 측정 화면에서 사용자가 포인트를 드래그 후 저장.
- 디버그 빌드에서만 JSON 로그(`Documents/Corrections/corrections_YYYYMMDD.json`)에 자동 측정값과 최종값, 좌표, 메타데이터를 append.
  - 필수 필드: `timestamp`, `clothingType`, `measurementType`, `autoValue`, `finalValue`, 자동/최종 좌표, 신뢰도, 이미지/Depth 크기, `wasAutoAdjusted` 등.

## 3. 로그 추출 (개발자 단말 → Mac)
- Xcode > Devices and Simulators → “Download Container…”, 또는 Files/Finder 공유를 통해 `Corrections` 폴더 복사.
- 모든 JSON 로그를 `data/corrections_raw/` 폴더에 모은다.

## 4. 로컬 학습 (보정 프로파일 / ML)
- Mac에서 Python/Swift 스크립트를 실행해 데이터 정제 및 분석.
- 예시(평균 오차 기반 보정 프로파일):

```python
import json, glob, collections

totals = collections.defaultdict(list)
for path in glob.glob("data/corrections_raw/*.json"):
    with open(path) as fp:
        for entry in json.load(fp):
            key = (entry["clothingType"], entry["measurementType"])
            delta = entry["finalValue"] - entry["autoValue"]
            totals[key].append(delta)

profile = {
    f"{ct}|{mt}": sum(values) / len(values)
    for (ct, mt), values in totals.items()
    if len(values) >= 5  # 최소 샘플 기준
}

with open("Generated/MeasurementCorrectionProfile.json", "w") as out:
    json.dump(profile, out, indent=2)
```

- 고도화: scikit-learn + coremltools 로 회귀 모델을 학습해 `MeasurementPointCorrection.mlmodel` 생성.
  - 입력: 의류 타입, 규칙 기반 좌표, 윤곽선 특징 등.
  - 출력: Δx, Δy 보정 벡터 또는 보정된 최종 좌표.

## 5. 앱 통합
- 생성된 JSON/ML 모델을 Xcode 리소스에 포함.
- `AutoMeasurementService` 또는 `MeasurementCalculator` 단계에서 자동 측정 결과에 보정 로직을 추가:
  - `value += correction` (프로파일)
  - 또는 ML 모델 추론 결과를 좌표/값에 적용.
- 프로파일/모델 버전을 관리(예: `"schemaVersion": 1`)해 추후 교체 시 호환성 확인.

## 6. QA 및 배포
- 개발/QA 빌드에서 새 보정이 정상 적용되는지 검증.
- 최종 `.json`/`.mlmodel`을 프로젝트에 포함한 뒤 App Store 빌드에 배포.
- 필요 시 빌드 스크립트(`prepare_corrections.py`)로 자동 생성/복사를 체계화.

## 7. 반복 개선
- 배포 후에도 디버그 로그로 새로운 보정 데이터를 수집.
- 일정 주기마다 2~4단계를 반복해 보정 프로파일/모델을 갱신 → 새 버전에 반영.
- Outlier 제거, 최소 샘플 수 조건, 개인정보 제외 등 안전 장치 유지.

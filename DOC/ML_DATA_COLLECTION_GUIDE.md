# ML 학습 데이터 수집 가이드 (현재 구현 기준)

최종 업데이트: 2026-02-22

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

- 앱 Documents: `MLTrainingData`
- 주요 파일
  - `labels.json`
  - `images/`
  - `createml_data.json` (CreateML 내보내기 시)

## 6) 터미널 점검 명령

```bash
cd scripts

# 수집 현황 요약
./test_data_collection.sh check

# 실시간 모니터링
./test_data_collection.sh monitor

# 무결성 검증
./test_data_collection.sh validate

# 리포트 생성
./test_data_collection.sh report
```

## 7) 품질 기준 (운영 권장)

- 총 샘플: 100+ (최소), 1000+ (권장)
- 사용자 수정 샘플 비율: 20%+
- 평균 신뢰도: 0.70+
- 의류 타입 편중 최소화

## 8) 내보내기

### 앱 내 내보내기

- `학습 데이터 내보내기`
- `CreateML 형식으로 내보내기`

### 프로그램적 내보내기

- `MLTrainingDataCollector.exportForCreateML()`
- `MLTrainingDataCollector.exportForCreateMLAsync()`

## 9) 자주 발생하는 문제

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

- `./test_data_collection.sh validate` 결과의 항목별 오류부터 수정

### CreateML 내보내기 실패

- 최소 샘플 수 부족(기본 100)
- 저장 공간 부족
- Documents 접근 오류

## 10) 관련 코드

- `ClothIQ/Features/Measurement/Data/Services/MLTrainingDataCollector.swift`
- `ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/PhotoMeasurementViewModel.swift`
- `ClothIQ/Features/Settings/Presentation/Views/MLTrainingSettingsView.swift`
- `scripts/test_data_collection.sh`

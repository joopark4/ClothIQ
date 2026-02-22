# ML 데이터 수집 테스트 가이드 (현재 구현 기준)

최종 업데이트: 2026-02-22

이 문서는 수집 기능이 실제로 동작하는지 검증하는 QA 시나리오를 정리합니다.

## 1) 테스트 범위

검증 대상:

- ML 모드 자동 감지 시 샘플 자동 저장
- 사용자 수동 수정 시 `isUserCorrected` 샘플 저장
- 통계 화면 값 반영
- CreateML 내보내기 동작
- 스크립트 기반 무결성 검증

## 2) 사전 준비

### 앱 측

1. 앱 실행
2. `설정 > ML 학습 설정`
3. `학습 데이터 수집` ON

### CLI 측

```bash
cd scripts
chmod +x test_data_collection.sh
./test_data_collection.sh check
```

## 3) 테스트 시나리오

### TC-01 자동 수집

절차:

1. 의류 항목 선택
2. `사진 측정` 진입
3. ML 모드 ON
4. 키포인트 자동 감지 완료

기대 결과:

- 콘솔에 `[MLTraining]` 수집 로그 출력
- `check`에서 총 샘플 수 증가

### TC-02 사용자 수정 수집

절차:

1. TC-01 수행
2. 앵커를 드래그로 수정
3. 저장

기대 결과:

- `userCorrectedSamples` 증가
- 최근 샘플에 사용자 수정 플래그 반영

### TC-03 통계 화면 반영

절차:

1. `설정 > ML 학습 설정 > 상세 통계 보기`
2. 총 샘플/수정 샘플/평균 신뢰도 확인

기대 결과:

- `MLTrainingDataCollector` 집계와 화면 수치 일치

### TC-04 CreateML 내보내기

절차:

1. `CreateML 형식으로 내보내기` 실행
2. 결과 메시지 확인
3. 파일 생성 여부 확인

기대 결과:

- 성공 메시지 출력
- `MLTrainingData/createml_data.json` 생성

### TC-05 무결성 검증

```bash
./test_data_collection.sh validate
```

기대 결과:

- JSON 파싱 성공
- 필수 필드 존재
- 이미지 유효성 통과

## 4) 판정 기준

필수 통과:

- TC-01, TC-02, TC-05

권장 통과:

- TC-03, TC-04

## 5) 실패 시 진단 순서

1. 수집 토글 상태 확인
2. ML 모드 상태 확인
3. `check` 출력에서 `labels.json` 존재 확인
4. `validate` 오류 항목 확인
5. 앱 재실행 후 재시도

## 6) 회귀 테스트 권장 시점

- `PhotoMeasurementViewModel` 수정 후
- `MLTrainingDataCollector` 수정 후
- 설정 화면(`MLTrainingSettingsView`) 수정 후
- 내보내기 포맷 변경 후

## 7) 관련 파일

- `ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/PhotoMeasurementViewModel.swift`
- `ClothIQ/Features/Measurement/Data/Services/MLTrainingDataCollector.swift`
- `ClothIQ/Features/Settings/Presentation/Views/MLTrainingSettingsView.swift`
- `scripts/test_data_collection.sh`

# ML 데이터 수집 빠른 참조

최종 업데이트: 2026-02-22

## 1) 가장 빠른 시작

1. 앱 실행
2. `설정 > ML 학습 설정`
3. `학습 데이터 수집` ON
4. 사진 측정 화면에서 ML 모드 ON
5. 자동 감지 + 필요 시 수동 수정

## 2) 1분 점검 명령

```bash
cd scripts
./test_data_collection.sh check
./test_data_collection.sh validate
```

## 3) 수집 체크리스트

- [ ] 의류 타입 분산(상의/하의)
- [ ] 흔들림/노출 불량 이미지 제외
- [ ] 사용자 수정 샘플 일정 비율 확보
- [ ] 하루 1회 `validate` 실행

## 4) 권장 목표

- 최소: 100 샘플
- 권장: 1000 샘플
- 사용자 수정 비율: 20%+
- 평균 신뢰도: 70%+

## 5) 저장 위치

- `Documents/MLTrainingData/labels.json`
- `Documents/MLTrainingData/images/`

## 6) 트러블슈팅 퀵 가이드

### 샘플 증가가 안 보임

- 수집 토글 ON 확인
- `사용자 수정 데이터만` 옵션 ON 여부 확인
- ML 모드 ON 확인

### 검증 실패

```bash
./test_data_collection.sh validate
```

출력된 실패 항목부터 순차 수정.

### 내보내기 실패

- 샘플 수 부족 여부 확인
- 저장 공간 확인
- 앱 재실행 후 다시 시도

## 7) 관련 문서

- 상세 가이드: `DOC/ML_DATA_COLLECTION_GUIDE.md`
- 테스트 시나리오: `DOC/ML_DATA_COLLECTION_TEST_GUIDE.md`
- Core ML 통합: `DOC/CORE_ML_INTEGRATION_GUIDE.md`

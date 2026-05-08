# ML 데이터 수집 빠른 참조

최종 업데이트: 2026-05-08

## 1) 가장 빠른 시작

1. 앱 실행
2. `설정 > ML 학습 설정`
3. `학습 데이터 수집` ON
4. 사진 측정 화면에서 ML 모드 ON
5. 자동 감지 + 필요 시 수동 수정

## 2) 1분 점검 명령

```bash
bash scripts/pull_training_snapshot.sh \
  --device-id <device-id> \
  --output-dir tmp/latest-training-snapshot \
  --completion-audit \
  --collection-plan tmp/ml-training-collection-plan-current-audit.md \
  --capture-checklist tmp/ml-training-required-capture-checklist.md
```

## 3) 수집 체크리스트

- [ ] 의류 타입 분산(상의/하의)
- [ ] 흔들림/노출 불량 이미지 제외
- [ ] 사용자 수정 샘플 일정 비율 확보
- [ ] 하루 1회 `validate` 실행

## 4) 권장 목표

- 타입별 고유 원본 촬영: 20장 이상
- 타입별 수동 보정 원본: 3장 이상
- 평균 신뢰도: 70% 이상
- 16개 의류 타입 전체 수집

현재는 실제 촬영/수동 보정 데이터가 부족해 타입별 ML 학습/배포를 보류합니다. 마지막 감사 기준 총 라벨은 17개, 고유 실제 원본은 16장, 고유 사용자 보정 원본은 1장입니다.

## 5) 저장 위치

- `Documents/clothing_images/*.jpg`
- `Documents/depth_maps/*.png`
- `Library/Application Support/default.store`
- `Documents/MLTrainingData/labels.json`
- `Documents/MLTrainingData/images/` (내보내기 시)
- `Documents/MLTrainingData/Models/*.mlmodelc` (학습 모델 배포 후)

## 6) 트러블슈팅 퀵 가이드

### 샘플 증가가 안 보임

- 수집 토글 ON 확인
- `사용자 수정 데이터만` 옵션 ON 여부 확인
- ML 모드 ON 확인

### 검증 실패

```bash
bash scripts/ml_training_workflow.sh \
  --data-path tmp/latest-training-snapshot/merged \
  --completion-audit \
  --capture-checklist tmp/ml-training-required-capture-checklist.md \
  --skip-export
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

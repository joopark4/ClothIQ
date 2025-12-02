# ML 데이터 수집 테스트 가이드

**작성일**: 2025년 11월 10일
**버전**: 1.0.0

---

## 📋 목차

1. [개요](#개요)
2. [테스트 준비](#테스트-준비)
3. [테스트 시나리오](#테스트-시나리오)
4. [데이터 확인 방법](#데이터-확인-방법)
5. [문제 해결](#문제-해결)
6. [체크리스트](#체크리스트)

---

## 개요

이 문서는 ClothIQ 앱의 ML 학습 데이터 수집 기능을 테스트하는 방법을 설명합니다.

### 테스트 목표

- ✅ 사진 측정 시 데이터가 자동으로 수집되는지 확인
- ✅ 사용자 수정 데이터가 올바르게 표시되는지 확인
- ✅ 수집된 데이터의 무결성 검증
- ✅ CreateML 형식으로 내보내기 기능 테스트

---

## 테스트 준비

### 1. 앱 빌드 및 실행

```bash
# 시뮬레이터에서 앱 실행
xcodebuild -project ClothIQ.xcodeproj -scheme ClothIQ \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.1' \
    build
```

### 2. 초기 설정

1. **시뮬레이터에서 앱 실행**
2. **설정 화면 열기**: 의류 라이브러리 → 설정(⚙️)
3. **ML 학습 설정 진입**
4. **"학습 데이터 수집" 토글 ON**

### 3. 테스트 도구 준비

```bash
# 테스트 스크립트 실행 권한
chmod +x scripts/test_data_collection.sh

# 초기 데이터 확인
./scripts/test_data_collection.sh check
```

---

## 테스트 시나리오

### 시나리오 1: 자동 데이터 수집 테스트

#### 단계

1. **의류 촬영 및 측정**
   ```
   의류 라이브러리 → + 버튼 → 카메라 촬영 → 의류 타입 선택
   ```

2. **사진 측정 화면 진입**
   ```
   저장된 의류 선택 → 사진 측정 버튼
   ```

3. **자동 키포인트 감지 대기**
   - ML 모드가 활성화되어 있으면 자동으로 데이터 수집

4. **데이터 확인**
   ```bash
   ./scripts/test_data_collection.sh check
   ```

#### 예상 결과

```
✅ 데이터 경로: .../Documents/MLTrainingData
📄 labels.json
   - 샘플 수: 1개
   - 파일 크기: 2.1K

최근 수집된 샘플:
   1. [  ] short_sleeve
      - 시간: 2025-11-10T21:30:00
      - 키포인트: 10개
      - 신뢰도: 75.0%
```

### 시나리오 2: 사용자 수정 데이터 수집

#### 단계

1. **자동 감지된 포인트 수정**
   - 사진 측정 화면에서 측정 포인트 드래그
   - 위치 조정 후 측정 완료

2. **데이터 확인**
   ```bash
   ./scripts/test_data_collection.sh monitor
   ```

#### 예상 결과

실시간 모니터링에서 `사용자 수정: 1개` 증가 확인

### 시나리오 3: 대량 데이터 수집

#### 단계

1. **여러 의류 촬영** (최소 5개)
   - 반팔 티셔츠 2개
   - 긴팔 티셔츠 1개
   - 반바지 1개
   - 긴바지 1개

2. **각 의류에 대해 측정 수행**

3. **통계 확인**
   ```
   설정 → ML 학습 설정 → 상세 통계 보기
   ```

4. **리포트 생성**
   ```bash
   ./scripts/test_data_collection.sh report
   ```

### 시나리오 4: CreateML 내보내기 테스트

#### 단계

1. **설정에서 내보내기**
   ```
   설정 → ML 학습 설정 → CreateML 형식으로 내보내기
   ```

2. **파일 확인**
   ```bash
   # 내보낸 파일 확인
   ls -la ~/Library/Developer/CoreSimulator/*/Documents/MLTrainingData/
   ```

3. **데이터 검증**
   ```bash
   ./scripts/test_data_collection.sh validate
   ```

---

## 데이터 확인 방법

### 1. 앱 내 확인

#### 통계 화면
```
설정 → ML 학습 설정 → 상세 통계 보기
```

- 총 샘플 수
- 의류 타입별 분포 차트
- 측정 항목별 분포
- 데이터 품질 지표

#### 디버그 모드 (DEBUG 빌드만)
```
설정 → ML 학습 설정 → 디버그 모드
```

- 실시간 모니터링
- 파일 시스템 확인
- 테스트 데이터 생성

### 2. 터미널 확인

#### 기본 확인
```bash
./scripts/test_data_collection.sh check
```

#### 실시간 모니터링
```bash
./scripts/test_data_collection.sh monitor
# Ctrl+C로 종료
```

#### 무결성 검증
```bash
./scripts/test_data_collection.sh validate
```

#### 상세 리포트
```bash
./scripts/test_data_collection.sh report
# ml_data_report_YYYYMMDD_HHMMSS.md 파일 생성
```

### 3. 로그 확인

#### Xcode 콘솔
```
📊 [MLTraining] 학습 데이터 수집 시작
✅ [MLTraining] 학습 데이터 수집 완료
  - 키포인트 수: 10
  - 사용자 수정: false
💾 [MLTraining] 샘플 저장 완료 (총 5개)
```

#### 시뮬레이터 로그
```bash
# 시뮬레이터 로그 모니터링
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.clothiq.app"'
```

---

## 문제 해결

### 문제 1: 데이터가 수집되지 않음

#### 확인 사항
1. **ML 학습 설정에서 "학습 데이터 수집" 토글이 ON인지 확인**
2. **"사용자 수정 데이터만" 옵션이 ON인 경우, 수동으로 포인트 수정 필요**

#### 해결 방법
```swift
// PhotoMeasurementViewModel에서 확인
if isMLModeEnabled {
    collectTrainingData()  // 이 부분이 호출되는지 확인
}
```

### 문제 2: 경로를 찾을 수 없음

#### 시뮬레이터 데이터 경로 직접 찾기
```bash
# 가장 최근 시뮬레이터 찾기
find ~/Library/Developer/CoreSimulator/Devices \
    -name "MLTrainingData" -type d 2>/dev/null
```

### 문제 3: JSON 파싱 오류

#### 데이터 복구
```bash
# 백업 생성
cp ~/path/to/MLTrainingData/labels.json ~/labels_backup.json

# JSON 유효성 검사
python3 -m json.tool ~/path/to/MLTrainingData/labels.json
```

### 문제 4: 이미지 누락

#### 확인 명령
```bash
# 이미지 파일 확인
ls -la ~/path/to/MLTrainingData/images/*.jpg

# 손상된 이미지 찾기
for img in ~/path/to/MLTrainingData/images/*.jpg; do
    if ! file "$img" | grep -q "JPEG"; then
        echo "손상됨: $img"
    fi
done
```

---

## 체크리스트

### 기본 기능 테스트

- [ ] 앱 설정에서 ML 학습 데이터 수집 활성화
- [ ] 의류 촬영 및 저장
- [ ] 사진 측정 시 자동 키포인트 감지
- [ ] 데이터 자동 수집 확인
- [ ] 통계 화면에서 수집된 데이터 확인

### 고급 기능 테스트

- [ ] 사용자가 수정한 포인트 데이터 별도 표시
- [ ] 5개 이상 샘플 수집
- [ ] CreateML 형식으로 내보내기
- [ ] 데이터 무결성 검증 통과
- [ ] 디버그 모드에서 실시간 모니터링

### 성능 테스트

- [ ] 100개 샘플 수집 시 앱 성능 확인
- [ ] 1000개 샘플 수집 시 파일 크기 확인
- [ ] 내보내기 속도 측정

### 오류 처리 테스트

- [ ] 저장 공간 부족 시 동작
- [ ] 잘못된 이미지 데이터 처리
- [ ] 네트워크 없이 동작 확인

---

## 다음 단계

데이터 수집 테스트가 완료되면:

1. **모델 학습 실행**
   ```bash
   ./scripts/ml_training_workflow.sh
   ```

2. **학습된 모델 통합**
   - `.mlmodel` 파일을 Xcode 프로젝트에 추가
   - VisionMLService에서 새 모델 로드

3. **성능 비교**
   - 기본 휴리스틱 vs ML 모델 정확도 비교
   - 처리 속도 측정

---

## 참고 자료

- [ML 학습 워크플로우 스크립트](../scripts/ml_training_workflow.sh)
- [Core ML 통합 가이드](./CORE_ML_INTEGRATION_GUIDE.md)
- [프로젝트 진행 상황](../PROGRESS.md)

---

**문서 버전**: 1.0.0
**마지막 업데이트**: 2025년 11월 10일
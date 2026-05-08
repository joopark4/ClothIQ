# ClothIQ 개발 진행 상황

> 최종 업데이트: 2026-05-08

## 현재 PR 상태 (2026-05-08)

- 브랜치: `RD`
- 대상 브랜치: `main`
- PR: `#5 Improve garment measurement ML workflow`
- PR 체크: 현재 보고된 체크 없음
- 워킹트리 기준: `RD`와 `origin/RD` 동기화 확인

## 현재 보류 항목 (2026-05-04)

### 타입별 ML 학습/배포 보류

실제 촬영 데이터 수집에는 시간이 걸리므로, 타입별 ML 학습/배포는 촬영 데이터가 기준을 충족할 때까지 보류합니다.

현재 기준:
- `ClothingType.allCases` 전체 타입별 고유 실제 원본 촬영 20장 이상
- 각 타입별 고유 사용자 보정 원본 촬영 3장 이상
- 필수 키포인트 coverage 충족
- `ClothingKeypointDetector_<type>.mlmodelc` 컴파일 및 배포

새로 촬영한 뒤에는 기기 스냅샷 추출, 완료 감사, 타입별 학습, `.mlmodelc` 배포 순서로 이어서 진행합니다.

## 전체 진행률

| Phase | 상태 | 비고 |
| --- | --- | --- |
| Phase 1 (핵심 MVP) | ✅ 완료 | 기본 측정/저장/라이브러리/배경 제거 |
| Phase 2 (고도화) | 🚧 진행 중 | 측정 안정화 + 디버깅/교정 + 자동화 확장 |
| Phase 3 (타입별 ML 정밀화) | ⏸️ 보류 | 실제 촬영/사용자 보정 데이터 부족 |

## 최근 완료 작업 (2026-05-04 ~ 2026-05-08)

### 1) 타입별 측정/키포인트 안정화 ✅

반영 내용:
- `ClothingType.allCases` 전체 타입 기준 측정 라인 coverage 검사 추가
- 선택된 측정 항목과 대응되는 라인이 없을 때 임의 첫 라인을 쓰는 fallback 제거
- 의류 타입별 키포인트/측정 라인 로직 분리
- 하의/스커트/복합 의류의 허리, 밑단, 엉덩이, 가랑이 계열 키포인트 보강

주요 파일:
- `ClothIQ/ClothIQ/Features/Measurement/Data/Services/ClothingKeypointDetector+MeasurementLines.swift`
- `ClothIQ/ClothIQ/Features/Measurement/Data/Services/ClothingKeypointDetector+BottomClothing.swift`
- `ClothIQ/ClothIQ/Features/Measurement/Data/Services/ClothingKeypointDetector+TopClothing.swift`
- `ClothIQ/ClothIQ/Features/Measurement/Data/Services/BottomMeasurementDetector.swift`
- `ClothIQ/ClothIQTests/MLFeatureTests.swift`

### 2) 사진 측정 ML ON 앵커 위치 오류 수정 ✅

문제:
- 사진 측정 진입 후 ML을 ON 하면 앵커, 라인, 키포인트가 의도와 다른 위치에 표시되는 케이스가 있었음

수정:
- ML 키포인트를 현재 이미지 표시 좌표계에 맞게 변환
- 사용자 보정 앵커를 타입별 training keypoint로 변환
- 측정선과 오버레이가 선택된 측정 타입을 기준으로 동작하도록 정리

주요 파일:
- `ClothIQ/ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/PhotoMeasurementViewModel+Keypoint.swift`
- `ClothIQ/ClothIQ/Features/Measurement/Data/Services/VisionMLService.swift`
- `ClothIQ/ClothIQ/Features/ClothingLibrary/Presentation/Components/KeypointOverlayView.swift`

### 3) 배경 제거 후처리 보강 ✅

문제:
- 촬영 이미지의 배경 제거 후 일부 배경이 얇게 남는 케이스가 있었음

수정:
- 전경 마스크 후처리와 가장자리 정리 보강
- 배경 제거 회귀 테스트 추가

주요 파일:
- `ClothIQ/ClothIQ/Features/ImageProcessing/Data/Services/ObjectCaptureService+BackgroundRemoval.swift`
- `ClothIQ/ClothIQTests/BackgroundRemovalTests.swift`

### 4) ML 학습/감사 워크플로우 정리 ✅

반영 내용:
- 기기 컨테이너에서 `Documents/MLTrainingData`, `Documents`, `Library/Application Support`를 함께 추출
- SwiftData `default.store`에서 복구 가능한 라벨을 생성
- 여러 기기/출처 라벨 병합
- 타입별 실제 원본/사용자 보정 원본/키포인트/model artifact 기준 완료 감사
- 촬영 부족분 체크리스트 생성
- 기준 미달 데이터로 타입별 모델을 만들지 않도록 학습 게이트 적용

주요 파일:
- `scripts/pull_training_snapshot.sh`
- `scripts/ml_training_workflow.sh`
- `scripts/audit_ml_training_completion.py`
- `scripts/merge_training_data.py`
- `scripts/extract_training_data_from_swiftdata.py`
- `scripts/train_keypoint_model.py`

### 5) ML 학습 보류와 재개 절차 문서화 ✅

현재 상태:
- 실제 촬영 데이터가 충분하지 않아 타입별 ML 학습/배포는 보류
- 새 촬영 데이터가 들어오면 스냅샷 추출, 완료 감사, 타입별 학습, `.mlmodelc` 배포 순서로 재개

현재 부족 요약:
- 총 라벨: 17개
- 고유 실제 촬영 원본: 16장
- 고유 사용자 보정 원본: 1장
- 학습 기준 충족 타입: 없음

## 이전 완료 작업 (2026-02-22)

### 1) 카메라 측정 플로우 안정화 ✅

요구사항 반영 결과:
- 카메라 화면에서 의류 타입 선택 가능
- 카메라 화면에서 측정 항목 선택 가능
- 선택 측정 항목 기준 앵커 측정 가능
- `적용`(확정) / `다시 찍기`(취소) 동작 가능
- 다른 측정 항목 선택 시 새 측정으로 갱신 및 덮어쓰기 가능

주요 구현 지점:
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/Components/InCameraMeasurementPicker.swift`
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/Views/MeasurementView.swift`
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/ViewModels/MeasurementViewModel+MeasurementManagement.swift`

### 2) "두 지점 필요" 오탐으로 저장 실패하던 문제 수정 ✅

문제:
- 길이 계산이 화면에 보였는데도 `적용` 시 "저장할 두 개의 측정 포인트가 필요합니다." 오류 발생

수정:
- `pendingMeasurement` 캐시를 활용해 계산 완료된 항목은 안전하게 적용되도록 분기 보강
- 현재 포인트 배열과 캐시 상태를 함께 판단하도록 `canApplyCurrentMeasurement` 및 `applyCurrentMeasurement()` 경로 정리

효과:
- 계산 완료 후 적용 실패 재현 케이스 해소

### 3) 불필요한 "30cm 이상" 차단 팝업 경로 제거 ✅

문제:
- 촬영/적용 단계에서 "측정값이 모자릅니다. 30cm 이상" 계열 팝업이 사용자 흐름을 차단

수정:
- 카메라 실측 확정 흐름에서 최소 길이 임계값 기반 차단을 제거
- 값 자체가 비정상(NaN/무한/0 이하)일 때만 에러 처리

효과:
- 정상 측정값이 팝업 때문에 막히는 현상 완화

### 4) 촬영 미리보기 오버레이 표시 개선 ✅

문제:
- 미리보기/완료 화면에서 촬영 이미지 위 앵커/측정값이 보이지 않음
- 미리보기에 촬영 이미지가 비정상적으로 표시되거나 비어 보이는 케이스 존재

수정:
- `MeasurementPreviewView` 오버레이 좌표 변환 로직 정리
- 미리보기 이미지 영역 높이/레이아웃 안정화
- `MeasurementView` fullScreenCover에서 데이터 준비 중 로딩 placeholder 추가

효과:
- 촬영 이미지 + 앵커 + 측정값 라벨 가시성 개선
- 미리보기 전환 타이밍 이슈 완화

주요 파일:
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/Views/MeasurementPreviewView.swift`
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/Views/MeasurementView.swift`

### 5) 카메라 측정값 vs 저장 후 표시값 불일치 완화 ✅

문제:
- 카메라에서 본 값과 상세/미리보기에서 본 값이 달라지는 케이스 존재

수정:
- AR 저장 시 측정 좌표를 정규화하여 `MeasurementModel`에 저장
- `measurementMethodRaw`(`ar`/`photo`) 저장 일관화
- AR 캡처에서 저장된 값은 상세 화면에서 photo 교정을 재적용하지 않도록 `calibratedValue()` 조건 보강

효과:
- 저장 전/후 값 일관성 개선

주요 파일:
- `ClothIQ/ClothIQ/Features/Measurement/Presentation/ViewModels/MeasurementViewModel+DataPersistence.swift`
- `ClothIQ/ClothIQ/Core/Data/SwiftData/Models/MeasurementModel.swift`
- `ClothIQ/ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/PhotoMeasurementViewModel.swift`
- `ClothIQ/ClothIQ/Features/ClothingLibrary/Presentation/ViewModels/BatchAutoMeasurementViewModel.swift`

## 기존 완료 항목 (요약)

### Phase 1 완료 사항

- LiDAR 기반 AR 측정 기본 플로우
- 의류 라이브러리/상세 화면
- SwiftData 저장 구조
- 촬영 이미지 저장 + Photos 연동
- 배경 제거 파이프라인
- iPhone/iPad 적응형 UI

### Phase 2 진행 사항

- 라이브 디버깅 오버레이/설정 패널
- 교정 프로파일/보정 계수 워크플로우
- AR/Photo 측정 방식 분리
- 배치 자동 측정
- 카메라 측정 UX/저장 안정화(현재 라운드)

## 빌드/배포 상태

- `./scripts/validate_build.sh --quick`: ✅ 성공, 새 경고 없음 (2026-05-04 검증)
- `./scripts/qa_check.sh --changed`: ✅ FAIL 0, WARN 48 (2026-05-04 검증)
- iPad 실기기 설치/실행: ✅ 확인
- iPhone 설치: ✅ 확인, 기기 잠금 상태에서는 launch 제한 가능
- PR 체크: 현재 보고된 체크 없음

## 프로젝트 통계 (현재 코드 기준)

- 플랫폼 타깃: iOS `26.0`
- 앱 소스 Swift 파일 수: `127` (`ClothIQ/ClothIQ` 기준)
- 앱 소스 라인 수: `39,343`

## 다음 작업

1. 실제 촬영 데이터 수집
   - 16개 의류 타입별 고유 실제 원본 20장 이상
   - 타입별 고유 사용자 보정 원본 3장 이상
2. 새 촬영 후 `scripts/pull_training_snapshot.sh`로 스냅샷 추출
3. 완료 감사 통과 확인
4. 타입별 `.mlmodelc` 학습/컴파일/배포
5. PR 리뷰 대응 및 `main` 병합

## 개인정보 제거 원칙 적용 상태

- 문서 내 개인 식별자/절대 경로/앱 식별자 직접 표기를 제거했습니다.
- 문서에는 상대 경로 및 일반화된 기술 정보만 유지합니다.

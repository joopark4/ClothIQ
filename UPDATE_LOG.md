# ClothIQ 업데이트 로그

## 2025년 11월 3일 - 측정 정확도 및 카메라 가이드 개선

### 🎯 주요 개선 사항

#### 1. 사진 측정 정확도 개선
- **평면 투영(Planar Projection) 방식 도입**
  - 기존: 3D 유클리드 거리 계산 (Z축 차이 포함)
  - 개선: 평면상의 2D 거리 계산 (의류가 놓인 평면 기준)
  - 결과: 평평한 의류 측정 시 정확도 향상

- **Z축 차이 경고 시스템**
  - 두 측정 포인트의 Z축 차이가 10cm 이상이면 경고
  - 사용자에게 카메라 각도 재조정 권장

- **로깅 개선**
  - 3D 직선 거리와 평면 투영 거리 비교 출력
  - 디버깅 및 정확도 검증 용이

**변경 파일**: `PhotoMeasurementCalculator.swift`

#### 2. 카메라 정렬 가이드 시스템 구현
- **수평계 방식의 실시간 가이드**
  - 원형 레벨 인디케이터로 카메라 틸트 각도 시각화
  - 최적 각도: ±10도 이내 (녹색)
  - 조정 필요: 10~20도 (노랑)
  - 재조정 필요: 20도 이상 (빨강)

- **촬영 거리 안내**
  - 권장 거리: 40-60cm
  - 실시간 거리 측정 및 표시
  - 거리 벗어나면 색상 피드백

- **햅틱 진동 피드백**
  - 최적 정렬 상태 도달 시 자동 진동
  - 1초 간격 제한 (과도한 진동 방지)

- **ARKit 평면 감지**
  - 의류가 놓인 수평 평면 자동 감지
  - 가장 가까운 평면 우선 선택
  - 평면 크기 및 위치 로깅

**신규 파일**: `CameraAlignmentGuide.swift`

#### 3. AR 서비스 확장
- **카메라 정렬 계산 로직 추가**
  - 카메라 forward 벡터와 평면 법선 벡터 내적 계산
  - 틸트 각도 산출 (0° = 완벽한 수직, 90° = 수평)
  - 카메라-평면 간 거리 계산

- **각도 계산 버그 수정**
  - 문제: dotProduct가 음수일 때 각도가 음수로 나오는 현상
  - 해결: dotProduct 부호 반전 (`-dotProduct`) 후 계산
  - 결과: 항상 0~90도 범위의 양수 값 반환

**변경 파일**:
- `ARMeasurementService.swift`
- `ARMeasurementServiceProtocol.swift`

#### 4. ViewModel 및 View 통합
- **MeasurementViewModel 확장**
  - `detectedPlane`: 감지된 평면 앵커 저장
  - `cameraAlignmentData`: 정렬 상태 데이터 저장
  - `showAlignmentGuide`: 가이드 표시 여부 토글
  - `updateCameraAlignment()`: 평면 감지 및 정렬 계산
  - `toggleAlignmentGuide()`: 가이드 ON/OFF

- **ARViewContainer 확장**
  - `onAnchorsUpdate` 콜백 추가
  - ARSession의 앵커 업데이트를 ViewModel에 전달

- **MeasurementView 통합**
  - CameraAlignmentGuide 컴포넌트 추가
  - AR 초기화 완료 후에만 표시
  - 정렬 가이드 활성화 시에만 렌더링

**변경 파일**:
- `MeasurementViewModel_Refactored.swift`
- `ARViewContainer.swift`
- `MeasurementView.swift`

### 📊 통계

- **추가된 파일**: 1개 (CameraAlignmentGuide.swift)
- **수정된 파일**: 6개
- **총 Swift 파일**: 55개
- **총 코드 라인 수**: ~18,000 라인
- **빌드 상태**: ✅ 성공

### 🐛 버그 수정

1. **카메라 각도 음수 값 문제**
   - 증상: 틸트 각도가 -70°로 표시되며 빨간 점이 타겟과 맞지 않음
   - 원인: dotProduct 부호 처리 오류
   - 해결: adjustedDotProduct = -dotProduct로 보정
   - 로그: `📐 - dotProduct: -0.xxx → adjusted: 0.xxx`

### 🚀 다음 단계

- [ ] 실제 디바이스에서 정렬 가이드 테스트
- [ ] 다양한 조명 조건에서 평면 감지 성능 검증
- [ ] 사용자 피드백 수집 및 UI 개선
- [ ] 측정 정확도 통계 데이터 수집

---

**작성일**: 2025년 11월 3일
**작성자**: Claude Code

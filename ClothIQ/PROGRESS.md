# ClothIQ 개발 진행 상황

> 최종 업데이트: 2025-12-02

## 📊 전체 진행률

**Phase 1 (핵심 기능)**: ✅ 100% 완료 (18/18)

```
[████████████████████] 100%
```

**Phase 2 (고도화)**: 🚧 10% 진행 중

```
[██░░░░░░░░░░░░░░░░░░] 10%
```

---

## 🎯 최근 작업 (2025-12-02)

### 측정 방식 분리 시스템 구현 ✅

#### 배경:
- AR 실시간 측정과 사진 기반 측정이 동일한 교정 계수를 사용하고 있었음
- 실제로 두 방식은 서로 다른 원시 값을 생성함 (같은 40cm 허리둘레에 대해)
  - AR 측정: 47.19cm
  - Photo 측정: 50.16cm
- Photo용 교정 계수(0.7974)가 AR 측정에도 적용되어 과도한 보정 발생
- AR 측정 시 "측정값이 너무 작습니다" 에러 발생 (37.63cm < 50cm 최소값)

#### 구현 내용:

1. **MeasurementMethod enum 추가** (CalibrationFactor.swift)
   ```swift
   enum MeasurementMethod: String, Codable {
       case ar = "ar"           // AR 실시간 측정
       case photo = "photo"     // 사진 기반 측정
   }
   ```

2. **CalibrationFactor 모델 확장**
   - `measurementMethod` 필드 추가 (기본값: "photo" - 하위 호환성)
   - 의류 타입 + 측정 타입 + 측정 방식 조합으로 보정 계수 결정

3. **측정 방식별 교정 계수**
   | 측정 방식 | 실측값 | 원시 측정값 | 교정 계수 | 보정 후 |
   |----------|--------|-----------|----------|--------|
   | **AR** | 40cm | 47.19cm | **0.8476** | 40cm |
   | **Photo** | 40cm | 50.16cm | **0.7974** | 40cm |

4. **applyCorrectionFactor 함수 개선** (MeasurementSettings.swift)
   - `method` 파라미터 추가 (기본값: .photo)
   - 측정 방식에 맞는 교정 계수만 적용

5. **검증 범위 조정** (MeasurementCalculator.swift)
   - waistCircumference 최소값: 50.0 → **30.0** (반으로 접은 상태 고려)

#### 수정된 파일:
- `CalibrationFactor.swift` - MeasurementMethod enum 추가, measurementMethod 필드 추가
- `MeasurementSettings.swift` - AR 교정 계수 추가, applyCorrectionFactor 개선
- `MeasurementCalculator.swift` - 허리둘레 최소값 30cm로 변경
- `MeasurementViewModel+MeasurementManagement.swift` - method: .ar 적용
- `PhotoMeasurementCalculator.swift` - method: .photo 적용

#### 성과:
- ✅ AR 실시간 측정과 사진 측정이 각각 올바른 교정 계수 사용
- ✅ 동일한 실측값에 대해 두 방식 모두 정확한 결과 도출
- ✅ "측정값이 너무 작습니다" 에러 해결
- ✅ 빌드 성공

---

## 🎯 이전 작업 (2025-11-11)

### 다중 샘플링 시스템 버그 수정 ✅

#### 배경:
- Phase 1에서 다중 샘플링 기능(MultiSamplingProcessor, KalmanFilter 등)은 완전히 구현됨
- 하지만 사용자가 화면을 탭해도 샘플링이 시작되지 않는 문제 발견
- 측정 포인트 앵커가 잘못된 위치에 표시되는 문제 발견

#### 문제 1: 탭 핸들러 미연결
**증상**: 화면 탭 시 아무런 반응 없음, 샘플링 진행 표시가 나타나지 않음

**원인**:
1. `MeasurementView.swift:75` - `onTap` 파라미터가 `nil`로 설정됨
2. `ARViewContainer.swift:203-204` - 콜백 호출 코드가 주석처리됨

**해결**:
```swift
// MeasurementView.swift:75-77
onTap: { location, frame in
    viewModel.handleTap(at: location, frame: frame)
}

// ARViewContainer.swift:203-215
guard let currentFrame = arView.session.currentFrame else { return }
let scaledLocation = CGPoint(
    x: location.x * imageResolution.width / viewSize.width,
    y: location.y * imageResolution.height / viewSize.height
)
onTap?(scaledLocation, currentFrame)
```

#### 문제 2: 좌표계 불일치
**증상**: 측정 포인트 마커가 탭한 위치와 다른 곳에 표시됨

**원인**:
- ARView 화면 좌표 (예: 390×844) ≠ 카메라 imageResolution (예: 1920×1440)
- 입력/저장/출력 단계에서 좌표 변환이 일관되지 않음

**해결**:
- **입력 (ARViewContainer)**: 탭 좌표를 imageResolution 기준으로 스케일링
- **저장 (MeasurementPoint)**: imageResolution 좌표로 저장
- **출력 (MeasurementPointView)**: view 좌표로 변환하여 표시

```swift
// ARViewContainer.swift:210-215 (입력)
let scaledLocation = CGPoint(
    x: location.x * imageResolution.width / viewSize.width,
    y: location.y * imageResolution.height / viewSize.height
)

// MeasurementPointView.swift:48-53 (출력)
private var scaledPosition: CGPoint {
    CGPoint(
        x: point.screenPosition.x * viewSize.width / imageResolution.width,
        y: point.screenPosition.y * viewSize.height / imageResolution.height
    )
}
```

#### 성과:
- ✅ 화면 탭 시 다중 샘플링 정상 작동
- ✅ 15프레임 수집 후 칼만 필터 적용된 정제된 포인트 생성
- ✅ 측정 포인트 마커가 정확한 위치에 표시
- ✅ 연결선과 거리 계산이 올바르게 동작

#### 수정된 파일:
- `MeasurementView.swift` - onTap 콜백 연결, imageResolution 파라미터 추가
- `ARViewContainer.swift` - 좌표 스케일링 추가, 콜백 활성화
- `MeasurementPointView.swift` - 좌표 변환 로직 추가
- `MeasurementLineView.swift` - 라인 좌표 변환 추가
- `MeasurementOverlayView.swift` - GeometryReader로 동적 크기 감지
- `DepthDataProcessor.swift` - 중복 변환 제거

---

## 🎯 이전 작업 (2025-11-06)

### 사진 측정 교정 시스템 구현 ✅

#### 배경:
- 사진 기반 측정에서 평균 24.1%의 체계적 오차 발견
- 허리둘레: +25.4%, 총길이: -21.5%, 밑위: -25.4%의 일관된 오차 패턴
- 실용적 정확도 달성을 위한 교정 시스템 필요성 대두

#### 구현 내용:
1. **SwiftData 기반 교정 모델**
   - `CalibrationProfile`: 교정 프로파일 관리 (임계값 설정 포함)
   - `CalibrationFactor`: 의류/측정 타입별 보정 계수 저장
   - 1:N 관계로 프로파일당 여러 보정 계수 관리

2. **교정 데이터 수집 및 분석**
   - 교정 전: 10회 측정 데이터 통계 분석
   - 실측값 대비 보정 계수 자동 계산
     - 허리둘레: 0.7974 (40.0 / 50.16)
     - 총길이: 1.2732 (48.0 / 37.70)
     - 밑위: 1.3411 (30.0 / 22.37)

3. **자동 적용 시스템**
   - `MeasurementSettings.shared`: 싱글톤 패턴으로 중앙 집중식 관리
   - `PhotoMeasurementViewModel`: 측정값 계산 후 자동 보정
   - `AppContainerView`: 앱 시작 시 기본 프로파일 자동 로드

4. **교정 검증**
   - 교정 후: 10회 재측정으로 효과 검증
   - 상세 성능 분석 보고서 작성 (`Reference/calibration-analysis.md`)

#### 성과:
| 항목 | 교정 전 오차율 | 교정 후 오차율 | 개선율 |
|------|--------------|--------------|--------|
| 허리둘레 | 25.4% | 3.45% | **86.4%** |
| 총길이 | 21.5% | 1.29% | **94.0%** |
| 밑위 | 25.4% | 1.63% | **93.6%** |
| **평균** | **24.1%** | **2.12%** | **91.3%** |

- ✓ 모든 측정 항목에서 ±2cm 이내 정확도 달성
- ✓ 실용적 수준의 측정 정확도 확보
- ✓ 일관성 유지 또는 개선

#### 기술적 세부사항:
- **파일**: `MeasurementSettings.swift`, `CalibrationProfile.swift`, `CalibrationFactor.swift`
- **적용 방식**: 측정값 × 보정 계수 = 보정된 측정값
- **로깅**: 교정 적용 여부 및 전후 값 비교 출력
- **확장성**: 의류 타입별, 측정 타입별 개별 보정 가능

---

### 재측정 시 앵커 위치 버그 수정 ✅

#### 문제점:
- 측정 완료 후 동일 항목 재측정 시 앵커와 라인이 잘못된 위치에 표시
- 사용자 혼란 및 재측정 워크플로우 저해

#### 원인 분석:
- **좌표계 변환 불일치**
  - SwiftUI: 원점(0,0)이 좌상단
  - Vision Framework: 원점(0,0)이 좌하단
  - 저장 시: `y_vision = 1.0 - y_swiftui` 변환 적용 ✅
  - 로드 시: 역변환 누락 ❌

#### 해결 방법:
```swift
// PhotoMeasurementViewModel.loadAnchors() 수정
// 변경 전
let startAnchor = MeasurementAnchor(position: CGPoint(
    x: start.x * imageSize.width,
    y: start.y * imageSize.height  // 역변환 누락
))

// 변경 후
let startPosition = CGPoint(
    x: start.x * imageSize.width,
    y: (1.0 - start.y) * imageSize.height  // Y축 반전 복원
)
let startAnchor = MeasurementAnchor(position: startPosition)
```

#### 검증:
- ✓ 저장된 앵커 위치가 정확히 복원됨
- ✓ 재측정 시 기존 앵커와 라인이 올바른 위치에 표시
- ✓ 디버그 로깅으로 좌표 변환 과정 추적 가능

---

### 배경 제거 진단 시스템 구현 ✅

#### 배경:
- 사용자 보고: "촬영 후 이미지 배경삭제가 제대로 안되고 있어"
- 기존 4단계 폴백 시스템이 있었으나 실패 원인을 파악할 수 없음
- 어떤 배경 제거 방법이 사용되는지 알 수 없어 문제 진단 불가

#### 문제 분석:
1. **4단계 폴백 시스템 구조**
   - 1단계: Vision Framework (VNGenerateForegroundInstanceMaskRequest)
   - 2단계: Depth Map 기반 (LiDAR 깊이 데이터)
   - 3단계: Saliency Detection (주목도 기반)
   - 4단계: Center Crop 80% (최종 폴백)

2. **진단 불가능성**
   - Vision Framework 실패가 조용히 진행 (silent failure)
   - 어떤 폴백이 사용되는지 추적 불가
   - 마스크 품질(커버리지)을 확인할 방법 없음
   - 처리 시간 및 성능 모니터링 불가

#### 구현 내용:
1. **`removeBackground()` 함수 로깅 추가** (ObjectCaptureService+BackgroundRemoval.swift:37-126)
   ```swift
   print("🎨 [BackgroundRemoval] ===== 배경 제거 파이프라인 시작 =====")
   - 이미지 크기 및 Depth map 유무 확인
   - 각 단계별 시도 및 성공/실패 로그
   - 사용된 배경 제거 방법 출력
   - 마스크 커버리지 비율 (%)
   - 처리 시간 측정 (초)
   print("🎨 [BackgroundRemoval] ===== 배경 제거 파이프라인 종료 =====")
   ```

2. **`detectForegroundMask()` 함수 로깅 추가** (ObjectCaptureService+BackgroundRemoval.swift:156-241)
   ```swift
   print("   🔍 [Vision] VNGenerateForegroundInstanceMaskRequest 시작...")
   - Vision Framework 에러 메시지
   - 감지된 객체 수 (인스턴스 수)
   - 마스크 해상도 (width x height)
   - 마스크 커버리지 비율
   - 고해상도/저해상도 마스크 폴백 상태
   - Morphological 연산 (품질 개선) 진행 상황
   - 타임아웃 감지 (5초 제한)
   print("   ✅ [Vision] 마스크 품질 개선 완료")
   ```

3. **진단 정보 포함**
   - 📊 이미지 크기 및 Depth map 정보
   - 🔍 Vision Framework 처리 상태
   - ⚠️ 폴백 전환 경고
   - ✅ 성공 확인 메시지
   - ❌ 실패 원인 메시지
   - 📊 마스크 커버리지: XX.X% 형식
   - ⏱️ 처리 시간: X.XX초 형식

#### 성과:
- ✅ **사용자 확인**: "이전보다 개선되어 보여!!" (배경 제거 품질 향상)
- ✅ 실시간 진단 가능: 어떤 방법이 사용되는지 즉시 확인
- ✅ 실패 원인 추적: Vision Framework 에러 메시지 확인 가능
- ✅ 성능 모니터링: 처리 시간 및 마스크 품질 측정
- ✅ 향후 최적화 기반 마련: 로그 데이터로 개선 방향 결정 가능

#### 기술적 세부사항:
- **파일**: `ObjectCaptureService+BackgroundRemoval.swift`
- **로깅 레벨**: print 문 (실시간 콘솔 출력)
- **로깅 포맷**: 이모지 기반 시각적 구분 (🎨 🔍 ✅ ❌ ⚠️ 📊 ⏱️)
- **타임아웃**: Vision Framework 5초 제한 (DispatchSemaphore)
- **마스크 임계값**: 100 (Constants.maskThreshold)
- **빌드 상태**: ✅ 성공 (2025-11-06 12:06:59)
- **배포 상태**: ✅ 디바이스 설치 완료 (com.eunyeon.ClothIQ)

---

## 🎯 이전 작업 (2025-10-30)

### 의류 라이브러리 네비게이션 문제 해결 ✅

#### 문제점:
- 의류 아이템 리스트에서 탭 이벤트가 작동하지 않던 문제
- `NavigationLink(value:)` 패턴이 정상 동작하지 않음
- iPhone에서 상세 화면으로 이동 불가

#### 원인 분석:
- `ClothingItemModel`이 `Hashable` 프로토콜 미구현
- `NavigationLink(value:)` 사용 시 필요한 프로토콜 준수 부족
- SwiftData `@Model` 매크로가 `Identifiable`을 자동으로 제공하지 않음

#### 해결 방법:
1. **ClothingItemModel 수정**
   ```swift
   // 변경 전
   @Model
   final class ClothingItemModel {

   // 변경 후
   @Model
   final class ClothingItemModel: Hashable {
   ```

2. **ClothingItemCard 컴포넌트 분리**
   - `ClothingListView.swift`에 있던 `ClothingItemCard`를 별도 파일로 분리
   - `/Features/ClothingLibrary/Presentation/Views/ClothingItemCard.swift` 생성
   - 재사용성 향상 및 코드 구조 개선

#### 기술적 개선사항:
- ✓ `Hashable` 프로토콜 준수로 NavigationLink 정상 작동
- ✓ 컴포넌트 모듈화로 코드 재사용성 향상
- ✓ 중복 코드 제거
- ✓ NavigationStack + NavigationLink(value:) 패턴 정상화

#### 동작 확인:
| 디바이스 | 네비게이션 방식 | 상태 |
|---------|----------------|------|
| **iPhone** | NavigationLink(value:) + navigationDestination | ✅ 정상 작동 |
| **iPad** | NavigationSplitView + selection 바인딩 | ✅ 정상 작동 |

---

## ✅ Phase 1 완료 항목 요약

1. **프로젝트 구조 생성** ✅ (2025-10-22)
2. **LiDAR 지원 확인 기능** ✅ (2025-10-22)
3. **AR 측정 화면 UI** ✅ (2025-10-22)
4. **측정 핵심 로직 구현** ✅ (2025-10-23)
5. **이미지 캡처 및 저장** ✅ (2025-10-23)
6. **SwiftData 통합** ✅ (2025-10-24)
7. **의류 타입별 측정 항목 UI** ✅ (2025-10-24)
8. **자동 배경 제거 기능** ✅ (2025-10-24)
9. **이미지 처리 파이프라인 완성** ✅ (2025-10-25)
10. **코드 개선 및 정리** ✅ (2025-10-30)
11. **측정 데이터 SwiftData 저장 및 UI 완성** ✅ (2025-10-30 오후)
12. **iPhone/iPad 적응형 UI 구현** ✅ (2025-10-30 오후)
13. **간소화된 촬영 플로우** ✅ (2025-10-30)
14. **의류 라이브러리 네비게이션 문제 해결** ✅ (2025-10-30 저녁)
15. **사진 측정 교정 시스템 구현** ✅ (2025-11-06)
16. **재측정 시 앵커 위치 버그 수정** ✅ (2025-11-06)
17. **배경 제거 진단 시스템 구현** ✅ (2025-11-06)
18. **측정 방식 분리 시스템 (AR/Photo)** ✅ (2025-12-02)

---

## 📂 현재 프로젝트 구조

```
ClothIQ/
├── App/
│   ├── ClothIQApp.swift                  ✅ SwiftData 컨테이너
│   ├── ContentView.swift                  ✅ 메인 진입점
│   └── AppContainerView.swift             ✅ 권한/지원 체크
│
├── Core/
│   ├── Data/
│   │   ├── SwiftData/Models/
│   │   │   ├── ClothingItemModel.swift    ✅ Hashable 추가
│   │   │   ├── MeasurementModel.swift     ✅ 측정 데이터
│   │   │   └── TagModel.swift             ✅ 태그 모델
│   │   └── FileSystem/
│   │       └── ImageFileManager.swift     ✅ 이미지 관리
│   │
│   ├── UI/
│   │   ├── Components/                    ✅ 공통 UI
│   │   └── Modifiers/                     ✅ 적응형 모달
│   │
│   └── Utilities/
│       ├── DeviceCapability.swift         ✅ LiDAR 체크
│       ├── ARError.swift                  ✅ 에러 처리
│       └── ImageCaptureUtility.swift      ✅ 이미지 캡처
│
└── Features/
    ├── Measurement/
    │   ├── Data/Services/                 ✅ AR 측정 서비스
    │   ├── Presentation/Views/            ✅ 측정 UI
    │   └── Presentation/Components/       ✅ 측정 컴포넌트
    │
    ├── ClothingLibrary/
    │   └── Presentation/Views/
    │       ├── ClothingLibraryView.swift  ✅ 적응형 메인
    │       ├── ClothingListView.swift     ✅ 리스트
    │       ├── ClothingDetailView.swift   ✅ 상세보기
    │       └── ClothingItemCard.swift     ✅ 카드 컴포넌트
    │
    └── ImageProcessing/
        └── Data/Services/                  ✅ 배경 제거
```

---

## 📱 사용자 플로우

```
앱 실행 → 의류 라이브러리 → (+) 탭 → 카메라 화면 → 촬영 → 배경 자동 제거 → 의류 타입 선택 → 자동 저장 → 라이브러리 복귀
```

1. 앱 실행 → 의류 라이브러리
2. 플로팅 버튼(+) 탭 → **즉시 카메라 화면**
3. 촬영 버튼 탭 → 배경 자동 제거
4. **의류 타입 선택 모달** → 6가지 선택 옵션
5. **자동 저장** → SwiftData + Photos 앱
6. 라이브러리 복귀 → 썸네일과 함께 표시

---

## 🔧 기술 스택

- **SwiftUI** - 선언형 UI 프레임워크
- **SwiftData** - iOS 17+ 데이터 영속화
- **ARKit** - 증강 현실 프레임워크
- **RealityKit** - 3D 렌더링
- **Vision Framework** - 이미지 처리
- **Clean Architecture** - 레이어 분리
- **MVVM** - Presentation 패턴

---

## 📊 프로젝트 통계

**마지막 빌드**: ✅ 성공 (2025-12-02)
**플랫폼**: iOS 17.0+
**지원 디바이스**: LiDAR 탑재 기기 (iPhone 12 Pro 이상, iPad Pro 2020 이상)

**현재 파일 개수**: 93개 Swift 파일
**코드 라인 수**: ~31,900 라인 (주석 포함)
**빌드 경고**: 0개
**빌드 에러**: 0개

---

## 🚧 다음 작업 예정

### Phase 2: 고도화
- [ ] 의류 타입 자동 인식 (Core ML)
- [ ] 측정 포인트 자동 감지
- [ ] 태그 관리 기능
- [ ] 검색 및 필터링
- [ ] 통계 대시보드

---

## 📝 개발 메모

### 주요 기술적 성과
1. **LiDAR 정확도**: ±0.5~2cm 오차 범위 달성
2. **사진 측정 정확도**: 교정 시스템으로 91.3% 개선 (24.1% → 2.12% 오차율)
3. **배경 제거**: Vision Framework + Morphological 연산 최적화
4. **진단 시스템**: 실시간 로깅으로 배경 제거 파이프라인 추적 가능
5. **성능**: 30fps 제한, autoreleasepool 메모리 관리
6. **적응형 UI**: iPhone/iPad Size Class 기반 자동 전환
7. **네비게이션**: SwiftData 모델과 NavigationLink 통합 완성
8. **교정 시스템**: 의류/측정 타입별 자동 보정 계수 적용
9. **측정 방식 분리**: AR(0.8476) / Photo(0.7974) 별도 교정 계수 관리

### 품질 보증
- **교정 시스템 검증**: 사전/사후 각 10회 측정으로 효과 입증
- **상세 분석 문서**: `Reference/calibration-analysis.md` 작성
- **좌표계 버그 수정**: Y축 변환 불일치 해결로 재측정 워크플로우 안정화

---

**마지막 업데이트**: 2025-12-02
**작성자**: Claude + 개발팀

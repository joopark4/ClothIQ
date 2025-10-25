# ClothIQ 프로젝트 구현 정리

## 1. 앱 개요
- **ClothIQ**는 LiDAR 기반 의류 치수 측정 iOS 앱입니다.
- SwiftUI + RealityKit 조합으로 AR 카메라 화면을 제공하고, SwiftData로 측정 결과를 관리합니다.
- Clean Architecture를 바탕으로 Presentation / Domain / Data 계층이 분리되어 있습니다.

## 2. 아키텍처 및 프로젝트 구조
- `ClothIQApp.swift`에서 `ModelContainer`를 구성하여 SwiftData 모델(`ClothingItemModel`, `MeasurementModel`, `TagModel`)을 등록합니다.
- `AppContainerView.swift`가 기기 지원 여부와 권한 상태를 점검하여 `ContentView`, `UnsupportedDeviceView`, `CameraPermissionView`를 라우팅합니다.
- `Core`, `Features`, `App` 3개 상위 디렉터리로 나뉘며, `Features/Measurement`가 AR 측정 기능 전체를 담당합니다.
  - Domain: `MeasurementSession`, `MeasurementPoint`, `ARMeasurementServiceProtocol`
  - Data: `ARMeasurementService`, `DepthDataProcessor`, `MeasurementCalculator`, `ForegroundSegmentationService`
  - Presentation: `MeasurementView`, `MeasurementViewModel_Refactored`, UI Components

## 3. 핵심 기능 구현
- **기기·권한 체킹**: `DeviceCapability.checkMinimumRequirements()`로 LiDAR, iOS 17+, ARKit 지원 여부를 확인하고, 카메라 권한 상태를 검사합니다.
- **AR 세션 관리**: `ARViewContainer`가 `ARWorldTrackingConfiguration`을 설정해 Scene Depth/Smoothed Scene Depth를 활성화하고, 탭 제스처 및 프레임 업데이트를 SwiftUI로 전달합니다.
- **측정 파이프라인** (`MeasurementViewModel_Refactored`):
  1. 뷰 모델이 AR 세션 상태를 관리하고, 탭 이벤트를 `ARMeasurementService`에 위임해 `MeasurementPoint`를 생성합니다.
  2. `MeasurementCalculator`로 포인트 간 거리를 센티미터 단위로 변환하고, 측정 타입별 합리성 검증을 수행합니다.
  3. 측정 진행률(`MeasurementSession.completionProgress`)과 필수 항목 충족 여부를 계산해 UI에 반영합니다.
  4. 환경 점수(`environmentScore`)가 낮을 경우 맞춤형 가이드를 띄워 재측정을 유도합니다.
- **이미지 캡처 & 주석 처리**: `ARViewContainer`가 캡처 요청을 수신하면 `ImageCaptureUtility`로 화면을 캡처하고, 측정 포인트 오버레이를 합성한 뒤 `MeasurementSession`에 바이너리 데이터를 저장합니다.

## 4. Vision 기반 전경 분리
- `ForegroundSegmentationService`가 `VNGenerateForegroundInstanceMaskRequest`와 `VNClassifyImageRequest`를 사용해 의류 영역 마스크를 생성합니다.
- 마스크 품질 검증 후 `MeasurementGuideOverlay`에 감지 결과 메시지와 신뢰도를 전달하여 실시간 피드백을 제공합니다.
- 전경 마스크는 `MeasurementView`에서 깊이 시각화(`SimpleDepthOverlay`)에 활용되어 의류 위치를 강조합니다.

## 5. 데이터 영속화 및 UI 흐름
- `ContentView`가 SwiftData `@Query`로 의류 목록을 표시하며, 의류 타입 선택 시 `MeasurementView`로 이동합니다.
- `ClothingItemModel`·`MeasurementModel`·`TagModel`은 관계형 구조(1:N, N:M)를 활용해 측정값과 태그를 관리하고, 진행률·완료 여부를 계산하는 편의 프로퍼티를 제공합니다.
- `ImageFileManager`가 측정 이미지 파일을 Documents 하위 디렉터리에 저장하며, 뷰 모델의 `saveImageToFile()`에서 비동기로 호출할 수 있도록 설계되어 있습니다.

## 6. 권한 및 기기 요구 사항
- `App/README_PERMISSIONS.md`에 Info.plist에 추가해야 할 카메라·사진 라이브러리 권한 문자열과 `UIRequiredDeviceCapabilities` 항목이 정리되어 있습니다.
- 지원 디바이스 목록(`DeviceCapability.lidarSupportedIPhones/iPads`)을 통해 App Store 노출 범위를 제한할 수 있습니다.

## 7. 배경 제거 및 이미지 처리 (2025-10-24 업데이트)

### 7.1 Post-Capture Workflow
의류 촬영 후 배경 제거 프로세스가 다음과 같이 구현되었습니다:

1. **객체 촬영**: AR 카메라에서 원본 이미지 캡처 (Depth map 포함)
2. **1:1 정사각형 크롭**: 객체 중심으로 자동 크롭 (`detectAndCropObjectWithRect`)
3. **JPG 임시 저장**: 디스크에 임시 JPEG 파일 생성 (품질: 0.9)
4. **배경 제거 실행**: 임시 JPEG 파일에 대해 Vision Framework 기반 배경 제거
5. **최종 저장**: Photos 앨범 및 로컬 파일 시스템에 저장

**구현 위치:**
- `ObjectCaptureService.runPostCaptureWorkflow()` (ObjectCaptureService.swift:438)
- `MeasurementViewModel.handleCapturedImage()` (MeasurementViewModel_Refactored.swift:473)

### 7.2 배경 제거 알고리즘 개선

#### 문제점 및 해결 과정
**Phase 1: 객체가 배경과 함께 제거되는 문제**
- **원인**: Depth와 Vision 마스크 AND 연산으로 마스크 축소 (9.7% → 2.5%)
- **해결**:
  - Depth 결합 비활성화 (Vision 마스크 단독 사용)
  - Morphological 연산 강화 (Dilation: 10 → 6, Erosion: 8 → 5)
  - 임계값 조정 (128 → 100 → 50)

**Phase 2: 배경 일부가 남아있는 문제**
- **원인**: Morphological 확장이 과도하여 배경까지 전경으로 확장
- **해결**:
  - Morphological 연산 균형 조정 (Dilation: 6, Erosion: 5, 순 확장 1픽셀)
  - 임계값 재조정 (50 → 75)

**Phase 3: 마스크와 사물 불일치 문제**
- **원인**: Gaussian Blur + 낮은 Contrast로 마스크 왜곡 및 축소
- **해결**:
  - Gaussian Blur 제거
  - 강력한 이진화 적용 (Contrast: 1.5 → 10.0)
  - 임계값 최종 조정 (75 → 128)
  - 마스크 품질 검증 로직 추가

#### 최종 마스크 처리 파이프라인
```
Vision 마스크 생성 (VNGenerateForegroundInstanceMaskRequest)
  ↓
Dilation (radius: 6) - 구멍 메우기
  ↓
Erosion (radius: 5) - 노이즈 제거
  ↓
Strong Binarization (contrast: 10.0) - 0/255 이진화
  ↓
Quality Check - 전경 비율 검증 (5%-80% 범위)
  ↓
Pixel-by-Pixel 적용 (threshold: 128)
```

**구현 위치:**
- `ObjectCaptureService.refineMaskQuality()` (ObjectCaptureService.swift:766)
- `ObjectCaptureService.applyMaskPixelByPixel()` (ObjectCaptureService.swift:966)

### 7.3 카메라 포커스 기능
카메라 프리뷰 탭 시 거리 측정 대신 포커스 설정 기능으로 변경:

**기능:**
- 탭한 위치에 자동 포커스 설정 (`AVCaptureDevice`)
- 노출(Exposure) 자동 조절
- 노란색 원형 인디케이터로 시각적 피드백
- 페이드 인/아웃 애니메이션 (0.2초 → 0.5초 지연 → 0.3초)

**구현 위치:**
- `ARViewContainer.Coordinator.handleTap()` (ARViewContainer.swift:179)
- `ARViewContainer.Coordinator.setFocus()` (ARViewContainer.swift:197)
- `ARViewContainer.Coordinator.showFocusIndicator()` (ARViewContainer.swift:243)

### 7.4 기술적 개선 사항

#### Morphological 연산 최적화
- **Closing 연산**: Dilation → Erosion으로 마스크 내부 구멍 메우기
- **균형잡힌 파라미터**: 객체 보존과 배경 제거의 균형
- **이진화**: 중간 회색 값 제거로 명확한 경계 생성

#### 마스크 품질 검증
```swift
// 전경 비율 체크
if finalWhiteRatio < 0.05 {
    // 객체 미감지 경고
} else if finalWhiteRatio > 0.8 {
    // 배경 오인식 경고
}
```

#### 디버깅 로그 강화
- 각 처리 단계별 마스크 통계 출력
- 전경 픽셀 비율 추적
- 처리 시간 측정

## 8. 현재 개발 상태와 향후 보강 포인트
- `ClothIQ/PROGRESS.md` 기준 Phase 1 핵심 기능 85% 완료, 빌드 성공 상태입니다.
- **완료된 주요 기능** (2025-10-24):
  - ✅ 배경 제거 워크플로우 구현 및 최적화
  - ✅ Vision Framework 기반 전경 분리
  - ✅ Morphological 연산을 통한 마스크 품질 개선
  - ✅ 카메라 포커스 기능
  - ✅ 이미지 캡처 및 Photos 앨범 저장

- **남은 보완 항목**:
  - 환경 평가에서 카메라 모션 분석 추가 (`ARMeasurementService.assessEnvironment`의 TODO)
  - 다중 샘플링·이상치 제거·스무딩 등 측정 정확도 향상 로직을 실제 `MeasurementViewModel` 흐름에 통합
  - SwiftData 저장/불러오기, 태그 편집 UI 개선
  - 단위 테스트 및 UI 테스트 추가 (현재 기본 템플릿만 존재)
  - Core ML 의류 분류 모델 통합 (Phase 2 예정)

---

**최종 업데이트**: 2025-10-24
**문서 버전**: 1.1.0

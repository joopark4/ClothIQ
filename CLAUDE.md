# ClothIQ - 의류 측정 iOS 앱

## 프로젝트 개요

LiDAR 센서를 활용하여 의류의 각 부위별 사이즈를 정확하게 측정하는 iOS 네이티브 애플리케이션입니다. ARKit과 Vision Framework를 활용하여 3D 깊이 정보 기반의 실측 데이터를 제공하며, 촬영한 의류 이미지와 측정값을 로컬에 저장하여 관리합니다.

## 현재 구현 상태

> **상세한 개발 진행 상황은 [PROGRESS.md](./ClothIQ/PROGRESS.md) 파일을 참조하세요.**

### 진행률 요약

| Phase | 상태 | 진행률 |
|-------|------|--------|
| **Phase 1: MVP** | ✅ 완료 | 100% (18/18) |
| **Phase 2: 고도화** | 🚧 진행 중 | 10% |

### 주요 완료 기능

- ✅ LiDAR 기반 정밀 측정 (±0.5~2cm)
- ✅ Vision Framework 배경 제거
- ✅ SwiftData 데이터 관리
- ✅ iPhone/iPad 적응형 UI
- ✅ 사진 측정 교정 시스템 (91.3% 개선)
- ✅ 다중 샘플링 + 칼만 필터
- ✅ 측정 방식 분리 (AR/Photo)

### 프로젝트 통계

- **빌드 상태**: ✅ 성공
- **최소 iOS 버전**: 17.0+
- **지원 디바이스**: LiDAR 탑재 기기

---

## 구현된 주요 컴포넌트

### 서비스 레이어
- `ARMeasurementService`: LiDAR 측정 포인트 추출 및 환경 평가 (다중 샘플링 통합)
- `DepthDataProcessor`: 깊이 데이터 처리 및 3D 좌표 계산
- `MeasurementCalculator`: 측정 알고리즘 및 검증
- `ObjectCaptureService`: 배경 제거 및 Post-Capture 워크플로우
- `ForegroundSegmentationService`: 실시간 전경 분리 및 객체 감지
- `PhotoLibraryService`: Photos 앱 연동 및 권한 관리
- `ImageFileManager`: 로컬 이미지 파일 관리
- `MultiSamplingProcessor`: 15프레임 다중 샘플링 및 신뢰도 기반 평균화
- `KalmanFilter`: 1D/3D/Adaptive 노이즈 필터링
- `CameraCalibrator`: 카메라 각도/거리/렌즈 왜곡 보정
- `ClothingKeypointDetector`: Vision Framework 기반 키포인트 자동 감지
- `VisionMLService`: Core ML 모델 통합 및 하이브리드 감지
- `MLTrainingDataCollector`: 학습 데이터 수집 및 내보내기
- `AutoMeasurementService`: 자동 측정 및 검증
- `EnhancedMeasurementService`: 고급 측정 기능 통합

### UI 컴포넌트
- `MeasurementView`: 메인 측정 화면 (다중 샘플링 진행 표시 포함)
- `ARViewContainer`: AR 카메라 뷰 컨테이너 (좌표 변환 통합)
- `MeasurementOverlayView`: 측정 포인트 오버레이
- `MeasurementPointView`: 개별 측정 포인트 시각화
- `MeasurementLineView`: 측정 라인 및 거리 표시
- `CameraAlignmentGuide`: 카메라 정렬 가이드 (수평계 방식)
- `ClothingLibraryView`: 의류 라이브러리 메인 화면
- `ClothingDetailView`: 의류 상세 정보
- `PhotoMeasurementView`: 사진 기반 측정 화면
- `ZoomableImageView`: 확대/드래그 가능 이미지 뷰
- `KeypointOverlayView`: 키포인트 감지 결과 시각화
- `MLTrainingSettingsView`: ML 학습 설정 UI
- `DataCollectionDebugView`: 데이터 수집 디버그 UI

### 유틸리티
- `DeviceCapability`: 디바이스 기능 확인 (LiDAR 지원 등)
- `ImageCaptureUtility`: 이미지 캡처 및 최적화
- `ARError`: AR 측정 관련 에러 타입
- `MeasurementSettings`: 런타임 측정 설정 관리 (교정 계수 포함)

---

## 목차

1. [핵심 기능](#핵심-기능)
2. [기술 스택](#기술-스택)
3. [시스템 요구사항](#시스템-요구사항)
4. [아키텍처](#아키텍처)
5. [프로젝트 구조](#프로젝트-구조)
6. [데이터 모델](#데이터-모델)
7. [측정 항목 정의](#측정-항목-정의)
8. [iOS 디바이스 개발 도구](#ios-디바이스-개발-도구)
9. [라이브 디버깅 및 교정 시스템](#라이브-디버깅-및-교정-시스템)
10. [개발 가이드라인](#개발-가이드라인)
11. [Phase별 개발 계획](#phase별-개발-계획)
12. [향후 확장 계획](#향후-확장-계획)
13. [프로젝트 문서](#프로젝트-문서)

---

## 핵심 기능

### 1. LiDAR 기반 정밀 측정
- ARKit의 Scene Depth API를 활용한 3D 공간 측정
- 실시간 깊이 정보 기반 정확한 거리 계산
- 참조 객체를 통한 스케일 보정
- 측정 신뢰도 점수 제공

### 2. 의류 종류별 측정
지원하는 의류 타입:
- **반팔 티셔츠**: 어깨너비, 가슴둘레, 총길이, 소매길이
- **긴팔 티셔츠**: 어깨너비, 가슴둘레, 총길이, 소매길이, 팔둘레
- **반바지**: 허리둘레, 엉덩이둘레, 총길이, 밑위
- **긴바지**: 허리둘레, 엉덩이둘레, 총길이, 밑위, 밑단, 허벅지둘레
- **치마**: 허리둘레, 엉덩이둘레, 총길이

### 3. 이미지 처리
- **배경 제거**: Vision Framework 기반 VNGenerateForegroundInstanceMaskRequest
- **Post-Capture 워크플로우**: 5단계 처리 파이프라인
  1. AR 카메라에서 이미지 캡처
  2. 1:1 정사각형 자동 크롭 (객체 중심)
  3. JPEG로 임시 저장
  4. 배경 제거 실행
  5. Photos 앱 및 로컬 파일 시스템에 저장
- **마스크 품질 개선**: Morphological 연산 (Closing: Dilation + Erosion)
- **실시간 객체 감지**: 사각형/윤곽 기반 전경 분리
- **하이브리드 접근**: LiDAR Depth map + Vision mask 결합
- **고품질 이미지**: JPEG 압축 (품질 90%) 및 최적화

### 4. 데이터 관리
- **SwiftData 모델**: ClothingItemModel, MeasurementModel, TagModel (1:N, N:M 관계)
- **이미지 저장**: 파일 시스템에 JPEG 형식으로 저장 (성능 최적화)
- **Photos 앱 연동**: PhotoLibraryService를 통한 ClothIQ 전용 앨범 관리
- **권한 관리**: 카메라, 사진 라이브러리 권한 자동 요청 및 처리
- **측정 히스토리**: MeasurementSession을 통한 측정 세션 관리
- **태그 시스템**: 의류 분류 및 검색을 위한 태그 지원

### 5. AI/ML 통합 (Phase 2+)
- Core ML을 활용한 의류 자동 분류
- 측정 포인트 자동 감지
- 사전 학습 모델 사용 (on-device inference)
- 향후 서버 연동 시 모델 업데이트 지원

---

## 기술 스택

### 프레임워크 및 라이브러리

| 영역 | 기술 | 버전 | 용도 |
|------|------|------|------|
| UI | SwiftUI | iOS 17+ | 선언형 UI 구축 |
| 아키텍처 | MVVM + Combine | - | 반응형 상태 관리 |
| 데이터 | SwiftData | iOS 17+ | 로컬 데이터 영속성 |
| AR | ARKit | iOS 17+ | LiDAR 및 3D 공간 인식 |
| 3D 렌더링 | RealityKit | iOS 17+ | AR 콘텐츠 시각화 |
| 이미지 처리 | Vision | iOS 17+ | 배경 분리, 객체 감지 |
| ML | Core ML | iOS 17+ | 의류 분류 및 측정 고도화 |
| 의존성 관리 | Swift Package Manager | - | 패키지 관리 |
| 문서화 | DocC | Xcode 15+ | API 문서 자동 생성 |

### 개발 도구
- **Xcode**: 15.0 이상
- **Swift**: 5.9 이상
- **macOS**: Sonoma (14.0) 이상 권장

---

## 시스템 요구사항

### 필수 요구사항
- **iOS 버전**: 17.0 이상
- **LiDAR 센서**: 필수
  - iPhone 12 Pro / Pro Max 이후 Pro 모델
  - iPad Pro (2020년 이후 모델)
- **저장 공간**: 최소 500MB (이미지 저장용)
- **카메라 권한**: 필수
- **사진 라이브러리 권한**: 선택

### 권장 사양
- **iOS 버전**: 17.2 이상 (최신 Vision API 활용)
- **메모리**: 4GB 이상
- **저장 공간**: 2GB 이상 (대량 측정 데이터용)

### LiDAR 미지원 기기 대응
- 앱 실행 시 LiDAR 지원 여부 체크
- 미지원 기기의 경우 명확한 안내 메시지 표시
- App Store 설명에 지원 기기 명시

---

## 아키텍처

### MVVM + Clean Architecture

```
┌─────────────────────────────────────────────────┐
│                Presentation Layer                │
│  ┌─────────┐  ┌──────────┐  ┌───────────────┐  │
│  │  Views  │←─│ViewModels│←─│  Coordinators │  │
│  │(SwiftUI)│  │(Combine) │  │               │  │
│  └─────────┘  └──────────┘  └───────────────┘  │
└─────────────────────────────────────────────────┘
                      ↓ ↑
┌─────────────────────────────────────────────────┐
│                  Domain Layer                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ Entities │  │Use Cases │  │ Repositories │  │
│  │          │  │          │  │  (Protocol)  │  │
│  └──────────┘  └──────────┘  └──────────────┘  │
└─────────────────────────────────────────────────┘
                      ↓ ↑
┌─────────────────────────────────────────────────┐
│                  Data Layer                      │
│  ┌────────────┐  ┌──────────┐  ┌────────────┐  │
│  │ SwiftData  │  │   File   │  │   Core ML  │  │
│  │ Repository │  │  System  │  │  Service   │  │
│  └────────────┘  └──────────┘  └────────────┘  │
└─────────────────────────────────────────────────┘
                      ↓ ↑
┌─────────────────────────────────────────────────┐
│              Infrastructure Layer                │
│  ┌─────────┐  ┌─────────┐  ┌────────────────┐  │
│  │  ARKit  │  │ Vision  │  │   Extensions   │  │
│  │ Service │  │ Service │  │   & Utilities  │  │
│  └─────────┘  └─────────┘  └────────────────┘  │
└─────────────────────────────────────────────────┘
```

### 주요 레이어 설명

#### 1. Presentation Layer
- **Views (SwiftUI)**: 사용자 인터페이스 컴포넌트
- **ViewModels (Combine)**: 비즈니스 로직과 UI 상태 관리
- **Coordinators**: 화면 간 네비게이션 관리

#### 2. Domain Layer
- **Entities**: 비즈니스 모델 (의류 아이템, 측정값 등)
- **Use Cases**: 비즈니스 로직 (측정 수행, 데이터 저장 등)
- **Repository Protocols**: 데이터 접근 인터페이스

#### 3. Data Layer
- **SwiftData Repository**: 로컬 데이터 영속성 구현
- **File System Manager**: 이미지 파일 저장/로드
- **Core ML Service**: ML 모델 추론

#### 4. Infrastructure Layer
- **ARKit Service**: LiDAR 측정 및 AR 세션 관리
- **Vision Service**: 이미지 처리 및 배경 분리
- **Extensions & Utilities**: 공통 유틸리티 및 확장

---

## 프로젝트 구조

```
ClothIQ/
├── App/
│   ├── ClothIQApp.swift           # 앱 진입점
│   ├── AppDelegate.swift                # 앱 생명주기 관리
│   └── Info.plist                       # 앱 설정 및 권한
│
├── Features/                            # Feature 모듈
│   ├── Measurement/                     # 측정 기능
│   │   ├── Presentation/
│   │   │   ├── Views/
│   │   │   │   ├── MeasurementView.swift
│   │   │   │   ├── ARMeasurementView.swift
│   │   │   │   ├── ClothingTypeSelectionView.swift
│   │   │   │   └── MeasurementResultView.swift
│   │   │   ├── ViewModels/
│   │   │   │   ├── MeasurementViewModel.swift
│   │   │   │   └── ARMeasurementViewModel.swift
│   │   │   └── Components/
│   │   │       ├── MeasurementPointView.swift
│   │   │       └── ConfidenceIndicatorView.swift
│   │   ├── Domain/
│   │   │   ├── Entities/
│   │   │   │   ├── MeasurementPoint.swift
│   │   │   │   └── MeasurementResult.swift
│   │   │   └── UseCases/
│   │   │       ├── PerformMeasurementUseCase.swift
│   │   │       └── ValidateMeasurementUseCase.swift
│   │   └── Data/
│   │       └── Services/
│   │           ├── ARMeasurementService.swift
│   │           └── MeasurementCalculator.swift
│   │
│   ├── ClothingLibrary/                 # 의류 라이브러리
│   │   ├── Presentation/
│   │   │   ├── Views/
│   │   │   │   ├── LibraryView.swift
│   │   │   │   ├── ClothingDetailView.swift
│   │   │   │   └── ClothingListView.swift
│   │   │   └── ViewModels/
│   │   │       ├── LibraryViewModel.swift
│   │   │       └── ClothingDetailViewModel.swift
│   │   ├── Domain/
│   │   │   ├── Entities/
│   │   │   │   └── ClothingItem.swift
│   │   │   └── UseCases/
│   │   │       ├── SaveClothingItemUseCase.swift
│   │   │       ├── LoadClothingItemsUseCase.swift
│   │   │       └── DeleteClothingItemUseCase.swift
│   │   └── Data/
│   │       └── Repository/
│   │           └── ClothingRepository.swift
│   │
│   ├── ImageProcessing/                 # 이미지 처리
│   │   ├── Presentation/
│   │   │   ├── Views/
│   │   │   │   ├── BackgroundRemovalView.swift
│   │   │   │   └── ImageEditingView.swift
│   │   │   └── ViewModels/
│   │   │       └── ImageProcessingViewModel.swift
│   │   ├── Domain/
│   │   │   └── UseCases/
│   │   │       ├── RemoveBackgroundUseCase.swift
│   │   │       └── OptimizeImageUseCase.swift
│   │   └── Data/
│   │       └── Services/
│   │           ├── VisionService.swift
│   │           └── ImageFileManager.swift
│   │
│   └── Settings/                        # 설정
│       ├── Presentation/
│       │   ├── Views/
│       │   │   ├── SettingsView.swift
│       │   │   └── MeasurementUnitView.swift
│       │   └── ViewModels/
│       │       └── SettingsViewModel.swift
│       └── Domain/
│           └── Entities/
│               └── AppSettings.swift
│
├── Core/                                # 공통 모듈
│   ├── Data/
│   │   ├── SwiftData/
│   │   │   ├── PersistenceController.swift
│   │   │   └── Models/
│   │   │       ├── ClothingItemModel.swift
│   │   │       ├── MeasurementModel.swift
│   │   │       └── TagModel.swift
│   │   └── FileSystem/
│   │       └── FileManager+Extensions.swift
│   │
│   ├── Domain/
│   │   ├── Protocols/
│   │   │   ├── Repository.swift
│   │   │   └── UseCase.swift
│   │   └── Enums/
│   │       ├── ClothingType.swift
│   │       ├── MeasurementType.swift
│   │       └── MeasurementUnit.swift
│   │
│   ├── Extensions/
│   │   ├── Array+Extensions.swift
│   │   ├── Date+Extensions.swift
│   │   ├── Color+Extensions.swift
│   │   └── View+Extensions.swift
│   │
│   ├── Utilities/
│   │   ├── Logger.swift
│   │   ├── ErrorHandler.swift
│   │   └── Constants.swift
│   │
│   └── UI/
│       ├── Components/
│       │   ├── LoadingView.swift
│       │   ├── ErrorView.swift
│       │   └── EmptyStateView.swift
│       ├── Modifiers/
│       │   └── CustomViewModifiers.swift
│       └── Theme/
│           ├── Colors.swift
│           ├── Fonts.swift
│           └── Spacing.swift
│
├── Resources/
│   ├── Assets.xcassets/                 # 이미지 및 아이콘
│   ├── Localizations/                   # 다국어 지원
│   │   ├── en.lproj/
│   │   │   └── Localizable.strings
│   │   └── ko.lproj/
│   │       └── Localizable.strings
│   └── CoreML/                          # ML 모델
│       └── ClothingClassifier.mlmodel
│
├── Tests/
│   ├── UnitTests/
│   │   ├── MeasurementTests/
│   │   ├── ClothingLibraryTests/
│   │   └── ImageProcessingTests/
│   └── UITests/
│       └── ClothIQUITests.swift
│
└── Documentation/
    ├── Architecture.md
    ├── APIReference/                    # DocC 생성 문서
    └── Guides/
        ├── GettingStarted.md
        └── MeasurementGuide.md
```

### 파일 명명 규칙

- **Views**: `[Feature]View.swift` (예: `MeasurementView.swift`)
- **ViewModels**: `[Feature]ViewModel.swift`
- **Use Cases**: `[Action][Entity]UseCase.swift` (예: `SaveClothingItemUseCase.swift`)
- **Services**: `[Feature]Service.swift`
- **Extensions**: `[Type]+Extensions.swift`

---

## 데이터 모델

### SwiftData 모델

#### ClothingItemModel
```swift
import SwiftData
import Foundation

/// 의류 아이템 데이터 모델
/// 촬영한 의류의 기본 정보와 측정값을 저장합니다.
@Model
final class ClothingItemModel {
    /// 고유 식별자
    var id: UUID
    
    /// 의류 타입 (반팔, 긴팔, 바지 등)
    var type: String
    
    /// 생성 일시
    var createdAt: Date
    
    /// 수정 일시
    var updatedAt: Date
    
    /// 이미지 파일 경로 (Documents 디렉토리 내 상대 경로)
    var imagePath: String?
    
    /// 측정값 목록
    @Relationship(deleteRule: .cascade)
    var measurements: [MeasurementModel]
    
    /// 태그 목록
    @Relationship(deleteRule: .nullify)
    var tags: [TagModel]
    
    /// 메모
    var notes: String?
    
    /// 즐겨찾기 여부
    var isFavorite: Bool
    
    init(
        id: UUID = UUID(),
        type: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        imagePath: String? = nil,
        measurements: [MeasurementModel] = [],
        tags: [TagModel] = [],
        notes: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imagePath = imagePath
        self.measurements = measurements
        self.tags = tags
        self.notes = notes
        self.isFavorite = isFavorite
    }
}
```

#### MeasurementModel
```swift
import SwiftData
import Foundation

/// 측정값 데이터 모델
/// 개별 측정 항목의 값과 메타데이터를 저장합니다.
@Model
final class MeasurementModel {
    /// 고유 식별자
    var id: UUID
    
    /// 측정 타입 (어깨너비, 가슴둘레 등)
    var type: String
    
    /// 측정값 (센티미터)
    var value: Double
    
    /// 측정 단위
    var unit: String
    
    /// 측정 신뢰도 (0.0 ~ 1.0)
    var confidence: Double
    
    /// 측정 일시
    var measuredAt: Date
    
    /// 부모 의류 아이템
    var clothingItem: ClothingItemModel?
    
    init(
        id: UUID = UUID(),
        type: String,
        value: Double,
        unit: String = "cm",
        confidence: Double = 1.0,
        measuredAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.value = value
        self.unit = unit
        self.confidence = confidence
        self.measuredAt = measuredAt
    }
}
```

#### TagModel
```swift
import SwiftData
import Foundation

/// 태그 데이터 모델
/// 의류 아이템을 분류하고 검색하기 위한 태그입니다.
@Model
final class TagModel {
    /// 고유 식별자
    var id: UUID
    
    /// 태그 이름
    var name: String
    
    /// 태그 색상 (Hex)
    var colorHex: String
    
    /// 생성 일시
    var createdAt: Date
    
    /// 연관된 의류 아이템 목록
    var clothingItems: [ClothingItemModel]
    
    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#007AFF",
        createdAt: Date = Date(),
        clothingItems: [ClothingItemModel] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.clothingItems = clothingItems
    }
}
```

### Domain Entities

#### ClothingItem (Domain Entity)
```swift
/// 의류 아이템 도메인 엔티티
/// 비즈니스 로직에서 사용되는 의류 아이템 표현
struct ClothingItem: Identifiable, Equatable {
    let id: UUID
    let type: ClothingType
    let createdAt: Date
    let updatedAt: Date
    let image: UIImage?
    let measurements: [Measurement]
    let tags: [Tag]
    let notes: String?
    let isFavorite: Bool
}
```

#### Measurement (Domain Entity)
```swift
/// 측정값 도메인 엔티티
struct Measurement: Identifiable, Equatable {
    let id: UUID
    let type: MeasurementType
    let value: Double
    let unit: MeasurementUnit
    let confidence: Double
    let measuredAt: Date
    
    /// 측정값을 지정된 단위로 변환
    func converted(to unit: MeasurementUnit) -> Double {
        // 단위 변환 로직
    }
}
```

---

## 측정 항목 정의

### ClothingType Enum
```swift
/// 의류 타입 정의
enum ClothingType: String, CaseIterable, Codable {
    case shortSleeve = "short_sleeve"   // 반팔
    case longSleeve = "long_sleeve"     // 긴팔
    case shorts = "shorts"              // 반바지
    case pants = "pants"                // 긴바지
    case skirt = "skirt"                // 치마
    
    /// 각 의류 타입별 필수 측정 항목
    var requiredMeasurements: [MeasurementType] {
        switch self {
        case .shortSleeve:
            return [.shoulderWidth, .chestCircumference, .totalLength, .sleeveLength]
        case .longSleeve:
            return [.shoulderWidth, .chestCircumference, .totalLength, .sleeveLength, .armCircumference]
        case .shorts:
            return [.waistCircumference, .hipCircumference, .totalLength, .rise]
        case .pants:
            return [.waistCircumference, .hipCircumference, .totalLength, .rise, .hem, .thighCircumference]
        case .skirt:
            return [.waistCircumference, .hipCircumference, .totalLength]
        }
    }
    
    /// 선택적 측정 항목
    var optionalMeasurements: [MeasurementType] {
        switch self {
        case .shortSleeve, .longSleeve:
            return [.neckCircumference, .hemWidth]
        case .shorts, .pants:
            return [.inseam, .outseam, .kneeCircumference]
        case .skirt:
            return [.hemWidth]
        }
    }
}
```

### MeasurementType Enum
```swift
/// 측정 타입 정의
enum MeasurementType: String, CaseIterable, Codable {
    // 상의 측정 항목
    case shoulderWidth = "shoulder_width"                  // 어깨너비
    case chestCircumference = "chest_circumference"        // 가슴둘레
    case totalLength = "total_length"                      // 총길이
    case sleeveLength = "sleeve_length"                    // 소매길이
    case armCircumference = "arm_circumference"            // 팔둘레
    case neckCircumference = "neck_circumference"          // 목둘레
    
    // 하의 측정 항목
    case waistCircumference = "waist_circumference"        // 허리둘레
    case hipCircumference = "hip_circumference"            // 엉덩이둘레
    case rise = "rise"                                     // 밑위
    case hem = "hem"                                       // 밑단
    case thighCircumference = "thigh_circumference"        // 허벅지둘레
    case inseam = "inseam"                                 // 인심 (안쪽 솔기)
    case outseam = "outseam"                               // 아웃심 (바깥쪽 솔기)
    case kneeCircumference = "knee_circumference"          // 무릎둘레
    
    // 공통 측정 항목
    case hemWidth = "hem_width"                            // 밑단너비
    
    /// 측정 항목의 표시 이름
    var displayName: String {
        switch self {
        case .shoulderWidth: return "어깨너비"
        case .chestCircumference: return "가슴둘레"
        case .totalLength: return "총길이"
        case .sleeveLength: return "소매길이"
        case .armCircumference: return "팔둘레"
        case .neckCircumference: return "목둘레"
        case .waistCircumference: return "허리둘레"
        case .hipCircumference: return "엉덩이둘레"
        case .rise: return "밑위"
        case .hem: return "밑단"
        case .thighCircumference: return "허벅지둘레"
        case .inseam: return "인심"
        case .outseam: return "아웃심"
        case .kneeCircumference: return "무릎둘레"
        case .hemWidth: return "밑단너비"
        }
    }
    
    /// 측정 방법 설명
    var measurementGuide: String {
        switch self {
        case .shoulderWidth:
            return "양쪽 어깨 끝점 사이의 직선 거리를 측정합니다."
        case .chestCircumference:
            return "가슴 가장 넓은 부분의 둘레를 측정합니다."
        case .totalLength:
            return "목 뒤 중심에서 밑단까지의 길이를 측정합니다."
        case .sleeveLength:
            return "어깨 끝점에서 소매 끝까지의 길이를 측정합니다."
        case .armCircumference:
            return "팔의 가장 두꺼운 부분의 둘레를 측정합니다."
        case .neckCircumference:
            return "목둘레선의 둘레를 측정합니다."
        case .waistCircumference:
            return "허리 가장 좁은 부분의 둘레를 측정합니다."
        case .hipCircumference:
            return "엉덩이 가장 넓은 부분의 둘레를 측정합니다."
        case .rise:
            return "허리에서 밑위까지의 길이를 측정합니다."
        case .hem:
            return "바지 밑단의 둘레를 측정합니다."
        case .thighCircumference:
            return "허벅지 가장 두꺼운 부분의 둘레를 측정합니다."
        case .inseam:
            return "밑위에서 바지 밑단까지의 안쪽 솔기 길이를 측정합니다."
        case .outseam:
            return "허리에서 바지 밑단까지의 바깥쪽 솔기 길이를 측정합니다."
        case .kneeCircumference:
            return "무릎 부분의 둘레를 측정합니다."
        case .hemWidth:
            return "밑단의 너비를 측정합니다."
        }
    }
}
```

### MeasurementUnit Enum
```swift
/// 측정 단위 정의
enum MeasurementUnit: String, CaseIterable, Codable {
    case centimeter = "cm"
    case inch = "in"
    
    /// 단위 변환 비율
    var conversionFactor: Double {
        switch self {
        case .centimeter: return 1.0
        case .inch: return 2.54  // 1 inch = 2.54 cm
        }
    }
    
    /// 표시 이름
    var displayName: String {
        switch self {
        case .centimeter: return "센티미터"
        case .inch: return "인치"
        }
    }
}
```

---

## iOS 디바이스 개발 도구

### CLI 기반 자동화 워크플로우 (2025.11.05 추가)

프로젝트에 **CLI 기반 iOS 디바이스 개발 도구**가 통합되었습니다. 이를 통해 Claude Code CLI에서 완전히 자동화된 빌드, 배포, 디버깅 워크플로우를 실행할 수 있습니다.

#### 주요 기능

- ✅ **자동 빌드**: xcodebuild를 통한 프로젝트 빌드
- ✅ **디바이스 배포**: 연결된 아이패드/아이폰에 자동 설치
- ✅ **실시간 로그**: 앱 실행 중 로그 스트리밍
- ✅ **프로세스 관리**: 앱 실행/종료/모니터링
- ✅ **성능 분석**: Instruments 기반 프로파일링
- ✅ **크래시 수집**: 자동 크래시 로그 수집

#### 빠른 시작

```bash
cd scripts

# 1. 디바이스 확인
./ios_device_tools.sh list-devices

# 2. 빌드 + 배포 + 로그 (권장)
./ios_device_tools.sh full-deploy

# 3. 앱 종료
./ios_device_tools.sh stop
```

#### 주요 명령어

| 명령어 | 설명 | 사용 예시 |
|--------|------|----------|
| `list-devices` | 연결된 디바이스 목록 | `./ios_device_tools.sh list-devices` |
| `build` | 프로젝트 빌드 | `./ios_device_tools.sh build` |
| `install` | 앱 설치 | `./ios_device_tools.sh install` |
| `launch` | 앱 실행 | `./ios_device_tools.sh launch` |
| `logs` | 실시간 로그 스트리밍 | `./ios_device_tools.sh logs` |
| `stop` | 앱 종료 | `./ios_device_tools.sh stop` |
| **`full-deploy`** | **빌드→설치→실행→로그** | `./ios_device_tools.sh full-deploy` |
| `monitor` | 프로세스 모니터링 | `./ios_device_tools.sh monitor` |
| `crash-logs` | 크래시 로그 수집 | `./ios_device_tools.sh crash-logs` |
| `profile` | 성능 프로파일링 | `./ios_device_tools.sh profile "Time Profiler" 60` |

#### 실전 개발 워크플로우

**시나리오 1: 일반 개발**
```bash
# 1. 코드 수정 후...

# 2. 빌드 + 배포 + 테스트
./ios_device_tools.sh full-deploy

# 3. 로그 확인하면서 테스트 (자동 스트리밍)

# 4. 문제 발견 시 Ctrl+C로 종료

# 5. 코드 수정 후 다시 full-deploy
```

**시나리오 2: 크래시 디버깅**
```bash
# 1. 앱 실행 및 모니터링
./ios_device_tools.sh full-deploy

# 2. 크래시 발생!

# 3. 크래시 로그 수집
./ios_device_tools.sh crash-logs ./crash_$(date +%Y%m%d_%H%M%S)

# 4. 크래시 로그 분석
cat crash_*/ClothIQ*.ips
```

**시나리오 3: 성능 분석**
```bash
# 1. 앱 실행
./ios_device_tools.sh launch

# 2. CPU 프로파일링 (60초)
./ios_device_tools.sh profile "Time Profiler" 60

# 3. 메모리 프로파일링
./ios_device_tools.sh profile "Allocations" 60

# 4. Instruments로 결과 분석
open profiling_*.trace
```

#### 도구 파일 위치

```
scripts/
├── ios_device_tools.sh          # 메인 실행 스크립트
├── ios_device_config.sh         # ClothIQ 설정 파일
├── ios_device_config.template   # 설정 템플릿
└── README.md                    # 빠른 시작 가이드

IOS_DEVICE_GUIDE.md              # 상세 사용 가이드 (프로젝트 루트)
```

#### 상세 문서

완전한 사용 가이드는 **[IOS_DEVICE_GUIDE.md](./IOS_DEVICE_GUIDE.md)**를 참조하세요:
- 설정 방법 상세 설명
- 트러블슈팅 가이드
- 고급 사용법 (여러 디바이스, CI/CD 통합)
- 다른 프로젝트에 적용하는 방법

#### 다른 프로젝트 적용

이 도구는 **모든 iOS 프로젝트에 적용 가능**합니다:

1. 파일 복사 (`ios_device_tools.sh`, `ios_device_config.template`)
2. 설정 파일 생성 및 프로젝트 정보 입력
3. `./ios_device_tools.sh full-deploy` 실행

자세한 내용은 [IOS_DEVICE_GUIDE.md](./DOC/IOS_DEVICE_GUIDE.md)의 "다른 프로젝트에 적용하기" 섹션 참조.

---

## 라이브 디버깅 및 교정 시스템

### 개요 (2025.11.05 분석 완료)

ClothIQ는 **라이브 디버깅 및 교정 시스템** 구현이 완전히 가능합니다. 현재 측정 시스템의 아키텍처가 확장 가능하게 설계되어 있어, 다음 기능들을 추가할 수 있습니다:

- ✅ **실시간 임계값 조정**: 30+ 파라미터를 라이브로 조정
- ✅ **AR 카메라 오버레이**: 환경 점수, 깊이 품질, 거리 실시간 표시
- ✅ **교정 워크플로우**: 기준 샘플 → 실측값 입력 → 측정 → 보정 계수 저장
- ✅ **반복 학습**: 10회 측정 평균 → 자동 보정 적용
- ✅ **알고리즘 실험**: BFS, A*, 헤밀턴 거리 등 다양한 알고리즘 테스트

### 현재 측정 시스템 분석

#### 1. 핵심 컴포넌트

| 컴포넌트 | 위치 | 주요 기능 |
|---------|------|----------|
| **ARMeasurementService** | `Features/Measurement/Data/Services/` | LiDAR 측정, 환경 평가, 카메라 정렬 |
| **DepthDataProcessor** | `Features/Measurement/Data/Services/` | 깊이 맵 샘플링, 3D 좌표 계산 |
| **MeasurementCalculator** | `Features/Measurement/Data/Services/` | 거리 계산, 각도 보정, 평면 투영 |
| **PhotoMeasurementCalculator** | `Features/ClothingLibrary/Domain/UseCases/` | 저장된 depth map 기반 측정 |

#### 2. 하드코딩된 임계값 (30+ 파라미터)

**신뢰도 임계값**
- 최소 신뢰도: `0.6`
- 낮은 신뢰도 경고: `0.7`
- 매우 낮은 신뢰도: `0.4`

**거리 범위 (센티미터)**
- 어깨너비: `30.0 ~ 60.0`
- 가슴둘레: `70.0 ~ 150.0`
- 허리둘레: `50.0 ~ 150.0`

**최적 측정 거리 (미터)**
- 최적 범위: `0.7 ~ 1.0`

**환경 평가**
- 최적 조명: `1000 ~ 1500 lumens`

자세한 임계값 목록은 **[LIVE_DEBUG_ANALYSIS.md](./DOC/LIVE_DEBUG_ANALYSIS.md#하드코딩된-임계값-목록)** 참조.

### 제안 아키텍처

#### 1. 런타임 설정 관리자

```swift
class MeasurementSettings: ObservableObject {
    static let shared = MeasurementSettings()

    // 실시간 조정 가능한 파라미터
    @Published var minConfidence: Float = 0.6
    @Published var minDepthCoverage: Float = 0.2
    @Published var optimalMinDistance: Float = 0.7
    @Published var optimalMaxDistance: Float = 1.0

    // 교정 활성화 여부
    @Published var useCalibration: Bool = false
}
```

#### 2. 교정 데이터 모델 (SwiftData)

```swift
@Model
final class CalibrationProfile {
    var name: String  // "반바지 기준"
    var minConfidence: Float
    var calibrationFactors: [CalibrationFactor]
}

@Model
final class CalibrationFactor {
    var actualValue: Double      // 78.0 cm (실측값)
    var measuredValue: Double     // 76.5 cm (측정값)
    var correctionFactor: Double  // 1.0196 (보정 계수)
    var sampleCount: Int          // 10회
}
```

#### 3. 라이브 디버깅 UI

**DebugMetricsPanel** - 실시간 메트릭 표시
- 환경 점수: 색상 코딩 (녹색/노랑/빨강)
- 깊이 품질: 커버리지 퍼센트
- 카메라 거리: 최적 범위 피드백
- 감지된 포인트 수

**DebugSettingsPanel** - 슬라이더로 임계값 조정
- 최소 신뢰도
- 최소 깊이 커버리지
- 최적 측정 거리 (최소/최대)

### 워크플로우 예시

#### 시나리오: 반바지 기준 교정

```
1. [기준 샘플 선택]
   - 반바지 선택
   - 측정 타입: 허리둘레

2. [실측값 입력]
   - 자로 직접 측정: 78cm

3. [AR 측정 10회 반복]
   측정 1: 76.2 cm
   측정 2: 77.5 cm
   ...
   측정 10: 76.9 cm

   평균: 76.5 cm
   표준편차: 0.8 cm

4. [결과 비교]
   실측값: 78.0 cm
   측정값: 76.5 cm
   오차: 1.5 cm (1.9%)

   보정 계수: 78.0 / 76.5 = 1.0196

5. [교정 저장]
   "반바지 기준" 프로파일 생성
   허리둘레 보정 계수: 1.0196

6. [다른 의류에 적용]
   긴바지 허리둘레 측정: 82.3 cm
   보정 적용: 82.3 × 1.0196 = 83.9 cm ✅
```

### 구현 계획

**총 소요 시간: 7-10일**

#### Phase 1: 기본 인프라 (1-2일)
- MeasurementSettings 클래스 구현
- CalibrationProfile SwiftData 모델
- 기존 코드에 런타임 파라미터 주입

#### Phase 2: 라이브 디버깅 UI (2-3일)
- LiveDebugOverlay 구현
- DebugMetricsPanel (실시간 메트릭)
- DebugSettingsPanel (슬라이더 조정)
- 깊이 맵 히트맵 시각화

#### Phase 3: 교정 워크플로우 (2-3일)
- CalibrationViewModel 구현 (5단계 워크플로우)
- CalibrationWorkflowView (단계별 UI)
- 실측값 입력 폼
- 결과 비교 화면

#### Phase 4: 통합 및 테스트 (1-2일)
- 반바지 샘플 테스트 (10회 측정)
- 교정 계수 검증
- UI/UX 개선

### 예상 효과

1. **측정 정확도 향상**: 보정 계수 적용으로 ±0.5cm 정확도 달성
2. **개발 효율성 증가**: 실시간 디버깅으로 빠른 문제 파악
3. **사용자 경험 개선**: 환경별 최적 프로파일 제공
4. **알고리즘 실험 용이**: BFS, A*, 헤밀턴 거리 등 다양한 알고리즘 테스트

### 상세 문서

완전한 분석 보고서는 **[LIVE_DEBUG_ANALYSIS.md](./DOC/LIVE_DEBUG_ANALYSIS.md)** 참조:
- 현재 시스템 상세 분석
- 하드코딩된 임계값 전체 목록 (8개 카테고리)
- 제안 아키텍처 및 코드 예제
- 교정 워크플로우 UI 설계
- 알고리즘 실험 시나리오

---

## 개발 가이드라인

### 코드 작성 규칙

#### 1. 파일 크기 제한
- **최대 라인 수**: 1000 라인
- 초과 시 기능별로 파일 분리 필수
- Extensions를 활용한 기능 분리 권장

```swift
// ✅ Good: 기능별 파일 분리
// MeasurementViewModel.swift (600 lines)
// MeasurementViewModel+ARHandling.swift (300 lines)
// MeasurementViewModel+DataProcessing.swift (250 lines)

// ❌ Bad: 단일 파일에 모든 기능 (1500 lines)
// MeasurementViewModel.swift
```

#### 2. 주석 작성 규칙

**파일 헤더 주석**
```swift
//
//  MeasurementViewModel.swift
//  ClothIQ
//
//  Created on 2024-01-XX
//
//  Description:
//  의류 측정 화면의 ViewModel입니다.
//  ARKit을 활용한 실시간 측정 기능과 측정 결과 검증을 담당합니다.
//
//  Key Responsibilities:
//  - AR 세션 관리 및 LiDAR 데이터 처리
//  - 측정 포인트 추적 및 거리 계산
//  - 측정 신뢰도 평가
//  - 측정 결과 저장
//
```

**타입 주석 (DocC 형식)**
```swift
/// 의류 측정을 위한 ViewModel
///
/// ARKit의 LiDAR 센서를 활용하여 의류의 각 부위를 측정하고,
/// 측정 결과의 신뢰도를 평가합니다.
///
/// ## Topics
///
/// ### AR 세션 관리
/// - ``startARSession()``
/// - ``pauseARSession()``
/// - ``stopARSession()``
///
/// ### 측정 수행
/// - ``addMeasurementPoint(_:)``
/// - ``calculateDistance()``
/// - ``validateMeasurement()``
///
/// - Note: LiDAR 센서가 없는 기기에서는 사용할 수 없습니다.
/// - Important: AR 세션은 배터리를 많이 소모하므로 사용 후 반드시 중지해야 합니다.
///
final class MeasurementViewModel: ObservableObject {
    // ...
}
```

**메서드 주석**
```swift
/// 측정 포인트를 추가하고 거리를 계산합니다.
///
/// 사용자가 화면을 탭하면 호출되며, AR 공간의 3D 좌표를 기반으로
/// 측정 포인트를 생성합니다.
///
/// - Parameters:
///   - screenPoint: 화면 좌표계의 터치 지점
///   - frame: 현재 AR 프레임
/// - Returns: 생성된 측정 포인트. 실패 시 nil 반환
/// - Throws: `ARError.insufficientDepthData` - 깊이 데이터가 불충분한 경우
///
/// ## Example
/// ```swift
/// if let point = try? viewModel.addMeasurementPoint(
///     screenPoint: location,
///     frame: currentFrame
/// ) {
///     print("측정 포인트 추가됨: \(point)")
/// }
/// ```
///
/// - Note: 최소 2개의 포인트가 필요하며, 최대 10개까지 추가 가능합니다.
/// - Warning: AR 세션이 활성화되어 있지 않으면 nil을 반환합니다.
///
func addMeasurementPoint(
    at screenPoint: CGPoint,
    frame: ARFrame
) throws -> MeasurementPoint?
```

**프로퍼티 주석**
```swift
/// 현재 측정 중인 의류 타입
///
/// 이 값에 따라 필수 측정 항목이 결정됩니다.
/// 값 변경 시 측정 포인트가 초기화됩니다.
@Published var selectedClothingType: ClothingType = .shortSleeve
```

**복잡한 로직 주석**
```swift
// MARK: - 측정 신뢰도 계산
// 
// 신뢰도는 다음 요소들을 고려하여 계산됩니다:
// 1. LiDAR 깊이 데이터의 품질 (0.0 ~ 1.0)
// 2. 측정 포인트 간 거리의 안정성
// 3. 촬영 각도 및 조명 조건
// 4. 의류 표면의 반사율
//
// 최종 신뢰도는 가중 평균으로 계산되며,
// 0.7 미만일 경우 재측정을 권장합니다.
private func calculateConfidence() -> Double {
    let depthQuality = assessDepthQuality()      // 가중치: 40%
    let stabilityScore = assessStability()       // 가중치: 30%
    let environmentScore = assessEnvironment()   // 가중치: 20%
    let surfaceScore = assessSurface()           // 가중치: 10%
    
    return (depthQuality * 0.4) + 
           (stabilityScore * 0.3) + 
           (environmentScore * 0.2) + 
           (surfaceScore * 0.1)
}
```

#### 3. MARK 주석 활용
```swift
// MARK: - Properties
// MARK: - Initialization
// MARK: - Lifecycle
// MARK: - Public Methods
// MARK: - Private Methods
// MARK: - AR Session Management
// MARK: - Measurement Calculation
// MARK: - UI Updates
// MARK: - Error Handling
```

#### 4. 명명 규칙

**변수 및 상수**
```swift
// ✅ Good: 명확하고 설명적인 이름
let measuredShoulderWidth: Double
var isARSessionActive: Bool
private var confidenceThreshold: Double = 0.7

// ❌ Bad: 축약되거나 모호한 이름
let sw: Double
var active: Bool
private var threshold: Double = 0.7
```

**함수**
```swift
// ✅ Good: 동사로 시작, 의도가 명확
func calculateDistance(from startPoint: SIMD3<Float>, to endPoint: SIMD3<Float>) -> Double
func validateMeasurement(result: MeasurementResult) throws
func convertToMetric(value: Double, from unit: MeasurementUnit) -> Double

// ❌ Bad: 의도가 불명확
func calc(p1: SIMD3<Float>, p2: SIMD3<Float>) -> Double
func check(r: MeasurementResult) throws
func convert(v: Double, u: MeasurementUnit) -> Double
```

**타입**
```swift
// ✅ Good: 대문자로 시작, 단수형 명사
struct MeasurementPoint
class ARMeasurementService
protocol MeasurementRepository

// ❌ Bad
struct measurementPoint
class arMeasurementService
protocol MeasurementRepositoryProtocol  // Protocol 접미사 불필요
```

#### 5. 에러 처리

**커스텀 에러 타입 정의**
```swift
/// 측정 관련 에러 타입
enum MeasurementError: LocalizedError {
    case insufficientDepthData
    case invalidMeasurementPoints
    case arSessionNotAvailable
    case lidarNotSupported
    case confidenceTooLow(score: Double)
    
    var errorDescription: String? {
        switch self {
        case .insufficientDepthData:
            return "깊이 데이터가 충분하지 않습니다. 더 가까이 촬영해주세요."
        case .invalidMeasurementPoints:
            return "측정 포인트가 유효하지 않습니다."
        case .arSessionNotAvailable:
            return "AR 세션을 시작할 수 없습니다."
        case .lidarNotSupported:
            return "이 기기는 LiDAR를 지원하지 않습니다."
        case .confidenceTooLow(let score):
            return "측정 신뢰도가 낮습니다 (\(score)). 재측정을 권장합니다."
        }
    }
}
```

**에러 처리 패턴**
```swift
// ✅ Good: 명확한 에러 처리
func performMeasurement() async throws -> MeasurementResult {
    guard isLiDARAvailable else {
        throw MeasurementError.lidarNotSupported
    }
    
    guard let depthData = try await captureDepthData() else {
        throw MeasurementError.insufficientDepthData
    }
    
    let result = calculateMeasurement(from: depthData)
    
    guard result.confidence >= confidenceThreshold else {
        throw MeasurementError.confidenceTooLow(score: result.confidence)
    }
    
    return result
}

// ViewModel에서 사용
do {
    let result = try await performMeasurement()
    await updateUI(with: result)
} catch let error as MeasurementError {
    await showError(error)
} catch {
    await showError(MeasurementError.arSessionNotAvailable)
}
```

#### 6. 테스트 작성

**테스트 파일 구조**
```swift
import XCTest
@testable import ClothIQ

/// MeasurementViewModel 테스트
///
/// 측정 기능의 핵심 로직을 검증합니다.
final class MeasurementViewModelTests: XCTestCase {
    
    // MARK: - Properties
    
    var sut: MeasurementViewModel!
    var mockARService: MockARMeasurementService!
    var mockRepository: MockClothingRepository!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        mockARService = MockARMeasurementService()
        mockRepository = MockClothingRepository()
        sut = MeasurementViewModel(
            arService: mockARService,
            repository: mockRepository
        )
    }
    
    override func tearDown() {
        sut = nil
        mockARService = nil
        mockRepository = nil
        super.tearDown()
    }
    
    // MARK: - Tests
    
    /// 측정 포인트 추가 시 거리가 정확히 계산되는지 검증
    func testAddMeasurementPoint_CalculatesDistanceCorrectly() async throws {
        // Given
        let startPoint = SIMD3<Float>(0, 0, 0)
        let endPoint = SIMD3<Float>(1, 0, 0)
        let expectedDistance = 100.0  // 1m = 100cm
        
        // When
        try await sut.addMeasurementPoint(at: startPoint)
        try await sut.addMeasurementPoint(at: endPoint)
        let result = sut.currentMeasurement
        
        // Then
        XCTAssertEqual(result?.value, expectedDistance, accuracy: 0.1)
        XCTAssertEqual(result?.unit, .centimeter)
    }
    
    /// 신뢰도가 낮을 때 에러가 발생하는지 검증
    func testValidateMeasurement_ThrowsErrorWhenConfidenceLow() async throws {
        // Given
        mockARService.mockConfidence = 0.5
        
        // When & Then
        await XCTAssertThrowsError(
            try await sut.performMeasurement()
        ) { error in
            XCTAssertTrue(error is MeasurementError)
            if case .confidenceTooLow(let score) = error as? MeasurementError {
                XCTAssertEqual(score, 0.5, accuracy: 0.01)
            } else {
                XCTFail("Unexpected error type")
            }
        }
    }
}
```

#### 7. 모듈화 가이드

**Feature 모듈 구조**
```swift
// 각 Feature는 독립적인 모듈로 구성
// 의존성은 Domain Layer의 Protocol을 통해서만 연결

// MeasurementFeature/
//   - Presentation/   (UI 레이어)
//   - Domain/         (비즈니스 로직)
//   - Data/           (데이터 접근)

// 모듈 간 의존성 규칙:
// Presentation → Domain → Data
// Presentation은 Data를 직접 참조하지 않음
```

**의존성 주입 패턴**
```swift
/// ViewModel은 Protocol에 의존
final class MeasurementViewModel: ObservableObject {
    private let arService: ARMeasurementServiceProtocol
    private let repository: ClothingRepositoryProtocol
    
    init(
        arService: ARMeasurementServiceProtocol,
        repository: ClothingRepositoryProtocol
    ) {
        self.arService = arService
        self.repository = repository
    }
}

/// 실제 구현체는 DI Container에서 주입
struct MeasurementViewFactory {
    static func create() -> MeasurementView {
        let arService = ARMeasurementService()
        let repository = ClothingRepository(
            persistenceController: PersistenceController.shared
        )
        let viewModel = MeasurementViewModel(
            arService: arService,
            repository: repository
        )
        return MeasurementView(viewModel: viewModel)
    }
}
```

#### 8. SwiftUI 속성 래퍼 선택 가이드

**중요**: SwiftUI에서 ObservableObject를 사용할 때는 반드시 적절한 속성 래퍼를 선택해야 합니다.

##### 속성 래퍼 선택 기준표

| 속성 래퍼 | 용도 | 예시 | 생명주기 관리 |
|-----------|------|------|--------------|
| `@State` | 간단한 값 타입 | `Int`, `String`, `Bool` | View가 관리 |
| `@StateObject` | **View가 소유하는** ObservableObject | ViewModel 생성 | View가 관리 |
| `@ObservedObject` | **외부에서 전달받은** ObservableObject | 부모→자식 전달 | 외부에서 관리 |
| `@Binding` | 양방향 바인딩 | 값 공유 | 외부에서 관리 |

##### 핵심 원칙

**✅ 올바른 사용**
```swift
// ObservableObject + @Published = 반드시 @StateObject 또는 @ObservedObject 사용
@MainActor
final class PhotoMeasurementViewModel: ObservableObject {
    @Published var measurementAnchors: [MeasurementAnchor] = []
    @Published var currentMeasurementResult: MeasurementResult?
}

struct PhotoMeasurementView: View {
    // View가 ViewModel을 생성하고 소유 → @StateObject
    @StateObject private var viewModel: PhotoMeasurementViewModel

    init(item: ClothingItemModel, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: PhotoMeasurementViewModel(
            item: item,
            modelContext: modelContext
        ))
    }

    var body: some View {
        // viewModel.measurementAnchors 변경 시 UI 자동 업데이트 ✅
    }
}
```

**❌ 잘못된 사용**
```swift
struct PhotoMeasurementView: View {
    // ❌ ObservableObject를 @State로 선언하면 @Published 변경을 감지하지 못함!
    @State private var viewModel: PhotoMeasurementViewModel?

    var body: some View {
        // viewModel.measurementAnchors 변경해도 UI 업데이트 안 됨 ❌
    }
}
```

##### 일반적인 실수와 해결 방법

**문제 1: UI가 업데이트되지 않음**
```swift
// 증상: 백엔드 로그에는 데이터 변경이 보이지만 UI는 그대로
✅ [Backend] 앵커 추가됨 - 총 개수: 1
❌ [UI] anchors.count: 0  // UI가 업데이트 안 됨!

// 원인: @State로 ObservableObject 선언
@State private var viewModel: PhotoMeasurementViewModel?

// 해결: @StateObject로 변경
@StateObject private var viewModel: PhotoMeasurementViewModel
```

**문제 2: 초기화 패턴 혼동**
```swift
// ❌ 잘못된 패턴: 지연 초기화
@State private var viewModel: PhotoMeasurementViewModel?

init(item: ClothingItemModel) {
    self.item = item
}

var body: some View {
    if viewModel != nil {
        mainContent
    } else {
        ProgressView()
            .onAppear {
                self.viewModel = PhotoMeasurementViewModel(...)
            }
    }
}

// ✅ 올바른 패턴: init에서 StateObject 초기화
@StateObject private var viewModel: PhotoMeasurementViewModel

init(item: ClothingItemModel, modelContext: ModelContext) {
    _viewModel = StateObject(wrappedValue: PhotoMeasurementViewModel(
        item: item,
        modelContext: modelContext
    ))
}

var body: some View {
    mainContent  // 즉시 사용 가능
}
```

##### 디버깅 방법론

1. **로그 분석으로 불일치 발견**
   ```
   ✅ [Backend] 앵커 추가됨 - 총 개수: 1
   ❌ [UI] anchors.count: 0
   → 백엔드 데이터와 UI 데이터의 불일치 발견
   ```

2. **테스트 마커 활용**
   - 오버레이 자체는 렌더링되는지 확인 (테스트용 원 표시)
   - 렌더링이 되면 → 데이터 바인딩 문제
   - 렌더링이 안 되면 → UI 구조 문제

3. **코드 검토**
   ```swift
   // 의심스러운 패턴 찾기
   @State private var viewModel: PhotoMeasurementViewModel?  // ⚠️

   final class PhotoMeasurementViewModel: ObservableObject {  // ObservableObject!
       @Published var measurementAnchors: [MeasurementAnchor] = []  // @Published!
   }
   ```

4. **가설 검증**
   - SwiftUI 문서 확인: `@State`는 값 타입용, `@StateObject`는 ObservableObject용
   - 결론: `@State`가 `@Published` 변경을 감지하지 못하는 것이 원인

##### 참고: 관련 이슈 문서

이 가이드는 실제 발생한 버그를 기반으로 작성되었습니다:
- **이슈**: [ISSUE/2025-11-06-사진측정UI렌더링문제.md](./ISSUE/2025-11-06-사진측정UI렌더링문제.md)
- **증상**: 측정 포인트, 연결선, 거리 값이 화면에 표시되지 않음
- **근본 원인**: `@State`로 ObservableObject 선언
- **해결**: `@StateObject`로 변경 후 정상 작동

---

#### 9. ISSUE 문서 작성 가이드

**중요한 버그나 기술적 문제를 해결했을 때는 반드시 ISSUE 폴더에 문서를 작성하여 향후 참고 자료로 남겨야 합니다.**

##### 파일명 규칙

```
YYYY-MM-DD-이슈내용.md

예시:
- 2025-11-06-사진측정UI렌더링문제.md
- 2025-11-03-평면투영정확도개선.md
- 2025-10-30-네비게이션탭이벤트버그.md
```

**규칙:**
- 날짜: `YYYY-MM-DD` 형식 (해결 완료 날짜)
- 이슈내용: **20자 이내**로 핵심만 간결하게
- 띄어쓰기 없이 작성 (가독성을 위해)
- 한글 사용 가능

##### 문서 구조 템플릿

```markdown
# [이슈 제목]

**날짜**: YYYY년 MM월 DD일
**상태**: ✅ 해결 완료 / ⏳ 진행 중 / ❌ 미해결
**심각도**: Critical / High / Medium / Low
**영향 범위**: [영향받은 주요 컴포넌트]

---

## 문제 현상

### 증상
- [사용자가 겪는 문제 상황을 구체적으로 기술]
- [스크린샷이 있다면 포함]

### 백엔드 로그 분석 (해당되는 경우)
```
[관련 로그 내용]
```

- **백엔드**: [백엔드 동작 상태]
- **UI**: [UI 동작 상태]
- **결론**: [로그에서 발견한 핵심 단서]

---

## 근본 원인

### 잘못된 코드 (파일명:줄번호)

```swift
// ❌ 잘못된 코드
[문제가 있는 코드]
```

### 문제점

**[기술적 개념 설명]:**
- [왜 이 코드가 문제인지]
- [어떤 원리로 작동하지 않는지]

### 왜 작동하지 않았나?

1. [단계별로 문제 발생 과정 설명]
2. [...]
3. **결과**: [최종적으로 나타난 문제]

---

## 해결 방법

### 1. [파일명] 수정

```swift
// Before ❌
[수정 전 코드]

// After ✅
[수정 후 코드]
```

**변경 사항 설명:**
- [무엇을 어떻게 바꿨는지]
- [왜 이렇게 바꾸면 해결되는지]

### 2. [파일명2] 수정 (필요시)

[...]

---

## 원인을 찾은 방법

### 1. [디버깅 단계 1]
[무엇을 했고, 무엇을 발견했는지]

**핵심 단서**: [이 단계에서 발견한 중요한 정보]

### 2. [디버깅 단계 2]
[...]

### 3. [...]

---

## 교훈

### [기술적 개념] 가이드

[이번 이슈를 통해 배운 기술적 개념이나 Best Practice]

**핵심 원칙:**
- [...]
- [...]

---

## 영향 받은 파일

### 수정된 파일
1. `파일경로` - [변경 내용]
2. `파일경로` - [변경 내용]

### 테스트 결과
- ✅ [테스트 항목 1]
- ✅ [테스트 항목 2]

---

## 참고 자료

### 관련 파일 위치
- `/경로/파일명.swift:줄번호`

### 관련 로그
- [중요한 로그 내용이나 파일 경로]

### 참고 문서
- [Apple 공식 문서 링크]
- [Stack Overflow 답변 링크]
```

##### 작성 시 주의사항

1. **문제 현상은 구체적으로**
   - "안 된다"가 아니라 "어떤 상황에서 어떤 증상이 발생하는지" 명확히 작성
   - 로그가 있다면 반드시 포함 (핵심 부분만)

2. **근본 원인은 기술적으로**
   - "잘못됐다"가 아니라 "왜 잘못됐는지" 기술적 원리를 설명
   - 코드 예시는 Before/After 형식으로 비교

3. **디버깅 과정은 단계별로**
   - 어떤 순서로 문제를 추적했는지 재현 가능하게 작성
   - 각 단계에서 발견한 핵심 단서를 명시

4. **교훈은 재사용 가능하게**
   - 이번 경험을 통해 배운 원칙을 일반화
   - 향후 비슷한 문제를 예방할 수 있는 가이드라인 제시

5. **파일 위치는 정확하게**
   - 상대 경로 사용
   - 줄번호 포함 (예: `PhotoMeasurementView.swift:22`)

##### 실제 예시

실제로 작성된 이슈 문서 예시:
- [ISSUE/2025-11-06-사진측정UI렌더링문제.md](./ISSUE/2025-11-06-사진측정UI렌더링문제.md)

이 문서는 위 템플릿을 따라 작성되었으며, 다음 내용을 포함합니다:
- @State vs @StateObject 사용 오류
- 로그 분석을 통한 데이터 불일치 발견
- 5단계 디버깅 과정
- SwiftUI 속성 래퍼 선택 가이드

---

#### 10. Git 작업 규칙

**중요**: 다음 Git 작업은 사용자의 **명시적 요청이 있을 때만** 수행합니다.

**절대 자동으로 실행하지 말 것**:
- `git push` (원격 저장소로 푸시)
- `git push origin [branch]`
- `git push --force` (강제 푸시)
- `git push --force-with-lease`

**허용되는 Git 작업** (자동 실행 가능):
- `git status` - 현재 상태 확인
- `git diff` - 변경 사항 확인
- `git log` - 커밋 히스토리 확인
- `git add` - 스테이징 영역에 파일 추가
- `git commit` - 로컬 커밋 생성
- `git branch` - 브랜치 확인/생성

**규칙 요약**:
1. 로컬 커밋(`git commit`)까지는 사용자 요청 시 자동으로 수행 가능
2. 원격 푸시(`git push`)는 **반드시 사용자가 명시적으로 요청한 경우에만** 수행
3. 작업 완료 후 "커밋까지 완료했습니다. 푸시하시겠습니까?" 같은 확인 질문 금지
4. 사용자가 "푸시해줘", "원격에 올려줘" 등 명확하게 요청할 때만 푸시

**예시**:
```bash
# ✅ 허용 - 로컬 커밋
git add .
git commit -m "새 기능 추가"

# ❌ 금지 - 사용자 명시적 요청 없이 자동 푸시
git push origin main

# ✅ 허용 - 사용자가 "푸시해줘"라고 명시적으로 요청한 경우에만
git push origin main
```

---

## 참고 자료

### Apple 공식 문서
- [ARKit Documentation](https://developer.apple.com/documentation/arkit)
- [RealityKit Documentation](https://developer.apple.com/documentation/realitykit)
- [Vision Framework](https://developer.apple.com/documentation/vision)
- [Core ML](https://developer.apple.com/documentation/coreml)
- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)

### 샘플 코드
- [Creating a Fog Effect Using Scene Depth](https://developer.apple.com/documentation/arkit/creating_a_fog_effect_using_scene_depth)
- [Visualizing a Point Cloud Using Scene Depth](https://developer.apple.com/documentation/arkit/arkit_in_ios/environmental_analysis/visualizing_a_point_cloud_using_scene_depth)

### 관련 기술
- [MVVM Pattern in SwiftUI](https://www.avanderlee.com/swiftui/mvvm-pattern/)
- [Clean Architecture in iOS](https://tech.olx.com/clean-architecture-and-mvvm-on-ios-c9d167d9f5b3)
- [LiDAR Technology](https://en.wikipedia.org/wiki/Lidar)

---

## 프로젝트 문서

모든 프로젝트 관련 문서는 **[DOC/](./DOC/)** 폴더에 정리되어 있습니다.

### ML 학습 데이터 수집 가이드 🆕
- **[ML_DATA_COLLECTION_GUIDE.md](./DOC/ML_DATA_COLLECTION_GUIDE.md)** - ML 학습 데이터 수집 실무 가이드
  - 빠른 시작 (5분)
  - 상세 데이터 수집 절차
  - 품질 관리 및 모범 사례
  - 데이터 수집 시나리오 (빠른/고품질/특정 타입)
  - 문제 해결 및 FAQ

- **[ML_DATA_COLLECTION_QUICK_REFERENCE.md](./DOC/ML_DATA_COLLECTION_QUICK_REFERENCE.md)** - 빠른 참조 카드 (인쇄용)
  - 체크리스트 형식
  - 터미널 명령어 모음
  - 일일 목표 트래커
  - 품질 지표 빠른 참조

- **[ML_DATA_COLLECTION_TEST_GUIDE.md](./DOC/ML_DATA_COLLECTION_TEST_GUIDE.md)** - 데이터 수집 테스트 가이드
  - 테스트 시나리오
  - 데이터 확인 방법
  - 문제 해결
  - 체크리스트

- **[CORE_ML_INTEGRATION_GUIDE.md](./DOC/CORE_ML_INTEGRATION_GUIDE.md)** - Core ML 모델 통합 가이드
  - Vision + Core ML 하이브리드 접근법
  - 모델 학습 워크플로우
  - 성능 최적화

### 개발 도구 문서
- **[IOS_DEVICE_GUIDE.md](./DOC/IOS_DEVICE_GUIDE.md)** - iOS 디바이스 빌드 및 디버깅 완전 가이드
  - CLI 기반 자동화 도구 사용법
  - 디바이스 연결 및 배포 방법
  - 로그 수집 및 크래시 분석
  - 성능 프로파일링
  - 다른 프로젝트에 적용하기

### 측정 시스템 분석
- **[LIVE_DEBUG_ANALYSIS.md](./DOC/LIVE_DEBUG_ANALYSIS.md)** - 라이브 디버깅 및 교정 시스템 설계 문서
  - 현재 측정 시스템 완전 분석 (ARMeasurementService, DepthDataProcessor, MeasurementCalculator, PhotoMeasurementCalculator)
  - 하드코딩된 임계값 전체 목록 (30+ 파라미터, 8개 카테고리)
  - 런타임 설정 관리자 아키텍처
  - 교정 워크플로우 UI 설계 (5단계)
  - 구현 계획 (7-10일)
  - 워크플로우 예시 (반바지 기준 교정, 라이브 임계값 조정, BFS 알고리즘 실험)

### 진행 상황
- **[PROGRESS.md](./PROGRESS.md)** - 개발 진행 상황 및 최신 업데이트
  - Phase별 완료 항목
  - 최신 작업 내용
  - 다음 작업 예정 사항
  - 기술적 이슈 및 해결 과정

- **[IMPLEMENTATION_SUMMARY_20251110.md](./IMPLEMENTATION_SUMMARY_20251110.md)** - ML 시스템 구현 완료 보고서 🆕
  - 키포인트 자동 감지 시스템
  - Core ML 통합 및 VisionMLService
  - ML 학습 데이터 수집 시스템
  - 실시간 피드백 UI
  - 학습 워크플로우 스크립트
  - 빌드 성공 및 테스트 준비 완료

---

**마지막 업데이트**: 2025년 12월 2일
**문서 버전**: 1.6.0

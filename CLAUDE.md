# ClothIQ - 의류 측정 iOS 앱

## 프로젝트 개요

LiDAR 센서를 활용하여 의류의 각 부위별 사이즈를 정확하게 측정하는 iOS 네이티브 애플리케이션입니다. ARKit과 Vision Framework를 활용하여 3D 깊이 정보 기반의 실측 데이터를 제공하며, 촬영한 의류 이미지와 측정값을 로컬에 저장하여 관리합니다.

---

## 목차

1. [핵심 기능](#핵심-기능)
2. [기술 스택](#기술-스택)
3. [시스템 요구사항](#시스템-요구사항)
4. [아키텍처](#아키텍처)
5. [프로젝트 구조](#프로젝트-구조)
6. [데이터 모델](#데이터-모델)
7. [측정 항목 정의](#측정-항목-정의)
8. [개발 가이드라인](#개발-가이드라인)
9. [Phase별 개발 계획](#phase별-개발-계획)
10. [향후 확장 계획](#향후-확장-계획)

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
- Vision Framework를 활용한 배경 분리
- 의류 영역만 추출하여 저장
- 수동 보정 기능 제공
- 고품질 이미지 압축 및 최적화

### 4. 데이터 관리
- SwiftData를 활용한 로컬 데이터베이스
- 촬영 이미지는 파일 시스템에 저장 (성능 최적화)
- 측정 히스토리 및 통계 제공
- 태그 및 카테고리 기반 검색

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

---

## Phase별 개발 계획

### Phase 1: MVP (4-6주)
**목표**: 기본 측정 기능 구현 및 로컬 저장

#### 주요 기능
1. **AR 측정 기능**
   - LiDAR 기반 거리 측정
   - 수동 포인트 지정
   - 참조 객체 스케일 보정

2. **의류 타입 선택**
   - 5가지 기본 타입 지원
   - 타입별 필수 측정 항목 표시

3. **데이터 저장**
   - SwiftData를 활용한 로컬 저장
   - 이미지 파일 시스템 저장
   - 측정 히스토리

4. **기본 UI**
   - AR 카메라 뷰
   - 측정 결과 표시
   - 라이브러리 목록

#### 기술적 구현
- ARKit Scene Depth API 통합
- SwiftData 스키마 설계 및 구현
- MVVM 아키텍처 기본 구조
- 파일 시스템 매니저

#### 성공 지표
- LiDAR로 ±2cm 오차 범위 내 측정
- 측정 데이터 100% 저장 성공
- 앱 크래시 없음

---

### Phase 2: 자동화 및 고도화 (4-6주)
**목표**: AI/ML 통합 및 사용성 개선

#### 주요 기능
1. **자동 의류 인식**
   - Vision Framework 객체 감지
   - Core ML 의류 분류 모델
   - 자동 타입 선택

2. **배경 제거**
   - VNGenerateForegroundInstanceMaskRequest
   - 자동 배경 분리
   - 수동 보정 기능

3. **측정 포인트 자동 감지**
   - 의류 윤곽 감지
   - 주요 포인트 자동 마킹
   - 사용자 확인 및 조정

4. **측정 가이드**
   - 촬영 각도 안내
   - 조명 조건 체크
   - 실시간 피드백

#### 기술적 구현
- Core ML 모델 학습 및 통합
- Vision Framework 고급 기능
- 실시간 이미지 처리 파이프라인
- UX 최적화

#### 성공 지표
- 의류 타입 자동 인식 정확도 85%+
- 배경 제거 품질 만족도 80%+
- 측정 시간 50% 단축

---

### Phase 3: 사용성 및 안정성 (3-4주)
**목표**: 버그 수정, 최적화, 테스트

#### 주요 작업
1. **성능 최적화**
   - 메모리 사용량 최적화
   - AR 세션 배터리 소모 개선
   - 이미지 압축 및 캐싱

2. **에러 처리**
   - 모든 에러 시나리오 대응
   - 사용자 친화적 에러 메시지
   - 자동 복구 메커니즘

3. **테스트**
   - 단위 테스트 작성 (커버리지 70%+)
   - UI 테스트
   - 베타 테스트

4. **문서화**
   - DocC API 문서 완성
   - 사용자 가이드 작성
   - 개발자 문서 정리

#### 성공 지표
- 테스트 커버리지 70% 달성
- 크리티컬 버그 0건
- 앱 크래시율 0.1% 미만

---

### Phase 4: 출시 준비 (2-3주)
**목표**: App Store 출시 및 마케팅 준비

#### 주요 작업
1. **App Store 준비**
   - 앱 아이콘 및 스크린샷
   - 설명 및 키워드 최적화
   - 개인정보 처리방침

2. **다국어 지원**
   - 한국어/영어 기본 지원
   - Localizable.strings 완성

3. **접근성**
   - VoiceOver 지원
   - Dynamic Type
   - 색상 대비

4. **출시 마케팅**
   - 프로모션 비디오
   - 보도자료
   - SNS 홍보

---

## 향후 확장 계획

### 서버 연동 (Phase 5+)

#### 백엔드 아키텍처
```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│  iOS Client  │ ←────→  │  REST API    │ ←────→  │  Database    │
│              │  HTTPS  │  (FastAPI)   │         │  (PostgreSQL)│
└──────────────┘         └──────────────┘         └──────────────┘
                                ↓
                         ┌──────────────┐
                         │  ML Service  │
                         │  (Python)    │
                         └──────────────┘
                                ↓
                         ┌──────────────┐
                         │   S3/Cloud   │
                         │   Storage    │
                         └──────────────┘
```

#### 주요 기능
1. **클라우드 동기화**
   - 멀티 디바이스 데이터 동기화
   - iCloud 또는 자체 백엔드
   - 충돌 해결 전략

2. **ML 모델 업데이트**
   - 서버에서 최신 모델 배포
   - A/B 테스트
   - 점진적 롤아웃

3. **사용자 피드백**
   - 측정 결과 평가
   - 모델 재학습 데이터 수집
   - Federated Learning 적용

4. **소셜 기능**
   - 측정 데이터 공유
   - 커뮤니티 평균 비교
   - 추천 사이즈 제안

#### API 엔드포인트 (예시)
```
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh
GET    /api/v1/clothing/items
POST   /api/v1/clothing/items
PUT    /api/v1/clothing/items/{id}
DELETE /api/v1/clothing/items/{id}
POST   /api/v1/measurements
GET    /api/v1/models/latest
POST   /api/v1/feedback
```

#### 보안 고려사항
- OAuth 2.0 인증
- JWT 토큰 기반 세션
- HTTPS 필수
- 이미지 E2E 암호화
- GDPR/개인정보보호법 준수

---

### 추가 기능 아이디어

#### 1. 가상 피팅
- AR로 의류 3D 모델 생성
- 바디 스캔과 매칭
- 착용 시뮬레이션

#### 2. 쇼핑 연동
- 온라인 쇼핑몰 사이즈 매칭
- 맞춤 사이즈 추천
- 구매 링크 제공

#### 3. 의류 관리
- 세탁 방법 안내
- 보관 팁
- 계절별 추천

#### 4. 통계 및 분석
- 의류 착용 빈도
- 사이즈 변화 추적
- 구매 패턴 분석

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

**마지막 업데이트**: 2025년 10월 22일
**문서 버전**: 1.0.0

# ClothIQ - 라이브 디버깅 시스템 분석 및 설계

## 📋 목차
1. [현재 측정 시스템 분석](#현재-측정-시스템-분석)
2. [하드코딩된 임계값 목록](#하드코딩된-임계값-목록)
3. [라이브 디버깅 가능성 평가](#라이브-디버깅-가능성-평가)
4. [제안 아키텍처](#제안-아키텍처)
5. [구현 계획](#구현-계획)
6. [워크플로우 예시](#워크플로우-예시)

---

## 현재 측정 시스템 분석

### 1. ARMeasurementService
**위치**: `Features/Measurement/Data/Services/ARMeasurementService.swift`

**주요 기능**:
- LiDAR 측정 포인트 추출 (`extractMeasurementPoint`)
- 환경 평가 (`assessEnvironment`)
  - 깊이 데이터 품질
  - 추적 상태 (normal, limited, notAvailable)
  - 조명 조건 (500~2000 lumens)
- 카메라 정렬 계산 (`calculateCameraAlignment`)
  - 평면 법선 벡터와 카메라 forward 벡터 각도 계산
  - 카메라-평면 거리 계산

**핵심 알고리즘**:
```swift
// 화면 좌표 → 깊이 맵 좌표 변환
let scaleX = depthMapSize.width / imageResolution.width
let scaleY = depthMapSize.height / imageResolution.height

// 0~1 범위로 정규화
let normalizedPoint = CGPoint(
    x: depthMapPoint.x / depthMapSize.width,
    y: depthMapPoint.y / depthMapSize.height
)
```

### 2. DepthDataProcessor
**위치**: `Features/Measurement/Data/Services/DepthDataProcessor.swift`

**주요 기능**:
- 깊이 맵 샘플링 (`extractDepth`)
- 신뢰도 맵 처리 (`extractConfidence`)
- 3D 월드 좌표 계산 (`calculateWorldPosition`)
  - **카메라 intrinsics 사용** (핀홀 카메라 모델)
  - `fx, fy, cx, cy` 파라미터로 정확한 3D 좌표 계산
- 깊이 품질 평가 (`assessDepthQuality`)

**핵심 알고리즘** (카메라 intrinsics 기반 좌표 변환):
```swift
// 카메라 좌표계에서 3D 위치 계산
let x = (Float(imagePoint.x) - cx) * depth / fx
let y = (Float(imagePoint.y) - cy) * depth / fy
let z = -depth  // ARKit은 카메라가 -Z 방향을 바라봄

// 카메라 좌표계 → 월드 좌표계 변환
let worldPosition4 = cameraTransform * SIMD4<Float>(cameraSpacePosition, 1.0)
```

### 3. MeasurementCalculator
**위치**: `Features/Measurement/Data/Services/MeasurementCalculator.swift`

**주요 기능**:
- 유클리드 거리 계산 (`calculateDistance`)
- 각도 보정 거리 (`calculateCorrectedDistance`)
- 수평면 투영 거리 (`calculateHorizontalDistance`)
- **평면 투영 기반 거리** (`calculateDistanceOnPlane`)
  - PlaneEstimator로 평면 추정 (Least Squares)
  - 두 포인트를 평면에 투영
  - 투영된 포인트 간 거리 계산
- 둘레 계산 (`calculateCircumference`, `calculateCircumferenceFromFront`)
  - 타원 근사 공식 사용 (Ramanujan 공식)
- 타입별 검증 (`validateMeasurement`)
- 보정 알고리즘 (`calibrate`, `depthCorrectionFactor`)

**핵심 알고리즘** (타원 둘레):
```swift
// Ramanujan의 타원 둘레 근사 공식
let h = pow((a - b), 2) / pow((a + b), 2)
let circumference = π * (a + b) * (1 + (3 * h) / (10 + sqrt(4 - 3 * h)))
```

### 4. PhotoMeasurementCalculator
**위치**: `Features/ClothingLibrary/Domain/UseCases/PhotoMeasurementCalculator.swift`

**주요 기능**:
- 저장된 depth map 사용
- 2D 이미지 좌표 → 3D 월드 좌표 변환
  - intrinsics 우선 사용
  - 없으면 FOV 기반 추정
- **평면 투영 거리 계산**
  - 두 포인트의 평균 Z 깊이를 기준 평면으로 사용
  - Z축 차이 무시 (의류가 평평하게 놓인 가정)

**핵심 알고리즘**:
```swift
// 평면 투영: 평균 Z 깊이 기준
let avgZ = (pos1.z + pos2.z) / 2.0

// 각 포인트를 기준 평면에 투영
let projected1 = SIMD3<Float>(pos1.x, pos1.y, avgZ)
let projected2 = SIMD3<Float>(pos2.x, pos2.y, avgZ)

// 투영된 평면상의 거리
let distanceProjected = simd_distance(projected1, projected2)
```

---

## 하드코딩된 임계값 목록

### 1. 신뢰도 임계값
| 임계값 | 값 | 위치 | 설명 |
|-------|-----|------|------|
| 최소 신뢰도 | 0.6 | `MeasurementCalculator.validateCandidateConfidence` | 포인트 감지 최소 신뢰도 |
| 낮은 신뢰도 경고 | 0.7 | `MeasurementCalculator.validateCandidateConfidence` | 경고 표시 임계값 |
| 매우 낮은 신뢰도 | 0.4 | `MeasurementCalculator.validateCandidateConfidence` | 거부 임계값 |
| 기본 신뢰도 | 0.7 | `DepthDataProcessor.extractConfidence` | confidenceMap이 없을 때 기본값 |

### 2. 거리 범위 (센티미터)
| 측정 타입 | 최소값 | 최대값 | 위치 |
|----------|--------|--------|------|
| 어깨너비 | 30.0 | 60.0 | `MeasurementCalculator.getReasonableRange` |
| 가슴둘레 | 70.0 | 150.0 | `MeasurementCalculator.getReasonableRange` |
| 총길이 | 40.0 | 100.0 | `MeasurementCalculator.getReasonableRange` |
| 소매길이 | 15.0 | 80.0 | `MeasurementCalculator.getReasonableRange` |
| 팔둘레 | 20.0 | 50.0 | `MeasurementCalculator.getReasonableRange` |
| 허리둘레 | 50.0 | 150.0 | `MeasurementCalculator.getReasonableRange` |
| 밑위 | 20.0 | 40.0 | `MeasurementCalculator.getReasonableRange` |
| 밑단 | 30.0 | 60.0 | `MeasurementCalculator.getReasonableRange` |
| 허벅지둘레 | 40.0 | 80.0 | `MeasurementCalculator.getReasonableRange` |

### 3. 깊이 품질 평가
| 파라미터 | 값 | 위치 | 설명 |
|---------|-----|------|------|
| 최소 커버리지 | 0.2 (20%) | `DepthDataProcessor.assessDepthQuality` | 유효 픽셀 비율 |
| 중간 커버리지 | 0.1 (10%) | `DepthDataProcessor.assessDepthQuality` | 경고 수준 |
| 유효 깊이 범위 | > 0, isFinite | `DepthDataProcessor.extractDepth` | 유효한 깊이 값 조건 |

### 4. 최적 측정 거리 (미터)
| 범위 | 값 | 위치 | 설명 |
|------|-----|------|------|
| 최적 최소 거리 | 0.7 | `MeasurementCalculator.depthCorrectionFactor` | 최적 범위 시작 |
| 최적 최대 거리 | 1.0 | `MeasurementCalculator.depthCorrectionFactor` | 최적 범위 끝 |
| 너무 가까움 보정 | 0.95 ~ 1.0 | `MeasurementCalculator.depthCorrectionFactor` | 축소 보정 |
| 너무 멈 보정 | 1.0 ~ 1.2 | `MeasurementCalculator.depthCorrectionFactor` | 확대 보정 |

### 5. 평면 투영
| 파라미터 | 값 | 위치 | 설명 |
|---------|-----|------|------|
| 샘플 개수 | 100 | `MeasurementCalculator.calculateDistanceOnPlane` | 평면 추정 샘플링 수 |
| 최소 영역 크기 | 0.2 (20%) | `MeasurementCalculator.calculateDistanceOnPlane` | 샘플링 영역 최소 크기 |
| 허용 오차 | 50% | `MeasurementCalculator.calculateDistanceOnPlane` | 직접 거리와 비교 |

### 6. PhotoMeasurement 신뢰도
| 파라미터 | 값 | 위치 | 설명 |
|---------|-----|------|------|
| 유효 깊이 최소 | 0.2 m | `PhotoMeasurementCalculator.calculateConfidence` | 유효 깊이 범위 시작 |
| 유효 깊이 최대 | 5.0 m | `PhotoMeasurementCalculator.calculateConfidence` | 유효 깊이 범위 끝 |
| 최대 깊이 차이 | 2.0 m | `PhotoMeasurementCalculator.calculateConfidence` | 두 포인트 간 최대 차이 |
| 최대 신뢰도 | 0.85 | `PhotoMeasurementCalculator.calculateConfidence` | 사진 기반 측정 최대 신뢰도 |
| 유효 깊이 범위 | < 10.0 m | `PhotoMeasurementCalculator.extractDepth` | 비정상 깊이 필터링 |

### 7. 환경 평가 (ARMeasurementService)
| 조명 범위 (lumens) | 점수 | 설명 |
|-------------------|------|------|
| 1000 ~ 1500 | 1.0 | 이상적 |
| 500 ~ 1000, 1500 ~ 2000 | 0.8 | 양호 |
| 300 ~ 500, 2000 ~ 3000 | 0.6 | 허용 |
| < 300 | 0.3 | 너무 어두움 |
| > 3000 | 0.5 | 너무 밝음 |

### 8. 타원 둘레 계산 (타입별 깊이 비율)
| 측정 타입 | 깊이/너비 비율 | 설명 |
|----------|---------------|------|
| 가슴둘레 | 0.65 | 타원형 |
| 허리둘레 | 0.55 | 납작한 타원 |
| 허벅지둘레 | 0.85 | 원에 가까움 |
| 팔둘레 | 0.90 | 거의 원형 |
| 기본값 | 0.70 | 일반 타원 |

---

## 라이브 디버깅 가능성 평가

### ✅ 완전히 가능합니다!

현재 시스템은 다음과 같은 특징으로 인해 **라이브 디버깅 및 교정 시스템 구현이 용이**합니다:

1. **명확한 레이어 분리**
   - Service 레이어 (ARMeasurementService, DepthDataProcessor)
   - Calculator 레이어 (MeasurementCalculator, PhotoMeasurementCalculator)
   - 각 레이어의 임계값을 런타임에 주입 가능

2. **프로토콜 기반 설계**
   - `ARMeasurementServiceProtocol` 존재
   - Mock 서비스 제공 (`MockARMeasurementService`)
   - 런타임 파라미터 주입 용이

3. **이미 존재하는 디버그 인프라**
   - `DepthVisualizationView` - 깊이 데이터 시각화
   - `MeasurementGuideOverlay` - 측정 가이드
   - `CameraAlignmentGuide` - 카메라 정렬 가이드
   - 이를 확장하여 라이브 디버깅 UI 구현 가능

4. **보정 메커니즘 존재**
   - `calibrate()` 함수: 참조 객체 기반 보정
   - `depthCorrectionFactor()`: 거리 기반 보정
   - 교정 데이터 저장 구조만 추가하면 됨

---

## 제안 아키텍처

### 1. 새로운 데이터 모델

```swift
// MARK: - 교정 설정 모델
@Model
final class CalibrationProfile {
    var id: UUID
    var name: String  // "반바지 기준", "긴팔 기준" 등
    var createdAt: Date
    var updatedAt: Date

    // 신뢰도 임계값
    var minConfidence: Float = 0.6
    var lowConfidenceWarning: Float = 0.7
    var veryLowConfidence: Float = 0.4

    // 깊이 품질
    var minDepthCoverage: Float = 0.2
    var midDepthCoverage: Float = 0.1

    // 최적 측정 거리
    var optimalMinDistance: Float = 0.7
    var optimalMaxDistance: Float = 1.0

    // 평면 투영
    var planeSampleCount: Int = 100
    var planeErrorTolerance: Float = 0.5  // 50%

    // 타입별 거리 범위 (JSON으로 저장)
    var measurementRanges: Data  // [MeasurementType: (min, max)]

    // 교정 계수
    var calibrationFactors: [CalibrationFactor]
}

@Model
final class CalibrationFactor {
    var id: UUID
    var clothingType: String
    var measurementType: String

    // 실측값
    var actualValue: Double  // cm

    // 측정값
    var measuredValue: Double  // cm

    // 보정 계수 (자동 계산)
    var correctionFactor: Double  // = actualValue / measuredValue

    // 측정 횟수
    var sampleCount: Int = 1

    // 평균 측정값 (여러 번 측정한 경우)
    var averageMeasured: Double

    // 표준편차
    var stdDeviation: Double?

    var createdAt: Date
}
```

### 2. 런타임 설정 관리자

```swift
// MARK: - 런타임 측정 설정
class MeasurementSettings: ObservableObject {
    static let shared = MeasurementSettings()

    // 현재 활성 프로파일
    @Published var activeProfile: CalibrationProfile?

    // 디버그 모드
    @Published var isDebugMode: Bool = false

    // 실시간 조정 가능한 파라미터
    @Published var minConfidence: Float = 0.6
    @Published var minDepthCoverage: Float = 0.2
    @Published var optimalMinDistance: Float = 0.7
    @Published var optimalMaxDistance: Float = 1.0

    // 교정 활성화 여부
    @Published var useCalibration: Bool = false

    func applyProfile(_ profile: CalibrationProfile) {
        activeProfile = profile
        minConfidence = profile.minConfidence
        minDepthCoverage = profile.minDepthCoverage
        optimalMinDistance = profile.optimalMinDistance
        optimalMaxDistance = profile.optimalMaxDistance
    }

    func applyCorrectionFactor(
        type: MeasurementType,
        clothingType: ClothingType,
        value: Double
    ) -> Double {
        guard useCalibration,
              let profile = activeProfile else {
            return value
        }

        // 해당 타입의 보정 계수 찾기
        if let factor = profile.calibrationFactors.first(where: {
            $0.measurementType == type.rawValue &&
            $0.clothingType == clothingType.rawValue
        }) {
            return value * factor.correctionFactor
        }

        return value
    }
}
```

### 3. 라이브 디버깅 UI 컴포넌트

```swift
// MARK: - 라이브 디버깅 오버레이
struct LiveDebugOverlay: View {
    @ObservedObject var settings = MeasurementSettings.shared
    @ObservedObject var viewModel: MeasurementViewModel

    @State private var showSettings = false

    var body: some View {
        ZStack {
            // AR 카메라 뷰 (기존)
            ARViewContainer()

            // 디버그 정보 오버레이
            if settings.isDebugMode {
                VStack {
                    // 상단: 실시간 메트릭
                    DebugMetricsPanel(viewModel: viewModel)

                    Spacer()

                    // 하단: 임계값 조정 슬라이더
                    if showSettings {
                        DebugSettingsPanel(settings: settings)
                            .transition(.move(edge: .bottom))
                    }

                    // 설정 토글 버튼
                    Button {
                        withAnimation {
                            showSettings.toggle()
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding()
                }
            }

            // 깊이 맵 시각화 (토글)
            if settings.isDebugMode {
                DepthVisualizationView(frame: viewModel.currentFrame)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }

            // 측정 포인트 시각화
            MeasurementPointsOverlay(
                points: viewModel.detectedPoints,
                imageSize: viewModel.imageSize
            )
        }
    }
}

// MARK: - 실시간 메트릭 패널
struct DebugMetricsPanel: View {
    @ObservedObject var viewModel: MeasurementViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 환경 점수
            HStack {
                Text("환경 점수:")
                Spacer()
                Text("\(viewModel.environmentScore, specifier: "%.2f")")
                    .foregroundColor(scoreColor(viewModel.environmentScore))
            }

            // 깊이 품질
            HStack {
                Text("깊이 품질:")
                Spacer()
                Text("\(viewModel.depthQuality, specifier: "%.2f")")
                    .foregroundColor(scoreColor(viewModel.depthQuality))
            }

            // 카메라 거리
            if let distance = viewModel.cameraDistance {
                HStack {
                    Text("카메라 거리:")
                    Spacer()
                    Text("\(distance, specifier: "%.2f")m")
                        .foregroundColor(distanceColor(distance))
                }
            }

            // 감지된 포인트 수
            HStack {
                Text("감지된 포인트:")
                Spacer()
                Text("\(viewModel.detectedPoints.count)개")
            }

            // 현재 측정값 (있는 경우)
            if let currentMeasurement = viewModel.currentMeasurement {
                Divider()
                HStack {
                    Text("\(currentMeasurement.type.displayName):")
                    Spacer()
                    Text("\(currentMeasurement.value, specifier: "%.1f")cm")
                        .font(.headline)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
        .padding()
    }

    private func scoreColor(_ score: Float) -> Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .yellow
        default: return .red
        }
    }

    private func distanceColor(_ distance: Float) -> Color {
        if distance >= 0.7 && distance <= 1.0 {
            return .green
        } else if distance >= 0.5 && distance <= 1.2 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - 임계값 조정 패널
struct DebugSettingsPanel: View {
    @ObservedObject var settings: MeasurementSettings

    var body: some View {
        VStack(spacing: 16) {
            Text("실시간 임계값 조정")
                .font(.headline)

            // 최소 신뢰도
            VStack(alignment: .leading) {
                HStack {
                    Text("최소 신뢰도:")
                    Spacer()
                    Text("\(settings.minConfidence, specifier: "%.2f")")
                }
                Slider(value: $settings.minConfidence, in: 0.4...0.9, step: 0.05)
            }

            // 최소 깊이 커버리지
            VStack(alignment: .leading) {
                HStack {
                    Text("최소 깊이 커버리지:")
                    Spacer()
                    Text("\(settings.minDepthCoverage, specifier: "%.2f")")
                }
                Slider(value: $settings.minDepthCoverage, in: 0.1...0.5, step: 0.05)
            }

            // 최적 거리 (최소)
            VStack(alignment: .leading) {
                HStack {
                    Text("최적 거리 (최소):")
                    Spacer()
                    Text("\(settings.optimalMinDistance, specifier: "%.2f")m")
                }
                Slider(value: $settings.optimalMinDistance, in: 0.5...1.0, step: 0.05)
            }

            // 최적 거리 (최대)
            VStack(alignment: .leading) {
                HStack {
                    Text("최적 거리 (최대):")
                    Spacer()
                    Text("\(settings.optimalMaxDistance, specifier: "%.2f")m")
                }
                Slider(value: $settings.optimalMaxDistance, in: 0.8...1.5, step: 0.05)
            }

            Divider()

            // 교정 활성화 토글
            Toggle("교정 활성화", isOn: $settings.useCalibration)

            // 프로파일 선택
            if let profile = settings.activeProfile {
                HStack {
                    Text("현재 프로파일:")
                    Spacer()
                    Text(profile.name)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .padding()
    }
}
```

### 4. 교정 워크플로우 UI

```swift
// MARK: - 교정 워크플로우
struct CalibrationWorkflowView: View {
    @ObservedObject var viewModel: CalibrationViewModel
    @State private var actualValue: String = ""

    var body: some View {
        VStack(spacing: 20) {
            // 현재 단계 표시
            Text("단계 \(viewModel.currentStep)/5")
                .font(.headline)

            switch viewModel.currentStep {
            case 1:
                // 기준 샘플 선택
                SampleSelectionStep(viewModel: viewModel)
            case 2:
                // 실측값 입력
                ActualValueInputStep(
                    viewModel: viewModel,
                    actualValue: $actualValue
                )
            case 3:
                // AR 측정 수행
                ARMeasurementStep(viewModel: viewModel)
            case 4:
                // 결과 비교 및 확인
                ComparisonStep(
                    viewModel: viewModel,
                    actualValue: actualValue
                )
            case 5:
                // 교정 계수 저장
                SaveCalibrationStep(viewModel: viewModel)
            default:
                EmptyView()
            }

            // 다음/이전 버튼
            HStack {
                Button("이전") {
                    viewModel.previousStep()
                }
                .disabled(viewModel.currentStep == 1)

                Spacer()

                Button("다음") {
                    viewModel.nextStep()
                }
                .disabled(!viewModel.canProceed)
            }
            .padding()
        }
    }
}

// MARK: - 실측값 입력 단계
struct ActualValueInputStep: View {
    @ObservedObject var viewModel: CalibrationViewModel
    @Binding var actualValue: String

    var body: some View {
        VStack(spacing: 16) {
            Text("실측값 입력")
                .font(.title2)

            Text("자로 직접 측정한 실제 값을 입력해주세요.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // 측정 타입 표시
            HStack {
                Text("측정 항목:")
                Spacer()
                Text(viewModel.selectedMeasurementType.displayName)
                    .font(.headline)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // 실측값 입력
            HStack {
                TextField("실측값 (cm)", text: $actualValue)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                Text("cm")
                    .foregroundColor(.secondary)
            }

            // 입력 가이드
            Text("예: 어깨너비 45cm, 가슴둘레 98cm")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - 결과 비교 단계
struct ComparisonStep: View {
    @ObservedObject var viewModel: CalibrationViewModel
    let actualValue: String

    var body: some View {
        VStack(spacing: 20) {
            Text("측정 결과 비교")
                .font(.title2)

            // 실측값 vs 측정값
            HStack(spacing: 40) {
                VStack {
                    Text("실측값")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Text("\(actualValue) cm")
                        .font(.system(size: 36, weight: .bold))
                }

                Image(systemName: "arrow.left.arrow.right")
                    .font(.title)
                    .foregroundColor(.gray)

                VStack {
                    Text("측정값")
                        .font(.headline)
                        .foregroundColor(.green)
                    Text("\(viewModel.measuredValue, specifier: "%.1f") cm")
                        .font(.system(size: 36, weight: .bold))
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)

            // 오차 표시
            let error = abs(Double(actualValue) ?? 0 - viewModel.measuredValue)
            let errorPercent = (error / (Double(actualValue) ?? 1)) * 100

            VStack(spacing: 8) {
                HStack {
                    Text("오차:")
                    Spacer()
                    Text("\(error, specifier: "%.1f") cm")
                        .foregroundColor(errorColor(errorPercent))
                }

                HStack {
                    Text("오차율:")
                    Spacer()
                    Text("\(errorPercent, specifier: "%.1f")%")
                        .foregroundColor(errorColor(errorPercent))
                }

                HStack {
                    Text("보정 계수:")
                    Spacer()
                    Text("\(viewModel.correctionFactor, specifier: "%.4f")")
                        .font(.headline)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // 여러 번 측정 옵션
            Button("다시 측정하기") {
                viewModel.repeatMeasurement()
            }
            .buttonStyle(.bordered)

            if viewModel.measurementCount > 1 {
                Text("평균 \(viewModel.measurementCount)회 측정")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func errorColor(_ percent: Double) -> Color {
        switch percent {
        case 0..<5: return .green
        case 5..<10: return .yellow
        default: return .red
        }
    }
}
```

---

## 구현 계획

### Phase 1: 기본 인프라 (1-2일)
1. **MeasurementSettings 클래스 구현**
   - Singleton 패턴
   - @Published 프로퍼티로 실시간 업데이트
   - UserDefaults 저장/로드

2. **CalibrationProfile 모델 구현**
   - SwiftData @Model 추가
   - CRUD 작업 구현

3. **기존 코드 수정**
   - `MeasurementCalculator`에 런타임 파라미터 주입
   - `DepthDataProcessor`에 설정 적용
   - `ARMeasurementService`에 설정 연결

### Phase 2: 라이브 디버깅 UI (2-3일)
1. **LiveDebugOverlay 구현**
   - AR 뷰 위에 오버레이
   - 토글 가능한 디버그 모드

2. **DebugMetricsPanel 구현**
   - 실시간 메트릭 표시
   - 색상 코딩으로 상태 시각화

3. **DebugSettingsPanel 구현**
   - 슬라이더로 임계값 조정
   - 실시간 적용 및 테스트

4. **깊이 맵 히트맵 시각화**
   - 기존 `DepthVisualizationView` 확장
   - 토글 가능한 오버레이

### Phase 3: 교정 워크플로우 (2-3일)
1. **CalibrationViewModel 구현**
   - 5단계 워크플로우 관리
   - 실측값 vs 측정값 비교

2. **CalibrationWorkflowView 구현**
   - 단계별 UI
   - 실측값 입력 폼
   - 결과 비교 화면

3. **교정 데이터 저장**
   - CalibrationFactor 저장
   - 통계 계산 (평균, 표준편차)

4. **교정 적용**
   - MeasurementSettings에서 보정 계수 조회
   - 측정값에 자동 적용

### Phase 4: 통합 및 테스트 (1-2일)
1. **반바지 샘플 테스트**
   - 10회 측정 반복
   - 통계 분석

2. **교정 계수 검증**
   - 다른 의류 타입에 적용
   - 정확도 비교

3. **UI/UX 개선**
   - 햅틱 피드백
   - 애니메이션
   - 에러 처리

---

## 워크플로우 예시

### 시나리오 1: 반바지 기준 교정

```
1. [기준 샘플 선택]
   - 반바지 선택
   - 측정 타입: 허리둘레, 총길이, 밑위 등

2. [실측값 입력]
   - 자로 직접 측정: 허리둘레 78cm

3. [AR 측정 10회 반복]
   측정 1: 76.2 cm
   측정 2: 77.5 cm
   측정 3: 75.8 cm
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
   보정 적용: 82.3 × 1.0196 = 83.9 cm
```

### 시나리오 2: 라이브 임계값 조정

```
1. [디버그 모드 활성화]
   - 카메라 뷰에서 "디버그" 버튼 탭

2. [실시간 메트릭 확인]
   환경 점수: 0.75 (노란색)
   깊이 품질: 0.82 (녹색)
   카메라 거리: 0.65m (노란색 - 약간 가까움)
   감지된 포인트: 0개

3. [임계값 조정]
   최소 신뢰도: 0.6 → 0.5로 낮춤
   최소 깊이 커버리지: 0.2 → 0.15로 낮춤

4. [결과 확인]
   감지된 포인트: 4개 (어깨 좌/우, 밑단 좌/우)
   어깨너비: 45.2 cm (신뢰도 0.72)

5. [임계값 저장]
   현재 설정을 "낮은 조명 환경" 프로파일로 저장

6. [다음 촬영 시 적용]
   비슷한 환경에서 "낮은 조명 환경" 프로파일 로드
   자동으로 임계값 적용
```

### 시나리오 3: BFS 기반 거리 알고리즘 실험

```
1. [기존 알고리즘 성능 측정]
   - 유클리드 거리: 45.2 cm
   - 평면 투영 거리: 45.8 cm
   - 실측값: 46.0 cm
   - 오차: 0.2 cm (0.4%)

2. [BFS 기반 경로 탐색 구현]
   // 깊이 맵에서 두 포인트를 연결하는 표면 경로 탐색
   - 시작 포인트 (왼쪽 어깨)
   - BFS로 인접 픽셀 탐색 (깊이 차이 < 10cm)
   - 종료 포인트 (오른쪽 어깨) 도달
   - 경로 상의 거리 누적

3. [결과 비교]
   - BFS 표면 경로 거리: 46.3 cm
   - 평면 투영 거리: 45.8 cm
   - 실측값: 46.0 cm

   → BFS가 더 정확함 (오차 0.3 cm vs 0.2 cm)

4. [A* 휴리스틱 추가]
   // 유클리드 거리를 휴리스틱으로 사용
   - 탐색 속도 향상: 120ms → 45ms
   - 정확도 유지: 46.2 cm

5. [새 알고리즘 통합]
   MeasurementCalculator에 새 함수 추가:
   - calculateBFSDistance()
   - calculateAStarDistance()

6. [성능 비교]
   100회 측정 반복:
   - 평면 투영: 평균 오차 0.8 cm
   - BFS: 평균 오차 0.5 cm
   - A*: 평균 오차 0.5 cm (2배 빠름)
```

---

## 예상 효과

1. **측정 정확도 향상**
   - 보정 계수 적용으로 ±0.5cm 정확도 달성
   - 다양한 환경에서 안정적인 측정

2. **개발 효율성 증가**
   - 실시간 디버깅으로 빠른 문제 파악
   - 임계값 조정으로 즉시 결과 확인

3. **사용자 경험 개선**
   - 환경별 최적 프로파일 제공
   - 신뢰도 기반 피드백

4. **알고리즘 실험 용이**
   - BFS, A*, 헤밀턴 거리 등 다양한 알고리즘 테스트
   - 성능 비교 및 최적화

---

**작성일**: 2025-11-05
**작성자**: Claude Code Assistant
**버전**: 1.0

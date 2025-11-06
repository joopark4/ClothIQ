//
//  MeasurementSettings.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  런타임 측정 설정 관리자입니다.
//  실시간으로 조정 가능한 임계값 파라미터와 교정 프로파일을 관리합니다.
//
//  Key Responsibilities:
//  - 실시간 임계값 조정 (신뢰도, 깊이 품질, 최적 거리 등)
//  - 교정 프로파일 적용
//  - 보정 계수 적용
//  - 디버그 모드 관리
//

import Foundation
import Combine
import SwiftData

/// 런타임 측정 설정 관리자
///
/// Singleton 패턴으로 앱 전체에서 공유되는 측정 설정을 관리합니다.
/// @Published 프로퍼티를 통해 실시간 UI 업데이트를 지원합니다.
///
/// ## Topics
///
/// ### 디버그 모드
/// - ``isDebugMode``
///
/// ### 교정 프로파일
/// - ``activeProfile``
/// - ``useCalibration``
/// - ``applyProfile(_:)``
///
/// ### 실시간 임계값 조정
/// - ``minConfidence``
/// - ``minDepthCoverage``
/// - ``optimalMinDistance``
/// - ``optimalMaxDistance``
/// - ``lowConfidenceWarning``
/// - ``veryLowConfidence``
/// - ``midDepthCoverage``
///
/// ### 평면 투영 설정
/// - ``planeSampleCount``
/// - ``planeErrorTolerance``
///
/// ### 보정 계수 적용
/// - ``applyCorrectionFactor(type:clothingType:value:)``
///
final class MeasurementSettings: ObservableObject {

    // MARK: - Singleton

    static let shared = MeasurementSettings()

    private init() {
        loadFromUserDefaults()
    }

    // MARK: - Published Properties

    /// 현재 활성 교정 프로파일
    @Published var activeProfile: CalibrationProfile?

    /// 디버그 모드 활성화 여부
    ///
    /// true일 경우 라이브 디버깅 오버레이가 표시됩니다.
    @Published var isDebugMode: Bool = false {
        didSet { saveToUserDefaults() }
    }

    // MARK: - 실시간 조정 가능한 파라미터

    /// 최소 신뢰도 임계값
    ///
    /// 측정 포인트의 최소 신뢰도 값입니다.
    /// 이 값보다 낮은 신뢰도를 가진 측정 포인트는 무시됩니다.
    ///
    /// - 기본값: 0.6
    /// - 범위: 0.4 ~ 0.9
    @Published var minConfidence: Float = 0.6 {
        didSet { saveToUserDefaults() }
    }

    /// 낮은 신뢰도 경고 임계값
    ///
    /// 이 값보다 낮은 신뢰도는 경고 메시지를 표시합니다.
    ///
    /// - 기본값: 0.7
    @Published var lowConfidenceWarning: Float = 0.7 {
        didSet { saveToUserDefaults() }
    }

    /// 매우 낮은 신뢰도 임계값
    ///
    /// 이 값보다 낮은 신뢰도는 측정을 거부합니다.
    ///
    /// - 기본값: 0.4
    @Published var veryLowConfidence: Float = 0.4 {
        didSet { saveToUserDefaults() }
    }

    /// 최소 깊이 커버리지
    ///
    /// 측정 영역에서 유효한 깊이 데이터가 차지해야 하는 최소 비율입니다.
    ///
    /// - 기본값: 0.2 (20%)
    /// - 범위: 0.1 ~ 0.5
    @Published var minDepthCoverage: Float = 0.2 {
        didSet { saveToUserDefaults() }
    }

    /// 중간 깊이 커버리지
    ///
    /// 경고를 표시할 깊이 커버리지 임계값입니다.
    ///
    /// - 기본값: 0.1 (10%)
    @Published var midDepthCoverage: Float = 0.1 {
        didSet { saveToUserDefaults() }
    }

    /// 최적 측정 거리 (최소)
    ///
    /// 카메라에서 의류까지의 권장 최소 거리입니다. (미터 단위)
    ///
    /// - 기본값: 0.7m
    /// - 범위: 0.5 ~ 1.0m
    @Published var optimalMinDistance: Float = 0.7 {
        didSet { saveToUserDefaults() }
    }

    /// 최적 측정 거리 (최대)
    ///
    /// 카메라에서 의류까지의 권장 최대 거리입니다. (미터 단위)
    ///
    /// - 기본값: 1.0m
    /// - 범위: 0.8 ~ 1.5m
    @Published var optimalMaxDistance: Float = 1.0 {
        didSet { saveToUserDefaults() }
    }

    // MARK: - 평면 투영 설정

    /// 평면 추정에 사용할 샘플 포인트 수
    ///
    /// 더 많은 샘플을 사용하면 정확도가 높아지지만 성능이 저하될 수 있습니다.
    ///
    /// - 기본값: 100
    @Published var planeSampleCount: Int = 100 {
        didSet { saveToUserDefaults() }
    }

    /// 평면 오차 허용 범위
    ///
    /// 평면 추정 시 허용되는 최대 오차 비율입니다.
    ///
    /// - 기본값: 0.5 (50%)
    @Published var planeErrorTolerance: Float = 0.5 {
        didSet { saveToUserDefaults() }
    }

    // MARK: - 교정 설정

    /// 교정 활성화 여부
    ///
    /// true일 경우 측정값에 보정 계수를 자동으로 적용합니다.
    @Published var useCalibration: Bool = false {
        didSet { saveToUserDefaults() }
    }

    // MARK: - Public Methods

    /// 교정 프로파일을 적용합니다.
    ///
    /// 프로파일의 모든 임계값 설정을 현재 설정에 적용합니다.
    ///
    /// - Parameter profile: 적용할 교정 프로파일
    ///
    /// ## Example
    /// ```swift
    /// let profile = CalibrationProfile(name: "반바지 기준")
    /// MeasurementSettings.shared.applyProfile(profile)
    /// ```
    func applyProfile(_ profile: CalibrationProfile) {
        activeProfile = profile
        minConfidence = profile.minConfidence
        lowConfidenceWarning = profile.lowConfidenceWarning
        veryLowConfidence = profile.veryLowConfidence
        minDepthCoverage = profile.minDepthCoverage
        midDepthCoverage = profile.midDepthCoverage
        optimalMinDistance = profile.optimalMinDistance
        optimalMaxDistance = profile.optimalMaxDistance
        planeSampleCount = profile.planeSampleCount
        planeErrorTolerance = profile.planeErrorTolerance
    }

    /// 측정값에 보정 계수를 적용합니다.
    ///
    /// 교정이 활성화되어 있고 해당 측정 타입의 보정 계수가 존재하는 경우,
    /// 측정값에 보정 계수를 곱한 값을 반환합니다.
    ///
    /// - Parameters:
    ///   - type: 측정 타입 (어깨너비, 허리둘레 등)
    ///   - clothingType: 의류 타입 (반팔, 긴바지 등)
    ///   - value: 원본 측정값 (cm)
    /// - Returns: 보정이 적용된 측정값 (cm). 보정 계수가 없으면 원본 값 반환
    ///
    /// ## Example
    /// ```swift
    /// let correctedValue = MeasurementSettings.shared.applyCorrectionFactor(
    ///     type: .waistCircumference,
    ///     clothingType: .shorts,
    ///     value: 76.5
    /// )
    /// // correctedValue = 76.5 × 1.0196 = 78.0 (if calibration factor exists)
    /// ```
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

    /// 기본값으로 리셋합니다.
    func resetToDefaults() {
        minConfidence = 0.6
        lowConfidenceWarning = 0.7
        veryLowConfidence = 0.4
        minDepthCoverage = 0.2
        midDepthCoverage = 0.1
        optimalMinDistance = 0.7
        optimalMaxDistance = 1.0
        planeSampleCount = 100
        planeErrorTolerance = 0.5
        useCalibration = false
        activeProfile = nil
        isDebugMode = false

        saveToUserDefaults()
    }

    /// 2025-11-06 교정 데이터를 기반으로 기본 교정 프로파일을 생성합니다.
    ///
    /// - Parameter modelContext: SwiftData 모델 컨텍스트
    /// - Returns: 생성된 교정 프로파일
    ///
    /// ## 교정 데이터
    /// - 의류: 반바지 (Shorts)
    /// - 실측값: 허리 40cm, 총길이 48cm, 밑위 30cm
    /// - 측정값 (평균 10회): 허리 50.16cm, 총길이 37.70cm, 밑위 22.37cm
    /// - 보정 계수: 허리 0.7974, 총길이 1.2732, 밑위 1.3411
    ///
    static func createDefaultCalibrationProfile(modelContext: ModelContext) -> CalibrationProfile {
        // 교정 프로파일 생성
        let profile = CalibrationProfile(
            name: "반바지 기준 (2025-11-06)",
            minConfidence: 0.6,
            lowConfidenceWarning: 0.7,
            veryLowConfidence: 0.4,
            minDepthCoverage: 0.2,
            midDepthCoverage: 0.1,
            optimalMinDistance: 0.7,
            optimalMaxDistance: 1.0,
            planeSampleCount: 100,
            planeErrorTolerance: 0.5
        )

        // 허리둘레 보정 계수
        let waistFactor = CalibrationFactor(
            clothingType: ClothingType.shorts.rawValue,
            measurementType: MeasurementType.waistCircumference.rawValue,
            actualValue: 40.0,  // 실측값
            measuredValue: 50.16,  // 평균 측정값
            sampleCount: 10,
            averageMeasured: 50.16,
            stdDeviation: 1.17
        )

        // 총길이 보정 계수
        let lengthFactor = CalibrationFactor(
            clothingType: ClothingType.shorts.rawValue,
            measurementType: MeasurementType.totalLength.rawValue,
            actualValue: 48.0,  // 실측값
            measuredValue: 37.70,  // 평균 측정값
            sampleCount: 10,
            averageMeasured: 37.70,
            stdDeviation: 2.53
        )

        // 밑위 보정 계수
        let riseFactor = CalibrationFactor(
            clothingType: ClothingType.shorts.rawValue,
            measurementType: MeasurementType.rise.rawValue,
            actualValue: 30.0,  // 실측값
            measuredValue: 22.37,  // 평균 측정값
            sampleCount: 10,
            averageMeasured: 22.37,
            stdDeviation: 0.80
        )

        // 보정 계수를 프로파일에 추가
        profile.calibrationFactors = [waistFactor, lengthFactor, riseFactor]

        // SwiftData에 저장
        modelContext.insert(profile)
        try? modelContext.save()

        return profile
    }

    // MARK: - UserDefaults Persistence

    private func saveToUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(isDebugMode, forKey: "MeasurementSettings.isDebugMode")
        defaults.set(minConfidence, forKey: "MeasurementSettings.minConfidence")
        defaults.set(lowConfidenceWarning, forKey: "MeasurementSettings.lowConfidenceWarning")
        defaults.set(veryLowConfidence, forKey: "MeasurementSettings.veryLowConfidence")
        defaults.set(minDepthCoverage, forKey: "MeasurementSettings.minDepthCoverage")
        defaults.set(midDepthCoverage, forKey: "MeasurementSettings.midDepthCoverage")
        defaults.set(optimalMinDistance, forKey: "MeasurementSettings.optimalMinDistance")
        defaults.set(optimalMaxDistance, forKey: "MeasurementSettings.optimalMaxDistance")
        defaults.set(planeSampleCount, forKey: "MeasurementSettings.planeSampleCount")
        defaults.set(planeErrorTolerance, forKey: "MeasurementSettings.planeErrorTolerance")
        defaults.set(useCalibration, forKey: "MeasurementSettings.useCalibration")
    }

    private func loadFromUserDefaults() {
        let defaults = UserDefaults.standard

        if let value = defaults.object(forKey: "MeasurementSettings.isDebugMode") as? Bool {
            isDebugMode = value
        }
        if let value = defaults.object(forKey: "MeasurementSettings.minConfidence") as? Float {
            minConfidence = value
        }
        if let value = defaults.object(forKey: "MeasurementSettings.lowConfidenceWarning") as? Float {
            lowConfidenceWarning = value
        }
        if let value = defaults.object(forKey: "MeasurementSettings.veryLowConfidence") as? Float {
            veryLowConfidence = value
        }
        if let value = defaults.object(forKey: "MeasurementSettings.minDepthCoverage") as? Float {
            minDepthCoverage = value
        }
        if let value = defaults.object(forKey: "MeasurementSettings.midDepthCoverage") as? Float {
            midDepthCoverage = value
        }
        if let value = defaults.object(forKey: "MeasurementSettings.optimalMinDistance") as? Float {
            optimalMinDistance = value
        }
        if let value = defaults.object(forKey: "MeasurementSettings.optimalMaxDistance") as? Float {
            optimalMaxDistance = value
        }
        if let value = defaults.object(forKey: "MeasurementSettings.planeSampleCount") as? Int {
            planeSampleCount = value
        }
        if let value = defaults.object(forKey: "MeasurementSettings.planeErrorTolerance") as? Float {
            planeErrorTolerance = value
        }
        if let value = defaults.object(forKey: "MeasurementSettings.useCalibration") as? Bool {
            useCalibration = value
        }
    }
}

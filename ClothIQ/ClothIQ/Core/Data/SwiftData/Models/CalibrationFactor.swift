//
//  CalibrationFactor.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  교정 계수 데이터 모델입니다.
//  특정 의류 타입과 측정 타입에 대한 보정 계수를 저장합니다.
//
//  Key Responsibilities:
//  - 실측값과 측정값 비교 데이터 저장
//  - 보정 계수 자동 계산
//  - 통계 정보 저장 (평균, 표준편차)
//

import Foundation
import SwiftData

/// 측정 방식
enum MeasurementMethod: String, Codable {
    case ar = "ar"           // AR 실시간 측정
    case photo = "photo"     // 사진 기반 측정
}

/// 교정 계수 데이터 모델
///
/// 특정 의류 타입과 측정 타입에 대한 보정 계수를 저장합니다.
/// 실측값(actual)과 측정값(measured)을 비교하여 보정 계수를 계산합니다.
///
/// ## Formula
/// ```
/// correctionFactor = actualValue / measuredValue
/// correctedMeasurement = measuredValue × correctionFactor
/// ```
///
/// ## Example
/// ```swift
/// // 반바지 허리둘레 교정
/// // 실측값: 78.0 cm
/// // 측정값: 76.5 cm
/// let factor = CalibrationFactor(
///     clothingType: "shorts",
///     measurementType: "waist_circumference",
///     actualValue: 78.0,
///     measuredValue: 76.5
/// )
/// // factor.correctionFactor = 78.0 / 76.5 = 1.0196
/// ```
///
@Model
final class CalibrationFactor {

    // MARK: - Properties

    /// 고유 식별자
    var id: UUID

    /// 의류 타입
    ///
    /// ClothingType enum의 rawValue로 저장됩니다.
    /// 예: "shorts", "long_sleeve", "pants" 등
    var clothingType: String

    /// 측정 타입
    ///
    /// MeasurementType enum의 rawValue로 저장됩니다.
    /// 예: "waist_circumference", "shoulder_width" 등
    var measurementType: String

    /// 측정 방식
    ///
    /// AR 실시간 측정("ar") 또는 사진 기반 측정("photo")
    /// 기본값: "photo" (하위 호환성)
    var measurementMethod: String

    /// 실측값 (cm)
    ///
    /// 자로 직접 측정한 정확한 값입니다.
    var actualValue: Double

    /// 측정값 (cm)
    ///
    /// AR 측정 시스템으로 측정한 값입니다.
    /// 여러 번 측정한 경우 평균값을 사용합니다.
    var measuredValue: Double

    /// 보정 계수
    ///
    /// 자동으로 계산되는 값입니다.
    /// `correctionFactor = actualValue / measuredValue`
    var correctionFactor: Double

    /// 측정 횟수
    ///
    /// 평균을 계산하기 위해 측정한 총 횟수입니다.
    ///
    /// - 기본값: 1
    var sampleCount: Int

    /// 평균 측정값 (cm)
    ///
    /// 여러 번 측정한 경우의 평균값입니다.
    /// 단일 측정인 경우 measuredValue와 동일합니다.
    var averageMeasured: Double

    /// 표준편차
    ///
    /// 여러 번 측정한 경우의 표준편차입니다.
    /// 측정의 일관성을 평가하는 지표로 사용됩니다.
    ///
    /// nil인 경우: 단일 측정 또는 계산되지 않음
    var stdDeviation: Double?

    /// 생성 일시
    var createdAt: Date

    /// 부모 교정 프로파일
    ///
    /// 이 보정 계수가 속한 교정 프로파일입니다.
    var profile: CalibrationProfile?

    // MARK: - Initialization

    /// 교정 계수를 초기화합니다.
    ///
    /// - Parameters:
    ///   - id: 고유 식별자 (기본값: 새로운 UUID)
    ///   - clothingType: 의류 타입 rawValue
    ///   - measurementType: 측정 타입 rawValue
    ///   - measurementMethod: 측정 방식 ("ar" 또는 "photo", 기본값: "photo")
    ///   - actualValue: 실측값 (cm)
    ///   - measuredValue: 측정값 (cm)
    ///   - sampleCount: 측정 횟수 (기본값: 1)
    ///   - averageMeasured: 평균 측정값 (기본값: measuredValue와 동일)
    ///   - stdDeviation: 표준편차 (기본값: nil)
    ///   - createdAt: 생성 일시 (기본값: 현재 시각)
    ///
    /// ## Note
    /// correctionFactor는 자동으로 계산됩니다.
    init(
        id: UUID = UUID(),
        clothingType: String,
        measurementType: String,
        measurementMethod: String = MeasurementMethod.photo.rawValue,
        actualValue: Double,
        measuredValue: Double,
        sampleCount: Int = 1,
        averageMeasured: Double? = nil,
        stdDeviation: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.clothingType = clothingType
        self.measurementType = measurementType
        self.measurementMethod = measurementMethod
        self.actualValue = actualValue
        self.measuredValue = measuredValue
        self.correctionFactor = actualValue / measuredValue
        self.sampleCount = sampleCount
        self.averageMeasured = averageMeasured ?? measuredValue
        self.stdDeviation = stdDeviation
        self.createdAt = createdAt
    }
}

// MARK: - Convenience Methods

extension CalibrationFactor {

    /// 측정값에 보정 계수를 적용합니다.
    ///
    /// - Parameter value: 원본 측정값 (cm)
    /// - Returns: 보정이 적용된 측정값 (cm)
    ///
    /// ## Example
    /// ```swift
    /// let correctedValue = factor.apply(to: 76.5)
    /// // correctedValue = 76.5 × 1.0196 = 78.0
    /// ```
    func apply(to value: Double) -> Double {
        return value * correctionFactor
    }

    /// 오차율을 계산합니다.
    ///
    /// - Returns: 오차율 (백분율)
    ///
    /// ## Formula
    /// ```
    /// errorPercent = |actualValue - measuredValue| / actualValue × 100
    /// ```
    ///
    /// ## Example
    /// ```swift
    /// let errorPercent = factor.errorPercent()
    /// // errorPercent = |78.0 - 76.5| / 78.0 × 100 = 1.92%
    /// ```
    var errorPercent: Double {
        return abs(actualValue - measuredValue) / actualValue * 100.0
    }

    /// 측정의 정확도를 계산합니다.
    ///
    /// - Returns: 정확도 (0.0 ~ 1.0)
    ///
    /// ## Formula
    /// ```
    /// accuracy = 1.0 - (errorPercent / 100)
    /// ```
    ///
    /// ## Example
    /// ```swift
    /// let accuracy = factor.accuracy
    /// // accuracy = 1.0 - (1.92 / 100) = 0.9808 (98.08%)
    /// ```
    var accuracy: Double {
        return 1.0 - (errorPercent / 100.0)
    }

    /// 여러 측정값으로 표준편차를 계산하고 업데이트합니다.
    ///
    /// - Parameter measurements: 측정값 배열 (cm)
    ///
    /// ## Example
    /// ```swift
    /// let measurements = [76.2, 77.5, 75.8, 76.9, 76.3]
    /// factor.updateStatistics(with: measurements)
    /// // factor.averageMeasured = 76.54
    /// // factor.stdDeviation = 0.62
    /// // factor.sampleCount = 5
    /// ```
    func updateStatistics(with measurements: [Double]) {
        guard !measurements.isEmpty else { return }

        sampleCount = measurements.count

        // 평균 계산
        let sum = measurements.reduce(0, +)
        averageMeasured = sum / Double(measurements.count)
        measuredValue = averageMeasured

        // 표준편차 계산
        if measurements.count > 1 {
            let variance = measurements
                .map { pow($0 - averageMeasured, 2) }
                .reduce(0, +) / Double(measurements.count - 1)
            stdDeviation = sqrt(variance)
        } else {
            stdDeviation = nil
        }

        // 보정 계수 재계산
        correctionFactor = actualValue / measuredValue
    }

    /// 변동 계수(Coefficient of Variation)를 계산합니다.
    ///
    /// 변동 계수는 표준편차를 평균으로 나눈 값으로,
    /// 측정의 상대적 변동성을 나타냅니다.
    ///
    /// - Returns: 변동 계수 (백분율). 표준편차가 없으면 nil
    ///
    /// ## Formula
    /// ```
    /// CV = (stdDeviation / averageMeasured) × 100
    /// ```
    var coefficientOfVariation: Double? {
        guard let stdDev = stdDeviation, averageMeasured > 0 else {
            return nil
        }
        return (stdDev / averageMeasured) * 100.0
    }
}

// MARK: - Display Helpers

extension CalibrationFactor {

    /// 사람이 읽을 수 있는 형식의 요약 문자열
    ///
    /// ## Example
    /// ```
    /// "반바지 허리둘레: 78.0cm (실측) vs 76.5cm (측정), 보정 계수: 1.0196"
    /// ```
    var summary: String {
        let clothingTypeName = ClothingType(rawValue: clothingType)?.displayName ?? clothingType
        let measurementTypeName = MeasurementType(rawValue: measurementType)?.displayName ?? measurementType

        let actualValueStr = String(format: "%.1f", actualValue)
        let measuredValueStr = String(format: "%.1f", measuredValue)
        let correctionFactorStr = String(format: "%.4f", correctionFactor)

        return "\(clothingTypeName) \(measurementTypeName): \(actualValueStr)cm (실측) vs \(measuredValueStr)cm (측정), 보정 계수: \(correctionFactorStr)"
    }
}

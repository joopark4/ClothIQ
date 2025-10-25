//
//  MeasurementModel.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  측정값 데이터 모델입니다.
//  개별 측정 항목의 값과 메타데이터를 SwiftData로 저장합니다.
//
//  Key Responsibilities:
//  - 측정값 저장 (센티미터 단위로 정규화)
//  - 측정 신뢰도 저장
//  - 부모 의류 아이템과의 관계 관리
//

import Foundation
import SwiftData

/// 측정값 데이터 모델
///
/// 개별 측정 항목의 값과 메타데이터를 저장합니다.
/// 모든 측정값은 센티미터로 정규화되어 저장되며,
/// 표시 시 사용자 설정에 따라 다른 단위로 변환됩니다.
///
/// ## Example
/// ```swift
/// let measurement = MeasurementModel(
///     type: MeasurementType.shoulderWidth.rawValue,
///     value: 45.5,
///     confidence: 0.92
/// )
/// ```
///
@Model
final class MeasurementModel {
    /// 고유 식별자
    var id: UUID

    /// 측정 타입
    ///
    /// MeasurementType enum의 rawValue로 저장됩니다.
    /// 예: "shoulder_width", "chest_circumference"
    var type: String

    /// 측정값 (센티미터)
    ///
    /// 모든 측정값은 센티미터 단위로 정규화되어 저장됩니다.
    var value: Double

    /// 측정 단위
    ///
    /// 기본값은 "cm"이며, 표시용으로 사용됩니다.
    /// 실제 저장은 항상 센티미터로 이루어집니다.
    var unit: String

    /// 측정 신뢰도 (0.0 ~ 1.0)
    ///
    /// LiDAR 깊이 데이터의 품질, 측정 안정성 등을 고려한 신뢰도 점수입니다.
    /// - 0.9 이상: 매우 높음 (우수)
    /// - 0.7 ~ 0.9: 높음 (양호)
    /// - 0.5 ~ 0.7: 보통 (재측정 권장)
    /// - 0.5 미만: 낮음 (재측정 필수)
    var confidence: Double

    /// 측정 일시
    var measuredAt: Date

    /// 부모 의류 아이템
    ///
    /// 이 측정값이 속한 의류 아이템입니다.
    var clothingItem: ClothingItemModel?

    // MARK: - Initialization

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

// MARK: - Convenience Extensions

extension MeasurementModel {
    /// 측정 타입을 MeasurementType enum으로 반환
    var measurementType: MeasurementType? {
        MeasurementType(rawValue: type)
    }

    /// 측정 단위를 MeasurementUnit enum으로 반환
    var measurementUnit: MeasurementUnit? {
        MeasurementUnit(rawValue: unit)
    }

    /// 신뢰도 레벨
    var confidenceLevel: ConfidenceLevel {
        switch confidence {
        case 0.9...1.0:
            return .veryHigh
        case 0.7..<0.9:
            return .high
        case 0.5..<0.7:
            return .medium
        case 0.0..<0.5:
            return .low
        default:
            return .low
        }
    }

    /// 지정된 단위로 측정값 변환
    ///
    /// - Parameter targetUnit: 변환할 단위
    /// - Returns: 변환된 측정값
    func convertedValue(to targetUnit: MeasurementUnit) -> Double {
        // 현재 값은 이미 센티미터로 저장되어 있음
        return targetUnit.fromCentimeters(value)
    }

    /// 포맷된 측정값 문자열
    ///
    /// - Parameter targetUnit: 표시할 단위 (nil이면 기본 단위 사용)
    /// - Returns: 포맷된 문자열 (예: "45.5 cm")
    func formattedValue(unit targetUnit: MeasurementUnit? = nil) -> String {
        let displayUnit = targetUnit ?? (measurementUnit ?? .centimeter)
        let displayValue = convertedValue(to: displayUnit)
        return String(format: "%.1f %@", displayValue, displayUnit.symbol)
    }
}

/// 측정 신뢰도 레벨
enum ConfidenceLevel: String {
    case veryHigh = "very_high"  // 0.9 이상
    case high = "high"           // 0.7 ~ 0.9
    case medium = "medium"       // 0.5 ~ 0.7
    case low = "low"             // 0.5 미만

    var displayName: String {
        switch self {
        case .veryHigh:
            return "매우 높음"
        case .high:
            return "높음"
        case .medium:
            return "보통"
        case .low:
            return "낮음"
        }
    }

    var color: String {
        switch self {
        case .veryHigh:
            return "green"
        case .high:
            return "blue"
        case .medium:
            return "orange"
        case .low:
            return "red"
        }
    }
}

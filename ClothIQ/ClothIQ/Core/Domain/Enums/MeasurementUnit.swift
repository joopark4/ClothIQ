//
//  MeasurementUnit.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  측정 단위를 정의하는 열거형입니다.
//  센티미터와 인치 간의 변환 기능을 제공합니다.
//

import Foundation

/// 측정 단위 정의
///
/// 의류 측정에 사용되는 단위를 정의하고,
/// 단위 간 변환 기능을 제공합니다.
///
enum MeasurementUnit: String, CaseIterable, Codable {
    case centimeter = "cm"
    case inch = "in"

    /// 단위 변환 비율 (센티미터 기준)
    ///
    /// 모든 값은 내부적으로 센티미터로 저장되며,
    /// 이 비율을 사용하여 다른 단위로 변환합니다.
    var conversionFactor: Double {
        switch self {
        case .centimeter:
            return 1.0
        case .inch:
            return 2.54  // 1 inch = 2.54 cm
        }
    }

    /// 표시 이름
    var displayName: String {
        switch self {
        case .centimeter:
            return "센티미터"
        case .inch:
            return "인치"
        }
    }

    /// 단위 약어
    var symbol: String {
        return self.rawValue
    }

    /// 값을 센티미터로 변환
    ///
    /// - Parameter value: 현재 단위의 값
    /// - Returns: 센티미터로 변환된 값
    func toCentimeters(_ value: Double) -> Double {
        return value * conversionFactor
    }

    /// 센티미터 값을 현재 단위로 변환
    ///
    /// - Parameter centimeters: 센티미터 값
    /// - Returns: 현재 단위로 변환된 값
    func fromCentimeters(_ centimeters: Double) -> Double {
        return centimeters / conversionFactor
    }

    /// 값을 다른 단위로 변환
    ///
    /// - Parameters:
    ///   - value: 변환할 값
    ///   - targetUnit: 목표 단위
    /// - Returns: 변환된 값
    ///
    /// ## Example
    /// ```swift
    /// let inches = MeasurementUnit.centimeter.convert(50, to: .inch)
    /// // inches ≈ 19.69
    /// ```
    func convert(_ value: Double, to targetUnit: MeasurementUnit) -> Double {
        let centimeters = toCentimeters(value)
        return targetUnit.fromCentimeters(centimeters)
    }
}

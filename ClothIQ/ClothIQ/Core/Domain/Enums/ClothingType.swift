//
//  ClothingType.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  의류 타입을 정의하는 열거형입니다.
//  각 타입별로 필수 및 선택적 측정 항목을 정의합니다.
//

import Foundation

/// 의류 타입 정의
///
/// 지원하는 의류 종류를 나타내며, 각 타입별로 필수 측정 항목과 선택적 측정 항목을 제공합니다.
///
/// ## 지원 타입
/// - 반팔 티셔츠
/// - 긴팔 티셔츠
/// - 반바지
/// - 긴바지
/// - 치마
///
enum ClothingType: String, CaseIterable, Codable {
    case shortSleeve = "short_sleeve"   // 반팔
    case longSleeve = "long_sleeve"     // 긴팔
    case shorts = "shorts"              // 반바지
    case pants = "pants"                // 긴바지
    case skirt = "skirt"                // 치마

    /// 의류 타입의 표시 이름
    var displayName: String {
        switch self {
        case .shortSleeve:
            return "반팔 티셔츠"
        case .longSleeve:
            return "긴팔 티셔츠"
        case .shorts:
            return "반바지"
        case .pants:
            return "긴바지"
        case .skirt:
            return "치마"
        }
    }

    /// 각 의류 타입별 필수 측정 항목
    ///
    /// 측정을 완료하기 위해 반드시 측정해야 하는 항목들입니다.
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
    ///
    /// 추가로 측정할 수 있는 선택적 항목들입니다.
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

    /// 의류 카테고리 (상의/하의)
    var category: ClothingCategory {
        switch self {
        case .shortSleeve, .longSleeve:
            return .top
        case .shorts, .pants, .skirt:
            return .bottom
        }
    }
}

/// 의류 카테고리
enum ClothingCategory: String, Codable {
    case top = "top"        // 상의
    case bottom = "bottom"  // 하의

    var displayName: String {
        switch self {
        case .top:
            return "상의"
        case .bottom:
            return "하의"
        }
    }
}

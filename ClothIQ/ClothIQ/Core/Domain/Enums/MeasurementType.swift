//
//  MeasurementType.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  의류 측정 항목을 정의하는 열거형입니다.
//  각 측정 항목의 표시 이름과 측정 방법 가이드를 제공합니다.
//

import Foundation

/// 측정 타입 정의
///
/// 의류의 각 부위를 측정하는 항목들을 정의합니다.
/// 상의와 하의에 따라 다른 측정 항목이 사용됩니다.
///
enum MeasurementType: String, CaseIterable, Codable {
    // MARK: - 상의 측정 항목

    /// 어깨너비: 양쪽 어깨 끝점 사이의 직선 거리
    case shoulderWidth = "shoulder_width"

    /// 가슴둘레: 가슴 가장 넓은 부분의 둘레
    case chestCircumference = "chest_circumference"

    /// 총길이: 목 뒤 중심에서 밑단까지의 길이
    case totalLength = "total_length"

    /// 소매길이: 어깨 끝점에서 소매 끝까지의 길이
    case sleeveLength = "sleeve_length"

    /// 팔둘레: 팔의 가장 두꺼운 부분의 둘레
    case armCircumference = "arm_circumference"

    /// 목둘레: 목둘레선의 둘레
    case neckCircumference = "neck_circumference"

    // MARK: - 하의 측정 항목

    /// 허리둘레: 허리 가장 좁은 부분의 둘레
    case waistCircumference = "waist_circumference"

    /// 엉덩이둘레: 엉덩이 가장 넓은 부분의 둘레
    case hipCircumference = "hip_circumference"

    /// 밑위: 허리에서 밑위까지의 길이
    case rise = "rise"

    /// 밑단: 바지 밑단의 둘레
    case hem = "hem"

    /// 허벅지둘레: 허벅지 가장 두꺼운 부분의 둘레
    case thighCircumference = "thigh_circumference"

    /// 인심: 밑위에서 바지 밑단까지의 안쪽 솔기 길이
    case inseam = "inseam"

    /// 아웃심: 허리에서 바지 밑단까지의 바깥쪽 솔기 길이
    case outseam = "outseam"

    /// 무릎둘레: 무릎 부분의 둘레
    case kneeCircumference = "knee_circumference"

    // MARK: - 공통 측정 항목

    /// 밑단너비: 밑단의 너비
    case hemWidth = "hem_width"

    /// 측정 항목의 표시 이름
    var displayName: String {
        switch self {
        case .shoulderWidth:
            return "어깨너비"
        case .chestCircumference:
            return "가슴둘레"
        case .totalLength:
            return "총길이"
        case .sleeveLength:
            return "소매길이"
        case .armCircumference:
            return "팔둘레"
        case .neckCircumference:
            return "목둘레"
        case .waistCircumference:
            return "허리둘레"
        case .hipCircumference:
            return "엉덩이둘레"
        case .rise:
            return "밑위"
        case .hem:
            return "밑단"
        case .thighCircumference:
            return "허벅지둘레"
        case .inseam:
            return "인심"
        case .outseam:
            return "아웃심"
        case .kneeCircumference:
            return "무릎둘레"
        case .hemWidth:
            return "밑단너비"
        }
    }

    /// 측정 방법 설명
    ///
    /// 사용자가 올바르게 측정할 수 있도록 안내하는 설명입니다.
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

    /// 측정 타입의 카테고리
    var category: MeasurementCategory {
        switch self {
        case .shoulderWidth, .chestCircumference, .sleeveLength, .armCircumference, .neckCircumference:
            return .top
        case .waistCircumference, .hipCircumference, .rise, .hem, .thighCircumference, .inseam, .outseam, .kneeCircumference:
            return .bottom
        case .totalLength, .hemWidth:
            return .common
        }
    }
}

/// 측정 항목 카테고리
enum MeasurementCategory {
    case top     // 상의 전용
    case bottom  // 하의 전용
    case common  // 공통
}

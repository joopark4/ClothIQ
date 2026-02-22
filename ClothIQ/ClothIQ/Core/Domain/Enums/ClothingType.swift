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
    // MARK: - 기본 상의
    case shortSleeve = "short_sleeve"   // 반팔
    case longSleeve = "long_sleeve"     // 긴팔

    // MARK: - 셔츠류
    case shirt = "shirt"                // 셔츠
    case polo = "polo"                  // 폴로셔츠

    // MARK: - 아우터
    case jacket = "jacket"              // 재킷
    case coat = "coat"                  // 코트
    case vest = "vest"                  // 조끼
    case cardigan = "cardigan"          // 가디건
    case hoodie = "hoodie"              // 후드티

    // MARK: - 원피스류
    case dress = "dress"                // 원피스
    case jumpsuit = "jumpsuit"          // 점프수트

    // MARK: - 하의
    case shorts = "shorts"              // 반바지
    case pants = "pants"                // 긴바지
    case jeans = "jeans"                // 청바지
    case skirt = "skirt"                // 치마
    case leggings = "leggings"          // 레깅스

    /// 의류 타입의 표시 이름
    var displayName: String {
        switch self {
        case .shortSleeve:
            return "반팔 티셔츠"
        case .longSleeve:
            return "긴팔 티셔츠"
        case .shirt:
            return "셔츠"
        case .polo:
            return "폴로셔츠"
        case .jacket:
            return "재킷"
        case .coat:
            return "코트"
        case .vest:
            return "조끼"
        case .cardigan:
            return "가디건"
        case .hoodie:
            return "후드티"
        case .dress:
            return "원피스"
        case .jumpsuit:
            return "점프수트"
        case .shorts:
            return "반바지"
        case .pants:
            return "긴바지"
        case .jeans:
            return "청바지"
        case .skirt:
            return "치마"
        case .leggings:
            return "레깅스"
        }
    }

    /// 각 의류 타입별 필수 측정 항목
    ///
    /// 측정을 완료하기 위해 반드시 측정해야 하는 항목들입니다.
    var requiredMeasurements: [MeasurementType] {
        switch self {
        // 기본 상의
        case .shortSleeve:
            return [.shoulderWidth, .chestCircumference, .totalLength, .sleeveLength]
        case .longSleeve:
            return [.shoulderWidth, .chestCircumference, .totalLength, .sleeveLength, .armCircumference]

        // 셔츠류
        case .shirt:
            return [.shoulderWidth, .chestCircumference, .totalLength, .sleeveLength, .neckCircumference]
        case .polo:
            return [.shoulderWidth, .chestCircumference, .totalLength, .sleeveLength]

        // 아우터
        case .jacket:
            return [.shoulderWidth, .chestCircumference, .totalLength, .sleeveLength, .cuffCircumference]
        case .coat:
            return [.shoulderWidth, .chestCircumference, .totalLength, .sleeveLength]
        case .vest:
            return [.shoulderWidth, .chestCircumference, .totalLength]
        case .cardigan:
            return [.shoulderWidth, .chestCircumference, .totalLength, .sleeveLength]
        case .hoodie:
            return [.shoulderWidth, .chestCircumference, .totalLength, .sleeveLength]

        // 원피스류
        case .dress:
            return [.shoulderWidth, .chestCircumference, .totalLength, .waistCircumference, .hipCircumference]
        case .jumpsuit:
            return [.shoulderWidth, .chestCircumference, .totalLength, .waistCircumference, .hipCircumference, .rise]

        // 하의
        case .shorts:
            return [.waistCircumference, .totalLength, .rise]
        case .pants:
            return [.waistCircumference, .totalLength, .rise, .hem, .thighCircumference]
        case .jeans:
            return [.waistCircumference, .totalLength, .rise, .hem, .thighCircumference]
        case .skirt:
            return [.waistCircumference, .totalLength]
        case .leggings:
            return [.waistCircumference, .totalLength, .hipCircumference]
        }
    }

    /// 선택적 측정 항목
    ///
    /// 추가로 측정할 수 있는 선택적 항목들입니다.
    var optionalMeasurements: [MeasurementType] {
        return []
    }

    /// 의류 카테고리 (상의/하의/외투/원피스)
    var category: ClothingCategory {
        switch self {
        case .shortSleeve, .longSleeve, .shirt, .polo, .vest, .hoodie:
            return .top
        case .jacket, .coat, .cardigan:
            return .outerwear
        case .dress, .jumpsuit:
            return .onepiece
        case .shorts, .pants, .jeans, .skirt, .leggings:
            return .bottom
        }
    }
}

/// 의류 카테고리
enum ClothingCategory: String, Codable {
    case top = "top"           // 상의
    case bottom = "bottom"     // 하의
    case outerwear = "outerwear" // 외투
    case onepiece = "onepiece"   // 원피스류

    var displayName: String {
        switch self {
        case .top:
            return "상의"
        case .bottom:
            return "하의"
        case .outerwear:
            return "외투"
        case .onepiece:
            return "원피스류"
        }
    }
}

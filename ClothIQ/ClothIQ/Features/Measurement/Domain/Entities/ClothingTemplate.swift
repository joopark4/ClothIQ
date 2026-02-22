//
//  ClothingTemplate.swift
//  ClothIQ
//
//  Created on 2025-11-06
//
//  Description:
//  의류 타입별 측정 포인트 위치 템플릿을 정의합니다.
//  종횡비(aspect ratio)와 의류 타입에 따라 최적의 측정 위치를 제공하여
//  자동 측정 정확도를 향상시킵니다.
//
//  Key Features:
//  - 의류 타입별 특화된 측정 오프셋
//  - 종횡비 기반 자동 템플릿 선택
//  - 다양한 의류 변형 지원 (크롭탑, 긴 셔츠 등)
//

import Foundation
import CoreGraphics

/// 의류 측정 템플릿
///
/// 의류 타입별로 측정 포인트의 위치를 정의합니다.
/// 종횡비(height/width)를 기반으로 적절한 템플릿을 자동 선택합니다.
struct ClothingTemplate {

    // MARK: - Properties

    /// 의류 타입
    let type: ClothingType

    /// 템플릿 변형 이름 (예: "크롭탑", "긴 셔츠")
    let variant: String

    /// 적용 가능한 종횡비 범위 (height/width)
    let aspectRatioRange: ClosedRange<CGFloat>

    // MARK: 상의 측정 오프셋 (상단 기준, 아래 방향으로 비율)

    /// 어깨너비 측정 Y 오프셋 (상단에서 아래로)
    let shoulderOffset: CGFloat

    /// 가슴둘레 측정 Y 오프셋 (상단에서 아래로)
    let chestOffset: CGFloat

    /// 소매 끝점 탐색 깊이 (양옆에서 안쪽으로)
    let sleeveSearchDepth: CGFloat

    // MARK: 하의 측정 오프셋 (상단 기준, 아래 방향으로 비율)

    /// 허리둘레 측정 Y 오프셋 (상단에서 아래로)
    let waistOffset: CGFloat

    /// 엉덩이둘레 측정 Y 오프셋 (상단에서 아래로)
    let hipOffset: CGFloat

    /// 밑위 탐색 범위 (상단 기준)
    let riseSearchRange: ClosedRange<CGFloat>

    // MARK: - Initialization

    init(
        type: ClothingType,
        variant: String,
        aspectRatioRange: ClosedRange<CGFloat>,
        shoulderOffset: CGFloat = 0.02,
        chestOffset: CGFloat = 0.30,
        sleeveSearchDepth: CGFloat = 0.15,
        waistOffset: CGFloat = 0.10,
        hipOffset: CGFloat = 0.35,
        riseSearchRange: ClosedRange<CGFloat> = 0.35...0.65
    ) {
        self.type = type
        self.variant = variant
        self.aspectRatioRange = aspectRatioRange
        self.shoulderOffset = shoulderOffset
        self.chestOffset = chestOffset
        self.sleeveSearchDepth = sleeveSearchDepth
        self.waistOffset = waistOffset
        self.hipOffset = hipOffset
        self.riseSearchRange = riseSearchRange
    }

    // MARK: - Static Templates

    /// 모든 사전 정의된 템플릿
    static let allTemplates: [ClothingTemplate] = [
        // 기본 상의 템플릿
        .cropTop,
        .shortSleeveTShirt,
        .longSleeveTShirt,
        .longShirt,

        // 셔츠류 템플릿
        .shirt,
        .polo,

        // 아우터 템플릿
        .jacket,
        .coat,
        .vest,
        .cardigan,
        .hoodie,

        // 원피스류 템플릿
        .miniDress,
        .midiDress,
        .longDress,
        .jumpsuit,

        // 하의 템플릿
        .shorts,
        .pants,
        .jeans,
        .leggings,
        .miniSkirt,
        .midiSkirt,
        .longSkirt
    ]

    // MARK: 상의 템플릿

    /// 크롭탑 템플릿 (종횡비: 0.3 ~ 0.7)
    static let cropTop = ClothingTemplate(
        type: .shortSleeve,
        variant: "크롭탑",
        aspectRatioRange: 0.3...0.7,
        shoulderOffset: 0.015,    // 상단에서 1.5%
        chestOffset: 0.35,        // 상단에서 35% (크롭탑은 가슴 위치가 상대적으로 낮음)
        sleeveSearchDepth: 0.12   // 짧은 소매
    )

    /// 일반 반팔 티셔츠 템플릿 (종횡비: 0.7 ~ 1.2)
    static let shortSleeveTShirt = ClothingTemplate(
        type: .shortSleeve,
        variant: "반팔 티셔츠",
        aspectRatioRange: 0.7...1.2,
        shoulderOffset: 0.02,     // 상단에서 2%
        chestOffset: 0.30,        // 상단에서 30%
        sleeveSearchDepth: 0.15   // 일반 소매
    )

    /// 긴팔 티셔츠 템플릿 (종횡비: 1.0 ~ 1.5)
    static let longSleeveTShirt = ClothingTemplate(
        type: .longSleeve,
        variant: "긴팔 티셔츠",
        aspectRatioRange: 1.0...1.5,
        shoulderOffset: 0.02,     // 상단에서 2%
        chestOffset: 0.28,        // 상단에서 28% (긴팔은 약간 위로)
        sleeveSearchDepth: 0.18   // 긴 소매
    )

    /// 긴 셔츠 템플릿 (종횡비: 1.3 ~ 2.0)
    static let longShirt = ClothingTemplate(
        type: .longSleeve,
        variant: "긴 셔츠",
        aspectRatioRange: 1.3...2.0,
        shoulderOffset: 0.015,    // 상단에서 1.5% (긴 셔츠는 어깨가 위로)
        chestOffset: 0.25,        // 상단에서 25% (전체 길이가 길어서 위로)
        sleeveSearchDepth: 0.20   // 긴 소매
    )

    // MARK: 셔츠류 템플릿

    /// 셔츠 템플릿 (종횡비: 1.0 ~ 1.7)
    static let shirt = ClothingTemplate(
        type: .shirt,
        variant: "셔츠",
        aspectRatioRange: 1.0...1.7,
        shoulderOffset: 0.015,    // 상단에서 1.5%
        chestOffset: 0.26,        // 상단에서 26%
        sleeveSearchDepth: 0.20   // 긴 소매
    )

    /// 폴로셔츠 템플릿 (종횡비: 0.8 ~ 1.3)
    static let polo = ClothingTemplate(
        type: .polo,
        variant: "폴로셔츠",
        aspectRatioRange: 0.8...1.3,
        shoulderOffset: 0.02,     // 상단에서 2%
        chestOffset: 0.28,        // 상단에서 28%
        sleeveSearchDepth: 0.15   // 짧은 소매
    )

    // MARK: 아우터 템플릿

    /// 재킷 템플릿 (종횡비: 1.0 ~ 1.6)
    static let jacket = ClothingTemplate(
        type: .jacket,
        variant: "재킷",
        aspectRatioRange: 1.0...1.6,
        shoulderOffset: 0.02,     // 상단에서 2%
        chestOffset: 0.30,        // 상단에서 30%
        sleeveSearchDepth: 0.22   // 긴 소매
    )

    /// 코트 템플릿 (종횡비: 1.5 ~ 2.5)
    static let coat = ClothingTemplate(
        type: .coat,
        variant: "코트",
        aspectRatioRange: 1.5...2.5,
        shoulderOffset: 0.015,    // 상단에서 1.5%
        chestOffset: 0.25,        // 상단에서 25%
        sleeveSearchDepth: 0.25   // 매우 긴 소매
    )

    /// 조끼 템플릿 (종횡비: 0.7 ~ 1.3)
    static let vest = ClothingTemplate(
        type: .vest,
        variant: "조끼",
        aspectRatioRange: 0.7...1.3,
        shoulderOffset: 0.02,     // 상단에서 2%
        chestOffset: 0.32,        // 상단에서 32%
        sleeveSearchDepth: 0.05   // 소매 없음 (암홀만)
    )

    /// 가디건 템플릿 (종횡비: 1.1 ~ 1.8)
    static let cardigan = ClothingTemplate(
        type: .cardigan,
        variant: "가디건",
        aspectRatioRange: 1.1...1.8,
        shoulderOffset: 0.02,     // 상단에서 2%
        chestOffset: 0.28,        // 상단에서 28%
        sleeveSearchDepth: 0.20   // 긴 소매
    )

    /// 후드티 템플릿 (종횡비: 1.0 ~ 1.5)
    static let hoodie = ClothingTemplate(
        type: .hoodie,
        variant: "후드티",
        aspectRatioRange: 1.0...1.5,
        shoulderOffset: 0.025,    // 상단에서 2.5% (후드 때문에)
        chestOffset: 0.32,        // 상단에서 32%
        sleeveSearchDepth: 0.18   // 일반 긴 소매
    )

    // MARK: 원피스류 템플릿

    /// 미니 원피스 템플릿 (종횡비: 0.8 ~ 1.3)
    static let miniDress = ClothingTemplate(
        type: .dress,
        variant: "미니 원피스",
        aspectRatioRange: 0.8...1.3,
        shoulderOffset: 0.02,     // 상단에서 2%
        chestOffset: 0.25,        // 상단에서 25%
        waistOffset: 0.40,        // 상단에서 40%
        hipOffset: 0.55          // 상단에서 55%
    )

    /// 미디 원피스 템플릿 (종횡비: 1.3 ~ 1.8)
    static let midiDress = ClothingTemplate(
        type: .dress,
        variant: "미디 원피스",
        aspectRatioRange: 1.3...1.8,
        shoulderOffset: 0.015,    // 상단에서 1.5%
        chestOffset: 0.22,        // 상단에서 22%
        waistOffset: 0.35,        // 상단에서 35%
        hipOffset: 0.45          // 상단에서 45%
    )

    /// 롱 원피스 템플릿 (종횡비: 1.8 ~ 2.5)
    static let longDress = ClothingTemplate(
        type: .dress,
        variant: "롱 원피스",
        aspectRatioRange: 1.8...2.5,
        shoulderOffset: 0.01,     // 상단에서 1%
        chestOffset: 0.20,        // 상단에서 20%
        waistOffset: 0.30,        // 상단에서 30%
        hipOffset: 0.40          // 상단에서 40%
    )

    /// 점프수트 템플릿 (종횡비: 2.0 ~ 3.0)
    static let jumpsuit = ClothingTemplate(
        type: .jumpsuit,
        variant: "점프수트",
        aspectRatioRange: 2.0...3.0,
        shoulderOffset: 0.01,     // 상단에서 1%
        chestOffset: 0.18,        // 상단에서 18%
        waistOffset: 0.25,        // 상단에서 25%
        hipOffset: 0.35,          // 상단에서 35%
        riseSearchRange: 0.35...0.55  // 밑위 탐색 범위
    )

    // MARK: 하의 템플릿

    /// 반바지 템플릿 (종횡비: 0.4 ~ 1.6)
    /// 분류 임계값(1.6)과 일치하도록 범위 확장
    static let shorts = ClothingTemplate(
        type: .shorts,
        variant: "반바지",
        aspectRatioRange: 0.4...1.6,  // 0.8 → 1.6 확장
        waistOffset: 0.08,        // 상단에서 8%
        hipOffset: 0.40,          // 상단에서 40% (짧아서 엉덩이가 낮게)
        riseSearchRange: 0.30...0.55  // 밑위 탐색 범위 (짧음)
    )

    /// 긴바지 템플릿 (종횡비: 1.6 ~ 2.5)
    /// 반바지 범위(1.6)와 일치하도록 시작점 조정
    static let pants = ClothingTemplate(
        type: .pants,
        variant: "긴바지",
        aspectRatioRange: 1.6...2.5,  // 1.5 → 1.6으로 조정
        waistOffset: 0.10,        // 상단에서 10%
        hipOffset: 0.35,          // 상단에서 35%
        riseSearchRange: 0.35...0.65  // 밑위 탐색 범위
    )

    /// 미니 스커트 템플릿 (종횡비: 0.3 ~ 0.6)
    static let miniSkirt = ClothingTemplate(
        type: .skirt,
        variant: "미니 스커트",
        aspectRatioRange: 0.3...0.6,
        waistOffset: 0.08,        // 상단에서 8%
        hipOffset: 0.45,          // 상단에서 45% (짧아서 엉덩이가 낮게)
        riseSearchRange: 0.30...0.55
    )

    /// 미디 스커트 템플릿 (종횡비: 0.6 ~ 1.2)
    static let midiSkirt = ClothingTemplate(
        type: .skirt,
        variant: "미디 스커트",
        aspectRatioRange: 0.6...1.2,
        waistOffset: 0.10,        // 상단에서 10%
        hipOffset: 0.35,          // 상단에서 35%
        riseSearchRange: 0.35...0.60
    )

    /// 롱 스커트 템플릿 (종횡비: 1.2 ~ 2.0)
    static let longSkirt = ClothingTemplate(
        type: .skirt,
        variant: "롱 스커트",
        aspectRatioRange: 1.2...2.0,
        waistOffset: 0.12,        // 상단에서 12%
        hipOffset: 0.30,          // 상단에서 30% (길어서 위로)
        riseSearchRange: 0.35...0.65
    )

    /// 청바지 템플릿 (종횡비: 1.8 ~ 2.5)
    static let jeans = ClothingTemplate(
        type: .jeans,
        variant: "청바지",
        aspectRatioRange: 1.8...2.5,
        waistOffset: 0.10,        // 상단에서 10%
        hipOffset: 0.33,          // 상단에서 33%
        riseSearchRange: 0.35...0.65  // 밑위 탐색 범위
    )

    /// 레깅스 템플릿 (종횡비: 1.5 ~ 2.2)
    static let leggings = ClothingTemplate(
        type: .leggings,
        variant: "레깅스",
        aspectRatioRange: 1.5...2.2,
        waistOffset: 0.08,        // 상단에서 8% (높은 허리)
        hipOffset: 0.35,          // 상단에서 35%
        riseSearchRange: 0.30...0.55  // 밑위 탐색 범위
    )

    // MARK: - Template Selection

    /// 종횡비와 의류 타입에 맞는 템플릿 선택
    ///
    /// - Parameters:
    ///   - aspectRatio: 의류의 종횡비 (height/width)
    ///   - type: 의류 타입
    /// - Returns: 가장 적합한 템플릿. 매칭 실패 시 기본 템플릿 반환
    static func selectTemplate(
        for aspectRatio: CGFloat,
        type: ClothingType
    ) -> ClothingTemplate {
        // 해당 타입의 템플릿 중에서 종횡비 범위에 맞는 것 찾기
        let matchingTemplates = allTemplates.filter { template in
            template.type == type && template.aspectRatioRange.contains(aspectRatio)
        }

        // 매칭되는 템플릿이 있으면 첫 번째 반환
        if let template = matchingTemplates.first {
            return template
        }

        // 매칭 실패 시 기본 템플릿 반환
        return defaultTemplate(for: type)
    }

    /// 의류 타입별 기본 템플릿
    ///
    /// - Parameter type: 의류 타입
    /// - Returns: 기본 템플릿
    static func defaultTemplate(for type: ClothingType) -> ClothingTemplate {
        switch type {
        // 기본 상의
        case .shortSleeve:
            return .shortSleeveTShirt
        case .longSleeve:
            return .longSleeveTShirt

        // 셔츠류
        case .shirt:
            return .shirt
        case .polo:
            return .polo

        // 아우터
        case .jacket:
            return .jacket
        case .coat:
            return .coat
        case .vest:
            return .vest
        case .cardigan:
            return .cardigan
        case .hoodie:
            return .hoodie

        // 원피스류
        case .dress:
            return .midiDress
        case .jumpsuit:
            return .jumpsuit

        // 하의
        case .shorts:
            return .shorts
        case .pants:
            return .pants
        case .jeans:
            return .jeans
        case .leggings:
            return .leggings
        case .skirt:
            return .midiSkirt
        }
    }
}

// MARK: - CustomStringConvertible

extension ClothingTemplate: CustomStringConvertible {
    var description: String {
        """
        ClothingTemplate(
          type: \(type.rawValue),
          variant: \(variant),
          aspectRatio: \(aspectRatioRange.lowerBound)...\(aspectRatioRange.upperBound),
          shoulder: \(shoulderOffset), chest: \(chestOffset),
          waist: \(waistOffset), hip: \(hipOffset)
        )
        """
    }
}

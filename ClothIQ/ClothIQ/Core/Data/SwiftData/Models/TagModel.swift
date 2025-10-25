//
//  TagModel.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  태그 데이터 모델입니다.
//  의류 아이템을 분류하고 검색하기 위한 태그를 관리합니다.
//
//  Key Responsibilities:
//  - 태그 정보 저장 (이름, 색상)
//  - 의류 아이템과의 다대다 관계 관리
//

import Foundation
import SwiftData

/// 태그 데이터 모델
///
/// 의류 아이템을 분류하고 검색하기 위한 태그입니다.
/// 여러 의류 아이템에 적용될 수 있으며, 하나의 의류 아이템은 여러 태그를 가질 수 있습니다.
///
/// ## Example
/// ```swift
/// let winterTag = TagModel(
///     name: "겨울",
///     colorHex: "#4A90E2"
/// )
/// ```
///
@Model
final class TagModel {
    /// 고유 식별자
    var id: UUID

    /// 태그 이름
    ///
    /// 중복될 수 있으므로 고유성을 보장하지 않습니다.
    /// UI에서 중복 방지 로직을 구현해야 합니다.
    var name: String

    /// 태그 색상 (Hex)
    ///
    /// 6자리 Hex 색상 코드로 저장됩니다.
    /// 예: "#007AFF", "#FF3B30"
    var colorHex: String

    /// 생성 일시
    var createdAt: Date

    /// 연관된 의류 아이템 목록
    ///
    /// N:M 관계로, 이 태그가 적용된 모든 의류 아이템을 포함합니다.
    var clothingItems: [ClothingItemModel]

    // MARK: - Initialization

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

// MARK: - Convenience Extensions

extension TagModel {
    /// 이 태그가 적용된 의류 아이템 개수
    var itemCount: Int {
        clothingItems.count
    }

    /// 태그가 비어있는지 확인 (의류 아이템이 없는 경우)
    var isEmpty: Bool {
        clothingItems.isEmpty
    }
}

// MARK: - Predefined Tags

extension TagModel {
    /// 미리 정의된 기본 태그들
    static var predefinedTags: [TagModel] {
        [
            TagModel(name: "즐겨찾기", colorHex: "#FF9500"),
            TagModel(name: "겨울", colorHex: "#5AC8FA"),
            TagModel(name: "여름", colorHex: "#FFCC00"),
            TagModel(name: "봄/가을", colorHex: "#34C759"),
            TagModel(name: "정장", colorHex: "#000000"),
            TagModel(name: "캐주얼", colorHex: "#FF3B30"),
            TagModel(name: "운동복", colorHex: "#AF52DE"),
            TagModel(name: "외출복", colorHex: "#007AFF")
        ]
    }

    /// 기본 색상 팔레트
    static var colorPalette: [String] {
        [
            "#007AFF",  // Blue
            "#FF3B30",  // Red
            "#34C759",  // Green
            "#FFCC00",  // Yellow
            "#FF9500",  // Orange
            "#AF52DE",  // Purple
            "#5AC8FA",  // Light Blue
            "#FF2D55",  // Pink
            "#5856D6",  // Indigo
            "#000000"   // Black
        ]
    }
}

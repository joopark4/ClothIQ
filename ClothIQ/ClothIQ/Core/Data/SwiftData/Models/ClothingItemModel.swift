//
//  ClothingItemModel.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  의류 아이템 데이터 모델입니다.
//  촬영한 의류의 기본 정보와 측정값을 SwiftData로 저장합니다.
//
//  Key Responsibilities:
//  - 의류 아이템의 기본 정보 저장 (타입, 생성일시 등)
//  - 측정값과의 관계 관리 (1:N)
//  - 태그와의 관계 관리 (N:M)
//  - 이미지 파일 경로 저장
//

import Foundation
import SwiftData

/// 의류 아이템 데이터 모델
///
/// 촬영한 의류의 기본 정보와 측정값을 저장합니다.
/// 이미지는 파일 시스템에 저장되며, 이 모델은 경로만 보관합니다.
///
/// ## Relationships
/// - `measurements`: 1:N (하나의 의류 아이템은 여러 측정값을 가짐)
/// - `tags`: N:M (의류 아이템과 태그는 다대다 관계)
///
@Model
final class ClothingItemModel {
    /// 고유 식별자
    var id: UUID

    /// 의류 타입 (반팔, 긴팔, 바지 등)
    ///
    /// ClothingType enum의 rawValue로 저장됩니다.
    var type: String

    /// 생성 일시
    var createdAt: Date

    /// 수정 일시
    var updatedAt: Date

    /// 이미지 파일 경로
    ///
    /// Documents 디렉토리 내 상대 경로를 저장합니다.
    /// 예: "clothing_images/UUID.jpg"
    var imagePath: String?

    /// 측정값 목록
    ///
    /// cascade 삭제: 의류 아이템이 삭제되면 관련 측정값도 모두 삭제됩니다.
    @Relationship(deleteRule: .cascade)
    var measurements: [MeasurementModel]

    /// 태그 목록
    ///
    /// nullify 삭제: 의류 아이템이 삭제되어도 태그는 유지됩니다.
    @Relationship(deleteRule: .nullify)
    var tags: [TagModel]

    /// 메모
    var notes: String?

    /// 즐겨찾기 여부
    var isFavorite: Bool

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        type: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        imagePath: String? = nil,
        measurements: [MeasurementModel] = [],
        tags: [TagModel] = [],
        notes: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imagePath = imagePath
        self.measurements = measurements
        self.tags = tags
        self.notes = notes
        self.isFavorite = isFavorite
    }
}

// MARK: - Convenience Extensions

extension ClothingItemModel {
    /// 의류 타입을 ClothingType enum으로 반환
    var clothingType: ClothingType? {
        ClothingType(rawValue: type)
    }

    /// 특정 타입의 측정값 조회
    ///
    /// - Parameter measurementType: 조회할 측정 타입
    /// - Returns: 해당 타입의 측정값, 없으면 nil
    func measurement(for measurementType: MeasurementType) -> MeasurementModel? {
        measurements.first { $0.type == measurementType.rawValue }
    }

    /// 필수 측정 항목이 모두 완료되었는지 확인
    var isComplete: Bool {
        guard let clothingType = clothingType else { return false }
        let requiredTypes = clothingType.requiredMeasurements.map { $0.rawValue }
        let measuredTypes = measurements.map { $0.type }
        return requiredTypes.allSatisfy { measuredTypes.contains($0) }
    }

    /// 측정 완료 진행률 (0.0 ~ 1.0)
    var completionProgress: Double {
        guard let clothingType = clothingType else { return 0.0 }
        let requiredCount = clothingType.requiredMeasurements.count
        guard requiredCount > 0 else { return 0.0 }

        let completedCount = clothingType.requiredMeasurements.filter { measurementType in
            measurements.contains { $0.type == measurementType.rawValue }
        }.count

        return Double(completedCount) / Double(requiredCount)
    }
}

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
import UIKit
import simd

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
final class ClothingItemModel: Hashable {
    /// 고유 식별자
    var id: UUID

    /// 사용자 지정 타이틀
    ///
    /// 사용자가 직접 입력한 의류 아이템의 이름입니다.
    /// nil인 경우 의류 타입 이름을 사용합니다.
    var title: String?

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

    /// Depth map 파일 경로
    ///
    /// LiDAR 센서로 촬영한 깊이 데이터 파일 경로입니다.
    /// Documents 디렉토리 내 상대 경로를 저장합니다.
    /// 예: "depth_maps/UUID.png"
    /// 사진 기반 측정 시 이 데이터를 활용합니다.
    var depthMapPath: String?

    /// 원본 이미지 너비 (크롭 전)
    var originalImageWidth: Double?

    /// 원본 이미지 높이 (크롭 전)
    var originalImageHeight: Double?

    /// 처리된 이미지 너비 (크롭 후)
    var processedImageWidth: Double?

    /// 처리된 이미지 높이 (크롭 후)
    var processedImageHeight: Double?

    /// 크롭 영역 X 좌표 (원본 기준)
    var cropOriginX: Double?

    /// 크롭 영역 Y 좌표 (원본 기준)
    var cropOriginY: Double?

    /// 크롭 영역 너비
    var cropWidth: Double?

    /// 크롭 영역 높이
    var cropHeight: Double?

    /// 카메라 intrinsics 행렬 데이터 (simd_float3x3)
    var cameraIntrinsicsData: Data?

    /// 카메라 이미지 해상도 너비
    var cameraResolutionWidth: Double?

    /// 카메라 이미지 해상도 높이
    var cameraResolutionHeight: Double?

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
        title: String? = nil,
        type: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        imagePath: String? = nil,
        depthMapPath: String? = nil,
        originalImageWidth: Double? = nil,
        originalImageHeight: Double? = nil,
        processedImageWidth: Double? = nil,
        processedImageHeight: Double? = nil,
        cropOriginX: Double? = nil,
        cropOriginY: Double? = nil,
        cropWidth: Double? = nil,
        cropHeight: Double? = nil,
        cameraIntrinsicsData: Data? = nil,
        cameraResolutionWidth: Double? = nil,
        cameraResolutionHeight: Double? = nil,
        measurements: [MeasurementModel] = [],
        tags: [TagModel] = [],
        notes: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imagePath = imagePath
        self.depthMapPath = depthMapPath
        self.originalImageWidth = originalImageWidth
        self.originalImageHeight = originalImageHeight
        self.processedImageWidth = processedImageWidth
        self.processedImageHeight = processedImageHeight
        self.cropOriginX = cropOriginX
        self.cropOriginY = cropOriginY
        self.cropWidth = cropWidth
        self.cropHeight = cropHeight
        self.cameraIntrinsicsData = cameraIntrinsicsData
        self.cameraResolutionWidth = cameraResolutionWidth
        self.cameraResolutionHeight = cameraResolutionHeight
        self.measurements = measurements
        self.tags = tags
        self.notes = notes
        self.isFavorite = isFavorite
    }
}

// MARK: - Convenience Extensions

extension ClothingItemModel {
    /// 표시할 타이틀
    ///
    /// 사용자가 설정한 타이틀이 있으면 그것을 사용하고,
    /// 없으면 의류 타입 이름을 반환합니다.
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        return clothingType?.displayName ?? "의류 아이템"
    }

    /// 의류 타입을 ClothingType enum으로 반환
    var clothingType: ClothingType? {
        ClothingType(rawValue: type)
    }

    /// 특정 타입의 측정값 조회
    ///
    /// - Parameter measurementType: 조회할 측정 타입
    /// - Returns: 해당 타입의 측정값, 없으면 nil
    func measurement(for measurementType: MeasurementType) -> MeasurementModel? {
        measurements
            .filter { $0.type == measurementType.rawValue }
            .max { lhs, rhs in
                rhs.isPreferred(over: lhs)
            }
    }

    /// 화면과 저장 로직에서 사용할 타입별 최신 측정값 목록
    ///
    /// 과거 버전에서 같은 측정 타입이 중복 저장된 데이터가 있어도
    /// 사용자에게는 타입별 최신/최상 측정값 하나만 노출합니다.
    var displayMeasurements: [MeasurementModel] {
        var latestByType: [String: MeasurementModel] = [:]

        for measurement in measurements {
            if let current = latestByType[measurement.type] {
                if measurement.isPreferred(over: current) {
                    latestByType[measurement.type] = measurement
                }
            } else {
                latestByType[measurement.type] = measurement
            }
        }

        let order = measurementDisplayOrder
        return latestByType.values.sorted { lhs, rhs in
            let lhsOrder = order[lhs.type] ?? Int.max
            let rhsOrder = order[rhs.type] ?? Int.max

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            if lhs.measuredAt != rhs.measuredAt {
                return lhs.measuredAt < rhs.measuredAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// 기존 중복 측정값을 실제 데이터에서도 정리합니다.
    ///
    /// - Returns: 삭제한 중복 측정값 개수
    @discardableResult
    func deduplicateMeasurements(modelContext: ModelContext? = nil) -> Int {
        var latestByType: [String: MeasurementModel] = [:]

        for measurement in measurements {
            if let current = latestByType[measurement.type] {
                if measurement.isPreferred(over: current) {
                    latestByType[measurement.type] = measurement
                }
            } else {
                latestByType[measurement.type] = measurement
            }
        }

        let keepIDs = Set(latestByType.values.map { $0.id })
        let duplicates = measurements.filter { !keepIDs.contains($0.id) }

        for duplicate in duplicates {
            measurements.removeAll { $0.id == duplicate.id }
            modelContext?.delete(duplicate)
        }

        return duplicates.count
    }

    /// 측정값을 타입 기준으로 저장합니다.
    ///
    /// 같은 측정 타입은 하나만 유지하고 기존 값을 갱신합니다.
    @discardableResult
    func upsertMeasurement(
        type measurementType: MeasurementType,
        value: Double,
        unit: String = "cm",
        confidence: Double,
        measuredAt: Date = Date(),
        startPoint: CGPoint? = nil,
        endPoint: CGPoint? = nil,
        method: MeasurementMethod,
        modelContext: ModelContext? = nil
    ) -> MeasurementModel {
        let rawType = measurementType.rawValue
        let matchingMeasurements = measurements.filter { $0.type == rawType }

        let measurement: MeasurementModel
        if let existing = matchingMeasurements.first {
            measurement = existing
        } else {
            measurement = MeasurementModel(
                type: rawType,
                value: value,
                unit: unit,
                confidence: confidence,
                measuredAt: measuredAt,
                measurementMethodRaw: method.rawValue
            )
            measurements.append(measurement)
            measurement.clothingItem = self
        }

        measurement.type = rawType
        measurement.value = value
        measurement.unit = unit
        measurement.confidence = confidence
        measurement.measuredAt = measuredAt
        measurement.startPointX = startPoint.map { Double($0.x) }
        measurement.startPointY = startPoint.map { Double($0.y) }
        measurement.endPointX = endPoint.map { Double($0.x) }
        measurement.endPointY = endPoint.map { Double($0.y) }
        measurement.pathPoints = nil
        measurement.measurementMethodRaw = method.rawValue
        measurement.clothingItem = self

        for duplicate in matchingMeasurements.dropFirst() {
            measurements.removeAll { $0.id == duplicate.id }
            modelContext?.delete(duplicate)
        }

        return measurement
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

    /// 완료된 측정 항목 개수
    var completedMeasurements: Int {
        guard let clothingType = clothingType else { return 0 }
        return clothingType.requiredMeasurements.filter { measurementType in
            measurements.contains { $0.type == measurementType.rawValue }
        }.count
    }

    /// 필수 측정 항목 총 개수
    var totalRequiredMeasurements: Int {
        clothingType?.requiredMeasurements.count ?? 0
    }

    /// 저장된 이미지 로드
    func loadImage() -> UIImage? {
        guard let imagePath = imagePath else { return nil }
        return try? ImageFileManager.shared.loadImage(at: imagePath)
    }

    /// 저장된 depth map 로드
    ///
    /// - Returns: Depth map 이미지 (grayscale PNG), 없으면 nil
    func loadDepthMap() -> UIImage? {
        guard let depthMapPath = depthMapPath else { return nil }
        return try? ImageFileManager.shared.loadImage(at: depthMapPath)
    }

    /// 원본 이미지 크기
    var originalImageSize: CGSize? {
        guard let width = originalImageWidth, let height = originalImageHeight else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    /// 처리된 이미지 크기
    var processedImageSize: CGSize? {
        guard let width = processedImageWidth, let height = processedImageHeight else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    /// 크롭 영역 (원본 이미지 기준)
    var cropRect: CGRect? {
        guard
            let originX = cropOriginX,
            let originY = cropOriginY,
            let width = cropWidth,
            let height = cropHeight
        else {
            return nil
        }
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    /// 카메라 intrinsics 행렬
    var cameraIntrinsicsMatrix: simd_float3x3? {
        guard let data = cameraIntrinsicsData else { return nil }
        guard data.count == MemoryLayout<simd_float3x3>.size else { return nil }
        return data.withUnsafeBytes { buffer -> simd_float3x3? in
            guard buffer.count == MemoryLayout<simd_float3x3>.size else { return nil }
            return buffer.load(as: simd_float3x3.self)
        }
    }

    /// 카메라 이미지 해상도
    var cameraResolutionSize: CGSize? {
        guard let width = cameraResolutionWidth, let height = cameraResolutionHeight else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private var measurementDisplayOrder: [String: Int] {
        let preferredOrder = (clothingType?.requiredMeasurements ?? []) +
            (clothingType?.optionalMeasurements ?? [])
        return Dictionary(uniqueKeysWithValues: preferredOrder.enumerated().map { index, type in
            (type.rawValue, index)
        })
    }
}

private extension MeasurementModel {
    func isPreferred(over other: MeasurementModel) -> Bool {
        if measuredAt != other.measuredAt {
            return measuredAt > other.measuredAt
        }

        if hasCoordinates != other.hasCoordinates {
            return hasCoordinates
        }

        if confidence != other.confidence {
            return confidence > other.confidence
        }

        return id.uuidString > other.id.uuidString
    }
}

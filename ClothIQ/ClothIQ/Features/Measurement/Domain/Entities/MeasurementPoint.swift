//
//  MeasurementPoint.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  AR 공간의 측정 포인트를 나타내는 도메인 엔티티입니다.
//  사용자가 선택한 3D 공간의 좌표와 메타데이터를 포함합니다.
//

import Foundation
import simd

/// AR 공간의 측정 포인트
///
/// 사용자가 화면을 탭하여 선택한 3D 공간의 위치를 나타냅니다.
/// LiDAR 깊이 데이터를 기반으로 실제 공간 좌표를 저장합니다.
///
struct MeasurementPoint: Identifiable, Equatable {
    /// 고유 식별자
    let id: UUID

    /// 3D 공간 좌표 (월드 좌표계)
    ///
    /// ARKit의 월드 좌표계에서의 위치입니다.
    /// 단위: 미터 (meter)
    let worldPosition: SIMD3<Float>

    /// 화면 좌표
    ///
    /// 사용자가 탭한 2D 화면 좌표입니다.
    let screenPosition: CGPoint

    /// 깊이 값 (미터)
    ///
    /// 카메라로부터의 거리입니다.
    let depth: Float

    /// 신뢰도 (0.0 ~ 1.0)
    ///
    /// LiDAR 깊이 데이터의 품질을 나타냅니다.
    let confidence: Float

    /// 카메라 pitch 각도 (도)
    ///
    /// 측정 시점의 카메라 기울기 각도입니다.
    /// 0° = 수평, 90° = 수직 (아래를 향함)
    let cameraPitchAngle: Float

    /// 생성 시간
    let timestamp: Date

    /// 라벨 (선택적)
    ///
    /// 측정 포인트의 설명입니다.
    /// 예: "어깨 왼쪽", "가슴 오른쪽"
    var label: String?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        worldPosition: SIMD3<Float>,
        screenPosition: CGPoint,
        depth: Float,
        confidence: Float,
        cameraPitchAngle: Float = 0,
        timestamp: Date = Date(),
        label: String? = nil
    ) {
        self.id = id
        self.worldPosition = worldPosition
        self.screenPosition = screenPosition
        self.depth = depth
        self.confidence = confidence
        self.cameraPitchAngle = cameraPitchAngle
        self.timestamp = timestamp
        self.label = label
    }
}

// MARK: - Convenience Extensions

extension MeasurementPoint {
    /// 두 포인트 간의 거리 계산 (미터)
    ///
    /// - Parameter other: 다른 측정 포인트
    /// - Returns: 두 포인트 사이의 유클리드 거리 (미터)
    func distance(to other: MeasurementPoint) -> Float {
        return simd_distance(worldPosition, other.worldPosition)
    }

    /// 두 포인트 간의 거리 계산 (센티미터)
    ///
    /// - Parameter other: 다른 측정 포인트
    /// - Returns: 두 포인트 사이의 거리 (센티미터)
    func distanceInCentimeters(to other: MeasurementPoint) -> Double {
        return Double(distance(to: other)) * 100.0
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
        default:
            return .low
        }
    }

    /// 유효한 포인트인지 확인
    ///
    /// 신뢰도가 최소 임계값 이상인지 확인합니다.
    var isValid: Bool {
        let settings = MeasurementSettings.shared
        return confidence >= settings.minConfidence && depth > 0
    }
}

// MARK: - Static Helpers

extension MeasurementPoint {
    /// 최소 신뢰도 임계값
    ///
    /// MeasurementSettings에서 동적으로 가져옵니다.
    static var minimumConfidence: Float {
        return MeasurementSettings.shared.minConfidence
    }

    /// 최소 깊이 (미터) - 너무 가까우면 측정 불가
    static let minimumDepth: Float = 0.2

    /// 최대 깊이 (미터) - 너무 멀면 정확도 감소
    static let maximumDepth: Float = 3.0
}

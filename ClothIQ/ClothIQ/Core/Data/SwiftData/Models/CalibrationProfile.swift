//
//  CalibrationProfile.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  교정 프로파일 데이터 모델입니다.
//  측정 시스템의 임계값 설정과 보정 계수를 저장합니다.
//
//  Key Responsibilities:
//  - 임계값 설정 저장 (신뢰도, 깊이 품질, 최적 거리 등)
//  - 보정 계수 목록 관리 (1:N)
//  - 프로파일 메타데이터 관리 (이름, 생성일시 등)
//

import Foundation
import SwiftData

/// 교정 프로파일 데이터 모델
///
/// 측정 시스템의 임계값 파라미터와 보정 계수를 저장하는 프로파일입니다.
/// 다양한 측정 환경이나 의류 타입에 맞춘 프로파일을 생성하여 관리할 수 있습니다.
///
/// ## Relationships
/// - `calibrationFactors`: 1:N (하나의 프로파일은 여러 보정 계수를 가짐)
///
/// ## Example
/// ```swift
/// let profile = CalibrationProfile(
///     name: "반바지 기준",
///     minConfidence: 0.6,
///     optimalMinDistance: 0.7,
///     optimalMaxDistance: 1.0
/// )
/// modelContext.insert(profile)
/// ```
///
@Model
final class CalibrationProfile {

    // MARK: - Properties

    /// 고유 식별자
    var id: UUID

    /// 프로파일 이름
    ///
    /// 예: "반바지 기준", "긴팔 기준", "낮은 조명 환경" 등
    var name: String

    /// 생성 일시
    var createdAt: Date

    /// 수정 일시
    var updatedAt: Date

    // MARK: - 신뢰도 임계값

    /// 최소 신뢰도 임계값
    ///
    /// 측정 포인트의 최소 신뢰도 값입니다.
    /// 이 값보다 낮은 신뢰도를 가진 측정 포인트는 무시됩니다.
    ///
    /// - 기본값: 0.6
    var minConfidence: Float

    /// 낮은 신뢰도 경고 임계값
    ///
    /// 이 값보다 낮은 신뢰도는 경고 메시지를 표시합니다.
    ///
    /// - 기본값: 0.7
    var lowConfidenceWarning: Float

    /// 매우 낮은 신뢰도 임계값
    ///
    /// 이 값보다 낮은 신뢰도는 측정을 거부합니다.
    ///
    /// - 기본값: 0.4
    var veryLowConfidence: Float

    // MARK: - 깊이 품질

    /// 최소 깊이 커버리지
    ///
    /// 측정 영역에서 유효한 깊이 데이터가 차지해야 하는 최소 비율입니다.
    ///
    /// - 기본값: 0.2 (20%)
    var minDepthCoverage: Float

    /// 중간 깊이 커버리지
    ///
    /// 경고를 표시할 깊이 커버리지 임계값입니다.
    ///
    /// - 기본값: 0.1 (10%)
    var midDepthCoverage: Float

    // MARK: - 최적 측정 거리

    /// 최적 측정 거리 (최소)
    ///
    /// 카메라에서 의류까지의 권장 최소 거리입니다. (미터 단위)
    ///
    /// - 기본값: 0.7m
    var optimalMinDistance: Float

    /// 최적 측정 거리 (최대)
    ///
    /// 카메라에서 의류까지의 권장 최대 거리입니다. (미터 단위)
    ///
    /// - 기본값: 1.0m
    var optimalMaxDistance: Float

    // MARK: - 평면 투영 설정

    /// 평면 추정에 사용할 샘플 포인트 수
    ///
    /// 더 많은 샘플을 사용하면 정확도가 높아지지만 성능이 저하될 수 있습니다.
    ///
    /// - 기본값: 100
    var planeSampleCount: Int

    /// 평면 오차 허용 범위
    ///
    /// 평면 추정 시 허용되는 최대 오차 비율입니다.
    ///
    /// - 기본값: 0.5 (50%)
    var planeErrorTolerance: Float

    // MARK: - Relationships

    /// 보정 계수 목록
    ///
    /// 이 프로파일에 속한 측정 타입별 보정 계수들입니다.
    /// Cascade delete: 프로파일 삭제 시 보정 계수도 함께 삭제됩니다.
    @Relationship(deleteRule: .cascade)
    var calibrationFactors: [CalibrationFactor]

    // MARK: - Initialization

    /// 교정 프로파일을 초기화합니다.
    ///
    /// - Parameters:
    ///   - id: 고유 식별자 (기본값: 새로운 UUID)
    ///   - name: 프로파일 이름
    ///   - createdAt: 생성 일시 (기본값: 현재 시각)
    ///   - updatedAt: 수정 일시 (기본값: 현재 시각)
    ///   - minConfidence: 최소 신뢰도 (기본값: 0.6)
    ///   - lowConfidenceWarning: 낮은 신뢰도 경고 (기본값: 0.7)
    ///   - veryLowConfidence: 매우 낮은 신뢰도 (기본값: 0.4)
    ///   - minDepthCoverage: 최소 깊이 커버리지 (기본값: 0.2)
    ///   - midDepthCoverage: 중간 깊이 커버리지 (기본값: 0.1)
    ///   - optimalMinDistance: 최적 거리 최소값 (기본값: 0.7m)
    ///   - optimalMaxDistance: 최적 거리 최대값 (기본값: 1.0m)
    ///   - planeSampleCount: 평면 샘플 개수 (기본값: 100)
    ///   - planeErrorTolerance: 평면 오차 허용 (기본값: 0.5)
    ///   - calibrationFactors: 보정 계수 목록 (기본값: 빈 배열)
    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        minConfidence: Float = 0.6,
        lowConfidenceWarning: Float = 0.7,
        veryLowConfidence: Float = 0.4,
        minDepthCoverage: Float = 0.2,
        midDepthCoverage: Float = 0.1,
        optimalMinDistance: Float = 0.7,
        optimalMaxDistance: Float = 1.0,
        planeSampleCount: Int = 100,
        planeErrorTolerance: Float = 0.5,
        calibrationFactors: [CalibrationFactor] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.minConfidence = minConfidence
        self.lowConfidenceWarning = lowConfidenceWarning
        self.veryLowConfidence = veryLowConfidence
        self.minDepthCoverage = minDepthCoverage
        self.midDepthCoverage = midDepthCoverage
        self.optimalMinDistance = optimalMinDistance
        self.optimalMaxDistance = optimalMaxDistance
        self.planeSampleCount = planeSampleCount
        self.planeErrorTolerance = planeErrorTolerance
        self.calibrationFactors = calibrationFactors
    }
}

// MARK: - Convenience Methods

extension CalibrationProfile {

    /// 프로파일을 업데이트합니다.
    ///
    /// updatedAt 속성을 현재 시각으로 자동 갱신합니다.
    func markAsUpdated() {
        self.updatedAt = Date()
    }

    /// 특정 측정 타입의 보정 계수를 조회합니다.
    ///
    /// - Parameters:
    ///   - measurementType: 측정 타입
    ///   - clothingType: 의류 타입
    /// - Returns: 해당하는 보정 계수. 없으면 nil
    func calibrationFactor(
        for measurementType: MeasurementType,
        clothingType: ClothingType
    ) -> CalibrationFactor? {
        return calibrationFactors.first { factor in
            factor.measurementType == measurementType.rawValue &&
            factor.clothingType == clothingType.rawValue
        }
    }

    /// 보정 계수를 추가하거나 업데이트합니다.
    ///
    /// 이미 동일한 측정 타입과 의류 타입의 보정 계수가 존재하면 업데이트하고,
    /// 없으면 새로 추가합니다.
    ///
    /// - Parameter factor: 추가/업데이트할 보정 계수
    func upsertCalibrationFactor(_ factor: CalibrationFactor) {
        if let existingIndex = calibrationFactors.firstIndex(where: {
            $0.measurementType == factor.measurementType &&
            $0.clothingType == factor.clothingType
        }) {
            // 기존 보정 계수 업데이트
            calibrationFactors[existingIndex] = factor
        } else {
            // 새 보정 계수 추가
            calibrationFactors.append(factor)
        }
        markAsUpdated()
    }
}

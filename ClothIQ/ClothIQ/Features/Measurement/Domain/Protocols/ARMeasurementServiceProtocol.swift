//
//  ARMeasurementServiceProtocol.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  AR 측정 서비스의 프로토콜입니다.
//  측정 로직을 추상화하여 테스트 가능성과 유지보수성을 향상시킵니다.
//
//  Key Responsibilities:
//  - AR 프레임에서 3D 좌표 추출
//  - 깊이 데이터 처리
//  - 신뢰도 평가
//  - 거리 계산
//

import Foundation
import ARKit
import simd

/// AR 측정 서비스 프로토콜
///
/// AR 측정 관련 비즈니스 로직을 추상화합니다.
/// 이를 통해 ViewModel은 구체적인 구현에 의존하지 않습니다.
///
protocol ARMeasurementServiceProtocol {

    // MARK: - Coordinate Extraction

    /// 화면 좌표에서 3D 월드 좌표를 추출합니다.
    ///
    /// - Parameters:
    ///   - screenPoint: 화면 좌표
    ///   - frame: AR 프레임
    /// - Returns: 측정 포인트 (실패 시 nil)
    /// - Throws: ARError (깊이 데이터 부족 등)
    func extractMeasurementPoint(
        at screenPoint: CGPoint,
        from frame: ARFrame
    ) throws -> MeasurementPoint?

    // MARK: - Distance Calculation

    /// 두 측정 포인트 간의 거리를 계산합니다.
    ///
    /// - Parameters:
    ///   - start: 시작 포인트
    ///   - end: 끝 포인트
    /// - Returns: 거리 (센티미터)
    func calculateDistance(
        from start: MeasurementPoint,
        to end: MeasurementPoint
    ) -> Double

    // MARK: - Validation

    /// 측정 포인트의 유효성을 검증합니다.
    ///
    /// - Parameter point: 측정 포인트
    /// - Returns: 유효성 여부와 에러 메시지
    func validatePoint(_ point: MeasurementPoint) -> (isValid: Bool, error: ARError?)

    /// 측정 환경의 적합성을 평가합니다.
    ///
    /// - Parameter frame: AR 프레임
    /// - Returns: 환경 적합성 점수 (0.0 ~ 1.0)
    func assessEnvironment(from frame: ARFrame) -> Float

    // MARK: - Camera Alignment

    /// 카메라 정렬 상태를 계산합니다.
    ///
    /// - Parameters:
    ///   - frame: AR 프레임
    ///   - planeAnchor: 감지된 평면 앵커
    /// - Returns: 카메라 정렬 데이터 (평면이 없으면 nil)
    func calculateCameraAlignment(
        from frame: ARFrame,
        planeAnchor: ARPlaneAnchor?
    ) -> CameraAlignmentData?

    // MARK: - Confidence Assessment

    /// 측정 결과의 전체 신뢰도를 평가합니다.
    ///
    /// - Parameters:
    ///   - points: 측정 포인트 목록
    ///   - environmentScore: 환경 점수
    /// - Returns: 신뢰도 (0.0 ~ 1.0)
    func assessOverallConfidence(
        points: [MeasurementPoint],
        environmentScore: Float
    ) -> Float

    // MARK: - Multi-Sampling (Enhanced Measurement)

    /// 포인트 샘플링을 시작합니다 (다중 프레임 수집).
    ///
    /// - Parameter screenPoint: 화면 좌표
    /// - Returns: 샘플링 세션 ID
    func startPointSampling(at screenPoint: CGPoint) -> String

    /// AR 프레임에서 샘플을 수집하고 진행률을 반환합니다.
    ///
    /// - Parameters:
    ///   - samplingID: 샘플링 세션 ID
    ///   - frame: AR 프레임
    /// - Returns: 진행률 (0.0 ~ 1.0), 완료되면 nil
    /// - Throws: ARError (깊이 데이터 부족 등)
    func collectSample(
        for samplingID: String,
        from frame: ARFrame
    ) throws -> Float?

    /// 샘플링을 완료하고 정제된 측정 포인트를 반환합니다.
    ///
    /// - Parameter samplingID: 샘플링 세션 ID
    /// - Returns: 정제된 측정 포인트 (칼만 필터 + 다중 샘플링 적용)
    /// - Throws: ARError (샘플 부족 등)
    func finalizeSampledPoint(
        for samplingID: String
    ) throws -> MeasurementPoint

    /// 진행 중인 샘플링을 취소합니다.
    ///
    /// - Parameter samplingID: 샘플링 세션 ID
    func cancelSampling(for samplingID: String)
}

// MARK: - Default Implementations

extension ARMeasurementServiceProtocol {

    /// 두 포인트 간 거리 계산 (기본 구현)
    func calculateDistance(
        from start: MeasurementPoint,
        to end: MeasurementPoint
    ) -> Double {
        return start.distanceInCentimeters(to: end)
    }

    /// 포인트 유효성 검증 (기본 구현)
    func validatePoint(_ point: MeasurementPoint) -> (isValid: Bool, error: ARError?) {
        // 원거리 측정만 제한: 근거리(<30cm) 차단은 사용자 요청으로 비활성화
        if point.depth > MeasurementPoint.maximumDepth {
            return (false, .tooFar(maximumDistance: Double(MeasurementPoint.maximumDepth * 100)))
        }

        // 신뢰도 확인
        if point.confidence < MeasurementPoint.minimumConfidence {
            return (false, .confidenceTooLow(score: Double(point.confidence)))
        }

        return (true, nil)
    }

    /// 전체 신뢰도 평가 (기본 구현)
    func assessOverallConfidence(
        points: [MeasurementPoint],
        environmentScore: Float
    ) -> Float {
        guard !points.isEmpty else { return 0.0 }

        // 포인트 신뢰도 평균
        let avgPointConfidence = points.reduce(0.0) { $0 + $1.confidence } / Float(points.count)

        // 가중 평균: 포인트 신뢰도 70%, 환경 점수 30%
        return (avgPointConfidence * 0.7) + (environmentScore * 0.3)
    }
}

//
//  ARMeasurementService.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  AR 측정 서비스의 구현체입니다.
//  LiDAR 깊이 데이터를 활용하여 정확한 측정을 수행합니다.
//
//  Key Responsibilities:
//  - AR 프레임에서 측정 포인트 추출
//  - 깊이 데이터 검증
//  - 측정 환경 평가
//  - 신뢰도 계산
//

import Foundation
import ARKit
import simd

/// AR 측정 서비스
///
/// ARMeasurementServiceProtocol의 실제 구현체입니다.
///
final class ARMeasurementService: ARMeasurementServiceProtocol {

    // MARK: - Properties

    /// 뷰포트 크기 (화면 크기)
    private let viewportSize: CGSize

    // MARK: - Initialization

    init(viewportSize: CGSize = UIScreen.main.bounds.size) {
        self.viewportSize = viewportSize
    }

    // MARK: - ARMeasurementServiceProtocol

    func extractMeasurementPoint(
        at screenPoint: CGPoint,
        from frame: ARFrame
    ) throws -> MeasurementPoint? {
        // Scene Depth 확인 (smoothedSceneDepth 우선 사용)
        guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else {
            throw ARError.insufficientDepthData
        }

        let depthMap = sceneDepth.depthMap
        let confidenceMap = sceneDepth.confidenceMap

        // 카메라 해상도 기반 좌표 변환
        let depthMapSize = CGSize(
            width: CGFloat(CVPixelBufferGetWidth(depthMap)),
            height: CGFloat(CVPixelBufferGetHeight(depthMap))
        )

        // 화면 좌표 → 깊이 맵 좌표 (직접 변환)
        let scaleX = depthMapSize.width / viewportSize.width
        let scaleY = depthMapSize.height / viewportSize.height

        let depthMapPoint = CGPoint(
            x: screenPoint.x * scaleX,
            y: screenPoint.y * scaleY
        )

        // 0~1 범위로 정규화
        let normalizedPoint = CGPoint(
            x: depthMapPoint.x / depthMapSize.width,
            y: depthMapPoint.y / depthMapSize.height
        )

        // 깊이 값 추출
        guard let depth = DepthDataProcessor.extractDepth(
            at: normalizedPoint,
            from: depthMap
        ) else {
            throw ARError.insufficientDepthData
        }

        // 신뢰도 추출
        let confidence = DepthDataProcessor.extractConfidence(
            at: normalizedPoint,
            from: confidenceMap
        ) ?? 0.7

        // 3D 월드 좌표 계산 (화면 좌표 그대로 전달)
        let worldPosition = DepthDataProcessor.calculateWorldPosition(
            screenPoint: screenPoint,
            depth: depth,
            camera: frame.camera,
            viewportSize: viewportSize
        )

        // 측정 포인트 생성
        let point = MeasurementPoint(
            worldPosition: worldPosition,
            screenPosition: screenPoint,
            depth: depth,
            confidence: confidence
        )

        // 유효성 검증
        let validation = validatePoint(point)
        if !validation.isValid, let error = validation.error {
            throw error
        }

        return point
    }

    func assessEnvironment(from frame: ARFrame) -> Float {
        var scores: [Float] = []

        // 1. 깊이 데이터 품질 평가
        if let depthMap = frame.sceneDepth?.depthMap {
            let depthQuality = DepthDataProcessor.assessDepthQuality(depthMap: depthMap)
            scores.append(depthQuality)
        }

        // 2. 추적 상태 평가
        let trackingScore = assessTrackingState(frame.camera.trackingState)
        scores.append(trackingScore)

        // 3. 조명 조건 평가
        if let lightEstimate = frame.lightEstimate {
            let lightingScore = assessLighting(lightEstimate)
            scores.append(lightingScore)
        }

        // 4. 카메라 안정성 평가 (모션 블러)
        // TODO: 카메라 모션 분석 추가

        // 평균 점수 계산
        guard !scores.isEmpty else { return 0.5 }
        let avgScore = scores.reduce(0, +) / Float(scores.count)

        return avgScore
    }

    // MARK: - Private Helpers

    /// 추적 상태 평가
    private func assessTrackingState(_ state: ARCamera.TrackingState) -> Float {
        switch state {
        case .normal:
            return 1.0

        case .limited(let reason):
            switch reason {
            case .initializing:
                return 0.5
            case .relocalizing:
                return 0.6
            case .excessiveMotion:
                return 0.3
            case .insufficientFeatures:
                return 0.4
            @unknown default:
                return 0.5
            }

        case .notAvailable:
            return 0.0
        }
    }

    /// 조명 조건 평가
    private func assessLighting(_ lightEstimate: ARLightEstimate) -> Float {
        let ambientIntensity = lightEstimate.ambientIntensity

        // 적정 조명 범위: 500 ~ 2000 lumens
        switch ambientIntensity {
        case 1000...1500:
            return 1.0  // 이상적인 조명

        case 500..<1000, 1500..<2000:
            return 0.8  // 양호한 조명

        case 300..<500, 2000..<3000:
            return 0.6  // 허용 가능한 조명

        case 0..<300:
            return 0.3  // 너무 어두움

        default:
            return 0.5  // 너무 밝음
        }
    }
}

// MARK: - Mock Service (테스트용)

#if DEBUG
/// 테스트용 Mock AR 측정 서비스
final class MockARMeasurementService: ARMeasurementServiceProtocol {

    var shouldSucceed: Bool = true
    var mockConfidence: Float = 0.9
    var mockEnvironmentScore: Float = 0.85

    func extractMeasurementPoint(
        at screenPoint: CGPoint,
        from frame: ARFrame
    ) throws -> MeasurementPoint? {
        guard shouldSucceed else {
            throw ARError.insufficientDepthData
        }

        // Mock 포인트 생성
        let worldPosition = SIMD3<Float>(
            Float(screenPoint.x) / 1000.0,
            Float(screenPoint.y) / 1000.0,
            -1.0
        )

        return MeasurementPoint(
            worldPosition: worldPosition,
            screenPosition: screenPoint,
            depth: 1.0,
            confidence: mockConfidence
        )
    }

    func assessEnvironment(from frame: ARFrame) -> Float {
        return mockEnvironmentScore
    }
}
#endif

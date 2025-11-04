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

    init(viewportSize: CGSize? = nil) {
        if let viewportSize = viewportSize {
            self.viewportSize = viewportSize
        } else {
            // Get screen size from first window scene if available
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first {
                self.viewportSize = windowScene.screen.bounds.size
            } else {
                // Fallback to a reasonable default for iPhone
                self.viewportSize = CGSize(width: 393, height: 852)
            }
        }
    }

    // MARK: - ARMeasurementServiceProtocol

    func extractMeasurementPoint(
        at screenPoint: CGPoint,
        from frame: ARFrame
    ) throws -> MeasurementPoint? {
        // Scene Depth 확인 (AutoSize.md: sceneDepth 사용)
        guard let sceneDepth = frame.sceneDepth else {
            throw ARError.insufficientDepthData
        }

        let depthMap = sceneDepth.depthMap
        let confidenceMap = sceneDepth.confidenceMap

        // AR 카메라 이미지 해상도 사용 (중요!)
        let imageResolution = frame.camera.imageResolution

        // 깊이 맵 크기
        let depthMapSize = CGSize(
            width: CGFloat(CVPixelBufferGetWidth(depthMap)),
            height: CGFloat(CVPixelBufferGetHeight(depthMap))
        )

        // 화면 좌표 → 깊이 맵 좌표 (AR 카메라 해상도 기준)
        let scaleX = depthMapSize.width / imageResolution.width
        let scaleY = depthMapSize.height / imageResolution.height

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

        // 3D 월드 좌표 계산
        // 중요: screenPoint는 이미 imageResolution 기준이므로,
        // viewportSize도 imageResolution을 전달해야 함!
        let worldPosition = DepthDataProcessor.calculateWorldPosition(
            screenPoint: screenPoint,
            depth: depth,
            camera: frame.camera,
            viewportSize: imageResolution  // ❌ viewportSize가 아닌 imageResolution 사용!
        )

        // 카메라 각도 계산
        let cameraPitchAngle = AngleCorrectionService.calculateCameraPitch(from: frame.camera)

        // 측정 포인트 생성
        let point = MeasurementPoint(
            worldPosition: worldPosition,
            screenPosition: screenPoint,
            depth: depth,
            confidence: confidence,
            cameraPitchAngle: cameraPitchAngle
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

    /// 카메라 정렬 상태 계산
    ///
    /// 감지된 평면과 카메라의 각도 및 거리를 계산합니다.
    ///
    /// - Parameters:
    ///   - frame: 현재 AR 프레임
    ///   - planeAnchor: 감지된 평면 앵커 (옵셔널)
    /// - Returns: 카메라 정렬 데이터. 평면이 없으면 nil
    func calculateCameraAlignment(
        from frame: ARFrame,
        planeAnchor: ARPlaneAnchor?
    ) -> CameraAlignmentData? {
        guard let planeAnchor = planeAnchor else {
            return nil
        }

        // 카메라 transform 추출
        let cameraTransform = frame.camera.transform

        // 카메라의 forward 벡터 (Z축, 카메라가 보는 방향)
        // ARKit에서 카메라는 -Z 방향을 바라봄
        let cameraForward = SIMD3<Float>(
            -cameraTransform.columns.2.x,
            -cameraTransform.columns.2.y,
            -cameraTransform.columns.2.z
        )

        // 평면의 법선 벡터 (평면에 수직인 벡터)
        // ARKit의 평면은 Y축이 법선 방향
        let planeTransform = planeAnchor.transform
        let planeNormal = SIMD3<Float>(
            planeTransform.columns.1.x,
            planeTransform.columns.1.y,
            planeTransform.columns.1.z
        )

        // 두 벡터 정규화
        let normalizedCameraForward = normalize(cameraForward)
        let normalizedPlaneNormal = normalize(planeNormal)

        // 두 벡터 사이의 각도 계산 (내적 사용)
        // cos(θ) = a · b / (|a| * |b|)
        let dotProduct = dot(normalizedCameraForward, normalizedPlaneNormal)

        // 각도 계산 (라디안 → 도)
        // 카메라가 평면을 위에서 수직으로 내려다보면 dotProduct ≈ -1 (반대 방향)
        // 평행하면 dotProduct ≈ 0
        // 따라서 부호를 반전시켜 계산
        let adjustedDotProduct = -dotProduct
        let angleRadians = acos(max(-1.0, min(1.0, adjustedDotProduct)))
        let tiltAngle = Double(angleRadians * 180.0 / .pi)

        // tiltAngle:
        // - 0° = 완벽한 수직 (카메라가 평면을 정확히 내려다봄)
        // - 90° = 완벽한 수평 (카메라가 평면과 평행)

        // 카메라 위치 추출
        let cameraPosition = SIMD3<Float>(
            cameraTransform.columns.3.x,
            cameraTransform.columns.3.y,
            cameraTransform.columns.3.z
        )

        // 평면 중심 위치 추출
        let planePosition = SIMD3<Float>(
            planeTransform.columns.3.x,
            planeTransform.columns.3.y,
            planeTransform.columns.3.z
        )

        // 카메라에서 평면까지의 거리 계산
        let distance = simd_distance(cameraPosition, planePosition)

        print("📐 [ARMeasurementService] 카메라 정렬 계산")
        print("📐   - dotProduct: \(String(format: "%.3f", dotProduct)) → adjusted: \(String(format: "%.3f", adjustedDotProduct))")
        print("📐   - 틸트 각도: \(String(format: "%.1f", tiltAngle))°")
        print("📐   - 거리: \(String(format: "%.2f", distance))m")
        print("📐   - 평면 크기: \(String(format: "%.2f", planeAnchor.planeExtent.width))m x \(String(format: "%.2f", planeAnchor.planeExtent.height))m")

        return CameraAlignmentData(
            tiltAngle: tiltAngle,
            distance: Double(distance),
            hasPlaneDetected: true
        )
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

    func calculateCameraAlignment(
        from frame: ARFrame,
        planeAnchor: ARPlaneAnchor?
    ) -> CameraAlignmentData? {
        // Mock implementation - 테스트용 정렬 데이터 반환
        guard planeAnchor != nil else {
            return nil
        }

        return CameraAlignmentData(
            tiltAngle: 5.0,  // Mock: 거의 수직
            distance: 0.5,   // Mock: 50cm
            hasPlaneDetected: true
        )
    }
}
#endif

//
//  PhotoMeasurementCalculator.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  사진 기반 측정 계산 유틸리티입니다.
//  저장된 depth map을 활용하여 두 지점 간 실제 3D 거리를 계산합니다.
//
//  Key Responsibilities:
//  - Depth map에서 깊이 값 추출
//  - 2D 이미지 좌표 → 3D 월드 좌표 변환
//  - 두 지점 간 유클리드 거리 계산
//  - 측정 신뢰도 평가
//

import Foundation
import UIKit
import CoreVideo
import Darwin  // for utsname
import simd

/// 사진 기반 측정 계산기
///
/// LiDAR depth map을 활용하여 이미지에서 선택한 두 지점 간의
/// 실제 3D 거리를 계산합니다.
///
struct PhotoMeasurementCalculator {

    // MARK: - Measurement Result

    /// 측정 결과
    struct MeasurementResult {
        /// 측정값 (센티미터)
        let distance: Double

        /// 측정 신뢰도 (0.0 ~ 1.0)
        let confidence: Double

        /// 시작 지점의 depth 값 (미터)
        let point1Depth: Float

        /// 끝 지점의 depth 값 (미터)
        let point2Depth: Float

        /// 3D 거리 (미터)
        let distance3D: Float
    }

    // MARK: - Calculation

    /// 두 지점 간 거리를 측정합니다.
    ///
    /// - Parameters:
    ///   - point1: 시작 지점 (이미지 픽셀 좌표)
    ///   - point2: 끝 지점 (이미지 픽셀 좌표)
    ///   - depthMap: Depth map (CVPixelBuffer)
    ///   - imageSize: 이미지 크기
    /// - Returns: 측정 결과, 실패 시 nil
    static func calculateDistance(
        from point1: CGPoint,
        to point2: CGPoint,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?
    ) -> MeasurementResult? {

        // 1. 두 지점의 depth 값 추출
        guard let depth1 = extractDepth(at: point1, from: depthMap, imageSize: imageSize),
              let depth2 = extractDepth(at: point2, from: depthMap, imageSize: imageSize) else {
            print("❌ Depth 값 추출 실패")
            return nil
        }

        print("📊 Depth 값: P1=\(depth1)m, P2=\(depth2)m")

        // 2. 이미지 좌표 → 정규화 좌표 (0~1)
        let normalized1 = CGPoint(
            x: point1.x / imageSize.width,
            y: point1.y / imageSize.height
        )
        let normalized2 = CGPoint(
            x: point2.x / imageSize.width,
            y: point2.y / imageSize.height
        )

        // 3. 3D 좌표 계산 (intrinsics가 있으면 우선 사용)
        let pos1: SIMD3<Float>
        let pos2: SIMD3<Float>

        if let intrinsics = cameraIntrinsics, let resolution = cameraResolution {
            print("📐 Intrinsics 기반 좌표 변환 사용")
            pos1 = projectToCameraSpace(
                point: point1,
                depth: depth1,
                intrinsics: intrinsics,
                imageSize: imageSize,
                cameraResolution: resolution
            )
            pos2 = projectToCameraSpace(
                point: point2,
                depth: depth2,
                intrinsics: intrinsics,
                imageSize: imageSize,
                cameraResolution: resolution
            )
        } else {
            print("ℹ️ Intrinsics 없음 - FOV 근사 사용")

            // 정규화 좌표 → NDC (Normalized Device Coordinates: -1~1)
            // 중심이 (0, 0)인 좌표계로 변환
            let ndc1 = SIMD2<Float>(
                Float(normalized1.x * 2.0 - 1.0),
                Float((1.0 - normalized1.y) * 2.0 - 1.0)  // Y축 반전
            )
            let ndc2 = SIMD2<Float>(
                Float(normalized2.x * 2.0 - 1.0),
                Float((1.0 - normalized2.y) * 2.0 - 1.0)
            )

            // FOV 기반 3D 위치 계산
            let fovY = getEstimatedFOV()  // 라디안
            let aspect: Float = Float(imageSize.width / imageSize.height)

            let tanHalfFovY = tan(fovY / 2.0)
            let tanHalfFovX = tanHalfFovY * aspect

            pos1 = SIMD3<Float>(
                ndc1.x * depth1 * tanHalfFovX,
                ndc1.y * depth1 * tanHalfFovY,
                -depth1
            )

            pos2 = SIMD3<Float>(
                ndc2.x * depth2 * tanHalfFovX,
                ndc2.y * depth2 * tanHalfFovY,
                -depth2
            )
        }

        print("📍 3D 위치: P1=(\(pos1.x), \(pos1.y), \(pos1.z)), P2=(\(pos2.x), \(pos2.y), \(pos2.z))")

        // 5. 평면 투영 거리 계산
        // 의류는 평평하게 놓여있으므로, 평면상의 거리를 계산해야 정확함
        let distance3D = simd_distance(pos1, pos2)

        // 평면 투영: 두 포인트의 평균 Z 깊이를 기준 평면으로 사용
        let avgZ = (pos1.z + pos2.z) / 2.0

        // 각 포인트를 기준 평면에 투영
        let projected1 = SIMD3<Float>(pos1.x, pos1.y, avgZ)
        let projected2 = SIMD3<Float>(pos2.x, pos2.y, avgZ)

        // 투영된 평면상의 거리 계산
        let distanceProjected = simd_distance(projected1, projected2)

        // 두 방식 모두 로깅
        print("📏 3D 직선 거리: \(String(format: "%.2f", distance3D * 100))cm")
        print("📏 평면 투영 거리: \(String(format: "%.2f", distanceProjected * 100))cm (권장)")

        // 평면 투영 거리 사용 (더 정확함)
        let distanceCM = Double(distanceProjected * 100.0)  // 미터 → 센티미터

        // Z축 차이가 클 경우 경고
        let zDiff = abs(pos1.z - pos2.z)
        if zDiff > 0.1 {  // 10cm 이상 차이
            print("⚠️ Z축 차이 큼: \(String(format: "%.2f", zDiff * 100))cm - 카메라 각도 확인 필요")
        }

        print("📏 측정 거리: \(String(format: "%.2f", distanceCM))cm")

        // 6. 신뢰도 계산
        let confidence = calculateConfidence(depth1: depth1, depth2: depth2)

        return MeasurementResult(
            distance: distanceCM,
            confidence: confidence,
            point1Depth: depth1,
            point2Depth: depth2,
            distance3D: distance3D
        )
    }

    // MARK: - Private Helpers

    private static func projectToCameraSpace(
        point: CGPoint,
        depth: Float,
        intrinsics: simd_float3x3,
        imageSize: CGSize,
        cameraResolution: CGSize
    ) -> SIMD3<Float> {
        let fx = intrinsics[0, 0]
        let fy = intrinsics[1, 1]
        let cx = intrinsics[2, 0]
        let cy = intrinsics[2, 1]

        guard fx != 0, fy != 0, imageSize.width > 0, imageSize.height > 0,
              cameraResolution.width > 0, cameraResolution.height > 0 else {
            return SIMD3<Float>(0, 0, -depth)
        }

        let scaleX = Float(cameraResolution.width / imageSize.width)
        let scaleY = Float(cameraResolution.height / imageSize.height)

        let pixelX = Float(point.x) * scaleX
        let pixelY = Float(point.y) * scaleY

        let x = (pixelX - cx) * depth / fx
        let y = (pixelY - cy) * depth / fy
        let z = -depth

        return SIMD3<Float>(x, y, z)
    }

    /// 이미지 좌표에서 depth 값을 추출합니다.
    ///
    /// - Parameters:
    ///   - point: 이미지 픽셀 좌표
    ///   - depthMap: Depth map (CVPixelBuffer)
    ///   - imageSize: 이미지 크기
    /// - Returns: Depth 값 (미터), 실패 시 nil
    private static func extractDepth(
        at point: CGPoint,
        from depthMap: CVPixelBuffer,
        imageSize: CGSize
    ) -> Float? {
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        // 이미지 좌표 → depth map 좌표 변환
        let normalizedX = point.x / imageSize.width
        let normalizedY = point.y / imageSize.height

        let depthX = Int(normalizedX * CGFloat(depthWidth))
        let depthY = Int(normalizedY * CGFloat(depthHeight))

        // 범위 확인
        guard depthX >= 0 && depthX < depthWidth &&
              depthY >= 0 && depthY < depthHeight else {
            return nil
        }

        // Depth 값 읽기
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let rowData = baseAddress + depthY * bytesPerRow
        let depth = rowData.assumingMemoryBound(to: Float32.self)[depthX]

        // 유효성 검증
        guard depth > 0 && depth.isFinite && depth < 10.0 else {
            return nil
        }

        return depth
    }

    /// 측정 신뢰도를 계산합니다.
    ///
    /// - Parameters:
    ///   - depth1: 시작 지점 depth
    ///   - depth2: 끝 지점 depth
    /// - Returns: 신뢰도 (0.0 ~ 1.0)
    private static func calculateConfidence(depth1: Float, depth2: Float) -> Double {
        // 신뢰도 계산 요소:
        // 1. Depth 값의 유효성 (0.0 ~ 1.0)
        // 2. 두 지점의 depth 차이 (차이가 클수록 신뢰도 낮음)

        // 유효한 depth 범위: 0.2m ~ 5.0m
        let validRange: ClosedRange<Float> = 0.2...5.0
        let depthValidity = (validRange.contains(depth1) && validRange.contains(depth2)) ? 1.0 : 0.5

        // Depth 차이 (같은 평면에 있을수록 신뢰도 높음)
        let depthDifference = abs(depth1 - depth2)
        let maxAllowedDiff: Float = 2.0  // 2m 이상 차이나면 신뢰도 낮음
        let depthDiffScore = max(0.0, 1.0 - Double(depthDifference / maxAllowedDiff))

        // 종합 신뢰도 (가중 평균)
        let confidence = (depthValidity * 0.4) + (depthDiffScore * 0.6)

        // 사진 기반 측정은 LiDAR 직접 측정보다 낮은 신뢰도
        // 최대 0.85로 제한
        return min(confidence * 0.85, 0.85)
    }

    /// 디바이스별 추정 FOV를 반환합니다.
    ///
    /// - Returns: 세로 FOV (라디안)
    ///
    /// - Note:
    ///   실제 FOV는 디바이스와 렌즈에 따라 다르며, 가장 정확한 값은
    ///   ARFrame의 camera.intrinsics를 사용하는 것입니다.
    ///
    ///   현재 구현은 근사치를 사용하므로 ±5-10% 오차가 있을 수 있습니다.
    ///
    ///   참고 FOV 값:
    ///   - iPhone 12 Pro 이후 (Wide): ~69.4도
    ///   - iPhone 12 Pro 이후 (Ultra Wide): ~120도
    ///   - 일반 iPhone (Wide): ~60-65도
    private static func getEstimatedFOV() -> Float {
        // 디바이스 모델 확인
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }

        // LiDAR 탑재 기기는 일반적으로 Wide 카메라 FOV ~69.4도
        // 정확한 값은 기기마다 다르지만, 합리적인 기본값 사용
        if let model = modelCode {
            // iPhone 12 Pro 이후 또는 iPad Pro 2020 이후
            if model.contains("iPhone13") || // iPhone 12 series
               model.contains("iPhone14") || // iPhone 13 series
               model.contains("iPhone15") || // iPhone 14 series
               model.contains("iPhone16") || // iPhone 15 series
               model.contains("iPhone17") || // iPhone 16 series
               model.contains("iPad13") ||   // iPad Pro 2021
               model.contains("iPad14") {    // iPad Pro 2022+
                // 최신 기기: ~69.4도
                return 69.4 * .pi / 180.0
            }
        }

        // 기본값: 보수적인 60도 (구형 iPhone)
        return 60.0 * .pi / 180.0
    }

    // MARK: - Validation

    /// 측정 가능한 지점인지 검증합니다.
    ///
    /// - Parameters:
    ///   - point: 이미지 픽셀 좌표
    ///   - depthMap: Depth map
    ///   - imageSize: 이미지 크기
    /// - Returns: 측정 가능하면 true
    static func isValidMeasurementPoint(
        _ point: CGPoint,
        depthMap: CVPixelBuffer,
        imageSize: CGSize
    ) -> Bool {
        guard let depth = extractDepth(at: point, from: depthMap, imageSize: imageSize) else {
            return false
        }

        // 유효한 depth 범위 확인
        return depth > 0.1 && depth < 10.0
    }
}

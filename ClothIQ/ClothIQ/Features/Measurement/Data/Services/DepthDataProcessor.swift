//
//  DepthDataProcessor.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  LiDAR 깊이 데이터 처리 유틸리티입니다.
//  ARFrame의 Scene Depth 데이터를 추출하고 처리합니다.
//
//  Key Responsibilities:
//  - 깊이 맵에서 값 샘플링
//  - 신뢰도 맵 처리
//  - 화면 좌표 → 깊이 데이터 변환
//

import Foundation
import ARKit
import CoreVideo

/// 깊이 데이터 처리 유틸리티
///
/// LiDAR Scene Depth 데이터를 처리하는 헬퍼 클래스입니다.
///
struct DepthDataProcessor {

    // MARK: - Depth Extraction

    /// 화면 좌표에서 깊이 값을 추출합니다.
    ///
    /// - Parameters:
    ///   - point: 화면 좌표
    ///   - depthMap: 깊이 맵 (CVPixelBuffer)
    /// - Returns: 깊이 값 (미터), 실패 시 nil
    static func extractDepth(
        at point: CGPoint,
        from depthMap: CVPixelBuffer
    ) -> Float? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        // 화면 좌표를 깊이 맵 좌표로 변환 (이미 정규화되어 있다고 가정)
        // point.x, point.y는 0~1 범위의 normalized 좌표
        let u = Int(point.x * CGFloat(width))
        let v = Int(point.y * CGFloat(height))

        // 범위 확인
        guard u >= 0 && u < width && v >= 0 && v < height else {
            return nil
        }

        // 픽셀 버퍼 잠금
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        // 깊이 값 읽기
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        let rowData = baseAddress + v * bytesPerRow
        let depth = rowData.assumingMemoryBound(to: Float32.self)[u]

        // 유효하지 않은 깊이 값 필터링
        guard depth > 0 && depth.isFinite else {
            return nil
        }

        return depth
    }

    // MARK: - Confidence Extraction

    /// 화면 좌표에서 신뢰도 값을 추출합니다.
    ///
    /// - Parameters:
    ///   - point: 화면 좌표
    ///   - confidenceMap: 신뢰도 맵 (CVPixelBuffer)
    /// - Returns: 신뢰도 (0.0 ~ 1.0), 실패 시 nil
    static func extractConfidence(
        at point: CGPoint,
        from confidenceMap: CVPixelBuffer?
    ) -> Float? {
        guard let confidenceMap = confidenceMap else {
            return 0.7 // 기본값
        }

        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)

        let normalizedX = Float(point.x) / Float(width)
        let normalizedY = Float(point.y) / Float(height)

        let u = Int(normalizedX * Float(width))
        let v = Int(normalizedY * Float(height))

        guard u >= 0 && u < width && v >= 0 && v < height else {
            return nil
        }

        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
            return nil
        }

        let rowData = baseAddress + v * bytesPerRow
        let confidenceValue = rowData.assumingMemoryBound(to: UInt8.self)[u]

        // ARConfidenceLevel: 0 (low), 1 (medium), 2 (high)
        // 0.0 ~ 1.0 범위로 정규화
        return Float(confidenceValue) / 2.0
    }

    // MARK: - World Position Calculation

    /// 화면 좌표와 깊이를 사용하여 3D 월드 좌표를 계산합니다.
    ///
    /// 카메라 intrinsics를 사용하여 정확한 3D 좌표를 계산합니다.
    ///
    /// - Parameters:
    ///   - screenPoint: 화면 좌표 (픽셀 좌표)
    ///   - depth: 깊이 값 (미터)
    ///   - camera: AR 카메라
    ///   - viewportSize: 뷰포트 크기
    /// - Returns: 월드 좌표
    static func calculateWorldPosition(
        screenPoint: CGPoint,
        depth: Float,
        camera: ARCamera,
        viewportSize: CGSize
    ) -> SIMD3<Float> {
        // 카메라 내부 파라미터 (intrinsics)
        let intrinsics = camera.intrinsics
        let imageResolution = camera.imageResolution

        // 화면 좌표를 이미지 해상도 좌표계로 변환
        let scaleX = imageResolution.width / viewportSize.width
        let scaleY = imageResolution.height / viewportSize.height

        let imagePoint = CGPoint(
            x: screenPoint.x * scaleX,
            y: screenPoint.y * scaleY
        )

        // Camera intrinsics에서 파라미터 추출
        let fx = intrinsics[0, 0]  // focal length X
        let fy = intrinsics[1, 1]  // focal length Y
        let cx = intrinsics[2, 0]  // principal point X
        let cy = intrinsics[2, 1]  // principal point Y

        // 카메라 좌표계에서 3D 위치 계산 (핀홀 카메라 모델)
        let x = (Float(imagePoint.x) - cx) * depth / fx
        let y = (Float(imagePoint.y) - cy) * depth / fy
        let z = -depth  // ARKit은 카메라가 -Z 방향을 바라봄

        let cameraSpacePosition = SIMD3<Float>(x, y, z)

        // 카메라 좌표계 → 월드 좌표계 변환
        let cameraTransform = camera.transform
        let worldPosition4 = cameraTransform * SIMD4<Float>(cameraSpacePosition, 1.0)
        let worldPosition = SIMD3<Float>(worldPosition4.x, worldPosition4.y, worldPosition4.z)

        print("📍 좌표 변환: 화면(\(screenPoint.x), \(screenPoint.y)) → 이미지(\(imagePoint.x), \(imagePoint.y)) → 카메라(\(x), \(y), \(z)) → 월드(\(worldPosition.x), \(worldPosition.y), \(worldPosition.z)) @ \(depth)m")

        return worldPosition
    }


    // MARK: - Quality Assessment

    /// 깊이 데이터의 품질을 평가합니다.
    ///
    /// - Parameter depthMap: 깊이 맵
    /// - Returns: 품질 점수 (0.0 ~ 1.0)
    static func assessDepthQuality(depthMap: CVPixelBuffer) -> Float {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let totalPixels = width * height

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return 0.0
        }

        var validPixelCount = 0
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        for y in 0..<height {
            let rowData = baseAddress + y * bytesPerRow
            let pixels = rowData.assumingMemoryBound(to: Float32.self)

            for x in 0..<width {
                let depth = pixels[x]
                if depth > 0 && depth.isFinite {
                    validPixelCount += 1
                }
            }
        }

        // 유효한 픽셀 비율
        let coverage = Float(validPixelCount) / Float(totalPixels)

        // 더 관대한 평가 기준: 20% 이상이면 충분
        if coverage >= 0.2 {
            return min(coverage * 2.5, 1.0)
        } else if coverage >= 0.1 {
            return 0.5
        } else {
            return coverage * 5.0
        }
    }
}

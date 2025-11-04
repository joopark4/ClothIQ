//
//  PlaneEstimator.swift
//  ClothIQ
//
//  Created on 2025-10-31
//
//  Description:
//  Least Squares Plane Fitting 유틸리티입니다.
//  3D 포인트 집합으로부터 최적의 평면을 추정하고,
//  포인트를 평면에 투영하는 기능을 제공합니다.
//
//  Key Responsibilities:
//  - Least Squares 방법으로 평면 방정식 추정
//  - 3D 포인트를 평면에 투영
//  - 평면에서의 거리 계산 (카메라 기울기 보정)
//
//  References:
//  - AutoSize02.md: 평면 추정 및 투영을 통한 정확도 개선
//

import Foundation
import simd
import CoreVideo
import CoreGraphics

/// 3D 평면 표현
///
/// 평면 방정식: ax + by + cz + d = 0
/// normal = (a, b, c), d = 상수항
struct Plane {
    /// 평면의 법선 벡터 (정규화됨)
    let normal: SIMD3<Float>

    /// 평면 방정식의 상수항
    let d: Float

    /// 평면 위의 한 점 (원점에서 평면까지의 최단 거리 지점)
    var pointOnPlane: SIMD3<Float> {
        return -d * normal
    }

    /// 포인트에서 평면까지의 부호 있는 거리
    ///
    /// - Parameter point: 3D 포인트
    /// - Returns: 평면까지의 거리 (양수: 법선 방향, 음수: 법선 반대 방향)
    func signedDistance(to point: SIMD3<Float>) -> Float {
        return dot(normal, point) + d
    }

    /// 포인트를 평면에 투영
    ///
    /// - Parameter point: 투영할 3D 포인트
    /// - Returns: 평면에 투영된 포인트
    func project(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let distance = signedDistance(to: point)
        return point - distance * normal
    }
}

/// 평면 추정 유틸리티
///
/// Least Squares 방법을 사용하여 3D 포인트 집합으로부터
/// 최적의 평면을 추정합니다.
final class PlaneEstimator {

    /// Least Squares 방법으로 평면 추정
    ///
    /// ## Algorithm
    /// 1. 포인트들의 중심(centroid) 계산
    /// 2. 중심으로부터의 상대 좌표로 변환
    /// 3. 공분산 행렬 계산
    /// 4. 고유값 분해(eigenvalue decomposition)로 법선 벡터 추정
    ///
    /// - Parameter points: 평면을 추정할 3D 포인트 집합 (최소 3개)
    /// - Returns: 추정된 평면, 포인트가 부족하면 nil
    static func estimatePlane(from points: [SIMD3<Float>]) -> Plane? {
        guard points.count >= 3 else {
            print("⚠️ [PlaneEstimator] Not enough points for plane estimation: \(points.count)")
            return nil
        }

        print("📐 [PlaneEstimator] Estimating plane from \(points.count) points...")

        // 1. 중심(centroid) 계산
        var centroid = SIMD3<Float>(0, 0, 0)
        for point in points {
            centroid += point
        }
        centroid /= Float(points.count)

        print("  📍 Centroid: (\(centroid.x), \(centroid.y), \(centroid.z))")

        // 2. 중심으로부터의 상대 좌표
        let centered = points.map { $0 - centroid }

        // 3. 공분산 행렬 계산 (3x3)
        // C = Σ(p_i * p_i^T) / n
        var cov = matrix_float3x3()
        for p in centered {
            // 외적(outer product): p * p^T
            cov[0] += SIMD3<Float>(p.x * p.x, p.x * p.y, p.x * p.z)
            cov[1] += SIMD3<Float>(p.y * p.x, p.y * p.y, p.y * p.z)
            cov[2] += SIMD3<Float>(p.z * p.x, p.z * p.y, p.z * p.z)
        }
        cov[0] /= Float(points.count)
        cov[1] /= Float(points.count)
        cov[2] /= Float(points.count)

        // 4. 고유값 분해로 법선 벡터 추정
        // 가장 작은 고유값에 해당하는 고유벡터가 법선 벡터
        // 단순화를 위해 cross product 방법 사용

        // 안전한 정규화 함수
        func safeNormalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
            let len = length(v)
            if len < 0.0001 {
                return SIMD3<Float>(0, 0, 1) // 기본값 (z축)
            }
            return v / len
        }

        // 첫 번째와 두 번째 주성분 벡터 추정 (최대 분산 방향)
        let pc1 = safeNormalize(cov[0]) // 첫 번째 주성분
        let pc2Temp = cov[1] - dot(cov[1], pc1) * pc1
        let pc2 = safeNormalize(pc2Temp) // 두 번째 주성분 (직교화)

        // 법선 벡터는 두 주성분에 수직 (cross product)
        let crossProduct = cross(pc1, pc2)
        let normal = safeNormalize(crossProduct)

        print("  🧭 Normal vector: (\(normal.x), \(normal.y), \(normal.z))")

        // 5. 평면 방정식의 d 계산
        // d = -dot(normal, centroid)
        let d = -dot(normal, centroid)

        print("  📊 Plane equation: \(normal.x)x + \(normal.y)y + \(normal.z)z + \(d) = 0")

        // 6. Plane 객체 생성
        let plane = Plane(normal: normal, d: d)

        // 7. 평면 적합도(goodness of fit) 계산
        let avgDistance = averageDistanceToPlane(points: points, plane: plane)
        print("  ✅ Average distance to plane: \(avgDistance * 100)cm")

        if avgDistance > 0.05 { // 5cm 이상 오차
            print("  ⚠️ Warning: Large average distance, plane fit may be poor")
        }

        return plane
    }

    /// 평면 적합도 평가 - 포인트들의 평균 거리
    ///
    /// - Parameters:
    ///   - points: 평가할 포인트 집합
    ///   - plane: 평면
    /// - Returns: 평면까지의 평균 거리 (미터)
    static func averageDistanceToPlane(points: [SIMD3<Float>], plane: Plane) -> Float {
        guard !points.isEmpty else { return 0 }

        let totalDistance = points.reduce(0.0) { sum, point in
            return sum + abs(plane.signedDistance(to: point))
        }

        return totalDistance / Float(points.count)
    }

    /// 평면에서 두 포인트 간 거리 계산
    ///
    /// 두 포인트를 평면에 투영한 후 거리를 계산합니다.
    /// 카메라 기울기가 보정된 정확한 거리를 제공합니다.
    ///
    /// - Parameters:
    ///   - p1: 첫 번째 포인트
    ///   - p2: 두 번째 포인트
    ///   - plane: 평면
    /// - Returns: 평면에서의 거리 (미터)
    static func distanceOnPlane(
        from p1: SIMD3<Float>,
        to p2: SIMD3<Float>,
        plane: Plane
    ) -> Float {
        // 두 포인트를 평면에 투영
        let proj1 = plane.project(p1)
        let proj2 = plane.project(p2)

        // 투영된 포인트 간 거리
        let distance = length(proj2 - proj1)

        return distance
    }

    /// 깊이 맵에서 영역의 평면 추정
    ///
    /// 지정된 영역의 깊이 포인트들을 샘플링하여 평면을 추정합니다.
    ///
    /// - Parameters:
    ///   - depthMap: LiDAR 깊이 맵
    ///   - region: 샘플링할 정규화된 영역 (0~1)
    ///   - cameraTransform: AR 카메라 변환 행렬
    ///   - cameraIntrinsics: 카메라 내부 파라미터
    ///   - sampleCount: 샘플링할 포인트 개수 (기본값: 100)
    /// - Returns: 추정된 평면, 실패 시 nil
    static func estimatePlaneFromDepth(
        depthMap: CVPixelBuffer,
        region: CGRect,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        sampleCount: Int = 100
    ) -> Plane? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        // 영역을 픽셀 좌표로 변환 (경계 안전 처리)
        let minX = max(0, Int(region.minX * CGFloat(width)))
        let maxX = min(width - 1, Int(region.maxX * CGFloat(width)))
        let minY = max(0, Int(region.minY * CGFloat(height)))
        let maxY = min(height - 1, Int(region.maxY * CGFloat(height)))

        // 깊이 맵 잠금
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            print("❌ [PlaneEstimator] Failed to access depth map")
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        // 3D 포인트 샘플링
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(sampleCount)

        let stepX = max(1, (maxX - minX) / Int(sqrt(Double(sampleCount))))
        let stepY = max(1, (maxY - minY) / Int(sqrt(Double(sampleCount))))

        for y in stride(from: minY, to: maxY, by: stepY) {
            for x in stride(from: minX, to: maxX, by: stepX) {
                // 안전한 버퍼 접근 - 각 행마다 별도로 접근
                let rowData = baseAddress + y * bytesPerRow
                let pixels = rowData.assumingMemoryBound(to: Float32.self)

                // 범위 검사
                guard x < width && y < height else { continue }
                let depth = pixels[x]

                // 유효한 깊이값만 사용 (0.1m ~ 5m)
                guard depth > 0.1 && depth < 5.0 else { continue }

                // 2D → 3D 변환 (카메라 intrinsics 사용)
                let fx = cameraIntrinsics[0][0]
                let fy = cameraIntrinsics[1][1]
                let cx = cameraIntrinsics[2][0]
                let cy = cameraIntrinsics[2][1]

                let xNorm = (Float(x) - cx) / fx
                let yNorm = (Float(y) - cy) / fy

                // 카메라 좌표계에서의 3D 포인트
                let pointCamera = SIMD3<Float>(xNorm * depth, yNorm * depth, depth)

                // 월드 좌표계로 변환
                let pointWorld = cameraTransform * SIMD4<Float>(pointCamera, 1.0)

                points.append(SIMD3<Float>(pointWorld.x, pointWorld.y, pointWorld.z))

                if points.count >= sampleCount {
                    break
                }
            }

            if points.count >= sampleCount {
                break
            }
        }

        print("📊 [PlaneEstimator] Sampled \(points.count) depth points from region")

        // 평면 추정
        return estimatePlane(from: points)
    }
}

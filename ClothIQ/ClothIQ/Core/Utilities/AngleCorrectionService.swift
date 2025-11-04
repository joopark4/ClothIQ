//
//  AngleCorrectionService.swift
//  ClothIQ
//
//  Created on 2025-11-04
//
//  Description:
//  Angle correction utilities for improving measurement accuracy when
//  the camera is not perpendicular to the clothing surface.
//
//  Key Features:
//  - Camera pitch angle calculation
//  - Horizontal plane projection
//  - Surface normal estimation from point clouds
//  - Confidence assessment based on incident angle
//
//  Usage:
//  ```swift
//  let angle = AngleCorrectionService.calculateCameraPitch(from: camera)
//  let corrected = AngleCorrectionService.correctMeasurement(
//      rawDistance: 42.5,
//      incidentAngle: angle
//  )
//  ```
//

import Foundation
import ARKit
import simd

/// Angle correction service for measurement accuracy improvement
///
/// This service provides utilities for correcting measurements when the camera
/// is tilted relative to the clothing surface. It uses ARKit's gravity-aligned
/// world coordinate system to project measurements onto a horizontal plane.
///
/// ## Theory
/// When measuring at an angle θ, the apparent distance d' is related to the
/// true distance d by: d = d' / cos(θ)
///
/// ## Limitations
/// - Assumes clothing is on a horizontal surface
/// - Accuracy decreases for angles > 60°
/// - Does not handle curved surfaces well
///
final class AngleCorrectionService {

    // MARK: - Camera Angle Calculation

    /// Calculate the camera's pitch angle (tilt from horizontal)
    ///
    /// - Parameter camera: AR camera
    /// - Returns: Pitch angle in degrees (0° = horizontal, 90° = looking straight down)
    ///
    /// ## Algorithm
    /// 1. Extract camera's forward vector (Z-axis)
    /// 2. Project forward vector onto horizontal plane (XZ)
    /// 3. Calculate angle using atan2(vertical, horizontal)
    ///
    /// ## Example
    /// - Looking straight ahead (horizontal): 0°
    /// - Looking down at 45°: 45°
    /// - Looking straight down: 90°
    ///
    static func calculateCameraPitch(from camera: ARCamera) -> Float {
        let transform = camera.transform

        // Camera's forward vector (negative Z-axis in camera space)
        let forward = SIMD3<Float>(
            transform.columns.2.x,
            transform.columns.2.y,
            transform.columns.2.z
        )

        // Project forward vector onto horizontal plane (XZ plane, Y=0)
        let forwardXZ = SIMD3<Float>(forward.x, 0, forward.z)
        let forwardXZLength = simd_length(forwardXZ)

        // Calculate pitch angle using atan2
        // Negative because forward.y is positive when looking down
        let pitchRadians = atan2(-forward.y, forwardXZLength)

        // Convert to degrees
        return pitchRadians * 180.0 / .pi
    }

    /// Calculate the camera's roll angle (rotation around forward axis)
    ///
    /// - Parameter camera: AR camera
    /// - Returns: Roll angle in degrees
    static func calculateCameraRoll(from camera: ARCamera) -> Float {
        let transform = camera.transform

        // Camera's right vector (X-axis)
        let right = SIMD3<Float>(
            transform.columns.0.x,
            transform.columns.0.y,
            transform.columns.0.z
        )

        // Project right vector onto horizontal plane
        let rightXZ = SIMD3<Float>(right.x, 0, right.z)

        // Calculate roll angle
        let rollRadians = atan2(right.y, simd_length(rightXZ))

        return rollRadians * 180.0 / .pi
    }

    // MARK: - Plane Projection

    /// Project a 3D point onto the horizontal plane (Y=0)
    ///
    /// - Parameter point: 3D point in world coordinates
    /// - Returns: Projected point on horizontal plane
    ///
    /// This effectively removes the vertical component, projecting the point
    /// onto the ground plane defined by Y=0 in ARKit's gravity-aligned world space.
    ///
    static func projectToHorizontalPlane(point: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3<Float>(point.x, 0, point.z)
    }

    /// Calculate horizontal distance between two points
    ///
    /// - Parameters:
    ///   - start: Start point in world coordinates
    ///   - end: End point in world coordinates
    /// - Returns: Horizontal distance in centimeters
    ///
    /// This measures the distance as if both points were on the ground,
    /// ignoring any vertical separation.
    ///
    static func calculateHorizontalDistance(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>
    ) -> Double {
        let projectedStart = projectToHorizontalPlane(point: start)
        let projectedEnd = projectToHorizontalPlane(point: end)

        let distance = simd_distance(projectedStart, projectedEnd)

        // Convert meters to centimeters
        return Double(distance) * 100.0
    }

    // MARK: - Measurement Correction

    /// Correct a measurement based on camera incident angle
    ///
    /// - Parameters:
    ///   - rawDistance: Uncorrected distance (cm)
    ///   - incidentAngle: Angle between camera and surface normal (degrees)
    /// - Returns: Corrected distance (cm)
    ///
    /// ## Formula
    /// corrected = raw / cos(angle)
    ///
    /// ## Angle Limits
    /// - 0°~30°: Full correction applied
    /// - 30°~60°: Good correction
    /// - 60°~75°: Acceptable correction (warning threshold)
    /// - >75°: No correction (too unreliable)
    ///
    static func correctMeasurement(
        rawDistance: Double,
        incidentAngle: Float
    ) -> Double {
        // Don't correct if angle is too large (unreliable)
        // 75도까지 허용 (이전 60도에서 완화)
        guard incidentAngle < 75 else {
            return rawDistance
        }

        // Convert angle to radians
        let angleRadians = incidentAngle * .pi / 180.0

        // Cosine correction factor
        let correctionFactor = 1.0 / cos(angleRadians)

        // Apply correction
        return rawDistance * Double(correctionFactor)
    }

    // MARK: - Confidence Assessment

    /// Assess measurement confidence based on incident angle
    ///
    /// - Parameter angle: Incident angle in degrees
    /// - Returns: Confidence score (0.0 ~ 1.0)
    ///
    /// ## Confidence Levels
    /// - 0°~20°: Perfect (1.0)
    /// - 20°~40°: Very Good (0.9)
    /// - 40°~60°: Good (0.7)
    /// - 60°~75°: Moderate (0.5)
    /// - >75°: Poor (0.3)
    ///
    static func assessConfidence(for angle: Float) -> Float {
        switch angle {
        case 0..<20:
            return 1.0      // Perfect
        case 20..<40:
            return 0.9      // Very Good
        case 40..<60:
            return 0.7      // Good
        case 60..<75:
            return 0.5      // Moderate
        default:
            return 0.3      // Poor
        }
    }

    /// Get a user-friendly description of the measurement quality
    ///
    /// - Parameter angle: Incident angle in degrees
    /// - Returns: Quality description
    static func qualityDescription(for angle: Float) -> String {
        switch angle {
        case 0..<20:
            return "완벽"
        case 20..<40:
            return "매우 좋음"
        case 40..<60:
            return "양호"
        case 60..<75:
            return "보통"
        default:
            return "낮음 - 각도가 너무 큼"
        }
    }

    /// Check if the angle is within acceptable range
    ///
    /// - Parameter angle: Incident angle in degrees
    /// - Returns: True if angle is acceptable (<75°)
    static func isAngleAcceptable(_ angle: Float) -> Bool {
        return angle < 75
    }

    /// Check if the angle is optimal
    ///
    /// - Parameter angle: Incident angle in degrees
    /// - Returns: True if angle is optimal (<40°)
    static func isAngleOptimal(_ angle: Float) -> Bool {
        return angle < 40
    }

    // MARK: - Advanced: Surface Normal Estimation

    /// Estimate surface normal from a point cloud (simplified implementation)
    ///
    /// - Parameter points: Array of 3D points on the surface
    /// - Returns: Tuple of (normal vector, planarity confidence), or nil if insufficient points
    ///
    /// ## Algorithm
    /// Uses Principal Component Analysis (PCA) to find the plane that best fits
    /// the point cloud. The normal is the eigenvector corresponding to the smallest eigenvalue.
    ///
    /// ## Requirements
    /// - Minimum 3 points
    /// - Points should be roughly coplanar
    ///
    /// ## Note
    /// This is a simplified implementation. For production use, consider using
    /// RANSAC or other robust plane fitting algorithms.
    ///
    static func estimateSurfaceNormal(
        from points: [SIMD3<Float>]
    ) -> (normal: SIMD3<Float>, confidence: Float)? {
        guard points.count >= 3 else { return nil }

        // 1. Calculate centroid (center of mass)
        let centroid = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)

        // 2. Center points around centroid
        let centeredPoints = points.map { $0 - centroid }

        // 3. Compute covariance matrix (simplified)
        // For a full implementation, use Accelerate framework
        var sumXX: Float = 0, sumYY: Float = 0, sumZZ: Float = 0
        var sumXY: Float = 0, sumXZ: Float = 0, sumYZ: Float = 0

        for p in centeredPoints {
            sumXX += p.x * p.x
            sumYY += p.y * p.y
            sumZZ += p.z * p.z
            sumXY += p.x * p.y
            sumXZ += p.x * p.z
            sumYZ += p.y * p.z
        }

        let n = Float(points.count)
        sumXX /= n; sumYY /= n; sumZZ /= n
        sumXY /= n; sumXZ /= n; sumYZ /= n

        // 4. Simplified normal estimation
        // Use cross product of two principal directions
        // This is a rough approximation; proper PCA would be better
        let v1 = SIMD3<Float>(1, 0, sumXZ / max(sumXX, 0.001))
        let v2 = SIMD3<Float>(0, 1, sumYZ / max(sumYY, 0.001))

        let normal = simd_normalize(simd_cross(v1, v2))

        // 5. Estimate planarity (how well points fit a plane)
        // Calculate average distance from centroid to points
        let distances = centeredPoints.map { simd_length($0) }
        let avgDistance = distances.reduce(0, +) / Float(distances.count)
        let variance = distances.map { pow($0 - avgDistance, 2) }.reduce(0, +) / Float(distances.count)

        // Low variance means points are coplanar (high planarity)
        let planarity = 1.0 - min(variance / 0.01, 1.0) // Normalize variance

        return (normal, planarity)
    }

    /// Calculate incident angle between camera view and surface normal
    ///
    /// - Parameters:
    ///   - normal: Surface normal vector
    ///   - camera: AR camera
    /// - Returns: Incident angle in degrees (0° = perpendicular)
    ///
    /// The incident angle is the angle between the camera's view direction
    /// and the surface normal. Smaller angles mean better measurement conditions.
    ///
    static func calculateIncidentAngle(
        normal: SIMD3<Float>,
        camera: ARCamera
    ) -> Float {
        // Camera's view direction (negative Z-axis)
        let viewDirection = -SIMD3<Float>(
            camera.transform.columns.2.x,
            camera.transform.columns.2.y,
            camera.transform.columns.2.z
        )

        // Normalize both vectors
        let normalizedView = simd_normalize(viewDirection)
        let normalizedNormal = simd_normalize(normal)

        // Calculate angle using dot product
        let cosAngle = simd_dot(normalizedView, normalizedNormal)

        // Clamp to avoid floating point errors
        let clampedCos = simd_clamp(cosAngle, -1.0, 1.0)

        // Convert to degrees
        let angleRadians = acos(clampedCos)
        return angleRadians * 180.0 / .pi
    }
}

// MARK: - SIMD Extensions

private extension SIMD3 where Scalar == Float {
    /// Zero vector
    static var zero: SIMD3<Float> {
        return SIMD3<Float>(0, 0, 0)
    }
}

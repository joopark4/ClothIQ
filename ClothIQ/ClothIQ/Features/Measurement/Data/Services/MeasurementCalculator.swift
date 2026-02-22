//
//  MeasurementCalculator.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  측정값 계산 유틸리티입니다.
//  의류 타입별 측정 알고리즘과 검증 로직을 제공합니다.
//
//  Key Responsibilities:
//  - 의류 타입별 측정값 계산
//  - 측정값 검증 및 필터링
//  - 이상치 감지
//  - 보정 알고리즘 적용
//

import Foundation
import simd
import CoreVideo
import CoreGraphics

/// 측정 계산 유틸리티
///
/// 의류 측정에 필요한 계산 로직을 제공합니다.
///
struct MeasurementCalculator {

    // MARK: - Distance Calculation

    /// 두 포인트 간의 유클리드 거리 계산
    ///
    /// - Parameters:
    ///   - start: 시작 포인트
    ///   - end: 끝 포인트
    /// - Returns: 거리 (센티미터)
    static func calculateDistance(
        from start: MeasurementPoint,
        to end: MeasurementPoint
    ) -> Double {
        let distance = simd_distance(start.worldPosition, end.worldPosition)
        return Double(distance) * 100.0  // 미터 → 센티미터
    }

    /// 각도 보정이 적용된 거리 계산
    ///
    /// - Parameters:
    ///   - start: 시작 포인트
    ///   - end: 끝 포인트
    ///   - useAngleCorrection: 각도 보정 사용 여부 (기본: true)
    /// - Returns: 거리 (센티미터)
    ///
    /// ## 각도 보정 알고리즘
    /// 두 포인트의 평균 카메라 각도를 사용하여 수평 거리를 계산합니다.
    /// 각도가 75도를 초과하면 보정을 적용하지 않습니다 (신뢰도 낮음).
    ///
    static func calculateCorrectedDistance(
        from start: MeasurementPoint,
        to end: MeasurementPoint,
        useAngleCorrection: Bool = true
    ) -> Double {
        // 원본 거리 계산
        let rawDistance = calculateDistance(from: start, to: end)

        // 각도 보정 미사용 시 원본 거리 반환
        guard useAngleCorrection else {
            return rawDistance
        }

        // 두 포인트의 평균 카메라 각도
        let avgAngle = (start.cameraPitchAngle + end.cameraPitchAngle) / 2.0

        // 각도가 너무 크면 보정 안 함 (신뢰도 낮음)
        guard AngleCorrectionService.isAngleAcceptable(avgAngle) else {
            return rawDistance
        }

        // 각도 보정 적용
        return AngleCorrectionService.correctMeasurement(
            rawDistance: rawDistance,
            incidentAngle: avgAngle
        )
    }

    /// 수평면 투영 거리 계산 (중력 방향 무시)
    ///
    /// - Parameters:
    ///   - start: 시작 포인트
    ///   - end: 끝 포인트
    /// - Returns: 수평 거리 (센티미터)
    ///
    /// ARKit의 월드 좌표계는 중력 방향으로 정렬되어 있으므로,
    /// Y 좌표를 무시하면 수평면상의 거리를 얻을 수 있습니다.
    ///
    static func calculateHorizontalDistance(
        from start: MeasurementPoint,
        to end: MeasurementPoint
    ) -> Double {
        return AngleCorrectionService.calculateHorizontalDistance(
            from: start.worldPosition,
            to: end.worldPosition
        )
    }

    /// 평면 투영 기반 거리 계산 (카메라 기울기 보정)
    ///
    /// AutoSize02.md: 두 포인트를 평면에 투영하여 카메라 기울기를 보정한 정확한 거리를 계산합니다.
    ///
    /// ## Algorithm
    /// 1. 두 포인트 주변의 3D 포인트들로 평면 추정 (Least Squares)
    /// 2. 두 측정 포인트를 평면에 투영
    /// 3. 투영된 포인트 간 거리 계산
    ///
    /// - Parameters:
    ///   - start: 시작 포인트
    ///   - end: 끝 포인트
    ///   - depthMap: LiDAR 깊이 맵 (평면 추정에 사용)
    ///   - cameraTransform: AR 카메라 변환 행렬
    ///   - cameraIntrinsics: 카메라 내부 파라미터
    /// - Returns: 평면 투영된 거리 (센티미터), 평면 추정 실패 시 일반 거리 반환
    static func calculateDistanceOnPlane(
        from start: MeasurementPoint,
        to end: MeasurementPoint,
        depthMap: CVPixelBuffer,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3
    ) -> Double {
        // 두 포인트 중심의 영역 정의 (두 포인트를 포함하는 영역)
        let centerX = (start.screenPosition.x + end.screenPosition.x) / 2.0
        let centerY = (start.screenPosition.y + end.screenPosition.y) / 2.0

        // 이미지 해상도 (ARFrame의 capturedImage 해상도 가정: 1920x1440)
        let imageWidth: CGFloat = 1920.0
        let imageHeight: CGFloat = 1440.0

        // 영역 크기 (두 포인트 거리의 2배 정도, 최소 0.2)
        let dx = abs(start.screenPosition.x - end.screenPosition.x) / imageWidth
        let dy = abs(start.screenPosition.y - end.screenPosition.y) / imageHeight
        let regionSize = max(0.2, max(dx, dy) * 2.0)

        // 정규화된 영역 (0~1)
        let region = CGRect(
            x: max(0, (centerX / imageWidth) - regionSize / 2),
            y: max(0, (centerY / imageHeight) - regionSize / 2),
            width: min(1.0, regionSize),
            height: min(1.0, regionSize)
        )

        // 평면 추정
        guard let plane = PlaneEstimator.estimatePlaneFromDepth(
            depthMap: depthMap,
            region: region,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics,
            sampleCount: 100
        ) else {
            return calculateDistance(from: start, to: end)
        }

        // 평면에 투영된 거리 계산
        let distanceOnPlane = PlaneEstimator.distanceOnPlane(
            from: start.worldPosition,
            to: end.worldPosition,
            plane: plane
        )

        let distanceCm = Double(distanceOnPlane) * 100.0

        // 원래 거리와 비교
        let directDistance = calculateDistance(from: start, to: end)
        let difference = abs(distanceCm - directDistance)
        let percentDiff = (difference / directDistance) * 100.0

        // 평면 투영이 50% 이상 차이나면 직접 거리 사용
        if percentDiff > 50.0 {
            return directDistance
        }

        return distanceCm
    }

    /// 여러 포인트를 거치는 총 거리 계산
    ///
    /// - Parameter points: 측정 포인트 목록
    /// - Returns: 총 거리 (센티미터)
    static func calculateTotalDistance(points: [MeasurementPoint]) -> Double {
        guard points.count >= 2 else { return 0.0 }

        var totalDistance = 0.0
        for i in 0..<points.count - 1 {
            totalDistance += calculateDistance(from: points[i], to: points[i + 1])
        }

        return totalDistance
    }

    // MARK: - Circumference Calculation

    /// 원주(둘레) 계산
    ///
    /// 여러 포인트로 원주를 근사 계산합니다.
    ///
    /// - Parameter points: 원주 상의 포인트들 (최소 3개)
    /// - Returns: 원주 (센티미터)
    static func calculateCircumference(points: [MeasurementPoint]) -> Double? {
        guard points.count >= 3 else { return nil }

        // 포인트들을 연결한 경로의 길이 계산
        let pathLength = calculateTotalDistance(points: points)

        // 시작점과 끝점을 연결하여 폐곡선 만들기
        if let firstPoint = points.first, let lastPoint = points.last {
            let closingDistance = calculateDistance(from: lastPoint, to: firstPoint)
            return pathLength + closingDistance
        }

        return pathLength
    }

    // MARK: - Clothing-Specific Measurements

    /// 어깨너비 계산
    ///
    /// - Parameters:
    ///   - leftPoint: 왼쪽 어깨 끝점
    ///   - rightPoint: 오른쪽 어깨 끝점
    /// - Returns: 어깨너비 (센티미터)
    static func calculateShoulderWidth(
        leftPoint: MeasurementPoint,
        rightPoint: MeasurementPoint
    ) -> Double {
        return calculateDistance(from: leftPoint, to: rightPoint)
    }

    /// 가슴둘레 계산
    ///
    /// - Parameter points: 가슴 둘레 상의 포인트들
    /// - Returns: 가슴둘레 (센티미터)
    static func calculateChestCircumference(points: [MeasurementPoint]) -> Double? {
        return calculateCircumference(points: points)
    }

    /// 총길이 계산 (상의)
    ///
    /// - Parameters:
    ///   - topPoint: 목 뒤 중심 (또는 어깨 상단)
    ///   - bottomPoint: 밑단
    /// - Returns: 총길이 (센티미터)
    static func calculateTopLength(
        topPoint: MeasurementPoint,
        bottomPoint: MeasurementPoint
    ) -> Double {
        return calculateDistance(from: topPoint, to: bottomPoint)
    }

    /// 소매길이 계산
    ///
    /// - Parameters:
    ///   - shoulderPoint: 어깨 끝점
    ///   - cuffPoint: 소매 끝점
    /// - Returns: 소매길이 (센티미터)
    static func calculateSleeveLength(
        shoulderPoint: MeasurementPoint,
        cuffPoint: MeasurementPoint
    ) -> Double {
        return calculateDistance(from: shoulderPoint, to: cuffPoint)
    }

    // MARK: - Validation & Filtering

    /// 측정값의 합리성 검증
    ///
    /// - Parameters:
    ///   - value: 측정값 (센티미터)
    ///   - type: 측정 타입
    /// - Returns: 유효성 여부와 경고 메시지
    static func validateMeasurement(
        value: Double,
        type: MeasurementType
    ) -> (isValid: Bool, warning: String?) {
        let (min, max) = getReasonableRange(for: type)

        if value < min {
            return (false, "측정값이 너무 작습니다. (최소: \(min)cm)")
        }

        if value > max {
            return (false, "측정값이 너무 큽니다. (최대: \(max)cm)")
        }

        // 경고 범위 (최소/최대의 10% 이내)
        let warningMin = min * 1.1
        let warningMax = max * 0.9

        if value < warningMin {
            return (true, "측정값이 일반적인 범위보다 작습니다. 재측정을 권장합니다.")
        }

        if value > warningMax {
            return (true, "측정값이 일반적인 범위보다 큽니다. 재측정을 권장합니다.")
        }

        return (true, nil)
    }

    /// 측정 타입별 합리적인 범위
    ///
    /// - Parameter type: 측정 타입
    /// - Returns: (최소값, 최대값) in 센티미터
    static func getReasonableRange(for type: MeasurementType) -> (min: Double, max: Double) {
        switch type {
        // 상의 측정 항목
        case .shoulderWidth:
            return (30.0, 60.0)  // 어깨너비
        case .chestCircumference:
            return (70.0, 150.0)  // 가슴둘레
        case .totalLength:
            return (40.0, 100.0)  // 총길이
        case .sleeveLength:
            return (15.0, 80.0)  // 소매길이
        case .armCircumference:
            return (20.0, 50.0)  // 팔둘레

        // 하의 측정 항목
        case .waistCircumference:
            return (30.0, 150.0)  // 허리둘레 (반으로 접은 상태 고려)
        case .hipCircumference:
            return (60.0, 160.0)  // 엉덩이둘레
        case .rise:
            return (20.0, 40.0)  // 밑위
        case .hem:
            return (30.0, 60.0)  // 밑단
        case .thighCircumference:
            return (40.0, 80.0)  // 허벅지둘레

        // 기타 측정 항목
        case .neckCircumference:
            return (30.0, 50.0)  // 목둘레
        case .cuffCircumference:
            return (15.0, 30.0)  // 소매둘레
        }
    }

    // MARK: - Outlier Detection

    /// 이상치 감지
    ///
    /// 여러 측정 포인트 중 이상치를 감지합니다.
    ///
    /// - Parameter points: 측정 포인트 목록
    /// - Returns: 이상치 포인트의 인덱스 목록
    static func detectOutliers(in points: [MeasurementPoint]) -> [Int] {
        guard points.count >= 3 else { return [] }

        var outlierIndices: [Int] = []

        // 신뢰도 기반 이상치 감지
        let confidences = points.map { $0.confidence }
        let avgConfidence = confidences.reduce(0, +) / Float(points.count)
        let threshold = avgConfidence * 0.5  // 평균의 50% 미만이면 이상치

        for (index, point) in points.enumerated() {
            if point.confidence < threshold {
                outlierIndices.append(index)
            }
        }

        return outlierIndices
    }

    // MARK: - Smoothing & Calibration

    /// 측정값 스무딩 (여러 측정값의 평균)
    ///
    /// - Parameter measurements: 측정값 목록
    /// - Returns: 스무딩된 측정값
    static func smoothMeasurements(_ measurements: [Double]) -> Double {
        guard !measurements.isEmpty else { return 0.0 }

        // 이상치 제거 (상위/하위 10% 제거)
        let sorted = measurements.sorted()
        let trimCount = max(1, measurements.count / 10)

        let trimmed = Array(sorted.dropFirst(trimCount).dropLast(trimCount))

        guard !trimmed.isEmpty else {
            return measurements.reduce(0, +) / Double(measurements.count)
        }

        return trimmed.reduce(0, +) / Double(trimmed.count)
    }

    /// 측정값 보정 (참조 객체 기반)
    ///
    /// - Parameters:
    ///   - measuredValue: 측정된 값
    ///   - referenceValue: 참조 값 (실제 값)
    ///   - measuredReference: 측정된 참조 값
    /// - Returns: 보정된 측정값
    static func calibrate(
        measuredValue: Double,
        referenceValue: Double,
        measuredReference: Double
    ) -> Double {
        guard measuredReference > 0 else { return measuredValue }

        let calibrationFactor = referenceValue / measuredReference
        return measuredValue * calibrationFactor
    }

    // MARK: - Advanced Circumference Calculation

    /// 개선된 둘레 계산 알고리즘 (사진 측정용)
    ///
    /// 평평하게 펼쳐진 의류 사진에서 측정한 단면 너비를 그대로 반환합니다.
    /// 사진에서는 의류의 한쪽 면만 보이므로, 측정값이 곧 단면 너비입니다.
    ///
    /// - Parameters:
    ///   - frontWidth: 전면에서 측정한 너비 (cm) - 단면의 한쪽 끝에서 다른 끝까지
    ///   - depth: 객체의 깊이 (m) - 사진 측정에서는 사용하지 않음
    ///   - type: 측정 타입
    /// - Returns: 단면 너비 (cm)
    ///
    /// ## 계산 방식
    /// 사진에서 평평하게 펼쳐진 의류를 촬영한 경우:
    /// - 측정값 = 단면 너비 (의류의 한쪽 절반)
    /// - **전체 둘레가 필요한 경우 사용자가 × 2 해야 함**
    ///
    /// 예: 허리둘레 단면이 40cm로 측정 → 표시: 40cm (전체 허리둘레는 80cm)
    static func calculateCircumferenceFromFront(
        frontWidth: Double,
        depth: Float,
        type: MeasurementType
    ) -> Double {
        // 사진 측정: 단면 너비를 그대로 반환
        // 사용자가 전체 둘레가 필요하면 × 2 계산
        return frontWidth
    }

    /// 깊이 기반 보정 계수 계산
    ///
    /// 객체와의 거리에 따른 측정 오차를 보정합니다.
    ///
    /// - Parameter depth: 객체까지의 거리 (m)
    /// - Returns: 보정 계수 (0.8 ~ 1.2)
    static func depthCorrectionFactor(depth: Float) -> Double {
        // 최적 측정 거리: 0.7m ~ 1.0m
        let optimalMinDistance: Float = 0.7
        let optimalMaxDistance: Float = 1.0

        if depth < optimalMinDistance {
            // 너무 가까움 - 약간의 축소 보정
            let ratio = depth / optimalMinDistance
            return Double(0.95 + (ratio * 0.05))
        } else if depth > optimalMaxDistance {
            // 너무 멀음 - 약간의 확대 보정
            let ratio = min(depth / optimalMaxDistance, 1.5)
            return Double(1.0 + (ratio - 1.0) * 0.2)
        } else {
            // 최적 거리
            return 1.0
        }
    }

    // MARK: - Confidence Validation

    /// 측정 포인트 후보의 신뢰도 검증
    ///
    /// 자동 감지된 측정 포인트의 신뢰도가 충분한지 검증합니다.
    ///
    /// - Parameters:
    ///   - candidates: 측정 포인트 후보 배열
    ///   - minConfidence: 최소 허용 신뢰도 (기본값: 0.6)
    /// - Returns: 검증 결과 (통과 여부, 경고 메시지)
    static func validateCandidateConfidence(
        candidates: [MeasurementPointCandidate],
        minConfidence: Float = 0.6
    ) -> (isValid: Bool, warning: String?) {
        guard !candidates.isEmpty else {
            return (false, "측정 포인트를 찾을 수 없습니다.")
        }

        // 모든 후보의 평균 신뢰도 계산
        let avgConfidence = candidates.map { $0.confidence }.reduce(0, +) / Float(candidates.count)

        // 평균 신뢰도가 임계값 미만
        if avgConfidence < minConfidence {
            return (false, "측정 포인트 신뢰도가 낮습니다 (\(Int(avgConfidence * 100))%). 의류를 더 평평하게 펼쳐주세요.")
        }

        // 개별 포인트 중 신뢰도가 매우 낮은 것이 있는지 확인
        let veryLowConfidenceThreshold: Float = 0.4
        let lowConfidencePoints = candidates.filter { $0.confidence < veryLowConfidenceThreshold }

        if !lowConfidencePoints.isEmpty {
            let types = Set(lowConfidencePoints.map { $0.type.displayName }).joined(separator: ", ")
            return (false, "\(types) 측정 포인트의 신뢰도가 매우 낮습니다. 재측정을 권장합니다.")
        }

        // 신뢰도가 낮은 포인트가 있으면 경고 (하지만 통과)
        let lowConfidenceThreshold: Float = 0.7
        let warnPoints = candidates.filter { $0.confidence < lowConfidenceThreshold }

        if !warnPoints.isEmpty {
            let types = Set(warnPoints.map { $0.type.displayName }).joined(separator: ", ")
            return (true, "\(types) 측정 포인트의 신뢰도가 다소 낮습니다 (\(Int(avgConfidence * 100))%). 결과를 확인해주세요.")
        }

        // 모든 검증 통과
        return (true, nil)
    }

    /// 측정값 신뢰도 종합 평가
    ///
    /// 여러 요소를 종합하여 최종 신뢰도를 계산합니다.
    ///
    /// - Parameters:
    ///   - candidateConfidence: 포인트 감지 신뢰도
    ///   - depthQuality: 깊이 데이터 품질 (0.0 ~ 1.0)
    ///   - environmentScore: 환경 점수 (0.0 ~ 1.0)
    ///   - valueInRange: 측정값이 합리적 범위 내인지
    /// - Returns: 최종 신뢰도 (0.0 ~ 1.0)
    static func calculateOverallConfidence(
        candidateConfidence: Float,
        depthQuality: Float = 0.9,
        environmentScore: Float = 0.85,
        valueInRange: Bool = true
    ) -> Float {
        // 가중치 설정
        let candidateWeight: Float = 0.4   // 포인트 감지 신뢰도: 40%
        let depthWeight: Float = 0.3       // 깊이 데이터 품질: 30%
        let environmentWeight: Float = 0.2 // 환경 점수: 20%
        let rangeWeight: Float = 0.1       // 범위 검증: 10%

        // 범위 점수 계산
        let rangeScore: Float = valueInRange ? 1.0 : 0.5

        // 가중 평균 계산
        let overallConfidence = (candidateConfidence * candidateWeight) +
                                (depthQuality * depthWeight) +
                                (environmentScore * environmentWeight) +
                                (rangeScore * rangeWeight)

        return max(0.0, min(1.0, overallConfidence))
    }

    /// 신뢰도에 따른 사용자 피드백 생성
    ///
    /// - Parameter confidence: 신뢰도 (0.0 ~ 1.0)
    /// - Returns: 사용자에게 표시할 피드백 메시지
    static func getFeedbackMessage(for confidence: Float) -> String {
        switch confidence {
        case 0.9...1.0:
            return "측정 품질이 매우 좋습니다."
        case 0.8..<0.9:
            return "측정 품질이 좋습니다."
        case 0.7..<0.8:
            return "측정 품질이 양호합니다."
        case 0.6..<0.7:
            return "측정 품질이 다소 낮습니다. 결과를 확인해주세요."
        case 0.5..<0.6:
            return "측정 품질이 낮습니다. 의류를 더 평평하게 펼쳐주세요."
        default:
            return "측정 품질이 매우 낮습니다. 재측정을 권장합니다."
        }
    }

    /// 신뢰도에 따른 색상 반환 (UI용)
    ///
    /// - Parameter confidence: 신뢰도 (0.0 ~ 1.0)
    /// - Returns: 신뢰도 수준 (high, medium, low)
    static func getConfidenceLevel(for confidence: Float) -> String {
        switch confidence {
        case 0.8...1.0:
            return "high"      // 녹색
        case 0.6..<0.8:
            return "medium"    // 노란색
        default:
            return "low"       // 빨간색
        }
    }
}

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
    /// 각도가 60도를 초과하면 보정을 적용하지 않습니다 (신뢰도 낮음).
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
        case .neckCircumference:
            return (30.0, 50.0)  // 목둘레

        // 하의 측정 항목
        case .waistCircumference:
            return (50.0, 150.0)  // 허리둘레
        case .hipCircumference:
            return (70.0, 160.0)  // 엉덩이둘레
        case .rise:
            return (20.0, 40.0)  // 밑위
        case .hem:
            return (30.0, 60.0)  // 밑단
        case .thighCircumference:
            return (40.0, 80.0)  // 허벅지둘레
        case .inseam:
            return (50.0, 100.0)  // 인심
        case .outseam:
            return (60.0, 120.0)  // 아웃심
        case .kneeCircumference:
            return (30.0, 60.0)  // 무릎둘레

        // 공통 측정 항목
        case .hemWidth:
            return (30.0, 80.0)  // 밑단너비
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
}

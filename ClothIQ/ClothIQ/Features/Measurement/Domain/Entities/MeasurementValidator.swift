//
//  MeasurementValidator.swift
//  ClothIQ
//
//  Created on 2025-11-06
//
//  Description:
//  측정값 합리성 검증 유틸리티입니다.
//  LiDAR_SIZE_Ref.md의 validateMeasurements 기법을 적용하여
//  비정상적인 측정값을 필터링합니다.
//
//  Key Features:
//  - 측정값 범위 검증 (의류 타입별 최소/최대값)
//  - 비율 검증 (어깨너비 vs 총길이 등)
//  - 측정 신뢰도 종합 평가
//

import Foundation

/// 측정값 검증 결과
struct MeasurementValidationResult {
    /// 검증 통과 여부
    let isValid: Bool

    /// 실패 원인
    let failureReasons: [String]

    /// 경고 메시지
    let warnings: [String]

    /// 전체 신뢰도 점수 (0.0 ~ 1.0)
    let overallConfidence: Double
}

/// 측정값 합리성 검증기
///
/// LiDAR_SIZE_Ref.md의 검증 기법을 구현합니다:
/// - 합리성 검사: 20-100cm 범위 체크
/// - 비율 검사: 어깨너비/총길이 0.2-0.8 범위
struct MeasurementValidator {

    // MARK: - Validation Ranges (의류 타입별)

    /// 상의 측정값 범위 (센티미터)
    private static let topRanges: [MeasurementType: ClosedRange<Double>] = [
        .shoulderWidth: 20.0...100.0,       // 어깨너비
        .chestCircumference: 60.0...200.0,  // 가슴둘레
        .totalLength: 40.0...150.0,         // 총길이
        .sleeveLength: 10.0...100.0,        // 소매길이
        .armCircumference: 15.0...60.0      // 팔둘레
    ]

    /// 하의 측정값 범위 (센티미터)
    /// TODO: hipCircumference, inseam, outseam을 MeasurementType에 추가 후 활성화
    private static let bottomRanges: [MeasurementType: ClosedRange<Double>] = [
        .waistCircumference: 40.0...200.0,  // 허리둘레
        .totalLength: 20.0...150.0,         // 총길이 (반바지~긴바지)
        .rise: 15.0...50.0,                 // 밑위
        .hem: 15.0...60.0,                  // 밑단
        .thighCircumference: 30.0...100.0   // 허벅지둘레
    ]

    // MARK: - Validation Methods

    /// 측정값 검증 (종합)
    ///
    /// LiDAR_SIZE_Ref.md의 validateMeasurements 구현
    ///
    /// - Parameters:
    ///   - measurements: 측정값 딕셔너리
    ///   - clothingType: 의류 타입
    /// - Returns: 검증 결과
    static func validate(
        measurements: [MeasurementType: Double],
        clothingType: ClothingType
    ) -> MeasurementValidationResult {
        var isValid = true
        var failureReasons: [String] = []
        var warnings: [String] = []
        var confidenceScores: [Double] = []

        // 1. 개별 측정값 범위 검증
        let ranges = clothingType.isTop ? topRanges : bottomRanges

        for (type, value) in measurements {
            if let validRange = ranges[type] {
                if !validRange.contains(value) {
                    isValid = false
                    failureReasons.append(
                        "\(type.displayName): \(String(format: "%.1f", value))cm는 유효 범위(\(validRange.lowerBound)-\(validRange.upperBound)cm)를 벗어남"
                    )
                    confidenceScores.append(0.0)
                } else {
                    // 범위 내에 있으면 신뢰도 1.0
                    confidenceScores.append(1.0)
                }
            }
        }

        // 2. 상의: 어깨너비 vs 총길이 비율 검증
        if clothingType.isTop,
           let shoulderWidth = measurements[.shoulderWidth],
           let totalLength = measurements[.totalLength] {

            let ratio = shoulderWidth / totalLength

            // LiDAR_SIZE_Ref.md: 0.2 ~ 0.8 범위
            if ratio < 0.2 || ratio > 0.8 {
                isValid = false
                failureReasons.append(
                    "어깨너비/총길이 비율(\(String(format: "%.2f", ratio)))이 비정상적 (정상: 0.2-0.8)"
                )
                confidenceScores.append(0.0)
            } else {
                confidenceScores.append(1.0)
            }
        }

        // 3. 하의: 허리둘레만 검증 (엉덩이둘레는 MeasurementType에 아직 미구현)
        // TODO: hipCircumference를 MeasurementType에 추가 후 활성화

        // 4. 하의: 총길이 vs 밑위 비율 검증
        if !clothingType.isTop,
           let totalLength = measurements[.totalLength],
           let rise = measurements[.rise] {

            let ratio = rise / totalLength

            // 밑위는 일반적으로 총길이의 20-60%
            if ratio < 0.2 || ratio > 0.6 {
                warnings.append(
                    "밑위/총길이 비율(\(String(format: "%.2f", ratio)))이 비정상적 (정상: 0.2-0.6)"
                )
                confidenceScores.append(0.8)
            } else {
                confidenceScores.append(1.0)
            }
        }

        // 5. 전체 신뢰도 계산
        let overallConfidence = confidenceScores.isEmpty
            ? 0.0
            : confidenceScores.reduce(0, +) / Double(confidenceScores.count)

        return MeasurementValidationResult(
            isValid: isValid,
            failureReasons: failureReasons,
            warnings: warnings,
            overallConfidence: overallConfidence
        )
    }

    /// 단일 측정값 검증
    ///
    /// - Parameters:
    ///   - type: 측정 타입
    ///   - value: 측정값 (센티미터)
    ///   - clothingType: 의류 타입
    /// - Returns: 유효 여부
    static func isValid(
        measurementType type: MeasurementType,
        value: Double,
        for clothingType: ClothingType
    ) -> Bool {
        let ranges = clothingType.isTop ? topRanges : bottomRanges

        guard let validRange = ranges[type] else {
            return true  // 범위 정의 없으면 통과
        }

        return validRange.contains(value)
    }

    /// 측정값 신뢰도 평가
    ///
    /// - Parameters:
    ///   - type: 측정 타입
    ///   - value: 측정값
    ///   - confidence: LiDAR 신뢰도
    ///   - clothingType: 의류 타입
    /// - Returns: 종합 신뢰도 (0.0 ~ 1.0)
    static func evaluateConfidence(
        measurementType type: MeasurementType,
        value: Double,
        lidarConfidence: Double,
        for clothingType: ClothingType
    ) -> Double {
        let ranges = clothingType.isTop ? topRanges : bottomRanges

        guard let validRange = ranges[type] else {
            return lidarConfidence  // 범위 정의 없으면 LiDAR 신뢰도만 사용
        }

        // 1. 범위 검증
        let rangeConfidence: Double
        if validRange.contains(value) {
            // 범위 내: 중심에 가까울수록 신뢰도 높음
            let center = (validRange.lowerBound + validRange.upperBound) / 2
            let distance = abs(value - center)
            let maxDistance = (validRange.upperBound - validRange.lowerBound) / 2
            rangeConfidence = 1.0 - (distance / maxDistance) * 0.3  // 최대 30% 감소
        } else {
            rangeConfidence = 0.0  // 범위 외
        }

        // 2. LiDAR 신뢰도와 결합 (가중 평균)
        let finalConfidence = lidarConfidence * 0.7 + rangeConfidence * 0.3

        return max(0.0, min(1.0, finalConfidence))
    }
}

// MARK: - ClothingType Extension

extension ClothingType {
    /// 상의 여부
    var isTop: Bool {
        switch self {
        case .shortSleeve, .longSleeve, .shirt, .polo, .hoodie, .vest, .cardigan, .jacket, .coat:
            return true
        case .shorts, .pants, .skirt, .jeans, .leggings:
            return false
        case .dress, .jumpsuit:
            return false  // 원피스류는 별도 카테고리
        }
    }
}

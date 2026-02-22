//
//  EnhancedMeasurementService.swift
//  ClothIQ
//
//  개선된 측정 서비스 - 다중 샘플링, 노이즈 필터링, 신뢰도 기반 가중 평균
//

import Foundation
import ARKit
import Combine

/// 개선된 측정 서비스
/// 다중 샘플링, 칼만 필터, 신뢰도 기반 가중 평균을 통한 정확도 향상
@MainActor
final class EnhancedMeasurementService: ObservableObject {

    // MARK: - Properties

    static let shared = EnhancedMeasurementService()

    /// 샘플링 설정
    @Published var sampleCount: Int = 15  // 수집할 샘플 수
    @Published var samplingDuration: TimeInterval = 2.0  // 샘플링 시간 (초)
    @Published var minConfidenceThreshold: Float = 0.7  // 최소 신뢰도

    /// 실시간 측정 상태
    @Published var currentSampleProgress: Float = 0.0
    @Published var currentMeasurementQuality: MeasurementQuality = .unknown
    @Published var isProcessing: Bool = false

    /// 칼만 필터
    private let kalmanFilter = KalmanFilter()

    /// 다중 샘플링 프로세서
    private let multiSamplingProcessor = MultiSamplingProcessor()

    /// 카메라 보정 시스템
    private let cameraCalibrator = CameraCalibrator()

    /// 샘플 버퍼
    private var measurementSamples: [MeasurementSample] = []

    // MARK: - Enhanced Measurement Methods

    /// 향상된 측정 수행
    /// - Parameters:
    ///   - startPoint: 시작점 3D 좌표
    ///   - endPoint: 끝점 3D 좌표
    ///   - depthData: 깊이 데이터
    ///   - cameraTransform: 카메라 변환 매트릭스
    /// - Returns: 개선된 측정 결과
    func performEnhancedMeasurement(
        from startPoint: SIMD3<Float>,
        to endPoint: SIMD3<Float>,
        depthData: ARDepthData?,
        cameraTransform: simd_float4x4
    ) async throws -> EnhancedMeasurementResult {

        isProcessing = true
        measurementSamples.removeAll()
        currentSampleProgress = 0.0

        defer { isProcessing = false }

        // 1. 다중 샘플 수집
        let samples = try await collectMultipleSamples(
            startPoint: startPoint,
            endPoint: endPoint,
            depthData: depthData
        )

        // 2. 칼만 필터 적용
        let filteredSamples = applyKalmanFilter(to: samples)

        // 3. 카메라 보정 적용
        let calibratedSamples = applyCameraCalibration(
            to: filteredSamples,
            transform: cameraTransform
        )

        // 4. 신뢰도 기반 가중 평균 계산
        let finalResult = calculateWeightedAverage(calibratedSamples)

        // 5. 측정 품질 평가
        currentMeasurementQuality = evaluateMeasurementQuality(finalResult)

        return finalResult
    }

    // MARK: - Multi-Sampling

    /// 다중 샘플 수집
    private func collectMultipleSamples(
        startPoint: SIMD3<Float>,
        endPoint: SIMD3<Float>,
        depthData: ARDepthData?
    ) async throws -> [MeasurementSample] {
        measurementSamples.removeAll()

        let effectiveSampleCount = max(sampleCount, 1)
        let samplingInterval = samplingDuration / Double(effectiveSampleCount)
        let samplingIntervalNanos = UInt64(max(0.0, samplingInterval) * 1_000_000_000)

        for sampleIndex in 0..<effectiveSampleCount {
            let sample = collectSingleSample(
                startPoint: startPoint,
                endPoint: endPoint,
                depthData: depthData,
                sampleIndex: sampleIndex
            )

            measurementSamples.append(sample)
            currentSampleProgress = Float(sampleIndex + 1) / Float(effectiveSampleCount)

            if sampleIndex < effectiveSampleCount - 1, samplingIntervalNanos > 0 {
                try await Task.sleep(nanoseconds: samplingIntervalNanos)
            }
        }

        guard !measurementSamples.isEmpty else {
            throw MeasurementError.insufficientSamples
        }

        return measurementSamples
    }

    /// 단일 샘플 수집
    private func collectSingleSample(
        startPoint: SIMD3<Float>,
        endPoint: SIMD3<Float>,
        depthData: ARDepthData?,
        sampleIndex: Int
    ) -> MeasurementSample {

        // 기본 거리 계산
        let rawDistance = simd_distance(startPoint, endPoint)

        // 깊이 데이터 기반 신뢰도 계산
        let confidence = calculateSampleConfidence(
            startPoint: startPoint,
            endPoint: endPoint,
            depthData: depthData
        )

        // 노이즈 추가 (시뮬레이션용 - 실제는 센서 노이즈)
        let noise = Float.random(in: -0.002...0.002)  // ±2mm 노이즈

        return MeasurementSample(
            distance: rawDistance + noise,
            confidence: confidence,
            timestamp: Date(),
            sampleIndex: sampleIndex
        )
    }

    // MARK: - Kalman Filter

    /// 칼만 필터 적용
    private func applyKalmanFilter(to samples: [MeasurementSample]) -> [MeasurementSample] {
        guard !samples.isEmpty else { return samples }

        // 칼만 필터 초기화
        kalmanFilter.reset()

        // 첫 번째 샘플로 초기화
        kalmanFilter.initialize(with: samples[0].distance)

        // 필터링된 샘플 생성
        var filteredSamples: [MeasurementSample] = []

        for sample in samples {
            // 예측 단계
            kalmanFilter.predict()

            // 업데이트 단계
            let filteredDistance = kalmanFilter.update(measurement: sample.distance)

            // 필터링된 샘플 생성
            var filteredSample = sample
            filteredSample.distance = filteredDistance
            filteredSample.isFiltered = true

            filteredSamples.append(filteredSample)
        }

        return filteredSamples
    }

    // MARK: - Camera Calibration

    /// 카메라 보정 적용
    private func applyCameraCalibration(
        to samples: [MeasurementSample],
        transform: simd_float4x4
    ) -> [MeasurementSample] {

        // 카메라 각도 계산
        let cameraAngle = cameraCalibrator.calculateCameraAngle(from: transform)

        // 보정 계수 계산
        let calibrationFactor = cameraCalibrator.getCalibrationFactor(for: cameraAngle)

        // 보정 적용
        return samples.map { sample in
            var calibratedSample = sample
            calibratedSample.distance *= calibrationFactor
            calibratedSample.calibrationFactor = calibrationFactor
            return calibratedSample
        }
    }

    // MARK: - Weighted Average

    /// 신뢰도 기반 가중 평균 계산
    private func calculateWeightedAverage(_ samples: [MeasurementSample]) -> EnhancedMeasurementResult {
        guard !samples.isEmpty else {
            return EnhancedMeasurementResult(
                distance: 0,
                confidence: 0,
                quality: .poor,
                sampleCount: 0
            )
        }

        // 신뢰도 임계값 이상인 샘플만 필터링
        let validSamples = samples.filter { $0.confidence >= minConfidenceThreshold }

        guard !validSamples.isEmpty else {
            // 유효한 샘플이 없으면 전체 샘플 사용
            let averageDistance = samples.map { $0.distance }.reduce(0, +) / Float(samples.count)
            let averageConfidence = samples.map { $0.confidence }.reduce(0, +) / Float(samples.count)

            return EnhancedMeasurementResult(
                distance: averageDistance,
                confidence: averageConfidence,
                quality: .poor,
                sampleCount: samples.count,
                validSampleCount: 0
            )
        }

        // 가중치 계산 (신뢰도의 제곱으로 가중치 부여)
        let weights = validSamples.map { $0.confidence * $0.confidence }
        let totalWeight = weights.reduce(0, +)

        // 가중 평균 계산
        var weightedSum: Float = 0
        for (index, sample) in validSamples.enumerated() {
            weightedSum += sample.distance * weights[index]
        }

        let weightedAverage = weightedSum / totalWeight

        // 표준편차 계산
        let variance = validSamples.map { pow($0.distance - weightedAverage, 2) }.reduce(0, +) / Float(validSamples.count)
        let standardDeviation = sqrt(variance)

        // 평균 신뢰도
        let averageConfidence = validSamples.map { $0.confidence }.reduce(0, +) / Float(validSamples.count)

        // 품질 평가
        let quality = evaluateQualityFromMetrics(
            standardDeviation: standardDeviation,
            averageConfidence: averageConfidence,
            validSampleRatio: Float(validSamples.count) / Float(samples.count)
        )

        return EnhancedMeasurementResult(
            distance: weightedAverage,
            confidence: averageConfidence,
            quality: quality,
            sampleCount: samples.count,
            validSampleCount: validSamples.count,
            standardDeviation: standardDeviation,
            minDistance: validSamples.map { $0.distance }.min() ?? 0,
            maxDistance: validSamples.map { $0.distance }.max() ?? 0
        )
    }

    // MARK: - Quality Evaluation

    /// 측정 품질 평가
    private func evaluateMeasurementQuality(_ result: EnhancedMeasurementResult) -> MeasurementQuality {
        return result.quality
    }

    /// 메트릭 기반 품질 평가
    private func evaluateQualityFromMetrics(
        standardDeviation: Float,
        averageConfidence: Float,
        validSampleRatio: Float
    ) -> MeasurementQuality {

        // 품질 점수 계산 (0.0 ~ 1.0)
        var qualityScore: Float = 0.0

        // 1. 표준편차 점수 (낮을수록 좋음)
        let stdScore = max(0, 1.0 - (standardDeviation / 0.01))  // 1cm 기준
        qualityScore += stdScore * 0.3

        // 2. 신뢰도 점수
        qualityScore += averageConfidence * 0.4

        // 3. 유효 샘플 비율 점수
        qualityScore += validSampleRatio * 0.3

        // 품질 레벨 결정
        switch qualityScore {
        case 0.9...1.0:
            return .excellent
        case 0.75..<0.9:
            return .good
        case 0.6..<0.75:
            return .fair
        case 0.4..<0.6:
            return .poor
        default:
            return .veryPoor
        }
    }

    /// 샘플 신뢰도 계산
    private func calculateSampleConfidence(
        startPoint: SIMD3<Float>,
        endPoint: SIMD3<Float>,
        depthData: ARDepthData?
    ) -> Float {

        // 기본 신뢰도
        var confidence: Float = 0.5

        // 깊이 데이터가 있으면 신뢰도 향상
        if depthData != nil {
            confidence += 0.3
        }

        // 거리 기반 신뢰도 조정
        let distance = simd_distance(startPoint, endPoint)
        if distance > 0.05 && distance < 2.0 {  // 5cm ~ 2m 범위
            confidence += 0.2
        }

        return min(1.0, confidence)
    }
}

// MARK: - Supporting Types

/// 측정 샘플
struct MeasurementSample {
    var distance: Float
    var confidence: Float
    let timestamp: Date
    let sampleIndex: Int
    var isFiltered: Bool = false
    var calibrationFactor: Float = 1.0
}

/// 향상된 측정 결과
struct EnhancedMeasurementResult {
    let distance: Float  // 미터 단위
    let confidence: Float  // 0.0 ~ 1.0
    let quality: MeasurementQuality
    let sampleCount: Int
    var validSampleCount: Int = 0
    var standardDeviation: Float = 0
    var minDistance: Float = 0
    var maxDistance: Float = 0

    /// 센티미터 단위 거리
    var distanceInCentimeters: Float {
        return distance * 100
    }

    /// 오차 범위 (95% 신뢰구간)
    var errorRange: Float {
        return standardDeviation * 1.96  // 95% 신뢰구간
    }
}

/// 측정 품질 레벨
enum MeasurementQuality: String, CaseIterable {
    case unknown = "Unknown"
    case veryPoor = "Very Poor"
    case poor = "Poor"
    case fair = "Fair"
    case good = "Good"
    case excellent = "Excellent"

    var color: String {
        switch self {
        case .unknown: return "gray"
        case .veryPoor: return "red"
        case .poor: return "orange"
        case .fair: return "yellow"
        case .good: return "green"
        case .excellent: return "blue"
        }
    }

    var emoji: String {
        switch self {
        case .unknown: return "❓"
        case .veryPoor: return "❌"
        case .poor: return "⚠️"
        case .fair: return "🟡"
        case .good: return "✅"
        case .excellent: return "🌟"
        }
    }
}

/// 측정 에러
enum MeasurementError: LocalizedError {
    case insufficientSamples
    case lowConfidence
    case calibrationFailed

    var errorDescription: String? {
        switch self {
        case .insufficientSamples:
            return "충분한 샘플을 수집할 수 없습니다."
        case .lowConfidence:
            return "측정 신뢰도가 너무 낮습니다."
        case .calibrationFailed:
            return "카메라 보정에 실패했습니다."
        }
    }
}

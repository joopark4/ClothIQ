//
//  MultiSamplingProcessor.swift
//  ClothIQ
//
//  다중 샘플링 프로세서 - 여러 프레임에서 데이터 수집 및 통계 처리
//

import Foundation
import ARKit
import Accelerate

/// 다중 샘플링 프로세서
/// 여러 프레임에서 측정 데이터를 수집하고 통계적으로 처리
class MultiSamplingProcessor {

    // MARK: - Properties

    /// 샘플링 설정
    struct SamplingConfiguration {
        var targetSampleCount: Int = 15  // 목표 샘플 수
        var maxSampleCount: Int = 30  // 최대 샘플 수
        var samplingRate: Double = 30.0  // Hz
        var outlierThreshold: Float = 2.0  // 표준편차 배수
        var minValidSampleRatio: Float = 0.6  // 최소 유효 샘플 비율
    }

    private var configuration = SamplingConfiguration()

    /// 샘플 버퍼
    private var sampleBuffer: [DepthSample] = []
    private let bufferQueue = DispatchQueue(label: "com.clothiq.sampling", qos: .userInitiated)

    /// 통계 캐시
    private var cachedStatistics: SamplingStatistics?

    // MARK: - Public Methods

    /// 샘플링 시작
    func startSampling() {
        bufferQueue.async { [weak self] in
            self?.sampleBuffer.removeAll()
            self?.cachedStatistics = nil
        }
    }

    /// 샘플 추가
    /// - Parameters:
    ///   - point: 3D 포인트
    ///   - confidence: 신뢰도
    ///   - timestamp: 타임스탬프
    func addSample(point: SIMD3<Float>, confidence: Float, timestamp: Date = Date()) {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }

            let sample = DepthSample(
                point: point,
                confidence: confidence,
                timestamp: timestamp
            )

            self.sampleBuffer.append(sample)

            // 최대 샘플 수 제한
            if self.sampleBuffer.count > self.configuration.maxSampleCount {
                self.sampleBuffer.removeFirst()
            }

            // 통계 캐시 무효화
            self.cachedStatistics = nil
        }
    }

    /// 거리 샘플 추가
    func addDistanceSample(distance: Float, confidence: Float, timestamp: Date = Date()) {
        bufferQueue.async { [weak self] in
            guard let self = self else { return }

            let sample = DepthSample(
                distance: distance,
                confidence: confidence,
                timestamp: timestamp
            )

            self.sampleBuffer.append(sample)

            if self.sampleBuffer.count > self.configuration.maxSampleCount {
                self.sampleBuffer.removeFirst()
            }

            self.cachedStatistics = nil
        }
    }

    /// 샘플 처리 및 결과 반환
    /// - Returns: 처리된 샘플링 결과
    func processSamples() -> ProcessedSamplingResult? {
        return bufferQueue.sync { [weak self] in
            guard let self = self,
                  !self.sampleBuffer.isEmpty else { return nil }

            // 1. 아웃라이어 제거
            let cleanedSamples = self.removeOutliers(from: self.sampleBuffer)

            // 2. 시간 가중치 적용
            let weightedSamples = self.applyTimeWeighting(to: cleanedSamples)

            // 3. 통계 계산
            let statistics = self.calculateStatistics(from: weightedSamples)

            // 4. 품질 평가
            let quality = self.evaluateQuality(
                statistics: statistics,
                originalCount: self.sampleBuffer.count,
                cleanedCount: cleanedSamples.count
            )

            return ProcessedSamplingResult(
                finalValue: statistics.weightedMean,
                confidence: statistics.averageConfidence,
                quality: quality,
                statistics: statistics,
                sampleCount: self.sampleBuffer.count,
                validSampleCount: cleanedSamples.count
            )
        }
    }

    /// 실시간 통계 반환
    func getCurrentStatistics() -> SamplingStatistics? {
        return bufferQueue.sync { [weak self] in
            guard let self = self else { return nil }

            if let cached = self.cachedStatistics {
                return cached
            }

            guard !self.sampleBuffer.isEmpty else { return nil }

            let statistics = self.calculateStatistics(from: self.sampleBuffer)
            self.cachedStatistics = statistics
            return statistics
        }
    }

    // MARK: - Private Methods

    /// 아웃라이어 제거 (IQR 방법)
    private func removeOutliers(from samples: [DepthSample]) -> [DepthSample] {
        guard samples.count > 3 else { return samples }

        let distances = samples.compactMap { $0.distance }
        guard !distances.isEmpty else { return samples }

        // 정렬
        let sorted = distances.sorted()

        // 사분위수 계산
        let q1Index = sorted.count / 4
        let q3Index = (sorted.count * 3) / 4

        let q1 = sorted[q1Index]
        let q3 = sorted[q3Index]
        let iqr = q3 - q1

        // 아웃라이어 경계
        let lowerBound = q1 - (configuration.outlierThreshold * iqr)
        let upperBound = q3 + (configuration.outlierThreshold * iqr)

        // 필터링
        return samples.filter { sample in
            guard let distance = sample.distance else { return true }
            return distance >= lowerBound && distance <= upperBound
        }
    }

    /// 시간 가중치 적용 (최신 샘플에 더 높은 가중치)
    private func applyTimeWeighting(to samples: [DepthSample]) -> [WeightedSample] {
        guard !samples.isEmpty else { return [] }

        // 최신 타임스탬프 찾기
        let latestTime = samples.map { $0.timestamp }.max() ?? Date()

        return samples.map { sample in
            // 시간 차이 계산 (초)
            let timeDiff = latestTime.timeIntervalSince(sample.timestamp)

            // 지수 감쇠 가중치 (반감기: 1초)
            let timeWeight = exp(-timeDiff / 1.0)

            // 신뢰도와 시간 가중치 결합
            let combinedWeight = Float(timeWeight) * sample.confidence

            return WeightedSample(
                sample: sample,
                weight: combinedWeight
            )
        }
    }

    /// 통계 계산
    private func calculateStatistics(from samples: [DepthSample]) -> SamplingStatistics {
        let distances = samples.compactMap { $0.distance }

        guard !distances.isEmpty else {
            return SamplingStatistics()
        }

        // 기본 통계
        let mean = distances.reduce(0, +) / Float(distances.count)
        let median = calculateMedian(distances)

        // 표준편차
        let variance = distances.map { pow($0 - mean, 2) }.reduce(0, +) / Float(distances.count)
        let standardDeviation = sqrt(variance)

        // 신뢰도 평균
        let averageConfidence = samples.map { $0.confidence }.reduce(0, +) / Float(samples.count)

        // 가중 평균
        let weightedMean = calculateWeightedMean(samples: samples)

        return SamplingStatistics(
            mean: mean,
            median: median,
            standardDeviation: standardDeviation,
            min: distances.min() ?? 0,
            max: distances.max() ?? 0,
            weightedMean: weightedMean,
            averageConfidence: averageConfidence,
            sampleCount: samples.count
        )
    }

    private func calculateStatistics(from weightedSamples: [WeightedSample]) -> SamplingStatistics {
        let samples = weightedSamples.map { $0.sample }
        var statistics = calculateStatistics(from: samples)

        // 가중 평균 재계산
        let totalWeight = weightedSamples.map { $0.weight }.reduce(0, +)
        if totalWeight > 0 {
            let weightedSum = weightedSamples.compactMap { weighted -> Float? in
                guard let distance = weighted.sample.distance else { return nil }
                return distance * weighted.weight
            }.reduce(0, +)

            statistics.weightedMean = weightedSum / totalWeight
        }

        return statistics
    }

    /// 중앙값 계산
    private func calculateMedian(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let count = sorted.count

        if count % 2 == 0 {
            return (sorted[count/2 - 1] + sorted[count/2]) / 2.0
        } else {
            return sorted[count/2]
        }
    }

    /// 가중 평균 계산
    private func calculateWeightedMean(samples: [DepthSample]) -> Float {
        let validSamples = samples.filter { $0.distance != nil }
        guard !validSamples.isEmpty else { return 0 }

        let totalWeight = validSamples.map { $0.confidence }.reduce(0, +)
        guard totalWeight > 0 else {
            return validSamples.compactMap { $0.distance }.reduce(0, +) / Float(validSamples.count)
        }

        let weightedSum = validSamples.compactMap { sample -> Float? in
            guard let distance = sample.distance else { return nil }
            return distance * sample.confidence
        }.reduce(0, +)

        return weightedSum / totalWeight
    }

    /// 품질 평가
    private func evaluateQuality(
        statistics: SamplingStatistics,
        originalCount: Int,
        cleanedCount: Int
    ) -> SamplingQuality {

        var score: Float = 0.0

        // 1. 유효 샘플 비율 (30%)
        let validRatio = Float(cleanedCount) / Float(originalCount)
        score += min(1.0, validRatio / configuration.minValidSampleRatio) * 0.3

        // 2. 표준편차 (30%)
        let stdScore = max(0, 1.0 - (statistics.standardDeviation / 0.01))  // 1cm 기준
        score += stdScore * 0.3

        // 3. 신뢰도 (30%)
        score += statistics.averageConfidence * 0.3

        // 4. 샘플 수 (10%)
        let sampleScore = min(1.0, Float(cleanedCount) / Float(configuration.targetSampleCount))
        score += sampleScore * 0.1

        switch score {
        case 0.9...1.0: return .excellent
        case 0.75..<0.9: return .good
        case 0.6..<0.75: return .fair
        case 0.4..<0.6: return .poor
        default: return .veryPoor
        }
    }
}

// MARK: - Supporting Types

/// 깊이 샘플
struct DepthSample {
    var point: SIMD3<Float>?
    var distance: Float?
    let confidence: Float
    let timestamp: Date

    init(point: SIMD3<Float>, confidence: Float, timestamp: Date = Date()) {
        self.point = point
        self.distance = nil
        self.confidence = confidence
        self.timestamp = timestamp
    }

    init(distance: Float, confidence: Float, timestamp: Date = Date()) {
        self.point = nil
        self.distance = distance
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// 가중치가 적용된 샘플
struct WeightedSample {
    let sample: DepthSample
    let weight: Float
}

/// 샘플링 통계
struct SamplingStatistics {
    var mean: Float = 0
    var median: Float = 0
    var standardDeviation: Float = 0
    var min: Float = 0
    var max: Float = 0
    var weightedMean: Float = 0
    var averageConfidence: Float = 0
    var sampleCount: Int = 0

    /// 변동 계수 (Coefficient of Variation)
    var coefficientOfVariation: Float {
        guard mean > 0 else { return 0 }
        return standardDeviation / mean
    }

    /// 95% 신뢰구간
    var confidenceInterval95: (lower: Float, upper: Float) {
        let margin = 1.96 * standardDeviation / sqrt(Float(sampleCount))
        return (mean - margin, mean + margin)
    }
}

/// 샘플링 품질
enum SamplingQuality: String {
    case veryPoor = "Very Poor"
    case poor = "Poor"
    case fair = "Fair"
    case good = "Good"
    case excellent = "Excellent"
}

/// 처리된 샘플링 결과
struct ProcessedSamplingResult {
    let finalValue: Float
    let confidence: Float
    let quality: SamplingQuality
    let statistics: SamplingStatistics
    let sampleCount: Int
    let validSampleCount: Int

    /// 센티미터 단위 변환
    var finalValueInCentimeters: Float {
        return finalValue * 100
    }

    /// 오차 범위
    var errorMargin: Float {
        return statistics.standardDeviation * 1.96
    }

    /// 오차 범위 (센티미터)
    var errorMarginInCentimeters: Float {
        return errorMargin * 100
    }
}
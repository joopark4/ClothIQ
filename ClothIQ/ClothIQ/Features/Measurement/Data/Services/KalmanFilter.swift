//
//  KalmanFilter.swift
//  ClothIQ
//
//  칼만 필터 구현 - 측정 노이즈 제거 및 정확도 향상
//

import Foundation
import Accelerate

/// 1차원 칼만 필터
/// 측정 노이즈를 효과적으로 제거하고 정확한 값을 추정
class KalmanFilter {

    // MARK: - Properties

    /// 상태 추정값 (x̂)
    internal var stateEstimate: Float = 0.0

    /// 추정 오차 공분산 (P)
    internal var estimateCovariance: Float = 1.0

    /// 프로세스 노이즈 공분산 (Q)
    /// 시스템의 불확실성 - 작을수록 이전 값 신뢰
    internal var processNoise: Float = 0.0001

    /// 측정 노이즈 공분산 (R)
    /// 센서의 노이즈 - 작을수록 측정값 신뢰
    internal var measurementNoise: Float = 0.001

    /// 상태 전이 행렬 (A) - 1차원에서는 1.0
    internal let stateTransition: Float = 1.0

    /// 측정 행렬 (H) - 1차원에서는 1.0
    internal let measurementMatrix: Float = 1.0

    /// 칼만 이득 (K)
    internal var kalmanGain: Float = 0.0

    /// 초기화 여부
    internal var isInitialized: Bool = false

    // MARK: - Initialization

    init(processNoise: Float = 0.0001, measurementNoise: Float = 0.001) {
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }

    // MARK: - Public Methods

    /// 필터 초기화
    /// - Parameter initialValue: 초기 측정값
    func initialize(with initialValue: Float) {
        stateEstimate = initialValue
        estimateCovariance = 1.0
        isInitialized = true
    }

    /// 필터 리셋
    func reset() {
        stateEstimate = 0.0
        estimateCovariance = 1.0
        kalmanGain = 0.0
        isInitialized = false
    }

    /// 예측 단계 (Predict)
    /// 시간 업데이트 - 이전 상태로부터 다음 상태 예측
    func predict() {
        guard isInitialized else { return }

        // 상태 예측: x̂ₖ⁻ = A * x̂ₖ₋₁
        stateEstimate = stateTransition * stateEstimate

        // 오차 공분산 예측: Pₖ⁻ = A * Pₖ₋₁ * Aᵀ + Q
        estimateCovariance = stateTransition * estimateCovariance * stateTransition + processNoise
    }

    /// 업데이트 단계 (Update)
    /// 측정 업데이트 - 새로운 측정값으로 추정값 보정
    /// - Parameter measurement: 새로운 측정값
    /// - Returns: 필터링된 추정값
    @discardableResult
    func update(measurement: Float) -> Float {
        guard isInitialized else {
            initialize(with: measurement)
            return measurement
        }

        // 칼만 이득 계산: K = Pₖ⁻ * H^T * (H * Pₖ⁻ * H^T + R)⁻¹
        let innovation = measurementMatrix * estimateCovariance * measurementMatrix + measurementNoise
        kalmanGain = estimateCovariance * measurementMatrix / innovation

        // 상태 추정값 업데이트: x̂ₖ = x̂ₖ⁻ + K * (zₖ - H * x̂ₖ⁻)
        let measurementResidual = measurement - (measurementMatrix * stateEstimate)
        stateEstimate = stateEstimate + kalmanGain * measurementResidual

        // 오차 공분산 업데이트: Pₖ = (I - K * H) * Pₖ⁻
        estimateCovariance = (1.0 - kalmanGain * measurementMatrix) * estimateCovariance

        return stateEstimate
    }

    /// 현재 추정값 반환
    var currentEstimate: Float {
        return stateEstimate
    }

    /// 현재 불확실성 (표준편차)
    var currentUncertainty: Float {
        return sqrt(estimateCovariance)
    }

    /// 현재 칼만 이득
    var currentGain: Float {
        return kalmanGain
    }
}

/// 다차원 칼만 필터 (3D 포인트용)
class KalmanFilter3D {

    // MARK: - Properties

    /// X, Y, Z 각 축에 대한 독립적인 칼만 필터
    private let xFilter: KalmanFilter
    private let yFilter: KalmanFilter
    private let zFilter: KalmanFilter

    // MARK: - Initialization

    init(processNoise: Float = 0.0001, measurementNoise: Float = 0.001) {
        xFilter = KalmanFilter(processNoise: processNoise, measurementNoise: measurementNoise)
        yFilter = KalmanFilter(processNoise: processNoise, measurementNoise: measurementNoise)
        zFilter = KalmanFilter(processNoise: processNoise, measurementNoise: measurementNoise)
    }

    // MARK: - Public Methods

    /// 3D 포인트 초기화
    func initialize(with point: SIMD3<Float>) {
        xFilter.initialize(with: point.x)
        yFilter.initialize(with: point.y)
        zFilter.initialize(with: point.z)
    }

    /// 필터 리셋
    func reset() {
        xFilter.reset()
        yFilter.reset()
        zFilter.reset()
    }

    /// 예측 단계
    func predict() {
        xFilter.predict()
        yFilter.predict()
        zFilter.predict()
    }

    /// 업데이트 단계
    /// - Parameter measurement: 새로운 3D 측정 포인트
    /// - Returns: 필터링된 3D 포인트
    func update(measurement: SIMD3<Float>) -> SIMD3<Float> {
        let filteredX = xFilter.update(measurement: measurement.x)
        let filteredY = yFilter.update(measurement: measurement.y)
        let filteredZ = zFilter.update(measurement: measurement.z)

        return SIMD3<Float>(filteredX, filteredY, filteredZ)
    }

    /// 현재 추정값
    var currentEstimate: SIMD3<Float> {
        return SIMD3<Float>(
            xFilter.currentEstimate,
            yFilter.currentEstimate,
            zFilter.currentEstimate
        )
    }

    /// 현재 불확실성
    var currentUncertainty: SIMD3<Float> {
        return SIMD3<Float>(
            xFilter.currentUncertainty,
            yFilter.currentUncertainty,
            zFilter.currentUncertainty
        )
    }
}

/// 적응형 칼만 필터
/// 노이즈 레벨을 동적으로 조정하여 더 나은 성능 제공
class AdaptiveKalmanFilter: KalmanFilter {

    // MARK: - Properties

    /// 혁신 시퀀스 (Innovation sequence) 버퍼
    private var innovationBuffer: [Float] = []
    private let bufferSize: Int = 10

    /// 적응형 측정 노이즈
    private var adaptiveMeasurementNoise: Float

    // MARK: - Initialization

    override init(processNoise: Float = 0.0001, measurementNoise: Float = 0.001) {
        self.adaptiveMeasurementNoise = measurementNoise
        super.init(processNoise: processNoise, measurementNoise: measurementNoise)
    }

    // MARK: - Override Methods

    override func update(measurement: Float) -> Float {
        // 혁신 계산 (측정 잔차)
        let innovation = measurement - (measurementMatrix * stateEstimate)

        // 혁신 버퍼 업데이트
        innovationBuffer.append(abs(innovation))
        if innovationBuffer.count > bufferSize {
            innovationBuffer.removeFirst()
        }

        // 적응형 노이즈 조정
        if innovationBuffer.count >= bufferSize / 2 {
            let meanInnovation = innovationBuffer.reduce(0, +) / Float(innovationBuffer.count)
            let variance = innovationBuffer.map { pow($0 - meanInnovation, 2) }.reduce(0, +) / Float(innovationBuffer.count)

            // 측정 노이즈 동적 조정
            adaptiveMeasurementNoise = max(0.0001, min(0.01, variance))
        }

        // 부모 클래스의 업데이트 호출
        return super.update(measurement: measurement)
    }

    /// 현재 적응형 측정 노이즈
    var currentMeasurementNoise: Float {
        return adaptiveMeasurementNoise
    }
}

// MARK: - Utility Extensions

extension KalmanFilter {
    /// 배치 처리
    /// - Parameter measurements: 측정값 배열
    /// - Returns: 필터링된 값 배열
    func processBatch(_ measurements: [Float]) -> [Float] {
        var filtered: [Float] = []

        for measurement in measurements {
            predict()
            let filteredValue = update(measurement: measurement)
            filtered.append(filteredValue)
        }

        return filtered
    }

    /// 스무딩 팩터 계산 (0.0 ~ 1.0)
    /// 칼만 이득을 기반으로 얼마나 스무딩이 적용되는지 표시
    var smoothingFactor: Float {
        return 1.0 - kalmanGain
    }
}
//
//  KalmanFilter.swift
//  ClothIQ
//
//  Created on 2025-11-04
//
//  Description:
//  1D Kalman Filter for smoothing measurement values over time.
//  Reduces noise and improves measurement stability by fusing multiple frames.
//
//  Key Features:
//  - Temporal fusion of depth measurements
//  - Confidence-based measurement weighting
//  - Hand tremor compensation
//  - Real-time performance (O(1) complexity)
//

import Foundation

/// 1D Kalman Filter for measurement smoothing
///
/// The Kalman filter is an optimal estimator that combines predictions with noisy measurements
/// to produce more accurate estimates. This implementation is specialized for static measurements
/// (clothing items that don't move).
///
/// ## Usage
/// ```swift
/// let filter = KalmanFilter(initialValue: 50.0)
/// filter.predict()
/// let smoothed = filter.update(measurement: 51.2, measurementNoise: 1.0)
/// print("Filtered value: \(smoothed) cm")
/// ```
///
/// ## Algorithm
/// 1. **Predict**: Propagate state forward (no change for static objects)
/// 2. **Update**: Incorporate new measurement with Kalman gain weighting
///
/// ## References
/// - Kalman, R. E. (1960). "A New Approach to Linear Filtering and Prediction Problems"
/// - Welch & Bishop (2006). "An Introduction to the Kalman Filter"
///
final class KalmanFilter {

    // MARK: - State Variables

    /// Current estimate (in centimeters)
    private var x: Double

    /// Estimate error covariance (uncertainty)
    private var P: Double

    // MARK: - Model Parameters

    /// Process noise covariance (system uncertainty)
    ///
    /// This represents how much we expect the true value to change between measurements.
    /// For static clothing measurements, this should be very low.
    private let Q: Double

    /// Measurement noise covariance (measurement uncertainty)
    ///
    /// This is dynamically updated based on the confidence of each measurement.
    private var R: Double

    // MARK: - Initialization

    /// Creates a new Kalman filter
    ///
    /// - Parameters:
    ///   - initialValue: Initial estimate value (cm)
    ///   - initialUncertainty: Initial uncertainty (default: 1.0)
    ///   - processNoise: Process noise for static measurements (default: 0.01)
    init(
        initialValue: Double = 0.0,
        initialUncertainty: Double = 1.0,
        processNoise: Double = 0.01
    ) {
        self.x = initialValue
        self.P = initialUncertainty
        self.Q = processNoise
        self.R = 1.0
    }

    // MARK: - Prediction Step

    /// Predict the next state (time update)
    ///
    /// For static measurements, the state doesn't change, but uncertainty increases.
    func predict() {
        // State prediction: x_k|k-1 = x_k-1 (no change for static object)
        // x = x (unchanged)

        // Covariance prediction: P_k|k-1 = P_k-1 + Q
        P = P + Q
    }

    // MARK: - Update Step

    /// Update the estimate with a new measurement
    ///
    /// - Parameters:
    ///   - measurement: New measurement value (cm)
    ///   - measurementNoise: Measurement noise (uncertainty)
    /// - Returns: Updated filtered estimate (cm)
    ///
    /// The measurement noise should be inversely proportional to confidence:
    /// - High confidence (0.9) → Low noise (1.1)
    /// - Low confidence (0.3) → High noise (3.3)
    @discardableResult
    func update(measurement: Double, measurementNoise: Double) -> Double {
        // Update measurement noise
        R = measurementNoise

        // Kalman Gain: K = P / (P + R)
        // This determines how much to trust the measurement vs the prediction
        let K = P / (P + R)

        // State update: x_k = x_k|k-1 + K * (z_k - x_k|k-1)
        // z_k is the measurement, (z_k - x_k|k-1) is the innovation
        x = x + K * (measurement - x)

        // Covariance update: P_k = (1 - K) * P_k|k-1
        P = (1 - K) * P

        return x
    }

    // MARK: - Accessors

    /// Current filtered estimate (cm)
    var estimate: Double {
        return x
    }

    /// Current uncertainty (cm²)
    var uncertainty: Double {
        return P
    }

    /// Standard deviation of estimate (cm)
    var standardDeviation: Double {
        return sqrt(P)
    }

    // MARK: - Reset

    /// Reset the filter to a new initial value
    ///
    /// - Parameters:
    ///   - value: New initial value
    ///   - uncertainty: New initial uncertainty
    func reset(to value: Double, uncertainty: Double = 1.0) {
        x = value
        P = uncertainty
    }
}

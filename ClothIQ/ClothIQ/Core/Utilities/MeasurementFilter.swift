//
//  MeasurementFilter.swift
//  ClothIQ
//
//  Created on 2025-11-04
//
//  Description:
//  Measurement filtering manager that maintains separate Kalman filters
//  for each measurement type (shoulder width, chest circumference, etc.).
//
//  Key Features:
//  - Per-measurement-type filtering
//  - Confidence-based weighting
//  - Automatic filter lifecycle management
//  - Thread-safe operation
//
//  Usage:
//  ```swift
//  let filter = MeasurementFilter()
//  let smoothed = filter.update(
//      id: "shoulder_width",
//      value: 42.5,
//      confidence: 0.9
//  )
//  ```
//

import Foundation

/// Measurement filtering manager
///
/// This class manages multiple Kalman filters, one for each measurement type.
/// It automatically creates filters on-demand and provides a simple interface
/// for updating and retrieving filtered values.
///
/// ## Thread Safety
/// This class is thread-safe and can be called from multiple threads.
///
final class MeasurementFilter {

    // MARK: - Properties

    /// Dictionary of active Kalman filters, keyed by measurement ID
    private var filters: [String: KalmanFilter] = [:]

    /// Serial queue for thread-safe access to filters
    private let queue = DispatchQueue(label: "com.clothiq.measurementfilter")

    // MARK: - Initialization

    init() {
        // Empty init - filters created on demand
    }

    // MARK: - Public Methods

    /// Update a measurement with a new value and get the filtered result
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the measurement (e.g., "shoulder_width")
    ///   - value: Raw measurement value (cm)
    ///   - confidence: Measurement confidence (0.0 ~ 1.0)
    /// - Returns: Filtered measurement value (cm)
    ///
    /// ## Confidence Mapping
    /// The confidence value is converted to measurement noise:
    /// - confidence: 1.0 → noise: 1.0 (perfect measurement)
    /// - confidence: 0.5 → noise: 2.0 (moderate uncertainty)
    /// - confidence: 0.1 → noise: 10.0 (high uncertainty)
    ///
    func update(id: String, value: Double, confidence: Float) -> Double {
        return queue.sync {
            // Create filter if it doesn't exist
            if filters[id] == nil {
                filters[id] = KalmanFilter(
                    initialValue: value,
                    initialUncertainty: 1.0,
                    processNoise: 0.01
                )
            }

            guard let filter = filters[id] else {
                return value // Fallback (should never happen)
            }

            // Predict step
            filter.predict()

            // Convert confidence to measurement noise
            // Higher confidence → Lower noise
            let measurementNoise = convertConfidenceToNoise(confidence)

            // Update and return filtered value
            return filter.update(measurement: value, measurementNoise: measurementNoise)
        }
    }

    /// Reset a specific measurement filter
    ///
    /// - Parameter id: Measurement ID to reset
    ///
    /// Use this when starting a new measurement session for a specific type.
    func reset(id: String) {
        queue.sync {
            filters[id] = nil
        }
    }

    /// Reset all measurement filters
    ///
    /// Use this when starting a completely new measurement session.
    func resetAll() {
        queue.sync {
            filters.removeAll()
        }
    }

    /// Get the current filtered value without updating
    ///
    /// - Parameter id: Measurement ID
    /// - Returns: Current filtered value, or nil if filter doesn't exist
    func currentValue(for id: String) -> Double? {
        return queue.sync {
            return filters[id]?.estimate
        }
    }

    /// Get the uncertainty of a filtered measurement
    ///
    /// - Parameter id: Measurement ID
    /// - Returns: Standard deviation (cm), or nil if filter doesn't exist
    func uncertainty(for id: String) -> Double? {
        return queue.sync {
            return filters[id]?.standardDeviation
        }
    }

    /// Check if a filter exists for a given measurement
    ///
    /// - Parameter id: Measurement ID
    /// - Returns: True if filter exists
    func hasFilter(for id: String) -> Bool {
        return queue.sync {
            return filters[id] != nil
        }
    }

    // MARK: - Private Methods

    /// Convert confidence score to measurement noise
    ///
    /// - Parameter confidence: Confidence value (0.0 ~ 1.0)
    /// - Returns: Measurement noise (variance)
    ///
    /// ## Formula
    /// noise = 1.0 / max(confidence, 0.1)
    ///
    /// This ensures:
    /// - High confidence measurements have low noise (trusted more)
    /// - Low confidence measurements have high noise (trusted less)
    /// - Minimum confidence of 0.1 prevents division by very small numbers
    ///
    private func convertConfidenceToNoise(_ confidence: Float) -> Double {
        // Clamp confidence to prevent extreme noise values
        let clampedConfidence = max(confidence, 0.1)

        // Inverse relationship: higher confidence → lower noise
        return Double(1.0 / clampedConfidence)
    }
}

// MARK: - Convenience Extension

extension MeasurementFilter {

    /// Update multiple measurements at once
    ///
    /// - Parameter measurements: Dictionary of measurement ID to (value, confidence) tuples
    /// - Returns: Dictionary of filtered values
    func updateBatch(_ measurements: [String: (value: Double, confidence: Float)]) -> [String: Double] {
        var results: [String: Double] = [:]

        for (id, data) in measurements {
            results[id] = update(id: id, value: data.value, confidence: data.confidence)
        }

        return results
    }

    /// Get statistics for all active filters
    ///
    /// - Returns: Dictionary with filter statistics
    func statistics() -> [String: (estimate: Double, uncertainty: Double)] {
        return queue.sync {
            var stats: [String: (Double, Double)] = [:]

            for (id, filter) in filters {
                stats[id] = (filter.estimate, filter.standardDeviation)
            }

            return stats
        }
    }
}

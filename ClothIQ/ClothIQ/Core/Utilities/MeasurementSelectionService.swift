//
//  MeasurementSelectionService.swift
//  ClothIQ
//
//  Created on 2026-05-08
//
//  Description:
//  중복 측정값 중 화면/저장 로직에서 사용할 대표 측정값을 선택합니다.
//

import Foundation

enum MeasurementSelectionService {
    static func preferredMeasurement(
        for measurementType: MeasurementType,
        in measurements: [MeasurementModel]
    ) -> MeasurementModel? {
        preferredMeasurement(rawType: measurementType.rawValue, in: measurements)
    }

    static func preferredMeasurement(
        rawType: String,
        in measurements: [MeasurementModel]
    ) -> MeasurementModel? {
        measurements
            .filter { $0.type == rawType }
            .max { lhs, rhs in
                isPreferred(rhs, over: lhs)
            }
    }

    static func displayMeasurements(
        from measurements: [MeasurementModel],
        clothingType: ClothingType?
    ) -> [MeasurementModel] {
        let order = measurementDisplayOrder(for: clothingType)

        return latestByType(from: measurements).values.sorted { lhs, rhs in
            let lhsOrder = order[lhs.type] ?? Int.max
            let rhsOrder = order[rhs.type] ?? Int.max

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            if lhs.measuredAt != rhs.measuredAt {
                return lhs.measuredAt < rhs.measuredAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func duplicateMeasurements(in measurements: [MeasurementModel]) -> [MeasurementModel] {
        let keepIDs = Set(latestByType(from: measurements).values.map(\.id))
        return measurements.filter { !keepIDs.contains($0.id) }
    }

    static func isPreferred(_ measurement: MeasurementModel, over other: MeasurementModel) -> Bool {
        if measurement.measuredAt != other.measuredAt {
            return measurement.measuredAt > other.measuredAt
        }

        if measurement.hasCoordinates != other.hasCoordinates {
            return measurement.hasCoordinates
        }

        if measurement.confidence != other.confidence {
            return measurement.confidence > other.confidence
        }

        return measurement.id.uuidString > other.id.uuidString
    }

    private static func latestByType(from measurements: [MeasurementModel]) -> [String: MeasurementModel] {
        var latestByType: [String: MeasurementModel] = [:]

        for measurement in measurements {
            if let current = latestByType[measurement.type] {
                if isPreferred(measurement, over: current) {
                    latestByType[measurement.type] = measurement
                }
            } else {
                latestByType[measurement.type] = measurement
            }
        }

        return latestByType
    }

    private static func measurementDisplayOrder(for clothingType: ClothingType?) -> [String: Int] {
        let preferredOrder = (clothingType?.requiredMeasurements ?? []) +
            (clothingType?.optionalMeasurements ?? [])
        return Dictionary(uniqueKeysWithValues: preferredOrder.enumerated().map { index, type in
            (type.rawValue, index)
        })
    }
}

//
//  BottomMeasurementAnchorRepairPolicy.swift
//  ClothIQ
//
//  Created on 2026-05-02
//
//  Description:
//  기존 저장된 하의 밑위/밑단/총장 좌표가 초기 자동 측정의 잘못된 앵커로 남아 있을 때
//  새 자동 감지 결과로 교체할지 판단합니다.
//

import CoreGraphics
import Foundation

enum BottomMeasurementAnchorRepairPolicy {
    static let initialMeasurementWindow: TimeInterval = 10
    static let replacementDeltaThreshold: CGFloat = 0.02
    static let hemSlopeThreshold: CGFloat = 0.06
    static let riseSlopeThreshold: CGFloat = 0.06

    static func normalizedPoints(
        from result: AutoMeasurementResult,
        imageSize: CGSize
    ) -> (start: CGPoint, end: CGPoint)? {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return nil
        }

        return (
            start: CGPoint(
                x: clamp(result.point1.x / imageSize.width),
                y: clamp(result.point1.y / imageSize.height)
            ),
            end: CGPoint(
                x: clamp(result.point2.x / imageSize.width),
                y: clamp(result.point2.y / imageSize.height)
            )
        )
    }

    static func shouldRepair(
        measurement: MeasurementModel,
        replacementStart: CGPoint,
        replacementEnd: CGPoint,
        itemCreatedAt: Date
    ) -> Bool {
        guard let measurementType = measurement.measurementType,
              let currentStart = measurement.startPoint,
              let currentEnd = measurement.endPoint else {
            return false
        }

        switch measurementType {
        case .hem:
            if abs(currentStart.y - currentEnd.y) > hemSlopeThreshold {
                return true
            }
        case .rise:
            if abs(currentStart.x - currentEnd.x) > riseSlopeThreshold {
                return true
            }
        case .totalLength:
            break
        default:
            return false
        }

        guard isInitialAutomaticPhotoMeasurement(measurement, itemCreatedAt: itemCreatedAt) else {
            return false
        }

        return maxNormalizedDelta(
            currentStart: currentStart,
            currentEnd: currentEnd,
            replacementStart: replacementStart,
            replacementEnd: replacementEnd
        ) > replacementDeltaThreshold
    }

    static func apply(
        result: AutoMeasurementResult,
        to measurement: MeasurementModel,
        imageSize: CGSize,
        measuredAt: Date = Date()
    ) -> Bool {
        guard let normalized = normalizedPoints(from: result, imageSize: imageSize) else {
            return false
        }

        measurement.value = result.distance
        measurement.confidence = result.confidence
        measurement.measuredAt = measuredAt
        measurement.startPointX = Double(normalized.start.x)
        measurement.startPointY = Double(normalized.start.y)
        measurement.endPointX = Double(normalized.end.x)
        measurement.endPointY = Double(normalized.end.y)
        measurement.measurementMethodRaw = MeasurementMethod.photo.rawValue
        return true
    }

    private static func isInitialAutomaticPhotoMeasurement(
        _ measurement: MeasurementModel,
        itemCreatedAt: Date
    ) -> Bool {
        measurement.measurementMethod == .photo &&
            abs(measurement.measuredAt.timeIntervalSince(itemCreatedAt)) <= initialMeasurementWindow
    }

    private static func maxNormalizedDelta(
        currentStart: CGPoint,
        currentEnd: CGPoint,
        replacementStart: CGPoint,
        replacementEnd: CGPoint
    ) -> CGFloat {
        max(
            abs(currentStart.x - replacementStart.x),
            abs(currentStart.y - replacementStart.y),
            abs(currentEnd.x - replacementEnd.x),
            abs(currentEnd.y - replacementEnd.y)
        )
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        max(0, min(value, 1))
    }
}

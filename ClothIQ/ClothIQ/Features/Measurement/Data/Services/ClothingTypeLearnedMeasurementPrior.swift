//
//  ClothingTypeLearnedMeasurementPrior.swift
//  ClothIQ
//
//  Created on 2026-05-04
//
//  Description:
//  수집된 촬영/수정 샘플에서 의류 타입별 키포인트 prior를 추정합니다.
//

import CoreGraphics
import Foundation

enum ClothingTypeLearnedMeasurementPrior {
    static let minimumVisibleSamples = 3

    static func projectedKeypoints(
        from samples: [TrainingSample],
        clothingType: ClothingType,
        featurePoints: ClothingFeaturePoints,
        minimumVisibleSamples: Int = Self.minimumVisibleSamples
    ) -> [KeypointType: MeasurementKeypoint] {
        let profile = relativeProfile(
            from: samples,
            clothingType: clothingType,
            minimumVisibleSamples: minimumVisibleSamples
        )

        guard !profile.isEmpty else {
            return [:]
        }

        let width = Swift.max(featurePoints.width, 0.0001)
        let height = Swift.max(featurePoints.height, 0.0001)
        let leftX = Swift.min(featurePoints.leftmostPoint.x, featurePoints.rightmostPoint.x)
        let bottomY = Swift.min(featurePoints.bottomPoint.y, featurePoints.topPoint.y)

        return profile.mapValues { learnedPoint in
            let position = CGPoint(
                x: leftX + width * learnedPoint.relativeX,
                y: bottomY + height * learnedPoint.relativeY
            ).clampedToUnit()

            return MeasurementKeypoint(
                type: learnedPoint.type,
                position: position,
                confidence: learnedPoint.confidence
            )
        }
    }

    static func relativeProfile(
        from samples: [TrainingSample],
        clothingType: ClothingType,
        minimumVisibleSamples: Int = Self.minimumVisibleSamples
    ) -> [KeypointType: LearnedRelativeKeypoint] {
        let expectedTypes = ClothingTypeMeasurementPrior.expectedKeypointTypes(for: clothingType)
        var accumulators: [KeypointType: WeightedPointAccumulator] = [:]

        for sample in samples where sample.clothingType == clothingType.rawValue {
            let visibleLabels = sample.visibleKeypointLabels()
            guard visibleLabels.count >= 4,
                  let bounds = Self.keypointBounds(for: visibleLabels) else {
                continue
            }

            let sampleWeight = Self.sampleWeight(sample)
            for (type, label) in visibleLabels where expectedTypes.contains(type) {
                let relativeX = CGFloat((label.x - bounds.minX) / bounds.width).clampedToUnit()
                let relativeY = CGFloat((label.y - bounds.minY) / bounds.height).clampedToUnit()
                accumulators[type, default: WeightedPointAccumulator()].add(
                    x: relativeX,
                    y: relativeY,
                    weight: sampleWeight
                )
            }
        }

        var profile: [KeypointType: LearnedRelativeKeypoint] = [:]
        for (type, accumulator) in accumulators {
            guard accumulator.observationCount >= minimumVisibleSamples,
                  let point = accumulator.average(for: type) else {
                continue
            }
            profile[type] = point
        }
        return profile
    }

    private static func keypointBounds(
        for labels: [(type: KeypointType, label: KeypointLabel)]
    ) -> KeypointBounds? {
        let xs = labels.map { $0.label.x }
        let ys = labels.map { $0.label.y }
        guard let minX = xs.min(),
              let maxX = xs.max(),
              let minY = ys.min(),
              let maxY = ys.max() else {
            return nil
        }

        let width = maxX - minX
        let height = maxY - minY
        guard width > 0.01, height > 0.01 else {
            return nil
        }

        return KeypointBounds(minX: minX, minY: minY, width: width, height: height)
    }

    private static func sampleWeight(_ sample: TrainingSample) -> CGFloat {
        let confidence = CGFloat(Swift.max(sample.confidence, 0.25))
        return confidence * (sample.isUserCorrected ? 2.5 : 1.0)
    }

    struct LearnedRelativeKeypoint {
        let type: KeypointType
        let relativeX: CGFloat
        let relativeY: CGFloat
        let confidence: Float
    }

    private struct KeypointBounds {
        let minX: Float
        let minY: Float
        let width: Float
        let height: Float
    }

    private struct WeightedPointAccumulator {
        private var weightedX: CGFloat = 0
        private var weightedY: CGFloat = 0
        private var totalWeight: CGFloat = 0
        private(set) var observationCount: Int = 0

        mutating func add(x: CGFloat, y: CGFloat, weight: CGFloat) {
            weightedX += x * weight
            weightedY += y * weight
            totalWeight += weight
            observationCount += 1
        }

        func average(for type: KeypointType) -> LearnedRelativeKeypoint? {
            guard totalWeight > 0 else {
                return nil
            }

            let confidence = Swift.min(0.90, 0.68 + Float(observationCount) * 0.025)
            return LearnedRelativeKeypoint(
                type: type,
                relativeX: weightedX / totalWeight,
                relativeY: weightedY / totalWeight,
                confidence: confidence
            )
        }
    }
}

private extension TrainingSample {
    func visibleKeypointLabels() -> [(type: KeypointType, label: KeypointLabel)] {
        keypoints.compactMap { label in
            guard label.visibility >= 0.5,
                  (0.0...1.0).contains(label.x),
                  (0.0...1.0).contains(label.y),
                  let type = KeypointType(trainingIdentifier: label.identifier) else {
                return nil
            }
            return (type, label)
        }
    }
}

extension KeypointType {
    var trainingIdentifier: String {
        switch self {
        case .leftShoulder: return "left_shoulder"
        case .rightShoulder: return "right_shoulder"
        case .leftArmpit: return "left_armpit"
        case .rightArmpit: return "right_armpit"
        case .leftSleeveEnd: return "left_sleeve"
        case .rightSleeveEnd: return "right_sleeve"
        case .neckline: return "neckline"
        case .hemCenter: return "hem_center"
        case .chestLeft: return "chest_left"
        case .chestRight: return "chest_right"
        case .waistLeft: return "waist_left"
        case .waistRight: return "waist_right"
        case .hipLeft: return "hip_left"
        case .hipRight: return "hip_right"
        case .crotch: return "crotch"
        case .leftHem: return "hem_left"
        case .rightHem: return "hem_right"
        }
    }

    init?(trainingIdentifier: String) {
        switch trainingIdentifier {
        case "left_shoulder": self = .leftShoulder
        case "right_shoulder": self = .rightShoulder
        case "left_armpit": self = .leftArmpit
        case "right_armpit": self = .rightArmpit
        case "left_sleeve": self = .leftSleeveEnd
        case "right_sleeve": self = .rightSleeveEnd
        case "neckline": self = .neckline
        case "hem_center": self = .hemCenter
        case "chest_left": self = .chestLeft
        case "chest_right": self = .chestRight
        case "waist_left": self = .waistLeft
        case "waist_right": self = .waistRight
        case "hip_left": self = .hipLeft
        case "hip_right": self = .hipRight
        case "crotch": self = .crotch
        case "hem_left": self = .leftHem
        case "hem_right": self = .rightHem
        default: return nil
        }
    }
}

private extension CGFloat {
    func clampedToUnit() -> CGFloat {
        Swift.min(Swift.max(self, 0), 1)
    }
}

private extension CGPoint {
    func clampedToUnit() -> CGPoint {
        CGPoint(
            x: x.clampedToUnit(),
            y: y.clampedToUnit()
        )
    }
}

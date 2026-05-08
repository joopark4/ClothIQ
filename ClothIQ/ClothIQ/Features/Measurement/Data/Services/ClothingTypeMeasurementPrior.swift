//
//  ClothingTypeMeasurementPrior.swift
//  ClothIQ
//
//  Created on 2026-05-04
//
//  Description:
//  의류 타입별 사전 측정 프로파일을 사용해 키포인트를 보강합니다.
//

import CoreGraphics
import Foundation

enum ClothingTypeMeasurementPrior {
    private static let synthesizedConfidence: Float = 0.54
    private static let lowConfidenceBlendThreshold: Float = 0.72

    static func refine(
        _ keypoints: [MeasurementKeypoint],
        clothingType: ClothingType,
        featurePoints: ClothingFeaturePoints,
        learnedKeypoints: [KeypointType: MeasurementKeypoint]
    ) -> [MeasurementKeypoint] {
        let priorKeypoints = combinedPriorKeypoints(
            for: clothingType,
            featurePoints: featurePoints,
            learnedKeypoints: learnedKeypoints
        )
        let expectedTypes = expectedKeypointTypes(for: clothingType)

        guard !priorKeypoints.isEmpty else {
            return keypoints
        }

        var mergedByType: [KeypointType: MeasurementKeypoint] = [:]
        var typeOrder: [KeypointType] = []

        func upsert(_ keypoint: MeasurementKeypoint) {
            if mergedByType[keypoint.type] == nil {
                typeOrder.append(keypoint.type)
                mergedByType[keypoint.type] = keypoint
                return
            }

            if let existing = mergedByType[keypoint.type],
               keypoint.confidence > existing.confidence {
                mergedByType[keypoint.type] = keypoint
            }
        }

        for keypoint in keypoints {
            if let prior = priorKeypoints[keypoint.type] {
                upsert(blended(keypoint, with: prior, featurePoints: featurePoints))
            } else {
                upsert(keypoint)
            }
        }

        for expectedType in orderedExpectedTypes(for: clothingType) where expectedTypes.contains(expectedType) {
            guard mergedByType[expectedType] == nil,
                  let prior = priorKeypoints[expectedType] else {
                continue
            }
            upsert(prior)
        }

        return typeOrder.compactMap { mergedByType[$0] }
    }

    static func projectedKeypoints(
        for clothingType: ClothingType,
        featurePoints: ClothingFeaturePoints
    ) -> [KeypointType: MeasurementKeypoint] {
        let width = max(featurePoints.width, 0.0001)
        let height = max(featurePoints.height, 0.0001)
        let leftX = min(featurePoints.leftmostPoint.x, featurePoints.rightmostPoint.x)
        let bottomY = min(featurePoints.bottomPoint.y, featurePoints.topPoint.y)
        let template = ClothingTemplate.selectTemplate(
            for: height / width,
            type: clothingType
        )

        var projected: [KeypointType: MeasurementKeypoint] = [:]
        for relative in relativeKeypoints(for: clothingType, template: template) {
            let position = CGPoint(
                x: leftX + width * relative.x,
                y: bottomY + height * (1.0 - relative.topOffset)
            ).clampedToUnit()
            projected[relative.type] = MeasurementKeypoint(
                type: relative.type,
                position: position,
                confidence: relative.confidence
            )
        }
        return projected
    }

    static func expectedKeypointTypes(for clothingType: ClothingType) -> Set<KeypointType> {
        Set(orderedExpectedTypes(for: clothingType))
    }

    private static func combinedPriorKeypoints(
        for clothingType: ClothingType,
        featurePoints: ClothingFeaturePoints,
        learnedKeypoints: [KeypointType: MeasurementKeypoint]
    ) -> [KeypointType: MeasurementKeypoint] {
        let expectedTypes = expectedKeypointTypes(for: clothingType)
        var prior = projectedKeypoints(for: clothingType, featurePoints: featurePoints)

        for (type, keypoint) in learnedKeypoints where expectedTypes.contains(type) {
            prior[type] = keypoint
        }

        return prior
    }

    private static func blended(
        _ keypoint: MeasurementKeypoint,
        with prior: MeasurementKeypoint,
        featurePoints: ClothingFeaturePoints
    ) -> MeasurementKeypoint {
        let outsideBounds = !featurePoints.contains(keypoint.position, tolerance: 0.06)
        let confidenceGap = max(0, lowConfidenceBlendThreshold - keypoint.confidence)
        let confidenceWeight = CGFloat(confidenceGap / lowConfidenceBlendThreshold) * 0.35
        let priorWeight = outsideBounds ? max(confidenceWeight, 0.55) : confidenceWeight

        guard priorWeight > 0 else {
            return keypoint
        }

        let clampedWeight = min(max(priorWeight, 0), 0.65)
        let refinedPosition = CGPoint(
            x: keypoint.position.x * (1 - clampedWeight) + prior.position.x * clampedWeight,
            y: keypoint.position.y * (1 - clampedWeight) + prior.position.y * clampedWeight
        ).clampedToUnit()
        let refinedConfidence = max(keypoint.confidence, min(0.86, keypoint.confidence + 0.06))

        return MeasurementKeypoint(
            type: keypoint.type,
            position: refinedPosition,
            confidence: refinedConfidence
        )
    }

    private struct RelativeKeypoint {
        let type: KeypointType
        let x: CGFloat
        let topOffset: CGFloat
        let confidence: Float
    }

    private static func relativeKeypoints(
        for clothingType: ClothingType,
        template: ClothingTemplate
    ) -> [RelativeKeypoint] {
        switch clothingType {
        case .shortSleeve, .polo:
            return topProfile(template: template, sleeveTopOffset: 0.42, includesSleeves: true)
        case .longSleeve, .shirt, .cardigan, .hoodie:
            return topProfile(template: template, sleeveTopOffset: 0.78, includesSleeves: true)
        case .jacket:
            return topProfile(template: template, sleeveTopOffset: 0.76, includesSleeves: true)
        case .coat:
            return topProfile(template: template, sleeveTopOffset: 0.82, includesSleeves: true)
        case .vest:
            return topProfile(template: template, sleeveTopOffset: 0.0, includesSleeves: false)
        case .dress:
            return onePieceProfile(template: template, includesCrotch: false)
        case .jumpsuit:
            return onePieceProfile(template: template, includesCrotch: true)
        case .shorts:
            return bottomProfile(template: template, hemLeftX: 0.20, hemRightX: 0.42, includesLegHem: true)
        case .pants, .jeans:
            return bottomProfile(template: template, hemLeftX: 0.17, hemRightX: 0.34, includesLegHem: true)
        case .leggings:
            return bottomProfile(template: template, hemLeftX: 0.18, hemRightX: 0.32, includesLegHem: true)
        case .skirt:
            return skirtProfile(template: template)
        }
    }

    private static func topProfile(
        template: ClothingTemplate,
        sleeveTopOffset: CGFloat,
        includesSleeves: Bool
    ) -> [RelativeKeypoint] {
        var points: [RelativeKeypoint] = [
            RelativeKeypoint(type: .leftShoulder, x: 0.25, topOffset: template.shoulderOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .rightShoulder, x: 0.75, topOffset: template.shoulderOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .leftArmpit, x: 0.30, topOffset: max(template.chestOffset - 0.08, 0.12), confidence: synthesizedConfidence),
            RelativeKeypoint(type: .rightArmpit, x: 0.70, topOffset: max(template.chestOffset - 0.08, 0.12), confidence: synthesizedConfidence),
            RelativeKeypoint(type: .chestLeft, x: 0.18, topOffset: template.chestOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .chestRight, x: 0.82, topOffset: template.chestOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .neckline, x: 0.50, topOffset: 0.02, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .hemCenter, x: 0.50, topOffset: 0.96, confidence: synthesizedConfidence)
        ]

        if includesSleeves {
            points.append(contentsOf: [
                RelativeKeypoint(type: .leftSleeveEnd, x: 0.06, topOffset: sleeveTopOffset, confidence: synthesizedConfidence),
                RelativeKeypoint(type: .rightSleeveEnd, x: 0.94, topOffset: sleeveTopOffset, confidence: synthesizedConfidence)
            ])
        }

        return points
    }

    private static func onePieceProfile(
        template: ClothingTemplate,
        includesCrotch: Bool
    ) -> [RelativeKeypoint] {
        var points = topProfile(template: template, sleeveTopOffset: 0.58, includesSleeves: false)
        points.append(contentsOf: [
            RelativeKeypoint(type: .waistLeft, x: 0.26, topOffset: template.waistOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .waistRight, x: 0.74, topOffset: template.waistOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .hipLeft, x: 0.20, topOffset: template.hipOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .hipRight, x: 0.80, topOffset: template.hipOffset, confidence: synthesizedConfidence)
        ])

        if includesCrotch {
            let riseOffset = (template.riseSearchRange.lowerBound + template.riseSearchRange.upperBound) * 0.5
            points.append(RelativeKeypoint(type: .crotch, x: 0.50, topOffset: riseOffset, confidence: synthesizedConfidence))
        }

        return points
    }

    private static func bottomProfile(
        template: ClothingTemplate,
        hemLeftX: CGFloat,
        hemRightX: CGFloat,
        includesLegHem: Bool
    ) -> [RelativeKeypoint] {
        let riseOffset = (template.riseSearchRange.lowerBound + template.riseSearchRange.upperBound) * 0.5
        var points: [RelativeKeypoint] = [
            RelativeKeypoint(type: .waistLeft, x: 0.12, topOffset: template.waistOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .waistRight, x: 0.88, topOffset: template.waistOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .hipLeft, x: 0.10, topOffset: template.hipOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .hipRight, x: 0.90, topOffset: template.hipOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .crotch, x: 0.50, topOffset: riseOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .hemCenter, x: 0.50, topOffset: 0.96, confidence: synthesizedConfidence)
        ]

        if includesLegHem {
            points.append(contentsOf: [
                RelativeKeypoint(type: .leftHem, x: hemLeftX, topOffset: 0.94, confidence: synthesizedConfidence),
                RelativeKeypoint(type: .rightHem, x: hemRightX, topOffset: 0.94, confidence: synthesizedConfidence)
            ])
        }

        return points
    }

    private static func skirtProfile(template: ClothingTemplate) -> [RelativeKeypoint] {
        [
            RelativeKeypoint(type: .waistLeft, x: 0.18, topOffset: template.waistOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .waistRight, x: 0.82, topOffset: template.waistOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .hipLeft, x: 0.12, topOffset: template.hipOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .hipRight, x: 0.88, topOffset: template.hipOffset, confidence: synthesizedConfidence),
            RelativeKeypoint(type: .hemCenter, x: 0.50, topOffset: 0.96, confidence: synthesizedConfidence)
        ]
    }

    private static func orderedExpectedTypes(for clothingType: ClothingType) -> [KeypointType] {
        var ordered: [KeypointType] = []
        for measurementType in clothingType.requiredMeasurements + clothingType.optionalMeasurements {
            for type in keypointTypes(for: measurementType, clothingType: clothingType) where !ordered.contains(type) {
                ordered.append(type)
            }
        }
        return ordered
    }

    private static func keypointTypes(
        for measurementType: MeasurementType,
        clothingType: ClothingType
    ) -> [KeypointType] {
        switch measurementType {
        case .shoulderWidth:
            return [.leftShoulder, .rightShoulder]
        case .chestCircumference:
            return [.chestLeft, .chestRight]
        case .totalLength:
            switch clothingType.category {
            case .bottom:
                return [.waistLeft, .waistRight, .hemCenter, .leftHem, .rightHem]
            default:
                return [.neckline, .hemCenter]
            }
        case .sleeveLength:
            return [.leftShoulder, .leftSleeveEnd]
        case .armCircumference, .cuffCircumference:
            return [.leftSleeveEnd, .rightSleeveEnd]
        case .neckCircumference:
            return [.leftShoulder, .rightShoulder, .neckline]
        case .waistCircumference:
            return [.waistLeft, .waistRight]
        case .hipCircumference:
            return [.hipLeft, .hipRight]
        case .rise:
            return [.waistLeft, .waistRight, .crotch]
        case .hem:
            return [.leftHem, .rightHem]
        case .thighCircumference:
            return [.hipLeft, .hipRight, .crotch]
        }
    }
}

private extension ClothingFeaturePoints {
    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let minX = min(leftmostPoint.x, rightmostPoint.x) - tolerance
        let maxX = max(leftmostPoint.x, rightmostPoint.x) + tolerance
        let minY = min(bottomPoint.y, topPoint.y) - tolerance
        let maxY = max(bottomPoint.y, topPoint.y) + tolerance

        return point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

private extension CGPoint {
    func clampedToUnit() -> CGPoint {
        CGPoint(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1)
        )
    }
}

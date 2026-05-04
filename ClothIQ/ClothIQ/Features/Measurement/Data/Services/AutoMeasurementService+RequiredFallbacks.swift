//
//  AutoMeasurementService+RequiredFallbacks.swift
//  ClothIQ
//
//  Created on 2026-05-02
//
//  Description:
//  의류 타입별 필수 측정 항목 중 기본 윤곽/키포인트 측정에서 누락된 항목을
//  보수적인 윤곽선 기반 fallback으로 보강합니다.
//

import CoreGraphics
import CoreVideo
import Foundation
import simd

// MARK: - Required Measurement Fallbacks

extension AutoMeasurementService {

    func fillMissingRequiredMeasurements(
        into measurements: inout [MeasurementType: AutoMeasurementResult],
        featurePoints: ClothingFeaturePoints,
        clothingType: ClothingType,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        depthImageSize: CGSize?,
        cropRect: CGRect?
    ) {
        for measurementType in clothingType.requiredMeasurements where measurements[measurementType] == nil {
            guard let result = measureRequiredFallback(
                measurementType,
                featurePoints: featurePoints,
                clothingType: clothingType,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            ) else {
                continue
            }
            measurements[measurementType] = result
        }
    }

    private func measureRequiredFallback(
        _ measurementType: MeasurementType,
        featurePoints: ClothingFeaturePoints,
        clothingType: ClothingType,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        depthImageSize: CGSize?,
        cropRect: CGRect?
    ) -> AutoMeasurementResult? {
        switch measurementType {
        case .shoulderWidth:
            return measureShoulderWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        case .chestCircumference:
            return measureChestWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        case .waistCircumference:
            return measureWaistWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        case .hipCircumference:
            return measureHipWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        case .totalLength:
            return measureTotalLength(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        case .sleeveLength:
            return measureSleeveLength(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        case .armCircumference:
            return measureSleeveSpan(
                .armCircumference,
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        case .neckCircumference:
            return measureNeckCircumference(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        case .cuffCircumference:
            return measureSleeveSpan(
                .cuffCircumference,
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        case .rise:
            return measureRise(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        case .hem:
            if clothingType.category == .bottom,
               let hemSpan = featurePoints.robustBottomHemSpan() {
                return measureDistance(
                    from: hemSpan.left,
                    to: hemSpan.right,
                    depthMap: depthMap,
                    imageSize: imageSize,
                    confidence: hemSpan.confidence,
                    cameraIntrinsics: cameraIntrinsics,
                    cameraResolution: cameraResolution,
                    measurementType: .hem,
                    clothingType: clothingType,
                    depthImageSize: depthImageSize,
                    cropRect: cropRect
                )
            }

            return measureHorizontalFallback(
                .hem,
                centerY: featurePoints.bottomPoint.y + featurePoints.height * 0.04,
                confidenceScale: 0.80,
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        case .thighCircumference:
            return measureHorizontalFallback(
                .thighCircumference,
                centerY: featurePoints.hipY - featurePoints.height * 0.16,
                confidenceScale: 0.65,
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        }
    }

    private func measureSleeveLength(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType,
        depthImageSize: CGSize?,
        cropRect: CGRect?
    ) -> AutoMeasurementResult? {
        guard let sleeveLine = bestSleeveLine(featurePoints: featurePoints) else {
            return nil
        }
        return measureDistance(
            from: sleeveLine.shoulder,
            to: sleeveLine.end,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: sleeveLine.confidence,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .sleeveLength,
            clothingType: clothingType,
            depthImageSize: depthImageSize,
            cropRect: cropRect
        )
    }

    private func measureSleeveSpan(
        _ measurementType: MeasurementType,
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType,
        depthImageSize: CGSize?,
        cropRect: CGRect?
    ) -> AutoMeasurementResult? {
        guard let sleeveLine = bestSleeveLine(featurePoints: featurePoints) else {
            return nil
        }

        let targetY: CGFloat
        let confidenceScale: Float
        switch measurementType {
        case .cuffCircumference:
            targetY = sleeveLine.end.y
            confidenceScale = 0.60
        default:
            targetY = sleeveLine.shoulder.y + (sleeveLine.end.y - sleeveLine.shoulder.y) * 0.55
            confidenceScale = 0.70
        }

        let height = max(featurePoints.height, 0.0001)
        let halfSpans = [height * 0.035, height * 0.055, height * 0.08]
        guard let span = sideHorizontalSpan(
            around: targetY,
            shoulder: sleeveLine.shoulder,
            sleeveEnd: sleeveLine.end,
            halfSpans: halfSpans,
            featurePoints: featurePoints
        ) else {
            return nil
        }

        return measureDistance(
            from: span.left,
            to: span.right,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: span.confidence * confidenceScale,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: measurementType,
            clothingType: clothingType,
            depthImageSize: depthImageSize,
            cropRect: cropRect
        )
    }

    private func measureNeckCircumference(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType,
        depthImageSize: CGSize?,
        cropRect: CGRect?
    ) -> AutoMeasurementResult? {
        measureHorizontalFallback(
            .neckCircumference,
            centerY: featurePoints.topPoint.y - featurePoints.height * 0.045,
            confidenceScale: 0.60,
            selection: .narrowest,
            featurePoints: featurePoints,
            depthMap: depthMap,
            imageSize: imageSize,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            clothingType: clothingType,
            depthImageSize: depthImageSize,
            cropRect: cropRect
        )
    }

    private func measureRise(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType,
        depthImageSize: CGSize?,
        cropRect: CGRect?
    ) -> AutoMeasurementResult? {
        let height = max(featurePoints.height, 0.0001)
        let waistY: CGFloat
        if clothingType.category == .bottom,
           let waistSpan = featurePoints.robustBottomWaistSpan() {
            waistY = (waistSpan.left.y + waistSpan.right.y) * 0.5
        } else {
            waistY = featurePoints.averagedPoint(
                around: featurePoints.waistY,
                halfSpan: height * 0.035
            )?.y ?? featurePoints.waistY
        }
        let crotch: CGPoint
        let confidence: Float
        if clothingType.category == .bottom,
           let crotchPoint = featurePoints.robustBottomCrotchPoint() {
            crotch = crotchPoint.point
            confidence = crotchPoint.confidence
        } else {
            let crotchY = max(featurePoints.bottomPoint.y + height * 0.18, featurePoints.waistY - height * 0.42)
            crotch = CGPoint(x: featurePoints.centerX, y: crotchY)
            confidence = 0.55
        }
        let riseStart = CGPoint(x: crotch.x, y: waistY)

        return measureDistance(
            from: riseStart,
            to: crotch,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: confidence,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .rise,
            clothingType: clothingType,
            depthImageSize: depthImageSize,
            cropRect: cropRect
        )
    }

    private func measureHorizontalFallback(
        _ measurementType: MeasurementType,
        centerY: CGFloat,
        confidenceScale: Float,
        selection: ClothingFeaturePoints.HorizontalSpanSelection = .widest,
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType,
        depthImageSize: CGSize?,
        cropRect: CGRect?
    ) -> AutoMeasurementResult? {
        let height = max(featurePoints.height, 0.0001)
        let clampedY = max(featurePoints.bottomPoint.y, min(centerY, featurePoints.topPoint.y))
        let halfSpans = [height * 0.02, height * 0.04, height * 0.07]
        guard let span = featurePoints.bestHorizontalSpan(
            centeredAt: clampedY,
            halfSpans: halfSpans,
            selection: selection
        ) else {
            return nil
        }

        let confidence = featurePoints.calculateSymmetryConfidence(
            leftPoint: span.left,
            rightPoint: span.right
        ) * confidenceScale
        return measureDistance(
            from: span.left,
            to: span.right,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: confidence,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: measurementType,
            clothingType: clothingType,
            depthImageSize: depthImageSize,
            cropRect: cropRect
        )
    }

    private func bestSleeveLine(
        featurePoints: ClothingFeaturePoints
    ) -> (shoulder: CGPoint, end: CGPoint, confidence: Float)? {
        let height = max(featurePoints.height, 0.0001)
        guard let shoulderSpan = featurePoints.robustHorizontalSpan(
            at: featurePoints.topPoint.y - height * 0.02,
            halfSpans: [height * 0.015, height * 0.025, height * 0.04]
        ) else {
            return nil
        }

        let leftCandidate = sleeveEnd(
            from: shoulderSpan.left,
            side: .left,
            featurePoints: featurePoints
        )
        let rightCandidate = sleeveEnd(
            from: shoulderSpan.right,
            side: .right,
            featurePoints: featurePoints
        )

        let candidates = [
            leftCandidate.map { (shoulder: shoulderSpan.left, end: $0.point, confidence: min(shoulderSpan.confidence, $0.confidence)) },
            rightCandidate.map { (shoulder: shoulderSpan.right, end: $0.point, confidence: min(shoulderSpan.confidence, $0.confidence)) }
        ].compactMap { $0 }

        return candidates.max { lhs, rhs in
            normalizedDistance(from: lhs.shoulder, to: lhs.end) < normalizedDistance(from: rhs.shoulder, to: rhs.end)
        }
    }

    private enum SleeveSide {
        case left
        case right
    }

    private func sleeveEnd(
        from shoulder: CGPoint,
        side: SleeveSide,
        featurePoints: ClothingFeaturePoints
    ) -> (point: CGPoint, confidence: Float)? {
        let height = max(featurePoints.height, 0.0001)
        let lowerBound = max(featurePoints.bottomPoint.y, shoulder.y - height * 0.80)
        let range = lowerBound...shoulder.y
        let sideThreshold = featurePoints.width * 0.02
        let candidates = featurePoints.pointsInYRange(range).filter { point in
            switch side {
            case .left:
                return point.x <= shoulder.x + sideThreshold
            case .right:
                return point.x >= shoulder.x - sideThreshold
            }
        }
        guard !candidates.isEmpty else {
            return nil
        }

        let curvatureCandidates = featurePoints.detectCurvaturePoints(
            threshold: 0.25,
            yRange: range
        ).filter { point in
            switch side {
            case .left:
                return point.x <= shoulder.x + sideThreshold
            case .right:
                return point.x >= shoulder.x - sideThreshold
            }
        }

        if let curvaturePoint = farthestPoint(from: shoulder, in: curvatureCandidates) {
            return (curvaturePoint, 0.75)
        }
        if let edgePoint = farthestPoint(from: shoulder, in: candidates) {
            return (edgePoint, 0.55)
        }
        return nil
    }

    private func sideHorizontalSpan(
        around centerY: CGFloat,
        shoulder: CGPoint,
        sleeveEnd: CGPoint,
        halfSpans: [CGFloat],
        featurePoints: ClothingFeaturePoints
    ) -> (left: CGPoint, right: CGPoint, confidence: Float)? {
        let isRightSide = sleeveEnd.x >= shoulder.x
        var bestSpan: (left: CGPoint, right: CGPoint, confidence: Float)?
        var bestWidth: CGFloat = 0
        let minX = min(shoulder.x, sleeveEnd.x) - featurePoints.width * 0.08
        let maxX = max(shoulder.x, sleeveEnd.x) + featurePoints.width * 0.08

        for halfSpan in halfSpans where halfSpan > 0 {
            let lower = max(featurePoints.bottomPoint.y, centerY - halfSpan)
            let upper = min(featurePoints.topPoint.y, centerY + halfSpan)
            guard lower <= upper else { continue }

            let candidates = featurePoints.pointsInYRange(lower...upper).filter { point in
                let inSleeveBand = point.x >= minX && point.x <= maxX
                switch isRightSide {
                case true:
                    return inSleeveBand && point.x >= featurePoints.centerX
                case false:
                    return inSleeveBand && point.x <= featurePoints.centerX
                }
            }
            guard !candidates.isEmpty,
                  let left = candidates.min(by: { $0.x < $1.x }),
                  let right = candidates.max(by: { $0.x < $1.x }) else {
                continue
            }

            let width = right.x - left.x
            guard width > bestWidth else { continue }
            let density = min(Float(candidates.count) / 30.0, 1.0)
            let symmetry = max(0.0, 1.0 - Float(abs(left.y - right.y) / max(halfSpan, 0.001)))
            bestSpan = (left, right, (density + symmetry) / 2.0)
            bestWidth = width
        }

        return bestSpan
    }

    private func farthestPoint(from origin: CGPoint, in points: [CGPoint]) -> CGPoint? {
        points.max {
            normalizedDistance(from: origin, to: $0) < normalizedDistance(from: origin, to: $1)
        }
    }

    private func normalizedDistance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        sqrt(pow(rhs.x - lhs.x, 2) + pow(rhs.y - lhs.y, 2))
    }
}

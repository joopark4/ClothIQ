//
//  SkirtMeasurementDetector.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  치마 측정 포인트 자동 감지 구현체입니다.
//
//  Key Responsibilities:
//  - 허리둘레, 총길이 포인트 감지
//  - 신뢰도 점수 계산
//

import Foundation
import CoreGraphics
import Vision

// MARK: - Skirt Measurement Detector

/// 치마 측정 포인트 감지기
///
/// 치마의 측정 포인트를 자동으로 감지합니다.
/// - 허리둘레: 상단 좌우 폭
/// - 총길이: 허리 중심 → 밑단 중심
///
final class SkirtMeasurementDetector: MeasurementPointDetector {
    let supportedTypes: [ClothingType] = [.skirt]

    func detectPoints(
        featurePoints: ClothingFeaturePoints,
        contour: VNContoursObservation
    ) -> [MeasurementPointCandidate] {
        var candidates: [MeasurementPointCandidate] = []

        // 1. 허리둘레 포인트
        let waistPoints = detectWaistPoints(featurePoints: featurePoints)
        candidates.append(contentsOf: waistPoints)

        // 2. 총길이 포인트
        let lengthPoints = detectTotalLengthPoints(featurePoints: featurePoints)
        candidates.append(contentsOf: lengthPoints)

        return candidates
    }

    // MARK: - Private Detection Methods

    private func detectWaistPoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString
        let height = max(featurePoints.height, 0.0001)

        // 치마 허리: 상단에서 3-5%
        let waistCenter = featurePoints.topPoint.y - height * 0.04

        // 더 넓은 범위의 밴드로 탐색
        let halfSpans = [height * 0.02, height * 0.03, height * 0.05, height * 0.07]

        // 가장 좁은 폭을 찾되, 신뢰도도 계산
        var bestNarrowestSpan: (left: CGPoint, right: CGPoint)?
        var narrowestWidth: CGFloat = .infinity
        var narrowestConfidence: Float = 0.5

        for halfSpan in halfSpans {
            let range = (waistCenter - halfSpan)...(waistCenter + halfSpan)
            let candidates = featurePoints.pointsInYRange(range)

            guard !candidates.isEmpty,
                  let left = candidates.min(by: { $0.x < $1.x }),
                  let right = candidates.max(by: { $0.x < $1.x }) else {
                continue
            }

            let width = right.x - left.x
            if width < narrowestWidth {
                narrowestWidth = width
                bestNarrowestSpan = (left, right)

                // 신뢰도 계산
                let densityScore = min(Float(candidates.count) / 50.0, 1.0)
                let yDifference = abs(left.y - right.y)
                let symmetryScore = max(0.0, 1.0 - Float(yDifference / halfSpan))
                narrowestConfidence = (densityScore * 0.5) + (symmetryScore * 0.5)
            }
        }

        guard let span = bestNarrowestSpan else {
            return []
        }

        return [
            MeasurementPointCandidate(
                type: .waistCircumference,
                screenPosition: span.left,
                confidence: narrowestConfidence,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .waistCircumference,
                screenPosition: span.right,
                confidence: narrowestConfidence,
                groupId: groupId
            )
        ]
    }

    private func detectTotalLengthPoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString
        let height = max(featurePoints.height, 0.0001)

        let waistCenter = featurePoints.averagedPoint(
            around: featurePoints.topPoint.y - height * 0.03,
            halfSpan: height * 0.04
        ) ?? CGPoint(x: featurePoints.centerX, y: featurePoints.topPoint.y)

        let hemCenter = featurePoints.averagedPoint(
            around: featurePoints.bottomPoint.y + height * 0.02,
            halfSpan: height * 0.04
        ) ?? CGPoint(x: featurePoints.centerX, y: featurePoints.bottomPoint.y)

        return [
            MeasurementPointCandidate(
                type: .totalLength,
                screenPosition: waistCenter,
                confidence: 0.90,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .totalLength,
                screenPosition: hemCenter,
                confidence: 0.90,
                groupId: groupId
            )
        ]
    }
}

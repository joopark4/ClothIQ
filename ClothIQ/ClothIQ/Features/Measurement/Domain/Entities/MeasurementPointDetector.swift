//
//  MeasurementPointDetector.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  의류 타입별 측정 포인트 자동 감지 프로토콜 및 구현체들입니다.
//  특징점에서 측정 포인트를 추론하는 알고리즘을 제공합니다.
//
//  Key Responsibilities:
//  - 의류 타입별 측정 포인트 자동 감지
//  - 신뢰도 점수 계산
//  - 측정 포인트 후보 생성
//

import Foundation
import CoreGraphics
import Vision

// MARK: - Measurement Point Candidate

/// 자동 감지된 측정 포인트 후보
struct MeasurementPointCandidate {
    /// 측정 타입
    let type: MeasurementType

    /// 화면 좌표 (정규화)
    let screenPosition: CGPoint

    /// 신뢰도 (0.0 ~ 1.0)
    let confidence: Float

    /// 그룹 ID (같은 측정 항목에 속하는 포인트들)
    let groupId: String

    init(
        type: MeasurementType,
        screenPosition: CGPoint,
        confidence: Float,
        groupId: String? = nil
    ) {
        self.type = type
        self.screenPosition = screenPosition
        self.confidence = confidence
        self.groupId = groupId ?? UUID().uuidString
    }
}

// MARK: - Protocol

/// 측정 포인트 감지기 프로토콜
protocol MeasurementPointDetector {
    /// 지원하는 의류 타입
    var supportedTypes: [ClothingType] { get }

    /// 측정 포인트 감지
    ///
    /// - Parameters:
    ///   - featurePoints: 윤곽선에서 추출한 특징점
    ///   - contour: 전체 윤곽선
    /// - Returns: 감지된 측정 포인트 후보들
    func detectPoints(
        featurePoints: ClothingFeaturePoints,
        contour: VNContoursObservation
    ) -> [MeasurementPointCandidate]
}

// MARK: - Top Measurement Detector

/// 상의 측정 포인트 감지기
///
/// 반팔, 긴팔 티셔츠의 측정 포인트를 자동으로 감지합니다.
/// - 어깨너비: 상단 좌우 끝점
/// - 가슴둘레: 가슴 위치의 좌우 폭
/// - 총길이: 목 중심 → 밑단 중심
/// - 소매길이: 어깨 끝 → 소매 끝
///
final class TopMeasurementDetector: MeasurementPointDetector {
    let supportedTypes: [ClothingType] = [.shortSleeve, .longSleeve]

    func detectPoints(
        featurePoints: ClothingFeaturePoints,
        contour: VNContoursObservation
    ) -> [MeasurementPointCandidate] {
        var candidates: [MeasurementPointCandidate] = []

        // 1. 어깨너비 포인트
        let shoulderPoints = detectShoulderPoints(featurePoints: featurePoints)
        candidates.append(contentsOf: shoulderPoints)

        // 2. 가슴둘레 포인트
        let chestPoints = detectChestPoints(featurePoints: featurePoints)
        candidates.append(contentsOf: chestPoints)

        // 3. 총길이 포인트
        let lengthPoints = detectTotalLengthPoints(featurePoints: featurePoints)
        candidates.append(contentsOf: lengthPoints)

        // 4. 소매길이 포인트
        let sleevePoints = detectSleevePoints(featurePoints: featurePoints)
        candidates.append(contentsOf: sleevePoints)

        return candidates
    }

    // MARK: - Private Detection Methods

    private func detectShoulderPoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString

        let height = max(featurePoints.height, 0.0001)
        let shoulderCenterY = featurePoints.topPoint.y - height * 0.02
        let shoulderSpans = featurePoints.bestHorizontalSpan(
            centeredAt: shoulderCenterY,
            halfSpans: [height * 0.02, height * 0.04, height * 0.06],
            selection: .widest
        )

        guard let shoulders = shoulderSpans ?? featurePoints.bestHorizontalSpan(
            centeredAt: featurePoints.topPoint.y,
            halfSpans: [height * 0.02],
            selection: .widest
        ) else {
            return []
        }

        let leftShoulder = shoulders.left
        let rightShoulder = shoulders.right

        return [
            MeasurementPointCandidate(
                type: .shoulderWidth,
                screenPosition: leftShoulder,
                confidence: 0.85,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .shoulderWidth,
                screenPosition: rightShoulder,
                confidence: 0.85,
                groupId: groupId
            )
        ]
    }

    private func detectChestPoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString

        let height = max(featurePoints.height, 0.0001)
        let chestSpan = featurePoints.bestHorizontalSpan(
            centeredAt: featurePoints.chestY,
            halfSpans: [height * 0.03, height * 0.05, height * 0.07],
            selection: .widest
        )

        guard let span = chestSpan else {
            return []
        }

        let leftChest = span.left
        let rightChest = span.right

        return [
            MeasurementPointCandidate(
                type: .chestCircumference,
                screenPosition: leftChest,
                confidence: 0.80,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .chestCircumference,
                screenPosition: rightChest,
                confidence: 0.80,
                groupId: groupId
            )
        ]
    }

    private func detectTotalLengthPoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString
        let height = max(featurePoints.height, 0.0001)

        let neckCenter = featurePoints.averagedPoint(
            around: featurePoints.topPoint.y - height * 0.02,
            halfSpan: height * 0.03
        ) ?? CGPoint(x: featurePoints.centerX, y: featurePoints.topPoint.y)

        let hemCenter = featurePoints.averagedPoint(
            around: featurePoints.bottomPoint.y + height * 0.02,
            halfSpan: height * 0.03
        ) ?? CGPoint(x: featurePoints.centerX, y: featurePoints.bottomPoint.y)

        return [
            MeasurementPointCandidate(
                type: .totalLength,
                screenPosition: neckCenter,
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

    private func detectSleevePoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString

        let height = max(featurePoints.height, 0.0001)
        guard let shoulders = featurePoints.bestHorizontalSpan(
            centeredAt: featurePoints.topPoint.y - height * 0.02,
            halfSpans: [height * 0.02, height * 0.04, height * 0.06],
            selection: .widest
        ), let sleeveEnd = detectSleeveEnd(
            from: shoulders.right,
            featurePoints: featurePoints,
            garmentHeight: height
        ) else {
            return []
        }

        let rightShoulder = shoulders.right

        return [
            MeasurementPointCandidate(
                type: .sleeveLength,
                screenPosition: rightShoulder,
                confidence: 0.75,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .sleeveLength,
                screenPosition: sleeveEnd,
                confidence: 0.70,
                groupId: groupId
            )
        ]
    }

    private func detectSleeveEnd(
        from shoulder: CGPoint,
        featurePoints: ClothingFeaturePoints,
        garmentHeight: CGFloat
    ) -> CGPoint? {
        // 어깨보다 아래쪽 영역에서 소매 끝 찾기 (정규화 좌표는 위로 갈수록 값이 큼)
        let searchDepth = garmentHeight * 0.8
        let lowerBound = max(featurePoints.bottomPoint.y, shoulder.y - searchDepth)
        let range = lowerBound...shoulder.y
        let pointsInSleeveArea = featurePoints.pointsInYRange(range)

        // 오른쪽 소매: 어깨보다 바깥쪽에 있는 가장 큰 X 좌표
        let filtered = pointsInSleeveArea.filter { $0.x >= shoulder.x - featurePoints.width * 0.02 }
        return (filtered.isEmpty ? pointsInSleeveArea : filtered).max(by: { $0.x < $1.x })
    }
}

// MARK: - Bottom Measurement Detector

/// 하의 측정 포인트 감지기
///
/// 반바지, 긴바지의 측정 포인트를 자동으로 감지합니다.
/// - 허리둘레: 상단 좌우 폭
/// - 총길이: 허리 중심 → 밑단 중심
/// - 밑위: 허리 → 밑위 분기점
///
final class BottomMeasurementDetector: MeasurementPointDetector {
    let supportedTypes: [ClothingType] = [.pants, .shorts]

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

        // 3. 밑위 포인트
        let risePoints = detectRisePoints(featurePoints: featurePoints)
        candidates.append(contentsOf: risePoints)

        return candidates
    }

    // MARK: - Helper Methods (AutoSize02.md)

    /// AutoSize02.md: 여러 Y band에서 좌우 포인트를 추출하여 평균 계산
    private func detectWidthPointsWithMultipleBands(
        centerY: CGFloat,
        featurePoints: ClothingFeaturePoints,
        type: MeasurementType
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString

        // 더 넓은 범위의 band로 측정 (허리 감지 개선)
        let bands = [
            (centerY - 0.02)...(centerY + 0.02),   // 중심
            (centerY - 0.05)...(centerY - 0.02),   // 위쪽 (확장)
            (centerY + 0.02)...(centerY + 0.05),   // 아래쪽 (확장)
            (centerY - 0.10)...(centerY - 0.05),   // 더 위쪽 (추가)
            (centerY + 0.05)...(centerY + 0.10)    // 더 아래쪽 (추가)
        ]

        var leftPoints: [CGPoint] = []
        var rightPoints: [CGPoint] = []

        for band in bands {
            let pointsInBand = featurePoints.pointsInYRange(band)
            if !pointsInBand.isEmpty {
                if let left = pointsInBand.min(by: { $0.x < $1.x }) {
                    leftPoints.append(left)
                }
                if let right = pointsInBand.max(by: { $0.x < $1.x }) {
                    rightPoints.append(right)
                }
            }
        }

        guard !leftPoints.isEmpty, !rightPoints.isEmpty else {
            // Fallback: 단일 포인트
            guard let left = featurePoints.findLeftmostPoint(at: centerY, tolerance: 0.05),
                  let right = featurePoints.findRightmostPoint(at: centerY, tolerance: 0.05) else {
                return []
            }

            return [
                MeasurementPointCandidate(type: type, screenPosition: left, confidence: 0.70, groupId: groupId),
                MeasurementPointCandidate(type: type, screenPosition: right, confidence: 0.70, groupId: groupId)
            ]
        }

        // 평균 좌표 계산
        let avgLeftX = leftPoints.map { $0.x }.reduce(0, +) / CGFloat(leftPoints.count)
        let avgLeftY = leftPoints.map { $0.y }.reduce(0, +) / CGFloat(leftPoints.count)
        let avgRightX = rightPoints.map { $0.x }.reduce(0, +) / CGFloat(rightPoints.count)
        let avgRightY = rightPoints.map { $0.y }.reduce(0, +) / CGFloat(rightPoints.count)

        return [
            MeasurementPointCandidate(
                type: type,
                screenPosition: CGPoint(x: avgLeftX, y: avgLeftY),
                confidence: 0.90,  // 평균이므로 신뢰도 높음
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: type,
                screenPosition: CGPoint(x: avgRightX, y: avgRightY),
                confidence: 0.90,
                groupId: groupId
            )
        ]
    }

    // MARK: - Private Detection Methods

    private func detectWaistPoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let height = max(featurePoints.height, 0.0001)
        let waistCenter = featurePoints.topPoint.y - height * 0.05

        if let span = featurePoints.bestHorizontalSpan(
            centeredAt: waistCenter,
            halfSpans: [height * 0.02, height * 0.04, height * 0.06],
            selection: .narrowest
        ) {
            let groupId = UUID().uuidString
            return [
                MeasurementPointCandidate(type: .waistCircumference, screenPosition: span.left, confidence: 0.85, groupId: groupId),
                MeasurementPointCandidate(type: .waistCircumference, screenPosition: span.right, confidence: 0.85, groupId: groupId)
            ]
        }

        return detectWidthPointsWithMultipleBands(
            centerY: waistCenter,
            featurePoints: featurePoints,
            type: .waistCircumference
        )
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

    private func detectRisePoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString

        let waistCenter = CGPoint(
            x: featurePoints.centerX,
            y: featurePoints.topPoint.y
        )

        // 밑위 분기점 찾기 (중앙 근처에서 안쪽으로 들어간 점)
        guard let risePoint = detectRisePoint(featurePoints: featurePoints) else {
            return []
        }

        return [
            MeasurementPointCandidate(
                type: .rise,
                screenPosition: waistCenter,
                confidence: 0.75,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .rise,
                screenPosition: risePoint,
                confidence: 0.70,
                groupId: groupId
            )
        ]
    }

    private func detectRisePoint(
        featurePoints: ClothingFeaturePoints
    ) -> CGPoint? {
        // 중앙 근처의 점들 (X좌표 중심 ±10%)
        let centerRange = (featurePoints.centerX - 0.1)...(featurePoints.centerX + 0.1)
        let centerPoints = featurePoints.pointsInXRange(centerRange)

        guard !centerPoints.isEmpty else { return nil }

        // 가장 아래쪽(값이 작은) 포인트가 실제 밑위에 가깝다
        return centerPoints.min(by: { $0.y < $1.y })
    }
}

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
        let height = max(featurePoints.height, 0.0001)
        let waistCenter = featurePoints.topPoint.y - height * 0.04

        guard let span = featurePoints.bestHorizontalSpan(
            centeredAt: waistCenter,
            halfSpans: [height * 0.02, height * 0.04, height * 0.06],
            selection: .narrowest
        ) else {
            return []
        }

        let groupId = UUID().uuidString
        return [
            MeasurementPointCandidate(type: .waistCircumference, screenPosition: span.left, confidence: 0.85, groupId: groupId),
            MeasurementPointCandidate(type: .waistCircumference, screenPosition: span.right, confidence: 0.85, groupId: groupId)
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

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

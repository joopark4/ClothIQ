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

        // 5. 긴팔 전용 측정 항목 (aspectRatio > 1.0)
        let aspectRatio = featurePoints.aspectRatio
        if aspectRatio > 1.0 {
            // 5-1. 팔둘레 포인트
            let armPoints = detectArmCircumferencePoints(featurePoints: featurePoints)
            candidates.append(contentsOf: armPoints)
        }

        return candidates
    }

    // MARK: - Private Detection Methods

    private func detectShoulderPoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString

        let height = max(featurePoints.height, 0.0001)

        // 동적 오프셋 계산: 의류 종횡비와 높이를 고려
        // 긴 의류(셔츠)는 더 아래쪽, 짧은 의류(크롭 탑)는 더 위쪽
        let aspectRatio = featurePoints.aspectRatio
        let offsetMultiplier: CGFloat = aspectRatio > 1.2 ? 0.02 : 0.015  // 세로가 긴 의류는 2%, 짧은 의류는 1.5%
        let shoulderCenterY = featurePoints.topPoint.y - height * offsetMultiplier

        // 더 넓은 범위의 밴드로 탐색 (정확도 향상)
        let halfSpans = [height * 0.015, height * 0.025, height * 0.04, height * 0.06]

        // 개선된 가중 평균 방식 사용 (신뢰도 계산 포함)
        guard let result = featurePoints.robustHorizontalSpan(
            at: shoulderCenterY,
            halfSpans: halfSpans
        ) else {
            // Fallback: 기존 방식
            guard let shoulders = featurePoints.bestHorizontalSpan(
                centeredAt: featurePoints.topPoint.y,
                halfSpans: [height * 0.02],
                selection: .widest
            ) else {
                return []
            }

            return [
                MeasurementPointCandidate(
                    type: .shoulderWidth,
                    screenPosition: shoulders.left,
                    confidence: 0.60,  // Fallback은 신뢰도 낮음
                    groupId: groupId
                ),
                MeasurementPointCandidate(
                    type: .shoulderWidth,
                    screenPosition: shoulders.right,
                    confidence: 0.60,
                    groupId: groupId
                )
            ]
        }

        let leftShoulder = result.left
        let rightShoulder = result.right
        let confidence = result.confidence

        return [
            MeasurementPointCandidate(
                type: .shoulderWidth,
                screenPosition: leftShoulder,
                confidence: confidence,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .shoulderWidth,
                screenPosition: rightShoulder,
                confidence: confidence,
                groupId: groupId
            )
        ]
    }

    private func detectChestPoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString

        let height = max(featurePoints.height, 0.0001)

        // 가슴 위치는 의류 타입에 따라 다름
        // 타이트한 의류: 상단 30%, 루즈한 의류: 상단 35-40%
        // 여기서는 기본 chestY (30%) 사용하되, 더 넓은 범위 탐색
        let chestCenterY = featurePoints.chestY

        // 더 넓은 범위의 밴드로 탐색
        let halfSpans = [height * 0.02, height * 0.04, height * 0.06, height * 0.08]

        // 개선된 가중 평균 방식 사용
        guard let result = featurePoints.robustHorizontalSpan(
            at: chestCenterY,
            halfSpans: halfSpans
        ) else {
            // Fallback: 기존 방식
            guard let span = featurePoints.bestHorizontalSpan(
                centeredAt: chestCenterY,
                halfSpans: [height * 0.05],
                selection: .widest
            ) else {
                return []
            }

            return [
                MeasurementPointCandidate(
                    type: .chestCircumference,
                    screenPosition: span.left,
                    confidence: 0.55,  // Fallback은 신뢰도 낮음
                    groupId: groupId
                ),
                MeasurementPointCandidate(
                    type: .chestCircumference,
                    screenPosition: span.right,
                    confidence: 0.55,
                    groupId: groupId
                )
            ]
        }

        let leftChest = result.left
        let rightChest = result.right
        let confidence = result.confidence

        return [
            MeasurementPointCandidate(
                type: .chestCircumference,
                screenPosition: leftChest,
                confidence: confidence,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .chestCircumference,
                screenPosition: rightChest,
                confidence: confidence,
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

        // 어깨 포인트 재감지 (신뢰도 포함)
        let shoulderCenterY = featurePoints.topPoint.y - height * 0.02
        let halfSpans = [height * 0.015, height * 0.025, height * 0.04]

        guard let shoulderResult = featurePoints.robustHorizontalSpan(
            at: shoulderCenterY,
            halfSpans: halfSpans
        ) else {
            return []
        }

        let rightShoulder = shoulderResult.right
        let shoulderConfidence = shoulderResult.confidence

        // 소매 끝 감지 (개선된 버전)
        guard let (sleeveEnd, sleeveConfidence) = detectSleeveEnd(
            from: rightShoulder,
            featurePoints: featurePoints,
            garmentHeight: height
        ) else {
            return []
        }

        // 소매 길이 신뢰도: 어깨 신뢰도와 소매 끝 신뢰도의 평균
        let avgConfidence = (shoulderConfidence + sleeveConfidence) / 2.0

        return [
            MeasurementPointCandidate(
                type: .sleeveLength,
                screenPosition: rightShoulder,
                confidence: avgConfidence,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .sleeveLength,
                screenPosition: sleeveEnd,
                confidence: sleeveConfidence,
                groupId: groupId
            )
        ]
    }

    private func detectSleeveEnd(
        from shoulder: CGPoint,
        featurePoints: ClothingFeaturePoints,
        garmentHeight: CGFloat
    ) -> (point: CGPoint, confidence: Float)? {
        // 소매 영역 정의: 어깨보다 아래쪽, 어깨에서 80% 깊이까지
        let searchDepth = garmentHeight * 0.8
        let lowerBound = max(featurePoints.bottomPoint.y, shoulder.y - searchDepth)
        let range = lowerBound...shoulder.y
        let pointsInSleeveArea = featurePoints.pointsInYRange(range)

        // 방법 1: 곡률 기반 소매 끝 후보 찾기
        let curvatureCandidates = featurePoints.detectCurvaturePoints(
            threshold: 0.25,  // 소매 끝은 곡률이 큼
            yRange: range
        )

        // 오른쪽 소매: 어깨보다 바깥쪽에 있는 곡률 큰 점들
        let rightCurvatureCandidates = curvatureCandidates.filter {
            $0.x >= shoulder.x - featurePoints.width * 0.02  // 어깨 근처도 허용
        }

        // 방법 2: 가장 바깥쪽 포인트 (기존 방식)
        let filtered = pointsInSleeveArea.filter {
            $0.x >= shoulder.x - featurePoints.width * 0.02
        }
        let fallbackPoint = (filtered.isEmpty ? pointsInSleeveArea : filtered).max(by: { $0.x < $1.x })

        // 최선의 후보 선택
        var bestCandidate: CGPoint?
        var bestConfidence: Float = 0.5

        // 곡률 기반 후보가 있으면 우선 사용
        if let curvaturePoint = rightCurvatureCandidates.first {
            bestCandidate = curvaturePoint
            bestConfidence = 0.75  // 곡률 기반은 신뢰도 높음
        }
        // Fallback: 가장 바깥쪽 포인트
        else if let fallback = fallbackPoint {
            bestCandidate = fallback
            bestConfidence = 0.55  // 단순 최대값은 신뢰도 낮음
        }

        guard let sleeveEnd = bestCandidate else {
            return nil
        }

        // 추가 검증: 어깨로부터의 거리가 합리적인지
        let sleeveLength = sqrt(
            pow(sleeveEnd.x - shoulder.x, 2) + pow(sleeveEnd.y - shoulder.y, 2)
        )

        // 소매 길이가 너무 짧거나 너무 길면 신뢰도 하락
        let minLength = garmentHeight * 0.15  // 최소 15%
        let maxLength = garmentHeight * 0.95  // 최대 95%
        if sleeveLength < minLength || sleeveLength > maxLength {
            bestConfidence *= 0.7  // 신뢰도 30% 감소
        }

        return (point: sleeveEnd, confidence: bestConfidence)
    }

    /// 팔둘레 포인트 감지 (긴팔 전용)
    ///
    /// 팔둘레는 소매의 가장 두꺼운 부분 (어깨 끝에서 소매 중간 지점)을 측정합니다.
    ///
    private func detectArmCircumferencePoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString
        let height = max(featurePoints.height, 0.0001)

        // 어깨 위치 재감지
        let shoulderCenterY = featurePoints.topPoint.y - height * 0.02
        let halfSpans = [height * 0.015, height * 0.025]

        guard let shoulderResult = featurePoints.robustHorizontalSpan(
            at: shoulderCenterY,
            halfSpans: halfSpans
        ) else {
            return []
        }

        let rightShoulder = shoulderResult.right

        // 팔둘레 위치: 어깨에서 소매 중간 (어깨 아래 30-50%)
        let armCenterY = rightShoulder.y - height * 0.40  // 중간값 40%

        // 소매 영역에서 가장 넓은 폭을 찾음
        let armHalfSpans = [height * 0.05, height * 0.08, height * 0.12]

        var bestWidestSpan: (left: CGPoint, right: CGPoint)?
        var widestWidth: CGFloat = 0
        var widestConfidence: Float = 0.5

        for halfSpan in armHalfSpans {
            let range = (armCenterY - halfSpan)...(armCenterY + halfSpan)
            let candidates = featurePoints.pointsInYRange(range)

            // 오른쪽 소매 영역만 필터링 (X좌표가 어깨보다 바깥쪽)
            let sleeveCandsidates = candidates.filter { $0.x >= rightShoulder.x * 0.9 }

            guard !sleeveCandsidates.isEmpty,
                  let left = sleeveCandsidates.min(by: { $0.x < $1.x }),
                  let right = sleeveCandsidates.max(by: { $0.x < $1.x }) else {
                continue
            }

            let width = right.x - left.x
            if width > widestWidth {
                widestWidth = width
                bestWidestSpan = (left, right)

                // 신뢰도 계산
                let densityScore = min(Float(sleeveCandsidates.count) / 30.0, 1.0)
                let yDifference = abs(left.y - right.y)
                let symmetryScore = max(0.0, 1.0 - Float(yDifference / halfSpan))
                widestConfidence = (densityScore * 0.5) + (symmetryScore * 0.5)
            }
        }

        guard let span = bestWidestSpan else {
            return []
        }

        return [
            MeasurementPointCandidate(
                type: .armCircumference,
                screenPosition: span.left,
                confidence: widestConfidence,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .armCircumference,
                screenPosition: span.right,
                confidence: widestConfidence,
                groupId: groupId
            )
        ]
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

        // 4. 긴바지 전용 측정 항목 (aspectRatio > 1.5)
        let aspectRatio = featurePoints.aspectRatio
        if aspectRatio > 1.5 {
            // 4-1. 허벅지둘레 포인트
            let thighPoints = detectThighPoints(featurePoints: featurePoints)
            candidates.append(contentsOf: thighPoints)

            // 4-2. 밑단 포인트
            let hemPoints = detectHemPoints(featurePoints: featurePoints)
            candidates.append(contentsOf: hemPoints)
        }

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
        let groupId = UUID().uuidString
        let height = max(featurePoints.height, 0.0001)

        // 동적 오프셋 계산: 바지 타입에 따라 허리 위치 조정
        // 하이웨이스트: 3%, 미드라이즈: 5%, 로우라이즈: 8%
        // 종횡비로 추정: 긴 바지(>1.5)는 5%, 짧은 바지(<1.5)는 6%
        let aspectRatio = featurePoints.aspectRatio
        let offsetMultiplier: CGFloat = aspectRatio > 1.5 ? 0.05 : 0.06
        let waistCenter = featurePoints.topPoint.y - height * offsetMultiplier

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

        // 가장 좁은 폭을 찾았으면 사용
        if let span = bestNarrowestSpan {
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

        // Fallback: 여러 밴드 평균 방식
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

        // detectWaistPoints와 동일한 로직으로 허리 위치 계산
        let aspectRatio = featurePoints.aspectRatio
        let waistOffsetMultiplier: CGFloat = aspectRatio > 1.5 ? 0.05 : 0.06

        let waistCenter = featurePoints.averagedPoint(
            around: featurePoints.topPoint.y - height * waistOffsetMultiplier,
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

        // 밑위 분기점 찾기 (개선된 버전)
        guard let (risePoint, riseConfidence) = detectRisePoint(
            featurePoints: featurePoints
        ) else {
            return []
        }

        return [
            MeasurementPointCandidate(
                type: .rise,
                screenPosition: waistCenter,
                confidence: 0.85,  // 허리 중심은 신뢰도 높음
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .rise,
                screenPosition: risePoint,
                confidence: riseConfidence,
                groupId: groupId
            )
        ]
    }

    private func detectRisePoint(
        featurePoints: ClothingFeaturePoints
    ) -> (point: CGPoint, confidence: Float)? {
        // 밑위 영역: 반바지와 긴바지를 구분하여 탐색
        let height = featurePoints.height
        let aspectRatio = featurePoints.aspectRatio

        // 반바지 vs 긴바지 구분 (aspectRatio 임계값: 1.5)
        let (searchTop, searchBottom): (CGFloat, CGFloat)
        if aspectRatio < 1.5 {
            // 반바지: 상단에서 40~90% 사이 (밑위가 더 아래쪽에 위치)
            searchTop = featurePoints.topPoint.y - height * 0.4
            searchBottom = featurePoints.topPoint.y - height * 0.9
        } else {
            // 긴바지: 상단에서 30~70% 사이
            searchTop = featurePoints.topPoint.y - height * 0.3
            searchBottom = featurePoints.topPoint.y - height * 0.7
        }

        let riseYRange = searchBottom...searchTop

        // 방법 1: 곡률 기반 밑위 후보 찾기
        // 밑위 분기점은 곡률이 매우 큼 (급격한 방향 전환)
        let curvatureCandidates = featurePoints.detectCurvaturePoints(
            threshold: 0.4,  // 밑위는 곡률이 매우 큼
            yRange: riseYRange
        )

        // 중앙 근처의 곡률 큰 점들 (X좌표 중심 ±15%)
        let centerRange = (featurePoints.centerX - 0.15)...(featurePoints.centerX + 0.15)
        let centerCurvatureCandidates = curvatureCandidates.filter {
            centerRange.contains($0.x)
        }

        // 방법 2: 중앙 근처에서 가장 아래쪽 포인트 (기존 방식)
        let centerPoints = featurePoints.pointsInXRange(centerRange)
            .filter { riseYRange.contains($0.y) }
        let fallbackPoint = centerPoints.min(by: { $0.y < $1.y })

        // 최선의 후보 선택
        var bestCandidate: CGPoint?
        var bestConfidence: Float = 0.5

        // 곡률 기반 후보가 있으면 우선 사용
        if let curvaturePoint = centerCurvatureCandidates.first {
            bestCandidate = curvaturePoint
            bestConfidence = 0.80  // 곡률 기반은 신뢰도 높음
        }
        // Fallback: 중앙의 가장 아래쪽 포인트
        else if let fallback = fallbackPoint {
            bestCandidate = fallback
            bestConfidence = 0.60  // 단순 최소값은 신뢰도 중간
        }

        guard let risePoint = bestCandidate else {
            return nil
        }

        // 추가 검증: 밑위 길이가 합리적인지 (반바지 vs 긴바지)
        let waistCenterY = featurePoints.topPoint.y
        let riseLength = abs(waistCenterY - risePoint.y)

        // 반바지와 긴바지에 따라 다른 검증 범위 적용
        let expectedRiseRange: ClosedRange<CGFloat>
        if aspectRatio < 1.5 {
            // 반바지: 밑위가 전체 높이의 35~75% 차지
            expectedRiseRange = (height * 0.35)...(height * 0.75)
        } else {
            // 긴바지: 밑위가 전체 높이의 20~60% 차지
            expectedRiseRange = (height * 0.2)...(height * 0.6)
        }

        if !expectedRiseRange.contains(riseLength) {
            bestConfidence *= 0.8  // 범위를 벗어나면 신뢰도 20% 감소
        }

        return (point: risePoint, confidence: bestConfidence)
    }

    /// 허벅지둘레 포인트 감지 (긴바지 전용)
    ///
    /// 허벅지는 밑위 아래 10-20% 지점에서 가장 넓은 폭을 찾습니다.
    ///
    private func detectThighPoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString
        let height = max(featurePoints.height, 0.0001)

        // 허벅지 위치: 밑위 아래 10-20% (상단에서 약 45-55%)
        // 긴바지의 밑위가 30-50%에 있으므로, 그 아래 10-20%를 탐색
        let thighCenterY = featurePoints.topPoint.y - height * 0.50  // 중간값 50%

        // 다중 밴드 탐색
        let halfSpans = [height * 0.03, height * 0.05, height * 0.08]

        // 가장 넓은 폭을 찾음 (허벅지는 가장 두꺼운 부분)
        var bestWidestSpan: (left: CGPoint, right: CGPoint)?
        var widestWidth: CGFloat = 0
        var widestConfidence: Float = 0.5

        for halfSpan in halfSpans {
            let range = (thighCenterY - halfSpan)...(thighCenterY + halfSpan)
            let candidates = featurePoints.pointsInYRange(range)

            guard !candidates.isEmpty,
                  let left = candidates.min(by: { $0.x < $1.x }),
                  let right = candidates.max(by: { $0.x < $1.x }) else {
                continue
            }

            let width = right.x - left.x
            if width > widestWidth {
                widestWidth = width
                bestWidestSpan = (left, right)

                // 신뢰도 계산
                let densityScore = min(Float(candidates.count) / 50.0, 1.0)
                let yDifference = abs(left.y - right.y)
                let symmetryScore = max(0.0, 1.0 - Float(yDifference / halfSpan))
                widestConfidence = (densityScore * 0.5) + (symmetryScore * 0.5)
            }
        }

        guard let span = bestWidestSpan else {
            return []
        }

        return [
            MeasurementPointCandidate(
                type: .thighCircumference,
                screenPosition: span.left,
                confidence: widestConfidence,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .thighCircumference,
                screenPosition: span.right,
                confidence: widestConfidence,
                groupId: groupId
            )
        ]
    }

    /// 밑단 포인트 감지 (긴바지 전용)
    ///
    /// 밑단은 바지 하단에서 2-5% 위쪽의 좌우 폭을 측정합니다.
    ///
    private func detectHemPoints(
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementPointCandidate] {
        let groupId = UUID().uuidString
        let height = max(featurePoints.height, 0.0001)

        // 밑단 위치: 하단에서 2-5% 위쪽
        let hemCenterY = featurePoints.bottomPoint.y + height * 0.03  // 중간값 3%

        // 다중 밴드 탐색
        let halfSpans = [height * 0.02, height * 0.03, height * 0.05]

        // robustHorizontalSpan 사용 (가중 평균)
        guard let result = featurePoints.robustHorizontalSpan(
            at: hemCenterY,
            halfSpans: halfSpans
        ) else {
            return []
        }

        return [
            MeasurementPointCandidate(
                type: .hem,
                screenPosition: result.left,
                confidence: result.confidence,
                groupId: groupId
            ),
            MeasurementPointCandidate(
                type: .hem,
                screenPosition: result.right,
                confidence: result.confidence,
                groupId: groupId
            )
        ]
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

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

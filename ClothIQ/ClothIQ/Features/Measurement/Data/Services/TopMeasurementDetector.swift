//
//  TopMeasurementDetector.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  상의(반팔, 긴팔) 측정 포인트 자동 감지 구현체입니다.
//
//  Key Responsibilities:
//  - 어깨너비, 가슴둘레, 총길이, 소매길이, 팔둘레 포인트 감지
//  - 신뢰도 점수 계산
//

import Foundation
import CoreGraphics
import Vision

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

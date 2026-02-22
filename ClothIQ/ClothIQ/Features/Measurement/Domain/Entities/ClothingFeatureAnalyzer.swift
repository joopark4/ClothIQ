//
//  ClothingFeatureAnalyzer.swift
//  ClothIQ
//
//  Created on 2025-11-06
//
//  Description:
//  윤곽선 기반 의류 특징 분석기입니다.
//  종횡비만으로는 구분하기 어려운 의류 타입을 윤곽선 형태를 분석하여 정확하게 분류합니다.
//
//  Key Features:
//  - 소매 감지 (좌우 돌출 분석)
//  - 밑단 형태 분석 (V자형 vs 평평)
//  - 상단 영역 분석 (목선 vs 허리밴드)
//  - 종합 분류 (종횡비 + 윤곽 특징)
//
//  Expected Accuracy:
//  - 기존 (종횡비만): 60-70%
//  - 개선 (종횡비 + 윤곽): 75-80%
//

import Foundation
import CoreGraphics
import Vision

/// 의류 특징 분석 결과
struct ClothingFeatures {
    /// 소매 감지 결과
    let sleeveDetection: SleeveDetection

    /// 밑단 형태
    let hemlineShape: HemlineShape

    /// 상단 영역 형태 (목선 vs 허리밴드)
    let topRegionShape: TopRegionShape

    /// 종횡비 (height/width)
    let aspectRatio: CGFloat

    /// 전체 신뢰도 (0.0 ~ 1.0)
    var confidence: Float {
        let sleeveConfidence = sleeveDetection.confidence
        let hemlineConfidence = hemlineShape.confidence
        let topConfidence = topRegionShape.confidence

        // 가중 평균 (소매 40%, 밑단 30%, 상단 30%)
        return sleeveConfidence * 0.4 + hemlineConfidence * 0.3 + topConfidence * 0.3
    }
}

/// 소매 감지 결과
struct SleeveDetection {
    /// 소매 존재 여부
    let hasSleeves: Bool

    /// 왼쪽 소매 돌출 정도 (0.0 ~ 1.0)
    let leftProtrusionRatio: CGFloat

    /// 오른쪽 소매 돌출 정도 (0.0 ~ 1.0)
    let rightProtrusionRatio: CGFloat

    /// 소매 타입 추정
    var sleeveType: SleeveType {
        guard hasSleeves else { return .none }

        let avgProtrusion = (leftProtrusionRatio + rightProtrusionRatio) / 2.0

        if avgProtrusion < 0.10 {
            return .none
        } else if avgProtrusion < 0.18 {
            return .short
        } else {
            return .long
        }
    }

    /// 감지 신뢰도
    var confidence: Float {
        if !hasSleeves {
            return 0.9  // 소매 없음은 비교적 명확
        }

        // 좌우 대칭성 체크
        let symmetry = 1.0 - abs(leftProtrusionRatio - rightProtrusionRatio)
        return Float(symmetry) * 0.8 + 0.2
    }
}

/// 소매 타입
enum SleeveType {
    case none       // 민소매 (하의)
    case short      // 반팔
    case long       // 긴팔
}

/// 밑단 형태
struct HemlineShape {
    /// V자형 여부 (바지)
    let isVShaped: Bool

    /// 평평한 여부 (치마, 상의)
    let isFlat: Bool

    /// 밑단 중앙 Y 좌표
    let centerY: CGFloat

    /// 밑단 좌측 Y 좌표
    let leftY: CGFloat

    /// 밑단 우측 Y 좌표
    let rightY: CGFloat

    /// V자형 강도 (0.0 ~ 1.0)
    var vShapeStrength: CGFloat {
        guard leftY > 0 && rightY > 0 && centerY > 0 else { return 0 }

        // 좌우 평균 Y와 중앙 Y의 차이
        let avgSideY = (leftY + rightY) / 2.0
        let diff = abs(avgSideY - centerY)

        // 전체 높이 대비 차이 비율
        return diff
    }

    /// 감지 신뢰도
    var confidence: Float {
        if isVShaped {
            return Float(min(vShapeStrength * 2.0, 1.0))
        } else if isFlat {
            return Float(1.0 - vShapeStrength)
        } else {
            return 0.5  // 불확실
        }
    }
}

/// 상단 영역 형태
struct TopRegionShape {
    /// 목선 같은 좁은 형태인지
    let isNarrow: Bool

    /// 허리밴드 같은 넓은 형태인지
    let isWide: Bool

    /// 상단 너비 비율 (전체 너비 대비)
    let topWidthRatio: CGFloat

    /// 감지 신뢰도
    var confidence: Float {
        if isNarrow {
            return Float(1.0 - topWidthRatio)  // 좁을수록 높은 신뢰도
        } else if isWide {
            return Float(topWidthRatio)  // 넓을수록 높은 신뢰도
        } else {
            return 0.5
        }
    }
}

/// 의류 특징 분석기
final class ClothingFeatureAnalyzer {

    // MARK: - Public Methods

    /// 윤곽선에서 의류 특징 추출
    ///
    /// - Parameter contour: Vision 윤곽선 관찰 결과
    /// - Returns: 추출된 의류 특징
    func extractFeatures(from contour: VNContoursObservation) -> ClothingFeatures {
        // 가장 큰 윤곽선 선택 (의류 본체)
        guard let mainContour = selectMainContour(from: contour) else {
            return defaultFeatures()
        }

        let points = mainContour.normalizedPath.points()

        guard !points.isEmpty else {
            return defaultFeatures()
        }

        // 바운딩 박스 계산
        let boundingBox = calculateBoundingBox(from: points)
        let aspectRatio = boundingBox.height / boundingBox.width

        // 특징 추출
        let sleeveDetection = detectSleeves(points: points, boundingBox: boundingBox)
        let hemlineShape = analyzeHemline(points: points, boundingBox: boundingBox)
        let topRegionShape = analyzeTopRegion(points: points, boundingBox: boundingBox)

        return ClothingFeatures(
            sleeveDetection: sleeveDetection,
            hemlineShape: hemlineShape,
            topRegionShape: topRegionShape,
            aspectRatio: aspectRatio
        )
    }

    /// 의류 특징 기반 타입 추정
    ///
    /// - Parameter features: 의류 특징
    /// - Returns: 추정된 의류 타입
    func detectClothingCategory(from features: ClothingFeatures) -> ClothingType {
        // 1. 밑단 형태로 상의/하의 구분
        if features.hemlineShape.isVShaped {
            // V자형 밑단 → 바지
            if features.aspectRatio > 1.3 {
                return .pants  // 긴바지
            } else {
                return .shorts  // 반바지
            }
        }

        // 2. 상단 영역으로 상의/하의 구분
        if features.topRegionShape.isWide {
            // 넓은 상단 → 하의 (허리밴드)
            if features.aspectRatio > 1.0 {
                return .pants  // 긴바지
            } else if features.aspectRatio > 0.5 {
                return .shorts  // 반바지
            } else {
                return .skirt  // 미니 스커트
            }
        }

        // 3. 소매가 없고 종횡비가 높으면 무조건 하의 (반바지/긴바지)
        // 중요: 상단이 좁아 보여도, 소매가 없고 종횡비가 높으면 하의임!
        if !features.sleeveDetection.hasSleeves && features.aspectRatio > 1.0 {
            print("🔍 [ClothingCategory] 소매 없음 + 종횡비 높음 → 하의로 판정")
            if features.aspectRatio > 1.6 {  // 1.3 → 1.6 (반바지 범위: 0.8~1.6)
                return .pants  // 긴바지
            } else {
                return .shorts  // 반바지
            }
        }

        // 4. 소매 감지로 상의 세부 분류
        if features.topRegionShape.isNarrow {
            // 좁은 상단 → 상의 (목선)
            switch features.sleeveDetection.sleeveType {
            case .short:
                return .shortSleeve
            case .long:
                return .longSleeve
            case .none:
                // 민소매 → 종횡비로 판단
                if features.aspectRatio < 0.7 {
                    return .shortSleeve  // 크롭탑일 가능성
                } else {
                    return .longSleeve
                }
            }
        }

        // 4. 종횡비 기반 폴백 (기존 방식)
        if features.aspectRatio < 0.8 {
            return features.sleeveDetection.hasSleeves ? .shortSleeve : .skirt
        } else if features.aspectRatio < 1.3 {
            return features.sleeveDetection.hasSleeves ? .longSleeve : .skirt
        } else {
            return .pants
        }
    }

    // MARK: - Private Methods

    /// 가장 큰 윤곽선 선택
    private func selectMainContour(from observation: VNContoursObservation) -> VNContour? {
        var bestContour: VNContour?
        var bestArea: CGFloat = 0

        for i in 0..<observation.contourCount {
            guard let contour = try? observation.contour(at: i) else { continue }

            let points = contour.normalizedPath.points()
            guard points.count >= 30 else { continue }

            // 면적 계산
            let box = calculateBoundingBox(from: points)
            let area = box.width * box.height

            if area > 0.05 && area > bestArea {  // 최소 5% 이상
                bestArea = area
                bestContour = contour
            }
        }

        return bestContour
    }

    /// 바운딩 박스 계산
    private func calculateBoundingBox(from points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }

        let minX = points.map { $0.x }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 1
        let minY = points.map { $0.y }.min() ?? 0
        let maxY = points.map { $0.y }.max() ?? 1

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    /// 소매 감지
    ///
    /// 좌우 20% 지점에서 돌출 정도를 분석하여 소매 존재 여부를 판단합니다.
    private func detectSleeves(points: [CGPoint], boundingBox: CGRect) -> SleeveDetection {
        let topY = boundingBox.maxY  // Vision 좌표계: Y는 아래→위 증가 (상단이 maxY)
        let height = boundingBox.height

        // 상단 20% 지점 (소매가 있을 영역)
        // Vision 좌표계에서 아래로 내려가려면 빼야 함
        let sleeveY = topY - height * 0.20

        // 중앙 50% 지점도 확인 (반바지 엉덩이 부분과 구분)
        let midY = topY - height * 0.50

        // 해당 Y 근처 점들 필터링 (±5% 오차 허용)
        let tolerance = height * 0.05
        let sleevePoints = points.filter {
            abs($0.y - sleeveY) < tolerance
        }

        let midPoints = points.filter {
            abs($0.y - midY) < tolerance
        }

        guard !sleevePoints.isEmpty, !midPoints.isEmpty else {
            print("🔍 [SleeveDetection] 포인트 없음 - 소매 없음으로 판정")
            return SleeveDetection(
                hasSleeves: false,
                leftProtrusionRatio: 0,
                rightProtrusionRatio: 0
            )
        }

        // 상단 20% 지점의 너비
        let sleeveLeft = sleevePoints.min(by: { $0.x < $1.x })?.x ?? 0
        let sleeveRight = sleevePoints.max(by: { $0.x < $1.x })?.x ?? 0
        let sleeveWidth = sleeveRight - sleeveLeft

        // 중앙 50% 지점의 너비
        let midLeft = midPoints.min(by: { $0.x < $1.x })?.x ?? 0
        let midRight = midPoints.max(by: { $0.x < $1.x })?.x ?? 0
        let midWidth = midRight - midLeft

        // 소매 판정: 상단이 중앙보다 넓으면 소매 있음
        let widthRatio = sleeveWidth / max(midWidth, 0.001)

        print("🔍 [SleeveDetection] sleeveWidth: \(String(format: "%.3f", sleeveWidth)), midWidth: \(String(format: "%.3f", midWidth)), ratio: \(String(format: "%.2f", widthRatio))")

        // 소매 존재 여부: 상단이 중앙보다 15% 이상 넓으면 소매 있음
        let hasSleeves = widthRatio > 1.15

        let leftProtrusion = (sleeveLeft < midLeft) ? (midLeft - sleeveLeft) : 0
        let rightProtrusion = (sleeveRight > midRight) ? (sleeveRight - midRight) : 0
        let leftRatio = leftProtrusion / boundingBox.width
        let rightRatio = rightProtrusion / boundingBox.width

        print("🔍 [SleeveDetection] 결과: \(hasSleeves ? "소매 있음" : "소매 없음") (ratio: \(String(format: "%.2f", widthRatio)))")

        return SleeveDetection(
            hasSleeves: hasSleeves,
            leftProtrusionRatio: leftRatio,
            rightProtrusionRatio: rightRatio
        )
    }

    /// 밑단 형태 분석
    ///
    /// 밑단이 V자 형태인지 (바지), 평평한지 (치마/상의) 판단합니다.
    private func analyzeHemline(points: [CGPoint], boundingBox: CGRect) -> HemlineShape {
        let bottomY = boundingBox.minY  // Vision 좌표계: minY가 최하단
        let height = boundingBox.height
        let width = boundingBox.width

        // 하단 10% 영역의 점들
        let tolerance = height * 0.10  // 10%로 확대
        let hemlinePoints = points.filter {
            abs($0.y - bottomY) < tolerance
        }

        guard !hemlinePoints.isEmpty else {
            print("🔍 [HemlineAnalysis] 밑단 포인트 없음 - 평평으로 판정")
            return HemlineShape(
                isVShaped: false,
                isFlat: true,
                centerY: bottomY,
                leftY: bottomY,
                rightY: bottomY
            )
        }

        // 좌, 중앙, 우 샘플링
        let leftX = boundingBox.minX + width * 0.15
        let centerX = boundingBox.midX
        let rightX = boundingBox.maxX - width * 0.15

        let xTolerance = width * 0.10  // X 허용 범위 확대

        let leftPoints = hemlinePoints.filter { abs($0.x - leftX) < xTolerance }
        let centerPoints = hemlinePoints.filter { abs($0.x - centerX) < xTolerance }
        let rightPoints = hemlinePoints.filter { abs($0.x - rightX) < xTolerance }

        // 각 영역의 최하단 Y (Vision 좌표계에서는 최소값)
        let leftY = leftPoints.map { $0.y }.min() ?? bottomY
        let centerY = centerPoints.map { $0.y }.min() ?? bottomY
        let rightY = rightPoints.map { $0.y }.min() ?? bottomY

        // V자 판단: 중앙이 좌우보다 아래에 있고, 차이가 3% 이상 (완화)
        let avgSideY = (leftY + rightY) / 2.0
        let diff = abs(centerY - avgSideY) / height

        print("🔍 [HemlineAnalysis] leftY: \(String(format: "%.3f", leftY)), centerY: \(String(format: "%.3f", centerY)), rightY: \(String(format: "%.3f", rightY)), diff: \(String(format: "%.1f%%", diff * 100))")

        // 임계값 완화
        let isVShaped = centerY < avgSideY && diff > 0.03  // 5% → 3%
        let isFlat = diff < 0.02  // 3% → 2%

        print("🔍 [HemlineAnalysis] 결과: \(isVShaped ? "V자형" : isFlat ? "평평" : "불확실")")

        return HemlineShape(
            isVShaped: isVShaped,
            isFlat: isFlat,
            centerY: centerY,
            leftY: leftY,
            rightY: rightY
        )
    }

    /// 상단 영역 분석
    ///
    /// 상단이 좁은지 (목선, 상의), 넓은지 (허리밴드, 하의) 판단합니다.
    private func analyzeTopRegion(points: [CGPoint], boundingBox: CGRect) -> TopRegionShape {
        let topY = boundingBox.maxY  // Vision 좌표계: maxY가 최상단
        let height = boundingBox.height
        let totalWidth = boundingBox.width

        // 상단 10% 영역의 점들
        let tolerance = height * 0.10  // 10%로 확대
        let topPoints = points.filter {
            abs($0.y - topY) < tolerance
        }

        guard !topPoints.isEmpty else {
            print("🔍 [TopRegionAnalysis] 상단 포인트 없음 - 넓음으로 판정")
            return TopRegionShape(
                isNarrow: false,
                isWide: true,
                topWidthRatio: 1.0
            )
        }

        // 상단 좌우 끝점
        let leftX = topPoints.map { $0.x }.min() ?? boundingBox.minX
        let rightX = topPoints.map { $0.x }.max() ?? boundingBox.maxX

        let topWidth = rightX - leftX
        let widthRatio = topWidth / totalWidth

        print("🔍 [TopRegionAnalysis] topWidth: \(String(format: "%.3f", topWidth)), totalWidth: \(String(format: "%.3f", totalWidth)), ratio: \(String(format: "%.1f%%", widthRatio * 100))")

        // 판단 기준 (임계값 조정)
        let isNarrow = widthRatio < 0.55   // 55% 미만 (목선, 상의)
        let isWide = widthRatio > 0.75     // 75% 이상 (허리밴드, 하의) - 85% → 75%로 완화

        print("🔍 [TopRegionAnalysis] 결과: \(isNarrow ? "좁음(목선)" : isWide ? "넓음(허리)" : "중간") (ratio: \(String(format: "%.1f%%", widthRatio * 100)))")

        return TopRegionShape(
            isNarrow: isNarrow,
            isWide: isWide,
            topWidthRatio: widthRatio
        )
    }

    /// 기본 특징 반환 (감지 실패 시)
    private func defaultFeatures() -> ClothingFeatures {
        return ClothingFeatures(
            sleeveDetection: SleeveDetection(
                hasSleeves: false,
                leftProtrusionRatio: 0,
                rightProtrusionRatio: 0
            ),
            hemlineShape: HemlineShape(
                isVShaped: false,
                isFlat: true,
                centerY: 0,
                leftY: 0,
                rightY: 0
            ),
            topRegionShape: TopRegionShape(
                isNarrow: false,
                isWide: false,
                topWidthRatio: 0.5
            ),
            aspectRatio: 1.0
        )
    }
}

// MARK: - CustomStringConvertible

extension ClothingFeatures: CustomStringConvertible {
    var description: String {
        """
        ClothingFeatures(
          aspectRatio: \(String(format: "%.2f", aspectRatio)),
          sleeves: \(sleeveDetection.hasSleeves ? "Yes" : "No") (\(sleeveDetection.sleeveType)),
          hemline: \(hemlineShape.isVShaped ? "V-shaped" : "Flat"),
          topRegion: \(topRegionShape.isNarrow ? "Narrow" : topRegionShape.isWide ? "Wide" : "Medium"),
          confidence: \(String(format: "%.1f%%", confidence * 100))
        )
        """
    }
}

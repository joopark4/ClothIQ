//
//  ClothingFeaturePoints.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  의류 윤곽선에서 추출한 특징점들을 저장하는 구조체입니다.
//  자동 측정 알고리즘에서 측정 포인트를 추론하는 데 사용됩니다.
//
//  Key Responsibilities:
//  - 의류의 주요 특징점 저장 (최상단, 최하단, 좌우 끝 등)
//  - 측정 위치 계산용 기준점 제공
//

import Foundation
import CoreGraphics

/// 의류 윤곽선에서 추출한 특징점
///
/// Vision Framework의 윤곽선 감지 결과에서 극값(최상단, 최하단, 좌우 끝)과
/// 주요 측정 위치(가슴, 허리, 엉덩이)의 Y좌표를 저장합니다.
///
/// ## 좌표계
/// - 정규화된 좌표 (0.0 ~ 1.0)
/// - 원점: 좌측 하단
/// - Y축: 위로 갈수록 증가
///
struct ClothingFeaturePoints {
    // MARK: - 극값 포인트

    /// 최상단 지점 (목선 또는 허리선)
    let topPoint: CGPoint

    /// 최하단 지점 (밑단)
    let bottomPoint: CGPoint

    /// 최좌측 지점
    let leftmostPoint: CGPoint

    /// 최우측 지점
    let rightmostPoint: CGPoint

    // MARK: - 계산된 기준점

    /// 중심 X좌표
    let centerX: CGFloat

    /// 가슴 위치 Y좌표 (상단에서 30%)
    let chestY: CGFloat

    /// 허리 위치 Y좌표 (중앙 50%)
    let waistY: CGFloat

    /// 엉덩이 위치 Y좌표 (하단에서 30%)
    let hipY: CGFloat

    // MARK: - 전체 윤곽선 포인트

    /// 전체 윤곽선 포인트 배열 (정규화된 좌표)
    let allPoints: [CGPoint]

    // MARK: - Initialization

    init(
        topPoint: CGPoint,
        bottomPoint: CGPoint,
        leftmostPoint: CGPoint,
        rightmostPoint: CGPoint,
        allPoints: [CGPoint]
    ) {
        self.topPoint = topPoint
        self.bottomPoint = bottomPoint
        self.leftmostPoint = leftmostPoint
        self.rightmostPoint = rightmostPoint
        self.allPoints = allPoints

        // 중심 X좌표 계산
        self.centerX = (leftmostPoint.x + rightmostPoint.x) / 2.0

        // 주요 측정 위치 Y좌표 계산
        let totalHeight = abs(topPoint.y - bottomPoint.y)
        self.chestY = topPoint.y - totalHeight * 0.3  // 상단에서 30% 아래
        self.waistY = topPoint.y - totalHeight * 0.5  // 중앙
        self.hipY = topPoint.y - totalHeight * 0.7    // 상단에서 70% 아래
    }
}

extension ClothingFeaturePoints {
    // MARK: - Convenience Methods

    enum HorizontalSpanSelection {
        case widest
        case narrowest
    }

    /// 주어진 중심 높이를 기준으로 가장 넓거나 좁은 밴드의 좌우 끝점을 찾습니다.
    /// - Parameters:
    ///   - centerY: 기준이 되는 Y 좌표
    ///   - halfSpans: 탐색할 밴드의 절반 높이 목록 (정규화 좌표)
    ///   - selection: 가장 넓은/좁은 밴드 선택 기준
    /// - Returns: 선택된 밴드의 좌측/우측 포인트. 없으면 nil
    func bestHorizontalSpan(
        centeredAt centerY: CGFloat,
        halfSpans: [CGFloat],
        selection: HorizontalSpanSelection
    ) -> (left: CGPoint, right: CGPoint)? {
        guard !halfSpans.isEmpty else { return nil }

        var chosen: (left: CGPoint, right: CGPoint)?
        var chosenSpan: CGFloat?

        for halfSpan in halfSpans {
            guard halfSpan > 0 else { continue }

            let lower = max(bottomPoint.y, centerY - halfSpan)
            let upper = min(topPoint.y, centerY + halfSpan)
            guard lower <= upper else { continue }

            let range = lower...upper
            let candidates = pointsInYRange(range)
            guard !candidates.isEmpty,
                  let left = candidates.min(by: { $0.x < $1.x }),
                  let right = candidates.max(by: { $0.x < $1.x }) else {
                continue
            }

            let span = right.x - left.x
            guard span > 0 else { continue }

            if let current = chosenSpan {
                switch selection {
                case .widest:
                    if span <= current { continue }
                case .narrowest:
                    if span >= current { continue }
                }
            }

            chosen = (left, right)
            chosenSpan = span
        }

        return chosen
    }

    /// 특정 높이 주변의 포인트 평균을 반환합니다.
    /// - Parameters:
    ///   - centerY: 기준이 되는 Y 좌표
    ///   - halfSpan: 탐색할 절반 높이 (정규화)
    /// - Returns: 평균 좌표 (없으면 nil)
    func averagedPoint(around centerY: CGFloat, halfSpan: CGFloat) -> CGPoint? {
        guard halfSpan > 0 else { return nil }

        let lower = max(bottomPoint.y, centerY - halfSpan)
        let upper = min(topPoint.y, centerY + halfSpan)
        guard lower <= upper else { return nil }

        let candidates = pointsInYRange(lower...upper)
        guard !candidates.isEmpty else { return nil }

        let sum = candidates.reduce((x: CGFloat.zero, y: CGFloat.zero)) { partial, point in
            (partial.x + point.x, partial.y + point.y)
        }
        let count = CGFloat(candidates.count)
        return CGPoint(x: sum.x / count, y: sum.y / count)
    }
}

extension ClothingFeaturePoints {
    /// 특정 Y좌표에서 가장 왼쪽 포인트 찾기
    ///
    /// - Parameters:
    ///   - y: 검색할 Y좌표 (정규화)
    ///   - tolerance: Y좌표 허용 오차
    /// - Returns: 해당 높이에서 가장 왼쪽 포인트, 없으면 nil
    func findLeftmostPoint(at y: CGFloat, tolerance: CGFloat = 0.05) -> CGPoint? {
        let candidates = allPoints.filter { abs($0.y - y) <= tolerance }
        return candidates.min(by: { $0.x < $1.x })
    }

    /// 특정 Y좌표에서 가장 오른쪽 포인트 찾기
    ///
    /// - Parameters:
    ///   - y: 검색할 Y좌표 (정규화)
    ///   - tolerance: Y좌표 허용 오차
    /// - Returns: 해당 높이에서 가장 오른쪽 포인트, 없으면 nil
    func findRightmostPoint(at y: CGFloat, tolerance: CGFloat = 0.05) -> CGPoint? {
        let candidates = allPoints.filter { abs($0.y - y) <= tolerance }
        return candidates.max(by: { $0.x < $1.x })
    }

    /// 특정 X좌표 범위 내의 포인트들 필터링
    ///
    /// - Parameters:
    ///   - xRange: X좌표 범위
    /// - Returns: 해당 범위 내의 포인트들
    func pointsInXRange(_ xRange: ClosedRange<CGFloat>) -> [CGPoint] {
        return allPoints.filter { xRange.contains($0.x) }
    }

    /// 특정 Y좌표 범위 내의 포인트들 필터링
    ///
    /// - Parameters:
    ///   - yRange: Y좌표 범위
    /// - Returns: 해당 범위 내의 포인트들
    func pointsInYRange(_ yRange: ClosedRange<CGFloat>) -> [CGPoint] {
        return allPoints.filter { yRange.contains($0.y) }
    }

    /// 의류의 너비 (좌우 최대 거리)
    var width: CGFloat {
        return abs(rightmostPoint.x - leftmostPoint.x)
    }

    /// 의류의 높이 (상하 최대 거리)
    var height: CGFloat {
        return abs(topPoint.y - bottomPoint.y)
    }

    /// 의류의 종횡비 (높이/너비)
    var aspectRatio: CGFloat {
        guard width > 0 else { return 0 }
        return height / width
    }
}

// MARK: - CustomStringConvertible

extension ClothingFeaturePoints: CustomStringConvertible {
    var description: String {
        return """
        ClothingFeaturePoints(
          top: \(topPoint),
          bottom: \(bottomPoint),
          left: \(leftmostPoint),
          right: \(rightmostPoint),
          width: \(width),
          height: \(height),
          aspectRatio: \(aspectRatio)
        )
        """
    }
}

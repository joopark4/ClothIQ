//
//  ClothingFeaturePoints+BottomGeometry.swift
//  ClothIQ
//
//  Created on 2026-05-02
//
//  Description:
//  하의 전용 허리, 밑위, 밑단, 총길이 기준점을 계산합니다.
//

import CoreGraphics
import Foundation

extension ClothingFeaturePoints {
    /// 하의 허리선용 수평 span을 찾습니다.
    ///
    /// 반바지는 최상단 윤곽이 허리 전체가 아니라 중앙 돌출/접힘으로 잡히는 경우가 있어,
    /// 상단에서 조금 내려오며 처음으로 충분히 넓어지는 수평 band를 허리 후보로 사용합니다.
    func robustBottomWaistSpan() -> (left: CGPoint, right: CGPoint, confidence: Float)? {
        let garmentHeight = max(height, 0.0001)
        let garmentWidth = max(width, 0.0001)
        let upperRows = groupedRows(in: (topPoint.y - garmentHeight * 0.38)...topPoint.y)
            .compactMap(horizontalSpanRow)
            .sorted { $0.y > $1.y }

        if let maxUpperWidth = upperRows.map(\.width).max() {
            let edgeThreshold = max(garmentWidth * 0.32, maxUpperWidth * 0.72)
            if let upperEdge = upperRows.first(where: { $0.width >= edgeThreshold }) {
                let confidence = Float(min(0.92, max(0.62, upperEdge.width / garmentWidth)))
                return (upperEdge.left, upperEdge.right, confidence)
            }
        }

        let offsets: [CGFloat] = [0.08, 0.12, 0.16, 0.22, 0.28, 0.34]
        let halfSpans = [garmentHeight * 0.015, garmentHeight * 0.025, garmentHeight * 0.035]
        var candidates: [(left: CGPoint, right: CGPoint, width: CGFloat, y: CGFloat)] = []

        for offset in offsets {
            let centerY = topPoint.y - garmentHeight * offset
            guard let span = bestHorizontalSpan(
                centeredAt: centerY,
                halfSpans: halfSpans,
                selection: .widest
            ) else {
                continue
            }

            let spanWidth = span.right.x - span.left.x
            guard spanWidth > 0 else { continue }
            candidates.append((span.left, span.right, spanWidth, (span.left.y + span.right.y) * 0.5))
        }

        guard let maxWidth = candidates.map(\.width).max() else {
            return nil
        }

        let representativeThreshold = max(garmentWidth * 0.30, maxWidth * 0.66)
        if let topmostRepresentative = candidates
            .filter({ $0.width >= representativeThreshold })
            .max(by: { $0.y < $1.y }) {
            let confidence = Float(min(0.88, max(0.58, topmostRepresentative.width / garmentWidth)))
            return (topmostRepresentative.left, topmostRepresentative.right, confidence)
        }

        guard let widest = candidates.max(by: { $0.width < $1.width }),
              widest.width >= garmentWidth * 0.25 else {
            return nil
        }

        let confidence = Float(min(0.75, max(0.55, widest.width / garmentWidth)))
        return (widest.left, widest.right, confidence)
    }

    /// 하의 밑단 근처의 대표 수평 span을 찾습니다.
    func robustBottomHemSpan() -> (left: CGPoint, right: CGPoint, confidence: Float)? {
        let garmentHeight = max(height, 0.0001)
        let garmentWidth = max(width, 0.0001)
        let lower = bottomPoint.y
        let upper = min(topPoint.y, bottomPoint.y + garmentHeight * 0.24)
        let centerDeadZone = garmentWidth * 0.035
        let minLegWidth = garmentWidth * 0.08
        let maxLegWidth = garmentWidth * 0.58
        var candidates: [(left: CGPoint, right: CGPoint, width: CGFloat, y: CGFloat)] = []

        for row in groupedRows(in: lower...upper) {
            appendLegHemCandidate(from: row.filter { $0.x <= centerX - centerDeadZone }, to: &candidates)
            appendLegHemCandidate(from: row.filter { $0.x >= centerX + centerDeadZone }, to: &candidates)
        }

        if let best = candidates
            .filter({ $0.width >= minLegWidth && $0.width <= maxLegWidth })
            .max(by: { lhs, rhs in
                let lhsScore = lhs.width - abs(lhs.y - bottomPoint.y) * garmentWidth * 1.2
                let rhsScore = rhs.width - abs(rhs.y - bottomPoint.y) * garmentWidth * 1.2
                return lhsScore < rhsScore
            }) {
            let bottomCloseness = 1.0 - min(abs(best.y - bottomPoint.y) / (garmentHeight * 0.24), 1.0)
            let confidence = Float(min(0.86, max(0.56, best.width / maxLegWidth * 0.72 + bottomCloseness * 0.22)))
            return (best.left, best.right, confidence)
        }

        let centerY = bottomPoint.y + garmentHeight * 0.06
        let halfSpans = [garmentHeight * 0.025, garmentHeight * 0.05, garmentHeight * 0.08]
        guard let span = bestHorizontalSpan(
            centeredAt: centerY,
            halfSpans: halfSpans,
            selection: .widest
        ) else {
            return nil
        }

        let spanWidth = max(span.right.x - span.left.x, 0)
        guard spanWidth <= maxLegWidth else { return nil }

        let confidence = Float(min(0.85, max(0.50, spanWidth / garmentWidth)))
        return (span.left, span.right, confidence)
    }

    /// 하의 총길이용 대표 측정선을 찾습니다.
    func bestBottomTotalLengthLine() -> (start: CGPoint, end: CGPoint, confidence: Float)? {
        guard let waistSpan = robustBottomWaistSpan() else {
            return nil
        }

        let candidates = [
            bottomSideLine(from: waistSpan.left, side: .left, waistConfidence: waistSpan.confidence),
            bottomSideLine(from: waistSpan.right, side: .right, waistConfidence: waistSpan.confidence)
        ].compactMap { $0 }

        guard !candidates.isEmpty else {
            let waistCenter = CGPoint(
                x: (waistSpan.left.x + waistSpan.right.x) * 0.5,
                y: (waistSpan.left.y + waistSpan.right.y) * 0.5
            )
            return (waistCenter, bottomPoint, min(waistSpan.confidence, 0.55))
        }

        return candidates.max {
            bottomLengthScore(start: $0.start, end: $0.end) < bottomLengthScore(start: $1.start, end: $1.end)
        }
    }

    /// 하의 밑위용 대표 포인트를 찾습니다.
    func robustBottomCrotchPoint() -> (point: CGPoint, confidence: Float)? {
        let garmentHeight = max(height, 0.0001)
        let garmentWidth = max(width, 0.0001)
        let searchCenterX = centerX
        let waistCenterY: CGFloat
        if let waistSpan = robustBottomWaistSpan() {
            waistCenterY = (waistSpan.left.y + waistSpan.right.y) * 0.5
        } else {
            waistCenterY = topPoint.y
        }

        let upper = waistCenterY - garmentHeight * 0.18
        let lower = max(bottomPoint.y + garmentHeight * 0.14, waistCenterY - garmentHeight * 0.72)
        guard lower <= upper else { return nil }

        let centerGapThreshold = garmentWidth * 0.06
        let maxGapWidth = garmentWidth * 0.35
        let maxCenterOffset = garmentWidth * 0.14
        for row in groupedRows(in: lower...upper).sorted(by: { $0.first?.y ?? 0 > $1.first?.y ?? 0 }) {
            guard row.count >= 4 else { continue }
            let sorted = row.sorted { $0.x < $1.x }
            guard let leftInner = sorted.filter({ $0.x <= searchCenterX }).max(by: { $0.x < $1.x }),
                  let rightInner = sorted.filter({ $0.x >= searchCenterX }).min(by: { $0.x < $1.x }) else {
                continue
            }

            let gap = rightInner.x - leftInner.x
            let gapCenterX = (leftInner.x + rightInner.x) * 0.5
            guard gap >= centerGapThreshold,
                  gap <= maxGapWidth,
                  abs(gapCenterX - searchCenterX) <= maxCenterOffset,
                  leftInner.x < searchCenterX,
                  rightInner.x > searchCenterX else {
                continue
            }

            return (CGPoint(x: gapCenterX, y: (leftInner.y + rightInner.y) * 0.5), 0.78)
        }

        let centerRange = (searchCenterX - garmentWidth * 0.08)...(searchCenterX + garmentWidth * 0.08)
        let upperCentralLimit = waistCenterY - garmentHeight * 0.24
        let candidates = pointsInYRange(lower...upper).filter { centerRange.contains($0.x) }

        if let topmostCentralPoint = candidates
            .filter({ $0.y <= upperCentralLimit })
            .max(by: { $0.y < $1.y }) {
            return (CGPoint(x: searchCenterX, y: topmostCentralPoint.y), 0.62)
        }

        return (CGPoint(x: searchCenterX, y: waistCenterY - garmentHeight * 0.42), 0.52)
    }

    private enum BottomSide {
        case left
        case right
    }

    private func appendLegHemCandidate(
        from points: [CGPoint],
        to candidates: inout [(left: CGPoint, right: CGPoint, width: CGFloat, y: CGFloat)]
    ) {
        guard points.count >= 2,
              let left = points.min(by: { $0.x < $1.x }),
              let right = points.max(by: { $0.x < $1.x }) else {
            return
        }

        let width = right.x - left.x
        guard width > 0 else { return }
        candidates.append((left, right, width, (left.y + right.y) * 0.5))
    }

    private func horizontalSpanRow(_ row: [CGPoint]) -> (left: CGPoint, right: CGPoint, width: CGFloat, y: CGFloat)? {
        guard row.count >= 2,
              let left = row.min(by: { $0.x < $1.x }),
              let right = row.max(by: { $0.x < $1.x }) else {
            return nil
        }

        let width = right.x - left.x
        guard width > 0 else { return nil }
        return (left, right, width, (left.y + right.y) * 0.5)
    }

    private func groupedRows(in yRange: ClosedRange<CGFloat>) -> [[CGPoint]] {
        let filtered = pointsInYRange(yRange)
        guard !filtered.isEmpty else { return [] }

        let grouped = Dictionary(grouping: filtered) { point in
            Int((point.y * 1000).rounded())
        }

        return grouped.values
            .map { $0.sorted { $0.x < $1.x } }
            .sorted { ($0.first?.y ?? 0) < ($1.first?.y ?? 0) }
    }

    private func bottomSideLine(
        from waistPoint: CGPoint,
        side: BottomSide,
        waistConfidence: Float
    ) -> (start: CGPoint, end: CGPoint, confidence: Float)? {
        let garmentHeight = max(height, 0.0001)
        let lowerBand = bottomPoint.y...(bottomPoint.y + garmentHeight * 0.22)
        let sideCandidates = groupedRows(in: lowerBand).compactMap { row -> CGPoint? in
            let sidePoints = row.filter { point in
                switch side {
                case .left:
                    return point.x <= centerX
                case .right:
                    return point.x >= centerX
                }
            }

            switch side {
            case .left:
                return sidePoints.min(by: { $0.x < $1.x })
            case .right:
                return sidePoints.max(by: { $0.x < $1.x })
            }
        }

        guard let bottom = sideCandidates.min(by: {
            bottomSideScore($0, side: side) < bottomSideScore($1, side: side)
        }) else {
            return nil
        }

        let vertical = abs(waistPoint.y - bottom.y)
        let horizontal = abs(waistPoint.x - bottom.x)
        guard vertical > garmentHeight * 0.18 else { return nil }

        let verticality = vertical / max(vertical + horizontal, 0.0001)
        let confidence = min(0.88, max(0.55, waistConfidence * 0.7 + Float(verticality) * 0.25))
        return (waistPoint, bottom, confidence)
    }

    private func bottomSideScore(_ point: CGPoint, side: BottomSide) -> CGFloat {
        let bottomDistance = abs(point.y - bottomPoint.y)
        let outerness: CGFloat
        switch side {
        case .left:
            outerness = max(centerX - point.x, 0)
        case .right:
            outerness = max(point.x - centerX, 0)
        }
        return bottomDistance * 1.35 - outerness * 0.45
    }

    private func bottomLengthScore(start: CGPoint, end: CGPoint) -> CGFloat {
        let vertical = abs(start.y - end.y)
        let horizontal = abs(start.x - end.x)
        return vertical - horizontal * 0.25
    }
}

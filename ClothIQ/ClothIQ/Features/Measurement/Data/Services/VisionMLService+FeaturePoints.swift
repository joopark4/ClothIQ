//
//  VisionMLService+FeaturePoints.swift
//  ClothIQ
//
//  Created on 2026-05-04
//
//  Description:
//  Vision ML 하이브리드 감지에서 사전 프로파일 보정에 사용할 윤곽 특징점을 추출합니다.
//

import CoreGraphics
import Vision

extension VisionMLService {
    /// 특징점 추출 (간단한 버전)
    func extractFeaturePoints(
        from contour: VNContoursObservation,
        clothingType: ClothingType
    ) -> ClothingFeaturePoints {
        guard contour.contourCount > 0,
              let mainContour = try? contour.contour(at: 0) else {
            return ClothingFeaturePoints(
                topPoint: CGPoint(x: 0.5, y: 1.0),
                bottomPoint: CGPoint(x: 0.5, y: 0.0),
                leftmostPoint: CGPoint(x: 0.0, y: 0.5),
                rightmostPoint: CGPoint(x: 1.0, y: 0.5),
                allPoints: []
            )
        }

        let points = mainContour.normalizedPath.points()

        let topPoint = points.max(by: { $0.y < $1.y }) ?? CGPoint(x: 0.5, y: 1.0)
        let bottomPoint = points.min(by: { $0.y < $1.y }) ?? CGPoint(x: 0.5, y: 0.0)
        let leftmostPoint = points.min(by: { $0.x < $1.x }) ?? CGPoint(x: 0.0, y: 0.5)
        let rightmostPoint = points.max(by: { $0.x < $1.x }) ?? CGPoint(x: 1.0, y: 0.5)

        return ClothingFeaturePoints.withTemplate(
            topPoint: topPoint,
            bottomPoint: bottomPoint,
            leftmostPoint: leftmostPoint,
            rightmostPoint: rightmostPoint,
            allPoints: points,
            clothingType: clothingType
        )
    }
}

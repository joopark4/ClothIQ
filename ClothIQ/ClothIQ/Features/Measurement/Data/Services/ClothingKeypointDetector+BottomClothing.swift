//
//  ClothingKeypointDetector+BottomClothing.swift
//  ClothIQ
//
//  Created on 2025-11-10
//
//  Description:
//  하의(바텀) 의류 키포인트 감지 메서드 모음.
//  허리, 엉덩이, 밑위, 밑단 등 하의 관련 키포인트를 감지합니다.
//

import Foundation
import Vision
import CoreGraphics

extension ClothingKeypointDetector {

    // MARK: - Bottom Clothing Keypoints (하의)

    /// 하의 키포인트 감지
    func detectBottomKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints,
        isLongPants: Bool
    ) -> [MeasurementKeypoint] {

        var keypoints: [MeasurementKeypoint] = []

        let points: [CGPoint]
        if featurePoints.allPoints.isEmpty {
            guard let mainContour = selectMainContour(from: contour) else {
                return keypoints
            }
            points = mainContour.normalizedPath.points()
        } else {
            points = featurePoints.allPoints
        }

        // 1. 허리 위치 감지
        if let waistPoints = detectWaistPoints(points: points, featurePoints: featurePoints) {
            keypoints.append(contentsOf: waistPoints)
        }

        // 2. 엉덩이 위치 감지
        if let hipPoints = detectHipPoints(points: points, featurePoints: featurePoints) {
            keypoints.append(contentsOf: hipPoints)
        }

        // 3. 밑위 감지
        if let crotchPoint = detectCrotchPoint(points: points, featurePoints: featurePoints) {
            keypoints.append(crotchPoint)
        }

        // 4. 밑단 감지
        if let hemPoints = detectHemPoints(points: points, featurePoints: featurePoints) {
            keypoints.append(contentsOf: hemPoints)
        }

        return keypoints
    }

    /// 치마 키포인트 감지
    func detectSkirtKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementKeypoint] {

        var keypoints: [MeasurementKeypoint] = []

        let points: [CGPoint]
        if featurePoints.allPoints.isEmpty {
            guard let mainContour = selectMainContour(from: contour) else {
                return keypoints
            }
            points = mainContour.normalizedPath.points()
        } else {
            points = featurePoints.allPoints
        }

        // 1. 허리 위치 감지
        if let waistPoints = detectWaistPoints(points: points, featurePoints: featurePoints) {
            keypoints.append(contentsOf: waistPoints)
        }

        // 2. 엉덩이 위치 감지
        if let hipPoints = detectHipPoints(points: points, featurePoints: featurePoints) {
            keypoints.append(contentsOf: hipPoints)
        }

        // 3. 밑단 중앙
        keypoints.append(MeasurementKeypoint(
            type: .hemCenter,
            position: featurePoints.bottomPoint,
            confidence: 0.9
        ))

        return keypoints
    }

    /// 허리 위치 감지
    func detectWaistPoints(points: [CGPoint], featurePoints: ClothingFeaturePoints) -> [MeasurementKeypoint]? {
        if let waistSpan = featurePoints.robustBottomWaistSpan() {
            return [
                MeasurementKeypoint(type: .waistLeft, position: waistSpan.left, confidence: waistSpan.confidence),
                MeasurementKeypoint(type: .waistRight, position: waistSpan.right, confidence: waistSpan.confidence)
            ]
        }

        // 템플릿 기반 허리 Y좌표 사용
        let waistY = featurePoints.waistY

        let waistCandidates = points.filter { point in
            abs(point.y - waistY) < 0.05
        }

        guard waistCandidates.count >= 2 else { return nil }

        let leftWaist = waistCandidates.min(by: { $0.x < $1.x })!
        let rightWaist = waistCandidates.max(by: { $0.x < $1.x })!

        return [
            MeasurementKeypoint(type: .waistLeft, position: leftWaist, confidence: 0.8),
            MeasurementKeypoint(type: .waistRight, position: rightWaist, confidence: 0.8)
        ]
    }

    /// 엉덩이 위치 감지
    func detectHipPoints(points: [CGPoint], featurePoints: ClothingFeaturePoints) -> [MeasurementKeypoint]? {
        let height = max(featurePoints.height, 0.0001)
        let sourcePoints = featurePoints.allPoints.isEmpty ? points : featurePoints.allPoints
        let hipY = featurePoints.hipY
        let hipCandidates = sourcePoints.filter { point in
            abs(point.y - hipY) < height * 0.10
        }

        guard hipCandidates.count >= 2,
              let leftHip = hipCandidates.min(by: { $0.x < $1.x }),
              let rightHip = hipCandidates.max(by: { $0.x < $1.x }) else {
            return nil
        }

        return [
            MeasurementKeypoint(type: .hipLeft, position: leftHip, confidence: 0.8),
            MeasurementKeypoint(type: .hipRight, position: rightHip, confidence: 0.8)
        ]
    }

    /// 밑위 감지
    func detectCrotchPoint(points: [CGPoint], featurePoints: ClothingFeaturePoints) -> MeasurementKeypoint? {
        if let crotch = featurePoints.robustBottomCrotchPoint() {
            return MeasurementKeypoint(type: .crotch, position: crotch.point, confidence: crotch.confidence)
        }

        // V자 형태의 중앙 최하단 찾기
        let centerX = featurePoints.centerX
        let searchRange = 0.1  // 중앙에서 좌우 10% 범위

        let centerPoints = points.filter { point in
            abs(point.x - centerX) < searchRange &&
            point.y < featurePoints.topPoint.y - 0.3 &&  // 상단 30% 아래
            point.y > featurePoints.bottomPoint.y + 0.3  // 하단 30% 위
        }

        // 중앙 부근에서 가장 아래 점
        if let crotch = centerPoints.min(by: { $0.y < $1.y }) {
            return MeasurementKeypoint(type: .crotch, position: crotch, confidence: 0.75)
        }

        return nil
    }

    /// 밑단 감지
    func detectHemPoints(points: [CGPoint], featurePoints: ClothingFeaturePoints) -> [MeasurementKeypoint]? {
        if let hemSpan = featurePoints.robustBottomHemSpan() {
            let hemCenter = CGPoint(
                x: (hemSpan.left.x + hemSpan.right.x) * 0.5,
                y: (hemSpan.left.y + hemSpan.right.y) * 0.5
            )
            return [
                MeasurementKeypoint(type: .leftHem, position: hemSpan.left, confidence: hemSpan.confidence),
                MeasurementKeypoint(type: .rightHem, position: hemSpan.right, confidence: hemSpan.confidence),
                MeasurementKeypoint(type: .hemCenter, position: hemCenter, confidence: hemSpan.confidence)
            ]
        }

        let hemY = featurePoints.bottomPoint.y

        let hemCandidates = points.filter { point in
            abs(point.y - hemY) < 0.03
        }

        guard hemCandidates.count >= 2 else { return nil }

        let leftHem = hemCandidates.min(by: { $0.x < $1.x })!
        let rightHem = hemCandidates.max(by: { $0.x < $1.x })!

        return [
            MeasurementKeypoint(type: .leftHem, position: leftHem, confidence: 0.85),
            MeasurementKeypoint(type: .rightHem, position: rightHem, confidence: 0.85)
        ]
    }
}

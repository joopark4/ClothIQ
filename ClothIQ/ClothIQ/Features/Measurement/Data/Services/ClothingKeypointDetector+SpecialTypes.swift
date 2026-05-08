//
//  ClothingKeypointDetector+SpecialTypes.swift
//  ClothIQ
//
//  Created on 2025-11-10
//
//  Description:
//  특수 의류 타입별 키포인트 감지 메서드 모음.
//  셔츠, 아우터, 조끼, 가디건, 후드티, 원피스, 점프수트, 레깅스 등을 처리합니다.
//

import Foundation
import Vision
import CoreGraphics

extension ClothingKeypointDetector {

    // MARK: - Special Type Keypoints

    /// 셔츠 키포인트 감지
    func detectShirtKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementKeypoint] {
        var keypoints = detectTopKeypoints(contour: contour, featurePoints: featurePoints, hasLongSleeves: true)

        // 셔츠 특유의 칼라/목둘레 포인트 추가
        let neckPoint = MeasurementKeypoint(
            type: .neckline,
            position: CGPoint(x: featurePoints.topPoint.x, y: featurePoints.topPoint.y + 0.02),
            confidence: 0.85
        )
        keypoints.append(neckPoint)

        return keypoints
    }

    /// 아우터(재킷/코트) 키포인트 감지
    func detectOuterwearKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints,
        isLong: Bool
    ) -> [MeasurementKeypoint] {
        var keypoints = detectTopKeypoints(contour: contour, featurePoints: featurePoints, hasLongSleeves: true)

        // 아우터는 일반적으로 더 넓은 어깨와 가슴 폭을 가짐
        // 기존 키포인트를 약간 조정
        keypoints = keypoints.map { keypoint in
            switch keypoint.type {
            case .leftShoulder:
                return MeasurementKeypoint(
                    type: keypoint.type,
                    position: CGPoint(x: keypoint.position.x - 0.02, y: keypoint.position.y),
                    confidence: keypoint.confidence
                )
            case .rightShoulder:
                return MeasurementKeypoint(
                    type: keypoint.type,
                    position: CGPoint(x: keypoint.position.x + 0.02, y: keypoint.position.y),
                    confidence: keypoint.confidence
                )
            default:
                return keypoint
            }
        }

        return keypoints
    }

    /// 조끼 키포인트 감지
    func detectVestKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementKeypoint] {
        var keypoints: [MeasurementKeypoint] = []

        // 조끼는 소매가 없으므로 어깨와 암홀만 감지
        guard let mainContour = selectMainContour(from: contour) else {
            return keypoints
        }

        let points = mainContour.normalizedPath.points()

        // 어깨 끝점
        if let shoulders = detectShoulderPoints(points: points, topPoint: featurePoints.topPoint) {
            keypoints.append(contentsOf: shoulders)
        }

        // 암홀 (겨드랑이) 포인트
        if let armpits = detectArmpitPoints(points: points, shoulders: keypoints) {
            keypoints.append(contentsOf: armpits)
        }

        // 가슴둘레
        if let chestPoints = detectChestPoints(points: points, armpits: keypoints) {
            keypoints.append(contentsOf: chestPoints)
        }

        // 밑단
        keypoints.append(MeasurementKeypoint(
            type: .hemCenter,
            position: featurePoints.bottomPoint,
            confidence: 0.9
        ))

        return keypoints
    }

    /// 가디건 키포인트 감지
    func detectCardiganKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementKeypoint] {
        // 가디건은 일반 긴팔과 유사하지만 앞이 열려있음
        var keypoints = detectTopKeypoints(contour: contour, featurePoints: featurePoints, hasLongSleeves: true)

        // 가디건의 경우 앞 중심선이 열려있을 수 있으므로 신뢰도를 약간 낮춤
        keypoints = keypoints.map { keypoint in
            MeasurementKeypoint(
                type: keypoint.type,
                position: keypoint.position,
                confidence: keypoint.confidence * 0.95
            )
        }

        return keypoints
    }

    /// 후드티 키포인트 감지
    func detectHoodieKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementKeypoint] {
        var keypoints = detectTopKeypoints(contour: contour, featurePoints: featurePoints, hasLongSleeves: true)

        // 후드 때문에 목선이 더 높을 수 있음
        if let neckIndex = keypoints.firstIndex(where: { $0.type == .neckline }) {
            keypoints[neckIndex] = MeasurementKeypoint(
                type: .neckline,
                position: CGPoint(x: featurePoints.topPoint.x, y: featurePoints.topPoint.y + 0.03),
                confidence: 0.8
            )
        }

        return keypoints
    }

    /// 원피스 키포인트 감지
    func detectDressKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementKeypoint] {
        var keypoints: [MeasurementKeypoint] = []

        guard let mainContour = selectMainContour(from: contour) else {
            return keypoints
        }

        let points = mainContour.normalizedPath.points()

        // 상의 부분 키포인트
        if let shoulders = detectShoulderPoints(points: points, topPoint: featurePoints.topPoint) {
            keypoints.append(contentsOf: shoulders)
        }

        if let chestPoints = detectChestPoints(points: points, armpits: []) {
            keypoints.append(contentsOf: chestPoints)
        }

        // 허리 부분 (원피스의 중간)
        let waistY = featurePoints.topPoint.y + (featurePoints.bottomPoint.y - featurePoints.topPoint.y) * 0.4
        keypoints.append(MeasurementKeypoint(
            type: .waistLeft,
            position: CGPoint(x: featurePoints.leftmostPoint.x, y: waistY),
            confidence: 0.75
        ))
        keypoints.append(MeasurementKeypoint(
            type: .waistRight,
            position: CGPoint(x: featurePoints.rightmostPoint.x, y: waistY),
            confidence: 0.75
        ))

        // 엉덩이 부분
        let hipY = featurePoints.topPoint.y + (featurePoints.bottomPoint.y - featurePoints.topPoint.y) * 0.55
        keypoints.append(MeasurementKeypoint(
            type: .hipLeft,
            position: CGPoint(x: featurePoints.leftmostPoint.x, y: hipY),
            confidence: 0.75
        ))
        keypoints.append(MeasurementKeypoint(
            type: .hipRight,
            position: CGPoint(x: featurePoints.rightmostPoint.x, y: hipY),
            confidence: 0.75
        ))

        // 밑단
        keypoints.append(MeasurementKeypoint(
            type: .hemCenter,
            position: featurePoints.bottomPoint,
            confidence: 0.9
        ))

        return keypoints
    }

    /// 점프수트 키포인트 감지
    func detectJumpsuitKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementKeypoint] {
        var keypoints: [MeasurementKeypoint] = []

        // 상의 부분은 원피스와 유사
        let dressKeypoints = detectDressKeypoints(contour: contour, featurePoints: featurePoints)
        keypoints.append(contentsOf: dressKeypoints)

        // 밑위 추가 (점프수트 특유)
        let crotchY = featurePoints.topPoint.y + (featurePoints.bottomPoint.y - featurePoints.topPoint.y) * 0.6
        keypoints.append(MeasurementKeypoint(
            type: .crotch,
            position: CGPoint(x: (featurePoints.leftmostPoint.x + featurePoints.rightmostPoint.x) / 2, y: crotchY),
            confidence: 0.7
        ))

        // 다리 부분 밑단
        keypoints.append(MeasurementKeypoint(
            type: .leftHem,
            position: CGPoint(x: featurePoints.leftmostPoint.x + 0.1, y: featurePoints.bottomPoint.y),
            confidence: 0.75
        ))
        keypoints.append(MeasurementKeypoint(
            type: .rightHem,
            position: CGPoint(x: featurePoints.rightmostPoint.x - 0.1, y: featurePoints.bottomPoint.y),
            confidence: 0.75
        ))

        return keypoints
    }

    /// 레깅스 키포인트 감지
    func detectLeggingsKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementKeypoint] {
        var keypoints = detectBottomKeypoints(contour: contour, featurePoints: featurePoints, isLongPants: true)

        // 레깅스는 일반적으로 높은 허리를 가짐
        if let waistLeftIndex = keypoints.firstIndex(where: { $0.type == .waistLeft }) {
            keypoints[waistLeftIndex] = MeasurementKeypoint(
                type: .waistLeft,
                position: CGPoint(
                    x: keypoints[waistLeftIndex].position.x,
                    y: featurePoints.topPoint.y + 0.05
                ),
                confidence: 0.85
            )
        }

        if let waistRightIndex = keypoints.firstIndex(where: { $0.type == .waistRight }) {
            keypoints[waistRightIndex] = MeasurementKeypoint(
                type: .waistRight,
                position: CGPoint(
                    x: keypoints[waistRightIndex].position.x,
                    y: featurePoints.topPoint.y + 0.05
                ),
                confidence: 0.85
            )
        }

        return keypoints
    }
}

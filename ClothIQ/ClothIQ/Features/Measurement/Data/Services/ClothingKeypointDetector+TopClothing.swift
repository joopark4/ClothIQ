//
//  ClothingKeypointDetector+TopClothing.swift
//  ClothIQ
//
//  Created on 2025-11-10
//
//  Description:
//  상의(탑) 의류 키포인트 감지 메서드 모음.
//  어깨, 겨드랑이, 가슴둘레, 소매 끝점 등 상의 관련 키포인트를 감지합니다.
//

import Foundation
import Vision
import CoreGraphics

extension ClothingKeypointDetector {

    // MARK: - Top Clothing Keypoints (상의)

    /// 상의 키포인트 감지
    func detectTopKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints,
        hasLongSleeves: Bool
    ) -> [MeasurementKeypoint] {

        var keypoints: [MeasurementKeypoint] = []

        // 메인 윤곽선 선택
        guard let mainContour = selectMainContour(from: contour) else {
            print("⚠️ [KeypointDetector] 메인 윤곽선 감지 실패")
            return keypoints
        }

        let points = mainContour.normalizedPath.points()
        guard points.count >= 8 else {
            print("⚠️ [KeypointDetector] 윤곽선 포인트 부족: \(points.count)개")
            return keypoints
        }

        // 1. 어깨 끝점 감지
        if let shoulders = detectShoulderPoints(points: points, topPoint: featurePoints.topPoint) {
            keypoints.append(contentsOf: shoulders)
        }

        // 2. 겨드랑이 위치 감지
        if let armpits = detectArmpitPoints(points: points, shoulders: keypoints) {
            keypoints.append(contentsOf: armpits)
        }

        // 3. 가슴둘레 위치 감지
        if let chestPoints = detectChestPoints(points: points, armpits: keypoints) {
            keypoints.append(contentsOf: chestPoints)
        }

        // 4. 소매 끝점 감지 (긴팔인 경우)
        if hasLongSleeves {
            if let sleeveEnds = detectSleeveEndPoints(points: points, shoulders: keypoints) {
                keypoints.append(contentsOf: sleeveEnds)
            }
        }

        // 5. 목선 중앙
        keypoints.append(MeasurementKeypoint(
            type: .neckline,
            position: featurePoints.topPoint,
            confidence: 0.9
        ))

        // 6. 밑단 중앙
        keypoints.append(MeasurementKeypoint(
            type: .hemCenter,
            position: featurePoints.bottomPoint,
            confidence: 0.9
        ))

        return keypoints
    }

    /// 어깨 끝점 감지
    func detectShoulderPoints(points: [CGPoint], topPoint: CGPoint) -> [MeasurementKeypoint]? {
        print("🔍 [ShoulderDetection] 어깨 끝점 감지 시작")

        // 상단 15-25% 영역에서 어깨 찾기
        let topY = topPoint.y
        let searchRangeStart = topY - 0.15  // 상단에서 15% 아래
        let searchRangeEnd = topY - 0.25    // 상단에서 25% 아래

        // 해당 Y 범위의 포인트 필터링
        let shoulderCandidates = points.filter { point in
            point.y <= searchRangeStart && point.y >= searchRangeEnd
        }

        guard shoulderCandidates.count >= 2 else {
            print("⚠️ [ShoulderDetection] 후보 포인트 부족")
            return nil
        }

        // 좌우 극값 찾기
        let leftShoulder = shoulderCandidates.min(by: { $0.x < $1.x })!
        let rightShoulder = shoulderCandidates.max(by: { $0.x < $1.x })!

        // 변곡점 분석으로 정확한 위치 보정
        if let refinedLeft = findInflectionPoint(near: leftShoulder, in: points, direction: .left),
           let refinedRight = findInflectionPoint(near: rightShoulder, in: points, direction: .right) {

            print("✅ [ShoulderDetection] 어깨 감지 성공")
            print("  - 왼쪽: (\(String(format: "%.3f", refinedLeft.x)), \(String(format: "%.3f", refinedLeft.y)))")
            print("  - 오른쪽: (\(String(format: "%.3f", refinedRight.x)), \(String(format: "%.3f", refinedRight.y)))")

            return [
                MeasurementKeypoint(type: .leftShoulder, position: refinedLeft, confidence: 0.85),
                MeasurementKeypoint(type: .rightShoulder, position: refinedRight, confidence: 0.85)
            ]
        }

        // 변곡점 찾기 실패 시 기본값 사용
        return [
            MeasurementKeypoint(type: .leftShoulder, position: leftShoulder, confidence: 0.7),
            MeasurementKeypoint(type: .rightShoulder, position: rightShoulder, confidence: 0.7)
        ]
    }

    /// 겨드랑이 위치 감지
    func detectArmpitPoints(points: [CGPoint], shoulders: [MeasurementKeypoint]) -> [MeasurementKeypoint]? {
        print("🔍 [ArmpitDetection] 겨드랑이 위치 감지 시작")

        // 어깨 포인트 추출
        let shoulderKeypoints = shoulders.filter { $0.type == .leftShoulder || $0.type == .rightShoulder }
        guard shoulderKeypoints.count == 2 else {
            print("⚠️ [ArmpitDetection] 어깨 포인트 필요")
            return nil
        }

        let leftShoulder = shoulderKeypoints.first(where: { $0.type == .leftShoulder })!
        let rightShoulder = shoulderKeypoints.first(where: { $0.type == .rightShoulder })!

        // 어깨 아래 10-20% 영역에서 안쪽으로 들어간 부분 찾기
        let searchY = leftShoulder.position.y - 0.15  // 어깨에서 15% 아래

        let armpitCandidates = points.filter { point in
            abs(point.y - searchY) < 0.05  // Y 허용 범위
        }

        guard armpitCandidates.count >= 2 else {
            print("⚠️ [ArmpitDetection] 후보 포인트 부족")
            return nil
        }

        // 어깨보다 안쪽에 있는 점 찾기
        let leftArmpit = armpitCandidates
            .filter { $0.x > leftShoulder.position.x && $0.x < 0.4 }  // 왼쪽 어깨보다 오른쪽, 중앙보다 왼쪽
            .min(by: { $0.x < $1.x })  // 가장 왼쪽

        let rightArmpit = armpitCandidates
            .filter { $0.x < rightShoulder.position.x && $0.x > 0.6 }  // 오른쪽 어깨보다 왼쪽, 중앙보다 오른쪽
            .max(by: { $0.x < $1.x })  // 가장 오른쪽

        var result: [MeasurementKeypoint] = []

        if let left = leftArmpit {
            result.append(MeasurementKeypoint(type: .leftArmpit, position: left, confidence: 0.75))
            print("  - 왼쪽 겨드랑이: (\(String(format: "%.3f", left.x)), \(String(format: "%.3f", left.y)))")
        }

        if let right = rightArmpit {
            result.append(MeasurementKeypoint(type: .rightArmpit, position: right, confidence: 0.75))
            print("  - 오른쪽 겨드랑이: (\(String(format: "%.3f", right.x)), \(String(format: "%.3f", right.y)))")
        }

        return result.isEmpty ? nil : result
    }

    /// 가슴둘레 위치 감지
    func detectChestPoints(points: [CGPoint], armpits: [MeasurementKeypoint]) -> [MeasurementKeypoint]? {
        print("🔍 [ChestDetection] 가슴둘레 위치 감지 시작")

        // 겨드랑이 위치 기준으로 가슴둘레 위치 추정
        let armpitKeypoints = armpits.filter { $0.type == .leftArmpit || $0.type == .rightArmpit }

        let chestY: CGFloat
        if !armpitKeypoints.isEmpty {
            // 겨드랑이 아래 5% 지점
            let avgArmpitY = armpitKeypoints.map { $0.position.y }.reduce(0, +) / CGFloat(armpitKeypoints.count)
            chestY = avgArmpitY - 0.05
        } else {
            // 겨드랑이 없으면 상단에서 30% 지점 사용
            chestY = 0.7
        }

        // 해당 Y 위치에서 가장 넓은 부분 찾기
        let chestCandidates = points.filter { point in
            abs(point.y - chestY) < 0.03  // Y 허용 범위
        }

        guard chestCandidates.count >= 2 else {
            print("⚠️ [ChestDetection] 후보 포인트 부족")
            return nil
        }

        let leftChest = chestCandidates.min(by: { $0.x < $1.x })!
        let rightChest = chestCandidates.max(by: { $0.x < $1.x })!

        print("✅ [ChestDetection] 가슴둘레 감지 성공")
        print("  - 왼쪽: (\(String(format: "%.3f", leftChest.x)), \(String(format: "%.3f", leftChest.y)))")
        print("  - 오른쪽: (\(String(format: "%.3f", rightChest.x)), \(String(format: "%.3f", rightChest.y)))")

        return [
            MeasurementKeypoint(type: .chestLeft, position: leftChest, confidence: 0.8),
            MeasurementKeypoint(type: .chestRight, position: rightChest, confidence: 0.8)
        ]
    }

    /// 소매 끝점 감지
    func detectSleeveEndPoints(points: [CGPoint], shoulders: [MeasurementKeypoint]) -> [MeasurementKeypoint]? {
        print("🔍 [SleeveEndDetection] 소매 끝점 감지 시작")

        // 어깨 위치 추출
        let shoulderKeypoints = shoulders.filter { $0.type == .leftShoulder || $0.type == .rightShoulder }
        guard shoulderKeypoints.count == 2 else {
            return nil
        }

        let leftShoulder = shoulderKeypoints.first(where: { $0.type == .leftShoulder })!
        let rightShoulder = shoulderKeypoints.first(where: { $0.type == .rightShoulder })!

        // 좌측 소매: 왼쪽 어깨보다 왼쪽에 있는 점들 중 최하단
        let leftSleevePoints = points.filter { point in
            point.x < leftShoulder.position.x - 0.05  // 어깨보다 확실히 왼쪽
        }

        // 우측 소매: 오른쪽 어깨보다 오른쪽에 있는 점들 중 최하단
        let rightSleevePoints = points.filter { point in
            point.x > rightShoulder.position.x + 0.05  // 어깨보다 확실히 오른쪽
        }

        var result: [MeasurementKeypoint] = []

        if let leftEnd = leftSleevePoints.min(by: { $0.y < $1.y }) {  // 최하단
            result.append(MeasurementKeypoint(type: .leftSleeveEnd, position: leftEnd, confidence: 0.7))
            print("  - 왼쪽 소매 끝: (\(String(format: "%.3f", leftEnd.x)), \(String(format: "%.3f", leftEnd.y)))")
        }

        if let rightEnd = rightSleevePoints.min(by: { $0.y < $1.y }) {  // 최하단
            result.append(MeasurementKeypoint(type: .rightSleeveEnd, position: rightEnd, confidence: 0.7))
            print("  - 오른쪽 소매 끝: (\(String(format: "%.3f", rightEnd.x)), \(String(format: "%.3f", rightEnd.y)))")
        }

        return result.isEmpty ? nil : result
    }
}

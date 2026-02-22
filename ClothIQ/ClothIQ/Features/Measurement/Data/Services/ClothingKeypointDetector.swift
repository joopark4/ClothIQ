//
//  ClothingKeypointDetector.swift
//  ClothIQ
//
//  Created on 2025-11-10
//
//  Description:
//  의류 이미지에서 측정 키포인트를 자동으로 감지하는 서비스입니다.
//  Vision Framework와 고급 알고리즘을 활용하여 정확한 측정 위치를 찾습니다.
//
//  Key Features:
//  - 어깨 끝점 감지 (상단 양쪽 변곡점)
//  - 가슴둘레 위치 감지 (겨드랑이 아래 최대 너비)
//  - 소매 끝점 감지 (팔 부분 끝점)
//  - 측정 포인트 시각화를 위한 좌표 제공
//

import Foundation
import Vision
import CoreGraphics
import UIKit

/// 측정 키포인트
struct MeasurementKeypoint {
    /// 키포인트 타입
    let type: KeypointType

    /// 정규화된 위치 (0.0 ~ 1.0)
    let position: CGPoint

    /// 감지 신뢰도 (0.0 ~ 1.0)
    let confidence: Float

    /// 키포인트 설명
    var description: String {
        return "\(type.displayName): (\(String(format: "%.3f", position.x)), \(String(format: "%.3f", position.y))) [신뢰도: \(String(format: "%.1f%%", confidence * 100))]"
    }
}

/// 키포인트 타입
enum KeypointType {
    // 상의 키포인트
    case leftShoulder       // 왼쪽 어깨 끝점
    case rightShoulder      // 오른쪽 어깨 끝점
    case leftArmpit        // 왼쪽 겨드랑이
    case rightArmpit       // 오른쪽 겨드랑이
    case leftSleeveEnd     // 왼쪽 소매 끝
    case rightSleeveEnd    // 오른쪽 소매 끝
    case neckline          // 목선 중앙
    case hemCenter         // 밑단 중앙
    case chestLeft         // 가슴 왼쪽 끝
    case chestRight        // 가슴 오른쪽 끝

    // 하의 키포인트
    case waistLeft         // 허리 왼쪽
    case waistRight        // 허리 오른쪽
    case hipLeft           // 엉덩이 왼쪽
    case hipRight          // 엉덩이 오른쪽
    case crotch            // 밑위
    case leftHem           // 왼쪽 밑단
    case rightHem          // 오른쪽 밑단

    var displayName: String {
        switch self {
        case .leftShoulder: return "왼쪽 어깨"
        case .rightShoulder: return "오른쪽 어깨"
        case .leftArmpit: return "왼쪽 겨드랑이"
        case .rightArmpit: return "오른쪽 겨드랑이"
        case .leftSleeveEnd: return "왼쪽 소매 끝"
        case .rightSleeveEnd: return "오른쪽 소매 끝"
        case .neckline: return "목선"
        case .hemCenter: return "밑단 중앙"
        case .chestLeft: return "가슴 왼쪽"
        case .chestRight: return "가슴 오른쪽"
        case .waistLeft: return "허리 왼쪽"
        case .waistRight: return "허리 오른쪽"
        case .hipLeft: return "엉덩이 왼쪽"
        case .hipRight: return "엉덩이 오른쪽"
        case .crotch: return "밑위"
        case .leftHem: return "왼쪽 밑단"
        case .rightHem: return "오른쪽 밑단"
        }
    }
}

/// 의류 키포인트 감지기
final class ClothingKeypointDetector {

    // MARK: - Properties

    /// 각도 변화 임계값 (변곡점 감지용)
    private let angleThreshold: CGFloat = 30.0  // 30도 이상 변화를 변곡점으로 판단

    /// 최소 신뢰도 임계값
    private let minConfidence: Float = 0.6

    // MARK: - Public Methods

    /// 의류 타입에 따른 키포인트 감지
    ///
    /// - Parameters:
    ///   - contour: Vision Framework의 윤곽선
    ///   - clothingType: 의류 타입
    ///   - featurePoints: 기본 특징점 (극값)
    /// - Returns: 감지된 키포인트 배열
    func detectKeypoints(
        from contour: VNContoursObservation,
        clothingType: ClothingType,
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementKeypoint] {

        print("🔍 [KeypointDetector] 키포인트 감지 시작 - \(clothingType.displayName)")

        var keypoints: [MeasurementKeypoint] = []

        // 의류 타입별 키포인트 감지
        switch clothingType {
        // 기본 상의
        case .shortSleeve, .longSleeve:
            keypoints.append(contentsOf: detectTopKeypoints(contour: contour, featurePoints: featurePoints, hasLongSleeves: clothingType == .longSleeve))

        // 셔츠류
        case .shirt:
            keypoints.append(contentsOf: detectShirtKeypoints(contour: contour, featurePoints: featurePoints))
        case .polo:
            keypoints.append(contentsOf: detectTopKeypoints(contour: contour, featurePoints: featurePoints, hasLongSleeves: false))

        // 아우터
        case .jacket, .coat:
            keypoints.append(contentsOf: detectOuterwearKeypoints(contour: contour, featurePoints: featurePoints, isLong: clothingType == .coat))
        case .vest:
            keypoints.append(contentsOf: detectVestKeypoints(contour: contour, featurePoints: featurePoints))
        case .cardigan:
            keypoints.append(contentsOf: detectCardiganKeypoints(contour: contour, featurePoints: featurePoints))
        case .hoodie:
            keypoints.append(contentsOf: detectHoodieKeypoints(contour: contour, featurePoints: featurePoints))

        // 원피스류
        case .dress:
            keypoints.append(contentsOf: detectDressKeypoints(contour: contour, featurePoints: featurePoints))
        case .jumpsuit:
            keypoints.append(contentsOf: detectJumpsuitKeypoints(contour: contour, featurePoints: featurePoints))

        // 하의
        case .shorts, .pants:
            keypoints.append(contentsOf: detectBottomKeypoints(contour: contour, featurePoints: featurePoints, isLongPants: clothingType == .pants))
        case .jeans:
            keypoints.append(contentsOf: detectBottomKeypoints(contour: contour, featurePoints: featurePoints, isLongPants: true))
        case .leggings:
            keypoints.append(contentsOf: detectLeggingsKeypoints(contour: contour, featurePoints: featurePoints))
        case .skirt:
            keypoints.append(contentsOf: detectSkirtKeypoints(contour: contour, featurePoints: featurePoints))
        }

        print("✅ [KeypointDetector] 키포인트 감지 완료: \(keypoints.count)개")
        for keypoint in keypoints {
            print("  - \(keypoint.description)")
        }

        return keypoints
    }

    // MARK: - Private Methods - 상의 키포인트

    /// 상의 키포인트 감지
    private func detectTopKeypoints(
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
    private func detectShoulderPoints(points: [CGPoint], topPoint: CGPoint) -> [MeasurementKeypoint]? {
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
    private func detectArmpitPoints(points: [CGPoint], shoulders: [MeasurementKeypoint]) -> [MeasurementKeypoint]? {
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
    private func detectChestPoints(points: [CGPoint], armpits: [MeasurementKeypoint]) -> [MeasurementKeypoint]? {
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
    private func detectSleeveEndPoints(points: [CGPoint], shoulders: [MeasurementKeypoint]) -> [MeasurementKeypoint]? {
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

    // MARK: - Private Methods - 하의 키포인트

    /// 하의 키포인트 감지
    private func detectBottomKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints,
        isLongPants: Bool
    ) -> [MeasurementKeypoint] {

        var keypoints: [MeasurementKeypoint] = []

        guard let mainContour = selectMainContour(from: contour) else {
            return keypoints
        }

        let points = mainContour.normalizedPath.points()

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
    private func detectSkirtKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints
    ) -> [MeasurementKeypoint] {

        var keypoints: [MeasurementKeypoint] = []

        guard let mainContour = selectMainContour(from: contour) else {
            return keypoints
        }

        let points = mainContour.normalizedPath.points()

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
    private func detectWaistPoints(points: [CGPoint], featurePoints: ClothingFeaturePoints) -> [MeasurementKeypoint]? {
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
    private func detectHipPoints(points: [CGPoint], featurePoints: ClothingFeaturePoints) -> [MeasurementKeypoint]? {
        // 템플릿 기반 엉덩이 Y좌표 사용
        let hipY = featurePoints.hipY

        let hipCandidates = points.filter { point in
            abs(point.y - hipY) < 0.07
        }

        guard hipCandidates.count >= 2 else { return nil }

        let leftHip = hipCandidates.min(by: { $0.x < $1.x })!
        let rightHip = hipCandidates.max(by: { $0.x < $1.x })!

        return [
            MeasurementKeypoint(type: .hipLeft, position: leftHip, confidence: 0.8),
            MeasurementKeypoint(type: .hipRight, position: rightHip, confidence: 0.8)
        ]
    }

    /// 밑위 감지
    private func detectCrotchPoint(points: [CGPoint], featurePoints: ClothingFeaturePoints) -> MeasurementKeypoint? {
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
    private func detectHemPoints(points: [CGPoint], featurePoints: ClothingFeaturePoints) -> [MeasurementKeypoint]? {
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

    // MARK: - Helper Methods

    /// 메인 윤곽선 선택
    private func selectMainContour(from observation: VNContoursObservation) -> VNContour? {
        var bestContour: VNContour?
        var bestArea: CGFloat = 0

        for i in 0..<observation.contourCount {
            guard let contour = try? observation.contour(at: i) else { continue }

            let points = contour.normalizedPath.points()
            guard points.count >= 8 else { continue }

            let box = calculateBoundingBox(from: points)
            let area = box.width * box.height

            if area > 0.02 && area > bestArea {
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

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 변곡점 찾기
    private func findInflectionPoint(near point: CGPoint, in points: [CGPoint], direction: Direction) -> CGPoint? {
        // 주변 포인트들에서 각도 변화를 분석하여 변곡점 찾기
        let searchRadius: CGFloat = 0.05

        let nearbyPoints = points.filter { p in
            let distance = sqrt(pow(p.x - point.x, 2) + pow(p.y - point.y, 2))
            return distance < searchRadius
        }.sorted { p1, p2 in
            // Y축 기준 정렬
            p1.y > p2.y
        }

        guard nearbyPoints.count >= 3 else { return nil }

        // 각도 변화 계산
        var maxAngleChange: CGFloat = 0
        var inflectionPoint: CGPoint?

        for i in 1..<(nearbyPoints.count - 1) {
            let p1 = nearbyPoints[i - 1]
            let p2 = nearbyPoints[i]
            let p3 = nearbyPoints[i + 1]

            let angle1 = atan2(p2.y - p1.y, p2.x - p1.x)
            let angle2 = atan2(p3.y - p2.y, p3.x - p2.x)

            let angleChange = abs(angle2 - angle1) * 180 / .pi

            if angleChange > maxAngleChange && angleChange > angleThreshold {
                maxAngleChange = angleChange
                inflectionPoint = p2
            }
        }

        return inflectionPoint ?? point
    }

    enum Direction {
        case left, right
    }

    // MARK: - Private Methods - 새로운 의류 타입 키포인트

    /// 셔츠 키포인트 감지
    private func detectShirtKeypoints(
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
    private func detectOuterwearKeypoints(
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
    private func detectVestKeypoints(
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
    private func detectCardiganKeypoints(
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
    private func detectHoodieKeypoints(
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
    private func detectDressKeypoints(
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
    private func detectJumpsuitKeypoints(
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
    private func detectLeggingsKeypoints(
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

// MARK: - Measurement Line Generation

extension ClothingKeypointDetector {

    /// 키포인트로부터 측정 라인 생성
    ///
    /// - Parameters:
    ///   - keypoints: 감지된 키포인트들
    ///   - clothingType: 의류 타입
    /// - Returns: 측정 타입과 시작/끝 포인트 매핑
    func generateMeasurementLines(
        from keypoints: [MeasurementKeypoint],
        clothingType: ClothingType
    ) -> [(type: MeasurementType, start: CGPoint, end: CGPoint)] {

        var lines: [(type: MeasurementType, start: CGPoint, end: CGPoint)] = []

        switch clothingType {
        // 기본 상의
        case .shortSleeve, .longSleeve, .shirt, .polo, .hoodie:
            // 어깨너비
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder }) {
                lines.append((.shoulderWidth, leftShoulder.position, rightShoulder.position))
            }

            // 가슴둘레
            if let leftChest = keypoints.first(where: { $0.type == .chestLeft }),
               let rightChest = keypoints.first(where: { $0.type == .chestRight }) {
                lines.append((.chestCircumference, leftChest.position, rightChest.position))
            }

            // 소매길이 (긴팔인 경우)
            if clothingType == .longSleeve || clothingType == .shirt || clothingType == .hoodie {
                if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
                   let leftSleeve = keypoints.first(where: { $0.type == .leftSleeveEnd }) {
                    lines.append((.sleeveLength, leftShoulder.position, leftSleeve.position))
                }
            }

            // 총길이
            if let neckline = keypoints.first(where: { $0.type == .neckline }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, neckline.position, hem.position))
            }

            // 목둘레 (셔츠의 경우)
            if clothingType == .shirt {
                if let neckline = keypoints.first(where: { $0.type == .neckline }) {
                    // 목둘레는 단일 포인트로 표시 (실제로는 둘레)
                    lines.append((.neckCircumference, neckline.position, neckline.position))
                }
            }

        // 아우터
        case .jacket, .coat, .cardigan:
            // 어깨너비
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder }) {
                lines.append((.shoulderWidth, leftShoulder.position, rightShoulder.position))
            }

            // 가슴둘레
            if let leftChest = keypoints.first(where: { $0.type == .chestLeft }),
               let rightChest = keypoints.first(where: { $0.type == .chestRight }) {
                lines.append((.chestCircumference, leftChest.position, rightChest.position))
            }

            // 소매길이
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let leftSleeve = keypoints.first(where: { $0.type == .leftSleeveEnd }) {
                lines.append((.sleeveLength, leftShoulder.position, leftSleeve.position))
            }

            // 총길이
            if let neckline = keypoints.first(where: { $0.type == .neckline }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, neckline.position, hem.position))
            }

            // 소매단둘레 (재킷의 경우)
            if clothingType == .jacket {
                if let leftSleeve = keypoints.first(where: { $0.type == .leftSleeveEnd }) {
                    lines.append((.cuffCircumference, leftSleeve.position, leftSleeve.position))
                }
            }

        // 조끼
        case .vest:
            // 어깨너비
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder }) {
                lines.append((.shoulderWidth, leftShoulder.position, rightShoulder.position))
            }

            // 가슴둘레
            if let leftChest = keypoints.first(where: { $0.type == .chestLeft }),
               let rightChest = keypoints.first(where: { $0.type == .chestRight }) {
                lines.append((.chestCircumference, leftChest.position, rightChest.position))
            }

            // 총길이
            if let neckline = keypoints.first(where: { $0.type == .neckline }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, neckline.position, hem.position))
            }

        // 원피스
        case .dress:
            // 어깨너비
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder }) {
                lines.append((.shoulderWidth, leftShoulder.position, rightShoulder.position))
            }

            // 가슴둘레
            if let leftChest = keypoints.first(where: { $0.type == .chestLeft }),
               let rightChest = keypoints.first(where: { $0.type == .chestRight }) {
                lines.append((.chestCircumference, leftChest.position, rightChest.position))
            }

            // 허리둘레
            if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
               let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                lines.append((.waistCircumference, leftWaist.position, rightWaist.position))
            }

            // 엉덩이둘레
            if let leftHip = keypoints.first(where: { $0.type == .hipLeft }),
               let rightHip = keypoints.first(where: { $0.type == .hipRight }) {
                lines.append((.hipCircumference, leftHip.position, rightHip.position))
            }

            // 총길이
            if let neckline = keypoints.first(where: { $0.type == .neckline }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, neckline.position, hem.position))
            }

        // 점프수트
        case .jumpsuit:
            // 어깨너비
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder }) {
                lines.append((.shoulderWidth, leftShoulder.position, rightShoulder.position))
            }

            // 가슴둘레
            if let leftChest = keypoints.first(where: { $0.type == .chestLeft }),
               let rightChest = keypoints.first(where: { $0.type == .chestRight }) {
                lines.append((.chestCircumference, leftChest.position, rightChest.position))
            }

            // 허리둘레
            if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
               let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                lines.append((.waistCircumference, leftWaist.position, rightWaist.position))
            }

            // 엉덩이둘레
            if let leftHip = keypoints.first(where: { $0.type == .hipLeft }),
               let rightHip = keypoints.first(where: { $0.type == .hipRight }) {
                lines.append((.hipCircumference, leftHip.position, rightHip.position))
            }

            // 밑위
            if let waist = keypoints.first(where: { $0.type == .waistLeft }),
               let crotch = keypoints.first(where: { $0.type == .crotch }) {
                lines.append((.rise, waist.position, crotch.position))
            }

            // 총길이
            if let neckline = keypoints.first(where: { $0.type == .neckline }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, neckline.position, hem.position))
            }

        // 하의
        case .shorts, .pants, .jeans:
            // 허리둘레
            if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
               let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                lines.append((.waistCircumference, leftWaist.position, rightWaist.position))
            }

            // 엉덩이둘레 (청바지는 필수가 아님)
            if clothingType != .jeans {
                if let leftHip = keypoints.first(where: { $0.type == .hipLeft }),
                   let rightHip = keypoints.first(where: { $0.type == .hipRight }) {
                    lines.append((.hipCircumference, leftHip.position, rightHip.position))
                }
            }

            // 밑위
            if let waist = keypoints.first(where: { $0.type == .waistLeft }),
               let crotch = keypoints.first(where: { $0.type == .crotch }) {
                lines.append((.rise, waist.position, crotch.position))
            }

            // 밑단
            if let leftHem = keypoints.first(where: { $0.type == .leftHem }),
               let rightHem = keypoints.first(where: { $0.type == .rightHem }) {
                lines.append((.hem, leftHem.position, rightHem.position))
            }

            // 허벅지둘레 (긴바지, 청바지의 경우)
            if clothingType == .pants || clothingType == .jeans {
                if let leftHip = keypoints.first(where: { $0.type == .hipLeft }) {
                    // 허벅지둘레는 엉덩이 아래쪽에 표시
                    let thighPoint = CGPoint(x: leftHip.position.x, y: leftHip.position.y + 0.1)
                    lines.append((.thighCircumference, thighPoint, thighPoint))
                }
            }

        // 레깅스
        case .leggings:
            // 허리둘레
            if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
               let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                lines.append((.waistCircumference, leftWaist.position, rightWaist.position))
            }

            // 엉덩이둘레
            if let leftHip = keypoints.first(where: { $0.type == .hipLeft }),
               let rightHip = keypoints.first(where: { $0.type == .hipRight }) {
                lines.append((.hipCircumference, leftHip.position, rightHip.position))
            }

            // 총길이
            if let waist = keypoints.first(where: { $0.type == .waistLeft }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, waist.position, hem.position))
            }

        case .skirt:
            // 허리둘레
            if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
               let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                lines.append((.waistCircumference, leftWaist.position, rightWaist.position))
            }

            // 엉덩이둘레 (스커트는 선택)
            if let leftHip = keypoints.first(where: { $0.type == .hipLeft }),
               let rightHip = keypoints.first(where: { $0.type == .hipRight }) {
                lines.append((.hipCircumference, leftHip.position, rightHip.position))
            }

            // 총길이
            if let waist = keypoints.first(where: { $0.type == .waistLeft }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, waist.position, hem.position))
            }
        }

        return lines
    }
}
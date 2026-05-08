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
enum KeypointType: Hashable, Sendable {
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
    let angleThreshold: CGFloat = 30.0  // 30도 이상 변화를 변곡점으로 판단

    /// 최소 신뢰도 임계값
    let minConfidence: Float = 0.6

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

        let learnedKeypoints = MLTrainingDataCollector.shared.learnedMeasurementPriorKeypoints(
            for: clothingType,
            featurePoints: featurePoints
        )
        let refinedKeypoints = ClothingTypeMeasurementPrior.refine(
            keypoints,
            clothingType: clothingType,
            featurePoints: featurePoints,
            learnedKeypoints: learnedKeypoints
        )

        print("✅ [KeypointDetector] 키포인트 감지 완료: \(refinedKeypoints.count)개")
        for keypoint in refinedKeypoints {
            print("  - \(keypoint.description)")
        }

        return refinedKeypoints
    }

    // MARK: - Helper Methods

    /// 메인 윤곽선 선택
    func selectMainContour(from observation: VNContoursObservation) -> VNContour? {
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
    func calculateBoundingBox(from points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }

        let minX = points.map { $0.x }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 1
        let minY = points.map { $0.y }.min() ?? 0
        let maxY = points.map { $0.y }.max() ?? 1

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// 변곡점 찾기
    func findInflectionPoint(near point: CGPoint, in points: [CGPoint], direction: Direction) -> CGPoint? {
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
}

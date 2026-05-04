//
//  MeasurementPointDetector.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  의류 타입별 측정 포인트 자동 감지 프로토콜 및 공통 타입입니다.
//  특징점에서 측정 포인트를 추론하는 알고리즘을 제공합니다.
//
//  Key Responsibilities:
//  - 의류 타입별 측정 포인트 자동 감지
//  - 신뢰도 점수 계산
//  - 측정 포인트 후보 생성
//

import Foundation
import CoreGraphics
import Vision

// MARK: - Measurement Point Candidate

/// 자동 감지된 측정 포인트 후보
struct MeasurementPointCandidate {
    /// 측정 타입
    let type: MeasurementType

    /// 화면 좌표 (정규화)
    let screenPosition: CGPoint

    /// 신뢰도 (0.0 ~ 1.0)
    let confidence: Float

    /// 그룹 ID (같은 측정 항목에 속하는 포인트들)
    let groupId: String

    init(
        type: MeasurementType,
        screenPosition: CGPoint,
        confidence: Float,
        groupId: String? = nil
    ) {
        self.type = type
        self.screenPosition = screenPosition
        self.confidence = confidence
        self.groupId = groupId ?? UUID().uuidString
    }
}

// MARK: - Protocol

/// 측정 포인트 감지기 프로토콜
protocol MeasurementPointDetector {
    /// 지원하는 의류 타입
    var supportedTypes: [ClothingType] { get }

    /// 측정 포인트 감지
    ///
    /// - Parameters:
    ///   - featurePoints: 윤곽선에서 추출한 특징점
    ///   - contour: 전체 윤곽선
    /// - Returns: 감지된 측정 포인트 후보들
    func detectPoints(
        featurePoints: ClothingFeaturePoints,
        contour: VNContoursObservation
    ) -> [MeasurementPointCandidate]
}

// MARK: - Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

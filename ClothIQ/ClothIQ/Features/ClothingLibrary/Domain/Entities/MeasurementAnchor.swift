//
//  MeasurementAnchor.swift
//  ClothIQ
//
//  Created on 2025-11-10
//
//  Description:
//  사진 측정에서 사용되는 측정 앵커 포인트를 정의합니다.
//  각 앵커는 위치와 측정 타입 정보를 포함합니다.
//

import Foundation
import SwiftUI

/// 측정 앵커 포인트
public struct MeasurementAnchor: Identifiable, Equatable {
    /// 고유 식별자
    public let id: UUID

    /// 앵커 위치 (픽셀 좌표)
    public var position: CGPoint

    /// 측정 타입
    public let measurementType: MeasurementType

    /// 신뢰도 점수 (0.0 ~ 1.0)
    public var confidence: Float

    public init(
        id: UUID = UUID(),
        position: CGPoint,
        measurementType: MeasurementType,
        confidence: Float = 1.0
    ) {
        self.id = id
        self.position = position
        self.measurementType = measurementType
        self.confidence = confidence
    }
}

/// 측정 결과 (RealTimeFeedback용)
public struct RTFMeasurementResult: Identifiable, Equatable {
    public let id: UUID
    public let type: MeasurementType
    public let value: Double
    public let confidence: Float

    public init(
        id: UUID = UUID(),
        type: MeasurementType,
        value: Double,
        confidence: Float
    ) {
        self.id = id
        self.type = type
        self.value = value
        self.confidence = confidence
    }
}

/// 측정선 (UI 표시용)
public struct MeasurementLineUI: Identifiable {
    public let id: UUID
    public let start: CGPoint
    public let end: CGPoint
    public let type: MeasurementType
    public let value: Double
    public let color: Color

    public init(
        id: UUID = UUID(),
        start: CGPoint,
        end: CGPoint,
        type: MeasurementType,
        value: Double,
        color: Color = .blue
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.type = type
        self.value = value
        self.color = color
    }
}
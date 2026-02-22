//
//  CompletedMeasurement.swift
//  ClothIQ
//
//  Created on 2026-02-22
//
//  Description:
//  진행 중인 측정 세션에서 완료된 개별 측정 항목(어깨너비, 가슴둘레 등)을 나타내는 로컬 도메인 모델입니다.
//  AR 카메라 화면상에서 누적 렌더링, 통합 저장을 위해 사용됩니다.
//

import Foundation

/// AR 화면에서 완료된 한 쌍의 측정선(2개 포인트)과 그 결과를 담는 모델
struct CompletedMeasurement: Identifiable, Equatable {
    let id: UUID
    let type: MeasurementType
    let startPoint: MeasurementPoint
    let endPoint: MeasurementPoint
    let distanceInCm: Double
    
    init(id: UUID = UUID(), type: MeasurementType, startPoint: MeasurementPoint, endPoint: MeasurementPoint, distanceInCm: Double) {
        self.id = id
        self.type = type
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.distanceInCm = distanceInCm
    }
}

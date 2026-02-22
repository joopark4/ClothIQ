//
//  MeasurementSession.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  측정 세션을 나타내는 도메인 엔티티입니다.
//  하나의 의류 측정 과정 전체를 관리합니다.
//

import Foundation

/// 측정 세션 상태
enum MeasurementSessionState {
    case idle                   // 대기 중
    case selectingClothingType  // 의류 타입 선택 중
    case measuring              // 측정 중
    case reviewing              // 결과 검토 중
    case completed              // 완료됨
    case cancelled              // 취소됨
}

/// 측정 세션
///
/// 하나의 의류를 측정하는 전체 과정을 나타냅니다.
/// 측정 포인트, 측정값, 상태 등을 관리합니다.
///
struct MeasurementSession: Identifiable {
    /// 고유 식별자
    let id: UUID

    /// 의류 타입
    var clothingType: ClothingType?

    /// 세션 상태
    var state: MeasurementSessionState

    /// 측정 포인트 목록
    var points: [MeasurementPoint]

    /// 측정값 목록
    ///
    /// 키: MeasurementType, 값: 측정값 (센티미터)
    var measurements: [MeasurementType: Double]

    /// 세션 시작 시간
    let startedAt: Date

    /// 세션 종료 시간
    var completedAt: Date?

    /// 캡처한 이미지 (선택적)
    var capturedImageData: Data?

    /// 메모
    var notes: String?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        clothingType: ClothingType? = nil,
        state: MeasurementSessionState = .idle,
        points: [MeasurementPoint] = [],
        measurements: [MeasurementType: Double] = [:],
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        capturedImageData: Data? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.clothingType = clothingType
        self.state = state
        self.points = points
        self.measurements = measurements
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.capturedImageData = capturedImageData
        self.notes = notes
    }
}

// MARK: - Session Management

extension MeasurementSession {
    /// 측정 포인트 추가
    mutating func addPoint(_ point: MeasurementPoint) {
        points.append(point)
    }

    /// 마지막 측정 포인트 제거
    mutating func removeLastPoint() {
        _ = points.popLast()
    }

    /// 모든 측정 포인트 제거
    mutating func clearPoints() {
        points.removeAll()
    }

    /// 측정값 추가 또는 업데이트
    mutating func setMeasurement(_ value: Double, for type: MeasurementType) {
        measurements[type] = value
    }

    /// 특정 타입의 측정값 제거
    mutating func removeMeasurement(for type: MeasurementType) {
        measurements.removeValue(forKey: type)
    }

    /// 세션 완료
    mutating func complete() {
        state = .completed
        completedAt = Date()
    }

    /// 세션 취소
    mutating func cancel() {
        state = .cancelled
        completedAt = Date()
    }
}

// MARK: - Computed Properties

extension MeasurementSession {
    /// 필수 측정 항목이 모두 완료되었는지 확인
    var isComplete: Bool {
        guard let clothingType = clothingType else { return false }
        let requiredTypes = clothingType.requiredMeasurements
        return requiredTypes.allSatisfy { measurements.keys.contains($0) }
    }

    /// 측정 완료 진행률 (0.0 ~ 1.0)
    var completionProgress: Double {
        guard let clothingType = clothingType else { return 0.0 }
        let requiredTypes = clothingType.requiredMeasurements
        guard !requiredTypes.isEmpty else { return 0.0 }

        let completedCount = requiredTypes.filter { measurements.keys.contains($0) }.count
        return Double(completedCount) / Double(requiredTypes.count)
    }

    /// 세션 지속 시간 (초)
    var duration: TimeInterval {
        let endTime = completedAt ?? Date()
        return endTime.timeIntervalSince(startedAt)
    }

    /// 평균 측정 포인트 신뢰도
    var averageConfidence: Float {
        guard !points.isEmpty else { return 0.0 }
        let totalConfidence = points.reduce(0.0) { $0 + $1.confidence }
        return totalConfidence / Float(points.count)
    }

    /// 유효한 포인트 개수
    var validPointCount: Int {
        points.filter { $0.isValid }.count
    }
}

// MARK: - Validation

extension MeasurementSession {
    /// 세션이 저장 가능한 상태인지 확인
    var canBeSaved: Bool {
        guard clothingType != nil else { return false }
        guard !measurements.isEmpty else { return false }
        guard state == .completed || state == .reviewing else { return false }
        return true
    }

    /// 세션의 유효성 검증
    ///
    /// - Returns: 유효성 여부와 에러 메시지
    func validate() -> (isValid: Bool, error: String?) {
        if clothingType == nil {
            return (false, "의류 타입이 선택되지 않았습니다.")
        }

        if points.isEmpty {
            return (false, "측정 포인트가 없습니다.")
        }

        if validPointCount < 2 {
            return (false, "유효한 측정 포인트가 부족합니다. (최소 2개 필요)")
        }

        if measurements.isEmpty {
            return (false, "측정값이 없습니다.")
        }

        if averageConfidence < 0.5 {
            return (false, "측정 신뢰도가 너무 낮습니다. 재측정을 권장합니다.")
        }

        return (true, nil)
    }
}

//
//  RealTimeFeedbackOverlay.swift
//  ClothIQ
//
//  Created on 2025-11-10
//
//  Description:
//  사진 측정 시 실시간 피드백을 제공하는 오버레이 컴포넌트입니다.
//  드래그 중 측정값 표시, 유효성 검증, 스냅 기능 등을 제공합니다.
//
//  Key Features:
//  - 드래그 중 실시간 거리 표시
//  - 비정상 측정값 경고
//  - 자동 스냅 기능
//  - 측정 가이드라인 표시
//  - 신뢰도 기반 색상 코딩
//

import SwiftUI
import UIKit

/// 실시간 피드백 오버레이
struct RealTimeFeedbackOverlay: View {

    // MARK: - Properties

    /// 드래그 중인 앵커
    let draggingAnchor: MeasurementAnchor?

    /// 현재 드래그 위치
    let dragPosition: CGPoint?

    /// 모든 측정 앵커들
    let allAnchors: [MeasurementAnchor]

    /// 이미지 크기
    let imageSize: CGSize

    /// 의류 타입
    let clothingType: ClothingType

    /// 스냅 가능한 포인트들 (윤곽선 등)
    let snapPoints: [CGPoint]

    /// 햅틱 피드백 콜백
    let onHapticFeedback: ((UIImpactFeedbackGenerator.FeedbackStyle) -> Void)?

    // MARK: - Computed Properties

    /// 현재 측정값
    private var currentMeasurement: RTFMeasurementResult? {
        guard let draggingAnchor = draggingAnchor,
              let dragPosition = dragPosition else { return nil }

        // 연결된 앵커 찾기
        if let connectedAnchor = findConnectedAnchor(for: draggingAnchor) {
            let distance = calculateDistance(
                from: dragPosition,
                to: connectedAnchor.position,
                imageSize: imageSize
            )

            return RTFMeasurementResult(
                type: draggingAnchor.measurementType,
                value: distance,
                confidence: calculateConfidence(for: distance, type: draggingAnchor.measurementType)
            )
        }

        return nil
    }

    /// 스냅 포인트 찾기
    private var nearestSnapPoint: CGPoint? {
        guard let dragPosition = dragPosition else { return nil }

        let snapThreshold: CGFloat = 20.0 // 20픽셀 이내

        return snapPoints.min { point1, point2 in
            distance(from: dragPosition, to: point1) < distance(from: dragPosition, to: point2)
        }.flatMap { nearestPoint in
            distance(from: dragPosition, to: nearestPoint) <= snapThreshold ? nearestPoint : nil
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 측정 가이드라인
                if draggingAnchor != nil {
                    measurementGuidelines
                }

                // 드래그 중 실시간 측정값 표시
                if let measurement = currentMeasurement,
                   let dragPosition = dragPosition {
                    measurementValueOverlay(
                        measurement: measurement,
                        position: dragPosition,
                        geometry: geometry
                    )
                }

                // 스냅 인디케이터
                if let snapPoint = nearestSnapPoint {
                    snapIndicator(at: snapPoint, geometry: geometry)
                }

                // 유효성 경고
                if let warning = getValidationWarning() {
                    validationWarning(warning, geometry: geometry)
                }
            }
        }
    }

    // MARK: - Components

    /// 측정 가이드라인
    private var measurementGuidelines: some View {
        Canvas { context, size in
            guard let draggingAnchor = draggingAnchor,
                  let dragPosition = dragPosition else { return }

            // 수평/수직 가이드라인
            let path = Path { path in
                // 수평선
                path.move(to: CGPoint(x: 0, y: dragPosition.y))
                path.addLine(to: CGPoint(x: size.width, y: dragPosition.y))

                // 수직선
                path.move(to: CGPoint(x: dragPosition.x, y: 0))
                path.addLine(to: CGPoint(x: dragPosition.x, y: size.height))
            }

            context.stroke(
                path,
                with: .color(.blue.opacity(0.3)),
                style: StrokeStyle(lineWidth: 1, dash: [5, 5])
            )

            // 연결된 앵커와의 연결선
            if let connectedAnchor = findConnectedAnchor(for: draggingAnchor) {
                let connectionPath = Path { path in
                    path.move(to: dragPosition)
                    path.addLine(to: connectedAnchor.position)
                }

                let confidence = calculateConfidence(
                    for: currentMeasurement?.value ?? 0,
                    type: draggingAnchor.measurementType
                )

                context.stroke(
                    connectionPath,
                    with: .color(colorForConfidence(confidence)),
                    style: StrokeStyle(lineWidth: 2)
                )
            }
        }
    }

    /// 측정값 오버레이
    private func measurementValueOverlay(
        measurement: RTFMeasurementResult,
        position: CGPoint,
        geometry: GeometryProxy
    ) -> some View {
        let confidence = measurement.confidence
        let color = colorForConfidence(confidence)

        return Text("\(String(format: "%.1f", measurement.value)) cm")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
            )
            .position(
                x: min(max(position.x + 40, 60), geometry.size.width - 60),
                y: max(position.y - 30, 30)
            )
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.3), value: measurement.value)
    }

    /// 스냅 인디케이터
    private func snapIndicator(at point: CGPoint, geometry: GeometryProxy) -> some View {
        Circle()
            .stroke(Color.green, lineWidth: 2)
            .frame(width: 16, height: 16)
            .position(point)
            .overlay(
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .position(point)
            )
            .onAppear {
                // 스냅 포인트에 도달하면 햅틱 피드백
                onHapticFeedback?(.light)
            }
    }

    /// 유효성 경고
    private func validationWarning(_ warning: String, geometry: GeometryProxy) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)

            Text(warning)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.9))
        )
        .position(
            x: geometry.size.width / 2,
            y: 50
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Helper Methods

    /// 연결된 앵커 찾기
    private func findConnectedAnchor(for anchor: MeasurementAnchor) -> MeasurementAnchor? {
        // 측정 타입에 따라 페어링된 앵커 찾기
        switch anchor.measurementType {
        case .shoulderWidth:
            return allAnchors.first {
                $0.measurementType == .shoulderWidth && $0.id != anchor.id
            }
        case .chestCircumference:
            return allAnchors.first {
                $0.measurementType == .chestCircumference && $0.id != anchor.id
            }
        case .waistCircumference:
            return allAnchors.first {
                $0.measurementType == .waistCircumference && $0.id != anchor.id
            }
        case .hipCircumference:
            return allAnchors.first {
                $0.measurementType == .hipCircumference && $0.id != anchor.id
            }
        default:
            return nil
        }
    }

    /// 거리 계산
    private func calculateDistance(from: CGPoint, to: CGPoint, imageSize: CGSize) -> Double {
        let dx = abs(from.x - to.x) * (imageSize.width / 1000) // 픽셀을 cm로 변환 (예시)
        let dy = abs(from.y - to.y) * (imageSize.height / 1000)
        return sqrt(dx * dx + dy * dy)
    }

    /// 두 포인트 간 거리
    private func distance(from: CGPoint, to: CGPoint) -> CGFloat {
        let dx = from.x - to.x
        let dy = from.y - to.y
        return sqrt(dx * dx + dy * dy)
    }

    /// 신뢰도 계산
    private func calculateConfidence(for value: Double, type: MeasurementType) -> Float {
        // 의류 타입별 정상 범위 체크
        let normalRanges: [MeasurementType: ClosedRange<Double>] = [
            .shoulderWidth: 30...60,
            .chestCircumference: 70...150,
            .waistCircumference: 50...150,
            .hipCircumference: 60...160,
            .totalLength: 40...120,
            .sleeveLength: 10...80
        ]

        guard let range = normalRanges[type] else { return 0.5 }

        if range.contains(value) {
            // 정상 범위 내
            let center = (range.lowerBound + range.upperBound) / 2
            let deviation = abs(value - center) / (range.upperBound - range.lowerBound)
            return Float(1.0 - deviation * 0.3) // 0.7 ~ 1.0
        } else {
            // 비정상 범위
            if value < range.lowerBound {
                let deviation = (range.lowerBound - value) / range.lowerBound
                return Float(max(0.3, 0.6 - deviation))
            } else {
                let deviation = (value - range.upperBound) / range.upperBound
                return Float(max(0.3, 0.6 - deviation))
            }
        }
    }

    /// 신뢰도에 따른 색상
    private func colorForConfidence(_ confidence: Float) -> Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.6 {
            return .yellow
        } else {
            return .red
        }
    }

    /// 유효성 검증 경고 메시지
    private func getValidationWarning() -> String? {
        guard let measurement = currentMeasurement else { return nil }

        if measurement.confidence < 0.5 {
            switch measurement.type {
            case .shoulderWidth:
                return "어깨너비가 비정상적입니다 (일반: 30-60cm)"
            case .chestCircumference:
                return "가슴둘레가 비정상적입니다 (일반: 70-150cm)"
            case .waistCircumference:
                return "허리둘레가 비정상적입니다 (일반: 50-150cm)"
            default:
                return "측정값이 일반적인 범위를 벗어났습니다"
            }
        }

        return nil
    }
}


// MARK: - Preview

struct RealTimeFeedbackOverlay_Previews: PreviewProvider {
    static var previews: some View {
        RealTimeFeedbackOverlay(
            draggingAnchor: MeasurementAnchor(
                id: UUID(),
                position: CGPoint(x: 100, y: 100),
                measurementType: .shoulderWidth
            ),
            dragPosition: CGPoint(x: 300, y: 100),
            allAnchors: [
                MeasurementAnchor(
                    id: UUID(),
                    position: CGPoint(x: 100, y: 100),
                    measurementType: .shoulderWidth
                ),
                MeasurementAnchor(
                    id: UUID(),
                    position: CGPoint(x: 300, y: 100),
                    measurementType: .shoulderWidth
                )
            ],
            imageSize: CGSize(width: 1000, height: 1500),
            clothingType: .longSleeve,
            snapPoints: [
                CGPoint(x: 295, y: 100),
                CGPoint(x: 105, y: 100)
            ],
            onHapticFeedback: nil
        )
    }
}
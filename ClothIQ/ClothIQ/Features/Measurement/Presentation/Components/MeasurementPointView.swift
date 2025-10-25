//
//  MeasurementPointView.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  측정 포인트를 화면에 표시하는 컴포넌트입니다.
//  AR 화면 위에 오버레이되어 측정 포인트를 시각화합니다.
//

import SwiftUI

/// 측정 포인트 뷰
///
/// AR 화면 위에 측정 포인트를 표시합니다.
/// 포인트 번호, 신뢰도 등을 시각적으로 나타냅니다.
///
struct MeasurementPointView: View {
    let point: MeasurementPoint
    let index: Int
    let isSelected: Bool

    var body: some View {
        ZStack {
            // 외곽 원 (신뢰도에 따라 색상 변경)
            Circle()
                .stroke(confidenceColor, lineWidth: isSelected ? 3 : 2)
                .frame(width: isSelected ? 40 : 32, height: isSelected ? 40 : 32)

            // 내부 원
            Circle()
                .fill(confidenceColor.opacity(0.3))
                .frame(width: isSelected ? 36 : 28, height: isSelected ? 36 : 28)

            // 포인트 번호
            Text("\(index + 1)")
                .font(isSelected ? .caption.bold() : .caption2)
                .foregroundColor(.white)
        }
        .position(point.screenPosition)
        .animation(.spring(response: 0.3), value: isSelected)
    }

    // MARK: - Helpers

    private var confidenceColor: Color {
        switch point.confidenceLevel {
        case .veryHigh:
            return .green
        case .high:
            return .blue
        case .medium:
            return .orange
        case .low:
            return .red
        }
    }
}

// MARK: - Connection Line View

/// 두 측정 포인트를 연결하는 선
struct MeasurementLineView: View {
    let startPoint: MeasurementPoint
    let endPoint: MeasurementPoint
    let distance: Double  // 센티미터

    var body: some View {
        ZStack {
            // 연결선
            Path { path in
                path.move(to: startPoint.screenPosition)
                path.addLine(to: endPoint.screenPosition)
            }
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))

            // 거리 표시 (중간 지점)
            Text(String(format: "%.1f cm", distance))
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .position(midPoint)
        }
    }

    private var midPoint: CGPoint {
        CGPoint(
            x: (startPoint.screenPosition.x + endPoint.screenPosition.x) / 2,
            y: (startPoint.screenPosition.y + endPoint.screenPosition.y) / 2
        )
    }
}

// MARK: - Measurement Overlay View

/// 측정 오버레이 뷰
///
/// AR 화면 위에 모든 측정 포인트와 연결선을 표시합니다.
///
struct MeasurementOverlayView: View {
    let points: [MeasurementPoint]
    let selectedIndex: Int?

    var body: some View {
        ZStack {
            // 연결선 (포인트가 2개 이상일 때)
            if points.count >= 2 {
                ForEach(0..<points.count - 1, id: \.self) { index in
                    let start = points[index]
                    let end = points[index + 1]
                    let distance = start.distanceInCentimeters(to: end)

                    MeasurementLineView(
                        startPoint: start,
                        endPoint: end,
                        distance: distance
                    )
                }
            }

            // 측정 포인트들
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                MeasurementPointView(
                    point: point,
                    index: index,
                    isSelected: selectedIndex == index
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("Single Point") {
    let point = MeasurementPoint(
        worldPosition: SIMD3<Float>(0, 0, -1),
        screenPosition: CGPoint(x: 200, y: 300),
        depth: 1.0,
        confidence: 0.95
    )

    return ZStack {
        Color.black.ignoresSafeArea()
        MeasurementPointView(point: point, index: 0, isSelected: true)
    }
}

#Preview("Multiple Points with Lines") {
    let points = [
        MeasurementPoint(
            worldPosition: SIMD3<Float>(0, 0, -1),
            screenPosition: CGPoint(x: 100, y: 200),
            depth: 1.0,
            confidence: 0.95
        ),
        MeasurementPoint(
            worldPosition: SIMD3<Float>(0.5, 0, -1),
            screenPosition: CGPoint(x: 300, y: 200),
            depth: 1.0,
            confidence: 0.88
        ),
        MeasurementPoint(
            worldPosition: SIMD3<Float>(0.5, 0.3, -1),
            screenPosition: CGPoint(x: 300, y: 400),
            depth: 1.0,
            confidence: 0.75
        )
    ]

    ZStack {
        Color.black.ignoresSafeArea()
        MeasurementOverlayView(points: points, selectedIndex: 1)
    }
}

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
    let viewSize: CGSize  // GeometryReader로 전달받을 뷰 크기
    let imageResolution: CGSize  // ARFrame의 imageResolution

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
            if index >= 0 {
                Text("\(index + 1)")
                    .font(isSelected ? .caption.bold() : .caption2)
                    .foregroundColor(.white)
            } else {
                Image(systemName: "checkmark")
                    .font(.caption2.bold())
                    .foregroundColor(.white)
            }
        }
        .position(scaledPosition)
        .animation(.spring(response: 0.3), value: isSelected)
    }

    // screenPosition은 imageResolution 기준이므로, 실제 뷰 크기로 변환
    private var scaledPosition: CGPoint {
        CGPoint(
            x: point.screenPosition.x * viewSize.width / imageResolution.width,
            y: point.screenPosition.y * viewSize.height / imageResolution.height
        )
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
    let viewSize: CGSize
    let imageResolution: CGSize
    var isCompleted: Bool = false
    var label: String? = nil

    var body: some View {
        ZStack {
            // 연결선
            Path { path in
                path.move(to: scaledStartPosition)
                path.addLine(to: scaledEndPosition)
            }
            .stroke(isCompleted ? Color.green : Color.blue, style: StrokeStyle(lineWidth: isCompleted ? 3 : 2, dash: isCompleted ? [] : [5, 3]))

            // 거리 표시 (중간 지점)
            Text(label ?? String(format: "%.1f cm", distance))
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isCompleted ? Color.green : Color.blue)
                .foregroundColor(isCompleted ? .black : .white)
                .cornerRadius(8)
                .position(midPoint)
        }
    }

    private var scaledStartPosition: CGPoint {
        CGPoint(
            x: startPoint.screenPosition.x * viewSize.width / imageResolution.width,
            y: startPoint.screenPosition.y * viewSize.height / imageResolution.height
        )
    }

    private var scaledEndPosition: CGPoint {
        CGPoint(
            x: endPoint.screenPosition.x * viewSize.width / imageResolution.width,
            y: endPoint.screenPosition.y * viewSize.height / imageResolution.height
        )
    }

    private var midPoint: CGPoint {
        CGPoint(
            x: (scaledStartPosition.x + scaledEndPosition.x) / 2,
            y: (scaledStartPosition.y + scaledEndPosition.y) / 2
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
    let completedMeasurements: [CompletedMeasurement]
    let selectedIndex: Int?
    let imageResolution: CGSize?  // ARFrame의 imageResolution

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let resolution = imageResolution {
                    // 연결선 (포인트가 2개 이상일 때)
                    if points.count >= 2 {
                        ForEach(0..<points.count - 1, id: \.self) { index in
                            let start = points[index]
                            let end = points[index + 1]
                            let distance = start.distanceInCentimeters(to: end)

                            MeasurementLineView(
                                startPoint: start,
                                endPoint: end,
                                distance: distance,
                                viewSize: geometry.size,
                                imageResolution: resolution,
                                isCompleted: false,
                                label: nil
                            )
                        }
                    }

                    // 완료된 측정 항목 오버레이 (누적 선)
                    ForEach(completedMeasurements) { completed in
                        MeasurementLineView(
                            startPoint: completed.startPoint,
                            endPoint: completed.endPoint,
                            distance: completed.distanceInCm,
                            viewSize: geometry.size,
                            imageResolution: resolution,
                            isCompleted: true,
                            label: "\(completed.type.displayName) \(String(format: "%.1f", completed.distanceInCm))cm"
                        )
                        
                        MeasurementPointView(
                            point: completed.startPoint,
                            index: -1, // 점 표시는 숨기거나 다르게 표시할 수 있음
                            isSelected: false,
                            viewSize: geometry.size,
                            imageResolution: resolution
                        )
                        MeasurementPointView(
                            point: completed.endPoint,
                            index: -1,
                            isSelected: false,
                            viewSize: geometry.size,
                            imageResolution: resolution
                        )
                    }

                    // 현재 진행 중인 측정 포인트들
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        MeasurementPointView(
                            point: point,
                            index: index,
                            isSelected: selectedIndex == index,
                            viewSize: geometry.size,
                            imageResolution: resolution
                        )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

// MARK: - Preview

#Preview("Single Point") {
    let point = MeasurementPoint(
        worldPosition: SIMD3<Float>(0, 0, -1),
        screenPosition: CGPoint(x: 960, y: 720),  // imageResolution 기준 좌표
        depth: 1.0,
        confidence: 0.95
    )

    return ZStack {
        Color.black.ignoresSafeArea()
        MeasurementPointView(
            point: point,
            index: 0,
            isSelected: true,
            viewSize: CGSize(width: 1024, height: 768),
            imageResolution: CGSize(width: 1920, height: 1440)
        )
    }
}

#Preview("Multiple Points with Lines") {
    let points = [
        MeasurementPoint(
            worldPosition: SIMD3<Float>(0, 0, -1),
            screenPosition: CGPoint(x: 600, y: 400),  // imageResolution 기준
            depth: 1.0,
            confidence: 0.95
        ),
        MeasurementPoint(
            worldPosition: SIMD3<Float>(0.5, 0, -1),
            screenPosition: CGPoint(x: 1200, y: 400),
            depth: 1.0,
            confidence: 0.88
        ),
        MeasurementPoint(
            worldPosition: SIMD3<Float>(0.5, 0.3, -1),
            screenPosition: CGPoint(x: 1200, y: 900),
            depth: 1.0,
            confidence: 0.75
        )
    ]

    ZStack {
        Color.black.ignoresSafeArea()
        MeasurementOverlayView(
            points: points,
            completedMeasurements: [],
            selectedIndex: 1,
            imageResolution: CGSize(width: 1920, height: 1440)
        )
    }
}

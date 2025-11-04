//
//  MeasurementLinesOverlay.swift
//  ClothIQ
//
//  Created on 2025-10-31
//
//  Description:
//  의류 이미지 위에 측정 라인을 표시하는 오버레이 뷰입니다.
//  각 측정 타입별로 다른 색상과 스타일로 라인을 그리고
//  측정 이름과 값을 레이블로 표시합니다.
//

import SwiftUI

/// 측정 라인 오버레이 뷰
struct MeasurementLinesOverlay: View {
    // MARK: - Properties

    /// 측정 데이터 목록
    let measurements: [MeasurementModel]

    /// 이미지 원본 크기
    let imageSize: CGSize

    /// 선택된 측정 항목 (하이라이트용)
    @Binding var selectedMeasurement: MeasurementModel?

    /// 라인 표시 여부
    let showLines: Bool

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Canvas를 사용하지 않고 직접 View로 구현하여 애니메이션 적용
                if showLines {
                    ForEach(measurements) { measurement in
                        MeasurementOverlayLineView(
                            measurement: measurement,
                            displayRect: calculateDisplayRect(in: geometry.size),
                            isSelected: selectedMeasurement?.id == measurement.id
                        )
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.8)),
                                removal: .opacity.combined(with: .scale(scale: 0.8))
                            )
                        )
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.8),
                            value: selectedMeasurement?.id == measurement.id
                        )
                    }
                }
            }
            .onAppear {
                print("📐 [MeasurementLinesOverlay] Overlay appeared")
                print("   Show lines: \(showLines)")
                print("   Total measurements: \(measurements.count)")
                print("   Image size: \(imageSize)")
                print("   Display rect: \(calculateDisplayRect(in: geometry.size))")
                let withCoords = measurements.filter { $0.hasCoordinates }.count
                print("   Measurements with coordinates: \(withCoords)/\(measurements.count)")
            }
        }
    }

    // MARK: - Helper Methods

    /// 이미지 비율에 맞춰 표시 영역 계산
    private func calculateDisplayRect(in size: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = size.width / size.height

        var displaySize: CGSize
        if imageAspect > viewAspect {
            // 이미지가 더 넓음 (너비 기준)
            displaySize = CGSize(
                width: size.width,
                height: size.width / imageAspect
            )
        } else {
            // 이미지가 더 높음 (높이 기준)
            displaySize = CGSize(
                width: size.height * imageAspect,
                height: size.height
            )
        }

        let origin = CGPoint(
            x: (size.width - displaySize.width) / 2,
            y: (size.height - displaySize.height) / 2
        )

        return CGRect(origin: origin, size: displaySize)
    }

    /// 측정 포인트 그리기
    private func drawPoint(context: GraphicsContext, at point: CGPoint, color: Color, isSelected: Bool) {
        let pointSize: CGFloat = isSelected ? 12 : 8

        context.fill(
            Circle().path(in: CGRect(
                x: point.x - pointSize / 2,
                y: point.y - pointSize / 2,
                width: pointSize,
                height: pointSize
            )),
            with: .color(.white)
        )

        context.stroke(
            Circle().path(in: CGRect(
                x: point.x - pointSize / 2,
                y: point.y - pointSize / 2,
                width: pointSize,
                height: pointSize
            )),
            with: .color(color),
            lineWidth: 2
        )
    }

    /// 측정 레이블 그리기
    private func drawLabel(context: GraphicsContext, at point: CGPoint, measurement: MeasurementModel, color: Color, isSelected: Bool) {
        let displayName = measurement.measurementType?.displayName ?? measurement.type
        let formattedValue = String(format: "%.1fcm", measurement.value)
        let text = "\(displayName): \(formattedValue)"

        let fontSize: CGFloat = isSelected ? 14 : 12

        // 배경 박스 그리기
        let textSize = CGSize(width: CGFloat(text.count) * fontSize * 0.6, height: fontSize + 8)
        let backgroundRect = CGRect(
            x: point.x - textSize.width / 2,
            y: point.y - textSize.height / 2 - 20, // 라인 위에 표시
            width: textSize.width,
            height: textSize.height
        )

        context.fill(
            RoundedRectangle(cornerRadius: 4).path(in: backgroundRect),
            with: .color(color.opacity(0.9))
        )

        // 텍스트 그리기
        context.draw(
            Text(text)
                .font(.system(size: fontSize, weight: isSelected ? .semibold : .regular))
                .foregroundColor(.white),
            at: CGPoint(x: point.x, y: point.y - 20)
        )
    }

    /// 측정 타입별 색상
    private func colorForMeasurementType(_ type: String) -> Color {
        switch type {
        // 상의 측정 항목
        case "shoulder_width":
            return .blue
        case "chest_circumference":
            return .green
        case "total_length":
            return .orange
        case "sleeve_length":
            return .purple
        case "arm_circumference":
            return .cyan
        case "neck_circumference":
            return .indigo

        // 하의 측정 항목
        case "waist_circumference":
            return .red
        case "hip_circumference":
            return .green
        case "rise":
            return .purple
        case "hem":
            return .brown
        case "thigh_circumference":
            return .cyan
        case "inseam":
            return .indigo
        case "outseam":
            return .mint
        case "knee_circumference":
            return .pink

        // 기본값
        default:
            return .gray
        }
    }
}

// MARK: - Measurement Overlay Line View

/// 개별 측정 라인 뷰 (애니메이션 지원)
struct MeasurementOverlayLineView: View {
    let measurement: MeasurementModel
    let displayRect: CGRect
    let isSelected: Bool

    @State private var animationProgress: Double = 0.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 좌표가 있는 경우에만 그리기
                if measurement.hasCoordinates,
                   let startPoint = measurement.startPoint,
                   let endPoint = measurement.endPoint {

                    let start = CGPoint(
                        x: displayRect.minX + startPoint.x * displayRect.width,
                        y: displayRect.minY + startPoint.y * displayRect.height
                    )
                    let end = CGPoint(
                        x: displayRect.minX + endPoint.x * displayRect.width,
                        y: displayRect.minY + endPoint.y * displayRect.height
                    )

                    let color = colorForMeasurementType(measurement.type)

                    // 라인
                    MeasurementLine(
                        start: start,
                        end: end,
                        color: color,
                        lineWidth: isSelected ? 4 : 2,
                        opacity: isSelected ? 1.0 : 0.8
                    )
                    .animation(.spring(response: 0.3), value: isSelected)

                    // 시작 포인트
                    MeasurementPointCircle(
                        position: start,
                        color: color,
                        size: isSelected ? 12 : 8
                    )
                    .scaleEffect(animationProgress)
                    .animation(.spring(response: 0.3), value: isSelected)

                    // 끝 포인트
                    MeasurementPointCircle(
                        position: end,
                        color: color,
                        size: isSelected ? 12 : 8
                    )
                    .scaleEffect(animationProgress)
                    .animation(.spring(response: 0.3), value: isSelected)

                    // 레이블
                    if animationProgress > 0.5 {
                        let midPoint = CGPoint(
                            x: (start.x + end.x) / 2,
                            y: (start.y + end.y) / 2
                        )

                        MeasurementLabel(
                            position: midPoint,
                            measurement: measurement,
                            color: color,
                            isSelected: isSelected
                        )
                        .opacity(animationProgress)
                        .scaleEffect(animationProgress)
                    }
                } else {
                    // 디버그: 좌표가 없는 경우
                    EmptyView()
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double.random(in: 0...0.2))) {
                animationProgress = 1.0
            }
        }
    }

    private func colorForMeasurementType(_ type: String) -> Color {
        switch type {
        case "shoulder_width": return .blue
        case "chest_circumference": return .green
        case "total_length": return .orange
        case "sleeve_length": return .purple
        case "arm_circumference": return .cyan
        case "neck_circumference": return .indigo
        case "waist_circumference": return .red
        case "hip_circumference": return .green
        case "rise": return .purple
        case "hem": return .brown
        case "thigh_circumference": return .cyan
        case "inseam": return .indigo
        case "outseam": return .mint
        case "knee_circumference": return .pink
        default: return .gray
        }
    }
}

// MARK: - Measurement Line Shape

struct MeasurementLine: View {
    let start: CGPoint
    let end: CGPoint
    let color: Color
    let lineWidth: CGFloat
    let opacity: Double

    var body: some View {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(color.opacity(opacity), lineWidth: lineWidth)
    }
}

// MARK: - Measurement Point Circle

struct MeasurementPointCircle: View {
    let position: CGPoint
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: size, height: size)

            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: size, height: size)
        }
        .position(position)
    }
}

// MARK: - Measurement Label

struct MeasurementLabel: View {
    let position: CGPoint
    let measurement: MeasurementModel
    let color: Color
    let isSelected: Bool

    var body: some View {
        let displayName = measurement.measurementType?.displayName ?? measurement.type
        let formattedValue = String(format: "%.1fcm", measurement.value)
        let text = "\(displayName): \(formattedValue)"

        Text(text)
            .font(.system(size: isSelected ? 14 : 12, weight: isSelected ? .semibold : .regular))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.95))
                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
            )
            .position(x: position.x, y: position.y - 20)
    }
}

// MARK: - Preview

#Preview {
    MeasurementLinesOverlay(
        measurements: [],
        imageSize: CGSize(width: 1000, height: 1000),
        selectedMeasurement: .constant(nil),
        showLines: true
    )
}
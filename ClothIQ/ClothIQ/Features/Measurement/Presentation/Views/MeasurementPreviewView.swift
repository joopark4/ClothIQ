//
//  MeasurementPreviewView.swift
//  ClothIQ
//
//  Created on 2026-02-22
//
//  Description:
//  촬영 후 측정 항목을 확인하고 저장/취소를 확정하는 전체 화면 미리보기 뷰입니다.
//

import SwiftUI

struct MeasurementPreviewView: View {
    let image: UIImage
    let clothingType: ClothingType
    let measurements: [CompletedMeasurement]
    let originalImageSize: CGSize?
    let cropRect: CGRect?
    let processedImageSize: CGSize?
    let cameraResolution: CGSize?
    let canSave: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        MeasurementPreviewImageOverlay(
                            image: image,
                            measurements: measurements,
                            originalImageSize: originalImageSize,
                            cropRect: cropRect,
                            processedImageSize: processedImageSize,
                            cameraResolution: cameraResolution
                        )
                            .frame(maxWidth: .infinity)
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            Text("의류 타입")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(clothingType.displayName)
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("측정 항목")
                                .font(.headline)

                            if measurements.isEmpty {
                                Text("적용된 측정 항목이 없습니다.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(measurements) { measurement in
                                    measurementRow(measurement)
                                }
                            }
                        }
                    }
                    .padding(20)
                }

                Divider()

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("취소")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: onSave) {
                        Text("저장")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSave ? Color.blue : Color.gray.opacity(0.5))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canSave)
                }
                .padding(20)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("측정 미리보기")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func measurementRow(_ measurement: CompletedMeasurement) -> some View {
        HStack {
            Text(measurement.type.displayName)
                .font(.body)
            Spacer()
            Text(String(format: "%.1f cm", measurement.distanceInCm))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    let start = MeasurementPoint(
        worldPosition: SIMD3<Float>(0, 0, -1),
        screenPosition: CGPoint(x: 200, y: 200),
        depth: 1.0,
        confidence: 0.9
    )
    let end = MeasurementPoint(
        worldPosition: SIMD3<Float>(0.2, 0, -1),
        screenPosition: CGPoint(x: 500, y: 200),
        depth: 1.0,
        confidence: 0.9
    )

    MeasurementPreviewView(
        image: UIImage(systemName: "photo") ?? UIImage(),
        clothingType: .shortSleeve,
        measurements: [
            CompletedMeasurement(type: .shoulderWidth, startPoint: start, endPoint: end, distanceInCm: 42.3),
            CompletedMeasurement(type: .chestCircumference, startPoint: start, endPoint: end, distanceInCm: 51.4)
        ],
        originalImageSize: CGSize(width: 1920, height: 1440),
        cropRect: CGRect(x: 240, y: 0, width: 1440, height: 1440),
        processedImageSize: CGSize(width: 1024, height: 1024),
        cameraResolution: CGSize(width: 1920, height: 1440),
        canSave: true,
        onSave: {},
        onCancel: {}
    )
}

private struct MeasurementPreviewImageOverlay: View {
    let image: UIImage
    let measurements: [CompletedMeasurement]
    let originalImageSize: CGSize?
    let cropRect: CGRect?
    let processedImageSize: CGSize?
    let cameraResolution: CGSize?

    private struct RenderedMeasurement: Identifiable {
        let id: UUID
        let type: MeasurementType
        let distanceInCm: Double
        let start: CGPoint
        let end: CGPoint
    }

    private enum CoordinateTransform: CaseIterable {
        case direct
        case rotateRight
        case rotateLeft
        case rotate180
    }

    private var resolvedProcessedSize: CGSize {
        let size = processedImageSize ?? image.size
        if size.width > 0, size.height > 0 {
            return size
        }
        return CGSize(width: 1, height: 1)
    }

    private var resolvedOriginalSize: CGSize {
        if let originalImageSize, originalImageSize.width > 0, originalImageSize.height > 0 {
            return originalImageSize
        }
        if let cameraResolution, cameraResolution.width > 0, cameraResolution.height > 0 {
            return cameraResolution
        }
        return resolvedProcessedSize
    }

    private var resolvedCropRect: CGRect {
        if let cropRect, cropRect.width > 0, cropRect.height > 0 {
            return cropRect
        }
        return CGRect(origin: .zero, size: resolvedOriginalSize)
    }

    private var bestTransform: CoordinateTransform {
        guard let cameraResolution, cameraResolution.width > 0, cameraResolution.height > 0 else {
            return .direct
        }

        let transforms: [CoordinateTransform] = [.direct, .rotateRight, .rotateLeft, .rotate180]
        var selected: CoordinateTransform = .direct
        var bestScore = Int.min

        for transform in transforms {
            let score = score(for: transform)
            if score > bestScore {
                bestScore = score
                selected = transform
            }
        }

        return selected
    }

    private var convertedMeasurements: [RenderedMeasurement] {
        let transform = bestTransform
        return measurements.compactMap { measurement in
            guard
                let start = mapToProcessed(
                    measurement.startPoint.screenPosition,
                    transform: transform,
                    clampToBounds: true
                ),
                let end = mapToProcessed(
                    measurement.endPoint.screenPosition,
                    transform: transform,
                    clampToBounds: true
                )
            else {
                return nil
            }

            return RenderedMeasurement(
                id: measurement.id,
                type: measurement.type,
                distanceInCm: measurement.distanceInCm,
                start: start,
                end: end
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let displayRect = displayRect(in: geometry.size)
            let processedSize = resolvedProcessedSize

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displayRect.width, height: displayRect.height)
                    .position(x: displayRect.midX, y: displayRect.midY)

                ForEach(convertedMeasurements) { measurement in
                    let lineColor = color(for: measurement.type)
                    let start = pointInDisplay(measurement.start, displayRect: displayRect, processedSize: processedSize)
                    let end = pointInDisplay(measurement.end, displayRect: displayRect, processedSize: processedSize)
                    let labelPoint = labelPosition(forStart: start, end: end, in: displayRect)

                    Path { path in
                        path.move(to: start)
                        path.addLine(to: end)
                    }
                    .stroke(lineColor.opacity(0.95), lineWidth: 3)

                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .position(start)

                    Circle()
                        .stroke(lineColor, lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .position(start)

                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .position(end)

                    Circle()
                        .stroke(lineColor, lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .position(end)

                    Text("\(measurement.type.displayName) \(String(format: "%.1f", measurement.distanceInCm))cm")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(lineColor.opacity(0.9))
                        )
                        .position(labelPoint)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func score(for transform: CoordinateTransform) -> Int {
        let processedSize = resolvedProcessedSize
        var score = 0

        for measurement in measurements {
            if let start = mapToProcessed(
                measurement.startPoint.screenPosition,
                transform: transform,
                clampToBounds: false
            ), isInside(start, in: processedSize) {
                score += 1
            }

            if let end = mapToProcessed(
                measurement.endPoint.screenPosition,
                transform: transform,
                clampToBounds: false
            ), isInside(end, in: processedSize) {
                score += 1
            }
        }

        return score
    }

    private func mapToProcessed(
        _ point: CGPoint,
        transform: CoordinateTransform,
        clampToBounds: Bool
    ) -> CGPoint? {
        let processedSize = resolvedProcessedSize
        guard processedSize.width > 0, processedSize.height > 0 else {
            return nil
        }

        let sourceSize: CGSize
        if let cameraResolution, cameraResolution.width > 0, cameraResolution.height > 0 {
            sourceSize = cameraResolution
        } else {
            sourceSize = resolvedOriginalSize
        }

        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return nil
        }

        var normalized = normalizedPoint(
            point,
            sourceSize: sourceSize,
            transform: transform
        )

        if clampToBounds {
            normalized.x = clamp(normalized.x, min: 0, max: 1)
            normalized.y = clamp(normalized.y, min: 0, max: 1)
        }

        let originalSize = resolvedOriginalSize
        let originalPoint = CGPoint(
            x: normalized.x * originalSize.width,
            y: normalized.y * originalSize.height
        )

        let cropRect = resolvedCropRect
        let cropWidth = max(cropRect.width, 1)
        let cropHeight = max(cropRect.height, 1)
        var processedPoint = CGPoint(
            x: (originalPoint.x - cropRect.minX) * (processedSize.width / cropWidth),
            y: (originalPoint.y - cropRect.minY) * (processedSize.height / cropHeight)
        )

        if clampToBounds {
            processedPoint.x = clamp(processedPoint.x, min: 0, max: processedSize.width)
            processedPoint.y = clamp(processedPoint.y, min: 0, max: processedSize.height)
        }

        return processedPoint
    }

    private func normalizedPoint(
        _ point: CGPoint,
        sourceSize: CGSize,
        transform: CoordinateTransform
    ) -> CGPoint {
        let x = point.x / sourceSize.width
        let y = point.y / sourceSize.height

        switch transform {
        case .direct:
            return CGPoint(x: x, y: y)
        case .rotateRight:
            return CGPoint(x: y, y: 1 - x)
        case .rotateLeft:
            return CGPoint(x: 1 - y, y: x)
        case .rotate180:
            return CGPoint(x: 1 - x, y: 1 - y)
        }
    }

    private func isInside(_ point: CGPoint, in size: CGSize) -> Bool {
        point.x >= 0 &&
        point.y >= 0 &&
        point.x <= size.width &&
        point.y <= size.height
    }

    private func pointInDisplay(
        _ point: CGPoint,
        displayRect: CGRect,
        processedSize: CGSize
    ) -> CGPoint {
        guard processedSize.width > 0, processedSize.height > 0 else {
            return CGPoint(x: displayRect.midX, y: displayRect.midY)
        }

        return CGPoint(
            x: displayRect.minX + (point.x / processedSize.width) * displayRect.width,
            y: displayRect.minY + (point.y / processedSize.height) * displayRect.height
        )
    }

    private func labelPosition(
        forStart start: CGPoint,
        end: CGPoint,
        in rect: CGRect
    ) -> CGPoint {
        let raw = CGPoint(
            x: (start.x + end.x) * 0.5,
            y: ((start.y + end.y) * 0.5) - 18
        )
        return CGPoint(
            x: clamp(raw.x, min: rect.minX + 10, max: rect.maxX - 10),
            y: clamp(raw.y, min: rect.minY + 10, max: rect.maxY - 10)
        )
    }

    private func displayRect(in containerSize: CGSize) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return .zero
        }

        let imageSize = resolvedProcessedSize
        let imageAspect = imageSize.width / max(imageSize.height, 1)
        let containerAspect = containerSize.width / max(containerSize.height, 1)

        let displaySize: CGSize
        if imageAspect > containerAspect {
            displaySize = CGSize(
                width: containerSize.width,
                height: containerSize.width / imageAspect
            )
        } else {
            displaySize = CGSize(
                width: containerSize.height * imageAspect,
                height: containerSize.height
            )
        }

        return CGRect(
            x: (containerSize.width - displaySize.width) * 0.5,
            y: (containerSize.height - displaySize.height) * 0.5,
            width: displaySize.width,
            height: displaySize.height
        )
    }

    private func color(for type: MeasurementType) -> Color {
        switch type {
        case .shoulderWidth:
            return .blue
        case .chestCircumference:
            return .green
        case .totalLength:
            return .orange
        case .sleeveLength:
            return .purple
        case .armCircumference:
            return .cyan
        case .neckCircumference:
            return .indigo
        case .cuffCircumference:
            return .mint
        case .waistCircumference:
            return .red
        case .hipCircumference:
            return .pink
        case .rise:
            return .teal
        case .hem:
            return .brown
        case .thighCircumference:
            return .yellow
        }
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(value, maxValue))
    }
}

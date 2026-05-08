//
//  KeypointOverlayView.swift
//  ClothIQ
//
//  Created on 2025-11-10
//
//  Description:
//  의류 키포인트를 시각화하는 오버레이 뷰입니다.
//  감지된 키포인트를 이미지 위에 표시합니다.
//

import SwiftUI

/// 키포인트 오버레이 뷰
struct KeypointOverlayView: View {

    // MARK: - Properties

    /// 감지된 키포인트들
    let keypoints: [MeasurementKeypoint]

    /// 키포인트가 속한 의류 타입
    var clothingType: ClothingType? = nil

    /// 이미지 크기
    let imageSize: CGSize

    /// 실제 화면에 그려지는 이미지 크기
    var renderedImageSize: CGSize? = nil

    /// 표시 영역 크기 (GeometryReader로 전달받음)
    let displaySize: CGSize

    /// 이미지 회전 각도
    var rotation: Double = 0

    /// ZoomableImageView와 동일하게 적용할 이미지 여백
    var padding: CGFloat = 0

    /// ZoomableImageView의 확대 배율
    var scale: CGFloat = 1

    /// ZoomableImageView의 이동 오프셋
    var offset: CGSize = .zero

    // MARK: - Body

    var body: some View {
        ZStack {
            // 키포인트 연결선 (측정 라인)
            ForEach(measurementLines, id: \.id) { line in
                Path { path in
                    path.move(to: convertToDisplayPoint(line.start))
                    path.addLine(to: convertToDisplayPoint(line.end))
                }
                .stroke(line.color, lineWidth: 2)
                .opacity(0.8)
            }

            // 키포인트 마커
            ForEach(keypoints.indices, id: \.self) { index in
                let keypoint = keypoints[index]
                let displayPoint = convertToDisplayPoint(keypoint.position)

                KeypointMarker(
                    keypoint: keypoint,
                    position: displayPoint
                )
            }
        }
    }

    // MARK: - Helper Methods

    /// 정규화된 좌표를 디스플레이 좌표로 변환
    private func convertToDisplayPoint(_ normalizedPoint: CGPoint) -> CGPoint {
        // MeasurementKeypoint는 Vision 정규화 좌표계(Y=0 하단)를 사용한다.
        // 이미지 픽셀 좌표계(Y=0 상단)로 바꾼 뒤, 실제 aspectFit/패딩/회전 변환을 공유한다.
        let clampedX = max(0, min(normalizedPoint.x, 1))
        let clampedY = max(0, min(normalizedPoint.y, 1))
        let imagePoint = CGPoint(
            x: clampedX * imageSize.width,
            y: (1.0 - clampedY) * imageSize.height
        )
        let converter = CoordinateConverter(
            imageSize: imageSize,
            renderedImageSize: renderedImageSize,
            rotation: rotation
        )
        return converter.imageToView(
            imagePoint,
            in: displaySize,
            scale: scale,
            offset: offset,
            padding: padding
        )
    }

    /// 키포인트 쌍으로 측정 라인 생성
    private var measurementLines: [KeypointMeasurementLine] {
        if let clothingType {
            return ClothingKeypointDetector()
                .generateMeasurementLines(from: keypoints, clothingType: clothingType)
                .map { line in
                    KeypointMeasurementLine(
                        id: line.type.rawValue,
                        start: line.start,
                        end: line.end,
                        color: colorForMeasurementType(line.type)
                    )
                }
        }

        var lines: [KeypointMeasurementLine] = []

        // 어깨너비
        if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
           let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder }) {
            lines.append(KeypointMeasurementLine(
                id: "shoulder",
                start: leftShoulder.position,
                end: rightShoulder.position,
                color: .blue
            ))
        }

        // 가슴둘레
        if let leftChest = keypoints.first(where: { $0.type == .chestLeft }),
           let rightChest = keypoints.first(where: { $0.type == .chestRight }) {
            lines.append(KeypointMeasurementLine(
                id: "chest",
                start: leftChest.position,
                end: rightChest.position,
                color: .green
            ))
        }

        // 소매길이
        if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
           let leftSleeveEnd = keypoints.first(where: { $0.type == .leftSleeveEnd }) {
            lines.append(KeypointMeasurementLine(
                id: "sleeve",
                start: leftShoulder.position,
                end: leftSleeveEnd.position,
                color: .orange
            ))
        }

        // 총길이
        if let neckline = keypoints.first(where: { $0.type == .neckline }),
           let hemCenter = keypoints.first(where: { $0.type == .hemCenter }) {
            lines.append(KeypointMeasurementLine(
                id: "length",
                start: neckline.position,
                end: hemCenter.position,
                color: .purple
            ))
        }

        // 허리둘레
        if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
           let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
            lines.append(KeypointMeasurementLine(
                id: "waist",
                start: leftWaist.position,
                end: rightWaist.position,
                color: .red
            ))
        }

        // 엉덩이둘레
        if let leftHip = keypoints.first(where: { $0.type == .hipLeft }),
           let rightHip = keypoints.first(where: { $0.type == .hipRight }) {
            lines.append(KeypointMeasurementLine(
                id: "hip",
                start: leftHip.position,
                end: rightHip.position,
                color: .pink
            ))
        }

        return lines
    }

    private func colorForMeasurementType(_ type: MeasurementType) -> Color {
        switch type {
        case .shoulderWidth:
            return .blue
        case .chestCircumference:
            return .green
        case .sleeveLength:
            return .orange
        case .totalLength:
            return .purple
        case .waistCircumference:
            return .red
        case .hipCircumference:
            return .pink
        case .rise:
            return .indigo
        case .hem:
            return .brown
        default:
            return .gray
        }
    }
}

// MARK: - Supporting Types

/// 키포인트 측정 라인
private struct KeypointMeasurementLine {
    let id: String
    let start: CGPoint
    let end: CGPoint
    let color: Color
}

/// 키포인트 마커
private struct KeypointMarker: View {
    let keypoint: MeasurementKeypoint
    let position: CGPoint

    var body: some View {
        ZStack {
            // 외곽 원
            Circle()
                .fill(markerColor.opacity(0.3))
                .frame(width: 20, height: 20)
                .position(position)

            // 중심 점
            Circle()
                .fill(markerColor)
                .frame(width: 8, height: 8)
                .position(position)

            // 신뢰도 표시 (낮은 신뢰도일 때)
            if keypoint.confidence < 0.7 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.caption2)
                    .position(x: position.x + 12, y: position.y - 12)
            }

            // 라벨 (디버그 모드)
            #if DEBUG
            Text(keypoint.type.displayName)
                .font(.system(size: 9))
                .foregroundColor(.white)
                .padding(2)
                .background(markerColor.opacity(0.8))
                .cornerRadius(4)
                .position(x: position.x, y: position.y + 20)
            #endif
        }
    }

    private var markerColor: Color {
        switch keypoint.type {
        case .leftShoulder, .rightShoulder:
            return .blue
        case .leftArmpit, .rightArmpit:
            return .cyan
        case .leftSleeveEnd, .rightSleeveEnd:
            return .orange
        case .neckline:
            return .purple
        case .hemCenter:
            return .brown
        case .chestLeft, .chestRight:
            return .green
        case .waistLeft, .waistRight:
            return .red
        case .hipLeft, .hipRight:
            return .pink
        case .crotch:
            return .indigo
        case .leftHem, .rightHem:
            return .gray
        }
    }
}

// MARK: - Preview

struct KeypointOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        GeometryReader { geometry in
            KeypointOverlayView(
                keypoints: sampleKeypoints,
                imageSize: CGSize(width: 1000, height: 1500),
                displaySize: geometry.size,
                padding: 20
            )
            .background(Color.gray.opacity(0.1))
        }
    }

    static var sampleKeypoints: [MeasurementKeypoint] {
        [
            MeasurementKeypoint(
                type: .leftShoulder,
                position: CGPoint(x: 0.3, y: 0.8),
                confidence: 0.9
            ),
            MeasurementKeypoint(
                type: .rightShoulder,
                position: CGPoint(x: 0.7, y: 0.8),
                confidence: 0.9
            ),
            MeasurementKeypoint(
                type: .neckline,
                position: CGPoint(x: 0.5, y: 0.85),
                confidence: 0.85
            ),
            MeasurementKeypoint(
                type: .hemCenter,
                position: CGPoint(x: 0.5, y: 0.1),
                confidence: 0.9
            )
        ]
    }
}

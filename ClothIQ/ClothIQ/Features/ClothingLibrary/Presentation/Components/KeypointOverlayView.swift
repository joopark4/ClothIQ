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

    /// 이미지 크기
    let imageSize: CGSize

    /// 표시 영역 크기 (GeometryReader로 전달받음)
    let displaySize: CGSize

    /// 스케일 팩터
    private var scale: CGFloat {
        min(displaySize.width / imageSize.width,
            displaySize.height / imageSize.height)
    }

    /// 오프셋
    private var offset: CGSize {
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        return CGSize(
            width: (displaySize.width - scaledWidth) / 2,
            height: (displaySize.height - scaledHeight) / 2
        )
    }

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
        // Vision 좌표계 (Y=0이 하단) → SwiftUI 좌표계 (Y=0이 상단) 변환
        let x = normalizedPoint.x * imageSize.width * scale + offset.width
        let y = (1.0 - normalizedPoint.y) * imageSize.height * scale + offset.height

        return CGPoint(x: x, y: y)
    }

    /// 키포인트 쌍으로 측정 라인 생성
    private var measurementLines: [KeypointMeasurementLine] {
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
                displaySize: geometry.size
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
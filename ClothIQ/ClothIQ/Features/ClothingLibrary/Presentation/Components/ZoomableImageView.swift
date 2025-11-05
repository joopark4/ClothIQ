//
//  ZoomableImageView.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  줌/팬/회전이 가능한 이미지 뷰입니다.
//  측정 포인트 오버레이를 지원합니다.
//

import SwiftUI

/// 줌/팬 가능한 이미지 뷰
struct ZoomableImageView: View {

    // MARK: - Properties

    let image: UIImage
    let rotation: Double
    @Binding var measurementAnchors: [PhotoMeasurementViewModel.MeasurementAnchor]
    @Binding var isEditingAnchors: Bool
    var activeAnchorID: UUID?
    let onTap: (CGPoint) -> Void
    let onAnchorDragBegan: (UUID) -> Void
    let onAnchorDragChanged: (UUID, CGPoint) -> Void
    let onAnchorDragEnded: (UUID, CGPoint) -> Void
    let onAnchorSelected: (UUID) -> Void

    @State private var currentScale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0

    @State private var currentOffset: CGSize = .zero
    @State private var finalOffset: CGSize = .zero

    // MARK: - Constants

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    private let anchorHitRadius: CGFloat = 32.0
    private let imagePadding: CGFloat = 20.0  // 이미지 여백

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 배경
                Color.black.ignoresSafeArea()

                // 이미지
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(.degrees(rotation))
                    .padding(imagePadding)  // 이미지 주변 여백
                    .onTapGesture { location in
                        // 측정 포인트 추가
                        let convertedPoint = convertTapLocation(
                            location,
                            in: geometry.size
                        )
                        onTap(convertedPoint)
                    }
                    .overlay {
                        MeasurementAnchorsOverlay(
                            anchors: $measurementAnchors,
                            isEditingAnchors: $isEditingAnchors,
                            imageSize: CGSize(width: image.size.width, height: image.size.height),
                            scale: 1.0,  // 확대 비활성화
                            offset: .zero,  // 이동 비활성화
                            padding: imagePadding,  // 이미지 여백
                            activeAnchorID: activeAnchorID,
                            onDragBegan: onAnchorDragBegan,
                            onDragChanged: onAnchorDragChanged,
                            onDragEnded: onAnchorDragEnded,
                            onSelect: onAnchorSelected
                        )
                    }
            }
            // 줌/팬 제스처 완전 비활성화
        }
    }

    // MARK: - Gestures

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if isEditingAnchors {
                    return
                }
                let delta = value / currentScale
                currentScale = delta
                let newScale = finalScale * currentScale
                if newScale < minScale || newScale > maxScale {
                    currentScale = min(max(newScale, minScale), maxScale) / finalScale
                }
            }
            .onEnded { _ in
                if isEditingAnchors {
                    return
                }
                let newScale = finalScale * currentScale
                finalScale = min(max(newScale, minScale), maxScale)
                currentScale = 1.0

                // 줌 아웃하면 오프셋 리셋
                if finalScale == minScale {
                    withAnimation(.spring()) {
                        finalOffset = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if isEditingAnchors {
                    return
                }
                currentOffset = value.translation
            }
            .onEnded { _ in
                if isEditingAnchors {
                    return
                }
                finalOffset.width += currentOffset.width
                finalOffset.height += currentOffset.height
                currentOffset = .zero
            }
    }

    // MARK: - Helpers

    /// 탭 위치를 이미지 좌표로 변환
    private func convertTapLocation(_ location: CGPoint, in viewSize: CGSize) -> CGPoint {
        let scale = finalScale * currentScale
        let offset = CGSize(
            width: finalOffset.width + currentOffset.width,
            height: finalOffset.height + currentOffset.height
        )

        // 이미지의 실제 표시 크기 계산
        let imageAspect = image.size.width / image.size.height
        let viewAspect = viewSize.width / viewSize.height

        var displaySize: CGSize
        if imageAspect > viewAspect {
            // 이미지가 더 넓음 (너비 기준)
            displaySize = CGSize(
                width: viewSize.width,
                height: viewSize.width / imageAspect
            )
        } else {
            // 이미지가 더 높음 (높이 기준)
            displaySize = CGSize(
                width: viewSize.height * imageAspect,
                height: viewSize.height
            )
        }

        // 이미지 중심 위치
        let imageCenter = CGPoint(
            x: viewSize.width / 2,
            y: viewSize.height / 2
        )

        // 스케일과 오프셋 적용된 좌표 계산
        let scaledDisplaySize = CGSize(
            width: displaySize.width * scale,
            height: displaySize.height * scale
        )

        let imageOrigin = CGPoint(
            x: imageCenter.x - scaledDisplaySize.width / 2 + offset.width,
            y: imageCenter.y - scaledDisplaySize.height / 2 + offset.height
        )

        // 탭 위치를 이미지 좌표로 변환
        let relativeX = (location.x - imageOrigin.x) / scaledDisplaySize.width
        let relativeY = (location.y - imageOrigin.y) / scaledDisplaySize.height

        return CGPoint(
            x: relativeX * image.size.width,
            y: relativeY * image.size.height
        )
    }

    private func convertImagePointToView(_ point: CGPoint, in viewSize: CGSize) -> CGPoint {
        let scale = finalScale * currentScale
        let offset = CGSize(
            width: finalOffset.width + currentOffset.width,
            height: finalOffset.height + currentOffset.height
        )

        let imageAspect = image.size.width / image.size.height
        let viewAspect = viewSize.width / viewSize.height

        var displaySize: CGSize
        if imageAspect > viewAspect {
            displaySize = CGSize(width: viewSize.width, height: viewSize.width / imageAspect)
        } else {
            displaySize = CGSize(width: viewSize.height * imageAspect, height: viewSize.height)
        }

        let scaledDisplaySize = CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
        let imageCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let imageOrigin = CGPoint(
            x: imageCenter.x - scaledDisplaySize.width / 2 + offset.width,
            y: imageCenter.y - scaledDisplaySize.height / 2 + offset.height
        )

        let relativeX = point.x / image.size.width
        let relativeY = point.y / image.size.height

        return CGPoint(
            x: imageOrigin.x + relativeX * scaledDisplaySize.width,
            y: imageOrigin.y + relativeY * scaledDisplaySize.height
        )
    }

    private func anchor(at location: CGPoint, in viewSize: CGSize) -> PhotoMeasurementViewModel.MeasurementAnchor? {
        guard !measurementAnchors.isEmpty else { return nil }
        for anchor in measurementAnchors {
            let viewPoint = convertImagePointToView(anchor.position, in: viewSize)
            let distance = hypot(viewPoint.x - location.x, viewPoint.y - location.y)
            if distance <= anchorHitRadius {
                return anchor
            }
        }
        return nil
    }
}

// MARK: - Measurement Points Overlay

struct MeasurementAnchorsOverlay: View {
    @Binding var anchors: [PhotoMeasurementViewModel.MeasurementAnchor]
    @Binding var isEditingAnchors: Bool
    let imageSize: CGSize
    let scale: CGFloat
    let offset: CGSize
    let padding: CGFloat  // 이미지 여백
    let activeAnchorID: UUID?
    let onDragBegan: (UUID) -> Void
    let onDragChanged: (UUID, CGPoint) -> Void
    let onDragEnded: (UUID, CGPoint) -> Void
    let onSelect: (UUID) -> Void

    private let handleSize: CGFloat = 60  // 더 큰 터치 영역
    private let visualSize: CGFloat = 40  // 실제 표시 크기

    // 드래그 중 임시 위치 저장
    @State private var draggingAnchorID: UUID?
    @State private var draggingPosition: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if anchors.count == 2 {
                    let point1 = convertImageToViewCoordinates(anchors[0].position, in: geometry.size)
                    let point2 = convertImageToViewCoordinates(anchors[1].position, in: geometry.size)

                    Path { path in
                        path.move(to: point1)
                        path.addLine(to: point2)
                    }
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .onAppear {
                        logRenderingDetails(geometry: geometry, point1: point1, point2: point2)
                    }
                } else {
                    EmptyView()
                }

                ForEach(anchors) { anchor in
                    // 드래그 중인 앵커는 임시 위치 사용, 아니면 원래 위치 사용
                    let viewPoint: CGPoint = {
                        if anchor.id == draggingAnchorID, let dragPos = draggingPosition {
                            return dragPos
                        } else {
                            return convertImageToViewCoordinates(anchor.position, in: geometry.size)
                        }
                    }()
                    let isActive = anchor.id == activeAnchorID

                    ZStack {
                        // 투명한 큰 터치 영역
                        Circle()
                            .fill(Color.clear)
                            .frame(width: handleSize, height: handleSize)

                        // 실제 표시되는 원
                        Circle()
                            .fill(isActive ? Color.yellow : Color.blue)
                            .frame(width: visualSize, height: visualSize)  // 모든 포인트 크기 동일
                            .overlay {
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)  // 테두리 두께 증가
                            }
                            .overlay {
                                Text(anchorLabel(for: anchor))
                                    .font(.callout)  // 숫자 크기 증가
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                            }
                    }
                    .zIndex(1000)  // 최상위에 표시
                    .position(viewPoint)
                    .onTapGesture {
                        onSelect(anchor.id)
                    }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                // 드래그 시작
                                if draggingAnchorID == nil {
                                    draggingAnchorID = anchor.id
                                    onSelect(anchor.id)
                                    if !isEditingAnchors {
                                        isEditingAnchors = true
                                        onDragBegan(anchor.id)
                                    }
                                }

                                // 드래그 중 - 임시 위치 업데이트 (즉시 반영)
                                draggingPosition = value.location

                                // 이미지 좌표로 변환하여 콜백 호출
                                let imagePoint = convertViewToImageCoordinates(value.location, in: geometry.size)
                                onDragChanged(anchor.id, imagePoint)
                            }
                            .onEnded { value in
                                // 드래그 종료
                                let imagePoint = convertViewToImageCoordinates(value.location, in: geometry.size)
                                onDragEnded(anchor.id, imagePoint)

                                // 상태 초기화
                                isEditingAnchors = false
                                draggingAnchorID = nil
                                draggingPosition = nil
                            }
                    )
                }
            }
            .zIndex(999)  // 오버레이를 최상위에 표시
            .allowsHitTesting(true)
            .onChange(of: anchors.count) { oldValue, newValue in
            }
            .onChange(of: anchors.map { $0.id }) { oldValue, newValue in
            }
        }
    }

    private func anchorLabel(for anchor: PhotoMeasurementViewModel.MeasurementAnchor) -> String {
        guard let index = anchors.firstIndex(where: { $0.id == anchor.id }) else { return "" }
        return "\(index + 1)"
    }

    private func logRenderingDetails(geometry: GeometryProxy, point1: CGPoint, point2: CGPoint) {
    }

    private func convertImageToViewCoordinates(_ point: CGPoint, in viewSize: CGSize) -> CGPoint {
        // padding을 고려한 실제 표시 영역
        let availableSize = CGSize(
            width: viewSize.width - padding * 2,
            height: viewSize.height - padding * 2
        )

        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = availableSize.width / availableSize.height

        var displaySize: CGSize
        if imageAspect > viewAspect {
            displaySize = CGSize(width: availableSize.width, height: availableSize.width / imageAspect)
        } else {
            displaySize = CGSize(width: availableSize.height * imageAspect, height: availableSize.height)
        }

        let scaledDisplaySize = CGSize(width: displaySize.width * scale, height: displaySize.height * scale)

        let imageCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)

        let imageOrigin = CGPoint(
            x: imageCenter.x - scaledDisplaySize.width / 2 + offset.width,
            y: imageCenter.y - scaledDisplaySize.height / 2 + offset.height
        )

        let relativeX = point.x / imageSize.width
        let relativeY = point.y / imageSize.height

        return CGPoint(
            x: imageOrigin.x + relativeX * scaledDisplaySize.width,
            y: imageOrigin.y + relativeY * scaledDisplaySize.height
        )
    }

    private func convertViewToImageCoordinates(_ location: CGPoint, in viewSize: CGSize) -> CGPoint {
        // padding을 고려한 실제 표시 영역
        let availableSize = CGSize(
            width: viewSize.width - padding * 2,
            height: viewSize.height - padding * 2
        )

        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = availableSize.width / availableSize.height

        var displaySize: CGSize
        if imageAspect > viewAspect {
            displaySize = CGSize(width: availableSize.width, height: availableSize.width / imageAspect)
        } else {
            displaySize = CGSize(width: availableSize.height * imageAspect, height: availableSize.height)
        }

        let scaledDisplaySize = CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
        let imageCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let imageOrigin = CGPoint(
            x: imageCenter.x - scaledDisplaySize.width / 2 + offset.width,
            y: imageCenter.y - scaledDisplaySize.height / 2 + offset.height
        )

        let relativeX = (location.x - imageOrigin.x) / scaledDisplaySize.width
        let relativeY = (location.y - imageOrigin.y) / scaledDisplaySize.height

        return CGPoint(
            x: relativeX * imageSize.width,
            y: relativeY * imageSize.height
        )
    }
}

// MARK: - View Extension

extension View {
    @ViewBuilder
    func apply<T: View>(@ViewBuilder transform: (Self) -> T) -> some View {
        transform(self)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var anchors: [PhotoMeasurementViewModel.MeasurementAnchor] = []
    @Previewable @State var isEditing = false

    ZoomableImageView(
        image: UIImage(systemName: "photo")!,
        rotation: 0,
        measurementAnchors: $anchors,
        isEditingAnchors: $isEditing,
        activeAnchorID: nil,
        onTap: { point in
            let anchor = PhotoMeasurementViewModel.MeasurementAnchor(position: point)
            anchors.append(anchor)
            if anchors.count > 2 {
                anchors.removeFirst()
            }
        },
        onAnchorDragBegan: { _ in
            isEditing = true
        },
        onAnchorDragChanged: { id, position in
            if let index = anchors.firstIndex(where: { $0.id == id }) {
                anchors[index].position = position
            }
        },
        onAnchorDragEnded: { id, position in
            if let index = anchors.firstIndex(where: { $0.id == id }) {
                anchors[index].position = position
            }
            isEditing = false
        },
        onAnchorSelected: { _ in }
    )
}

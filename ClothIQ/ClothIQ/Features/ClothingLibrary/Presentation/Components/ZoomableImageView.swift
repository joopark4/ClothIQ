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
    let imageSize: CGSize  // 앵커 좌표 계산에 사용할 이미지 크기
    let rotation: Double
    @Binding var measurementAnchors: [MeasurementAnchor]
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
                // 배경 (터치 영역 확대)
                Color.clear

                // 이미지
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(.degrees(rotation))
                    .padding(imagePadding)  // 이미지 주변 여백

                // 오버레이 - 항상 표시 (내부에서 empty 체크)
                MeasurementAnchorsOverlay(
                    anchors: $measurementAnchors,
                    isEditingAnchors: $isEditingAnchors,
                    imageSize: imageSize,  // 전달받은 effectiveImageSize 사용
                    rotation: rotation,  // 회전 각도 전달 (좌표 변환에 필요)
                    scale: 1.0,  // 확대 비활성화
                    offset: .zero,  // 이동 비활성화
                    padding: imagePadding,  // 이미지 여백
                    activeAnchorID: activeAnchorID,
                    onDragBegan: onAnchorDragBegan,
                    onDragChanged: onAnchorDragChanged,
                    onDragEnded: onAnchorDragEnded,
                    onSelect: onAnchorSelected
                )
                .id(measurementAnchors.count)  // 앵커 개수 변경 시 뷰 강제 재생성
                // .allowsHitTesting(!measurementAnchors.isEmpty)  // 항상 렌더링되도록 주석 처리
                .onAppear {
                    print("🎨 [MeasurementAnchorsOverlay] 오버레이 최초 표시 - 앵커 개수: \(measurementAnchors.count)")
                }
            }
            .onTapGesture { location in
                print("🟢 [ZoomableImageView] Tap detected at: \(location)")
                // 측정 포인트 추가
                let convertedPoint = convertTapLocation(
                    location,
                    in: geometry.size
                )
                print("🟢 [ZoomableImageView] Converted point: \(convertedPoint)")
                onTap(convertedPoint)
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

    /// 탭 위치를 이미지 좌표로 변환 (rotation 반영)
    private func convertTapLocation(_ location: CGPoint, in viewSize: CGSize) -> CGPoint {
        let scale = finalScale * currentScale
        let offset = CGSize(
            width: finalOffset.width + currentOffset.width,
            height: finalOffset.height + currentOffset.height
        )

        // rotation 값을 정규화 (0/90/180/270)
        let normalizedRotation = ((Int(rotation) % 360) + 360) % 360
        let isRotated90or270 = (normalizedRotation == 90 || normalizedRotation == 270)

        // rotation 반영한 표시 크기 (90/270도이면 원본 width/height 교환)
        let displayedWidth = isRotated90or270 ? imageSize.height : imageSize.width
        let displayedHeight = isRotated90or270 ? imageSize.width : imageSize.height
        let imageAspect = displayedWidth / displayedHeight
        let viewAspect = viewSize.width / viewSize.height

        var displaySize: CGSize
        if imageAspect > viewAspect {
            // 표시 이미지가 더 넓음 (너비 기준)
            displaySize = CGSize(
                width: viewSize.width,
                height: viewSize.width / imageAspect
            )
        } else {
            // 표시 이미지가 더 높음 (높이 기준)
            displaySize = CGSize(
                width: viewSize.height * imageAspect,
                height: viewSize.height
            )
        }

        let scaledDisplaySize = CGSize(
            width: displaySize.width * scale,
            height: displaySize.height * scale
        )

        let imageCenter = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let imageOrigin = CGPoint(
            x: imageCenter.x - scaledDisplaySize.width / 2 + offset.width,
            y: imageCenter.y - scaledDisplaySize.height / 2 + offset.height
        )

        // 뷰 좌표 → 표시 이미지 내 상대 좌표 (0~1)
        let relativeX = (location.x - imageOrigin.x) / scaledDisplaySize.width
        let relativeY = (location.y - imageOrigin.y) / scaledDisplaySize.height

        // rotation 역변환하여 원본 이미지 좌표 계산
        let imageX: CGFloat
        let imageY: CGFloat
        switch normalizedRotation {
        case 90:   // 시계방향 90°: 표시 x가 원본 y, 표시 y가 원본 (1-x)
            imageX = imageSize.width * (1 - relativeY)
            imageY = imageSize.height * relativeX
        case 180:  // 180°: x/y 모두 반전
            imageX = imageSize.width * (1 - relativeX)
            imageY = imageSize.height * (1 - relativeY)
        case 270:  // 시계방향 270°: 표시 x가 원본 (1-y), 표시 y가 원본 x
            imageX = imageSize.width * relativeY
            imageY = imageSize.height * (1 - relativeX)
        default:   // 0°: 변환 없음
            imageX = imageSize.width * relativeX
            imageY = imageSize.height * relativeY
        }

        return CGPoint(x: imageX, y: imageY)
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

    private func anchor(at location: CGPoint, in viewSize: CGSize) -> MeasurementAnchor? {
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
    @Binding var anchors: [MeasurementAnchor]
    @Binding var isEditingAnchors: Bool
    let imageSize: CGSize
    let rotation: Double  // 회전 각도 (좌표 변환에 필요)
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
        let _ = print("📐 [MeasurementAnchorsOverlay] body 호출됨 - anchors.count: \(anchors.count)")

        return GeometryReader { geometry in
            ZStack {
                // 투명한 배경으로 터치 통과
                Color.clear
                    .allowsHitTesting(false)

                if anchors.count == 2 {
                    let point1 = convertImageToViewCoordinates(anchors[0].position, in: geometry.size)
                    let point2 = convertImageToViewCoordinates(anchors[1].position, in: geometry.size)

                    let _ = print("🔴 [MeasurementAnchorsOverlay] 빨간 선 그리기 - point1: \(point1), point2: \(point2)")

                    Path { path in
                        path.move(to: point1)
                        path.addLine(to: point2)
                    }
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .onAppear {
                        print("✅ [Line] 빨간 선이 화면에 나타남")
                        logRenderingDetails(geometry: geometry, point1: point1, point2: point2)
                    }
                } else {
                    EmptyView()
                        .onAppear {
                            print("⚠️ [MeasurementAnchorsOverlay] 앵커 개수 부족 - 선 그리지 않음")
                        }
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

                    let _ = print("🔵 [Anchor] 앵커 \(anchorLabel(for: anchor)) 그리기 - position: \(viewPoint)")

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
                    .onAppear {
                        print("✅ [Anchor] 앵커 \(anchorLabel(for: anchor))가 화면에 나타남")
                    }
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
            .allowsHitTesting(!anchors.isEmpty)  // anchors가 있을 때만 터치 활성화
            .onChange(of: anchors.count) { oldValue, newValue in
            }
            .onChange(of: anchors.map { $0.id }) { oldValue, newValue in
            }
        }
    }

    private func anchorLabel(for anchor: MeasurementAnchor) -> String {
        guard let index = anchors.firstIndex(where: { $0.id == anchor.id }) else { return "" }
        return "\(index + 1)"
    }

    private func logRenderingDetails(geometry: GeometryProxy, point1: CGPoint, point2: CGPoint) {
    }

    private func convertImageToViewCoordinates(_ point: CGPoint, in viewSize: CGSize) -> CGPoint {
        print("🔵 [convertImageToViewCoordinates] INPUT - point: \(point), imageSize: \(imageSize), rotation: \(rotation), viewSize: \(viewSize)")

        // rotation 값을 정규화 (0/90/180/270)
        let normalizedRotation = ((Int(rotation) % 360) + 360) % 360
        let isRotated90or270 = (normalizedRotation == 90 || normalizedRotation == 270)

        // rotation 반영한 표시 크기
        let displayedWidth = isRotated90or270 ? imageSize.height : imageSize.width
        let displayedHeight = isRotated90or270 ? imageSize.width : imageSize.height
        let imageAspect = displayedWidth / displayedHeight

        // padding을 고려한 실제 표시 영역
        let availableSize = CGSize(
            width: viewSize.width - padding * 2,
            height: viewSize.height - padding * 2
        )
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

        // rotation 적용하여 원본 이미지 좌표 → 뷰 내 상대 좌표 변환
        let relativeX: CGFloat
        let relativeY: CGFloat
        switch normalizedRotation {
        case 90:   // 시계방향 90°
            relativeX = 1 - (point.y / imageSize.height)
            relativeY = point.x / imageSize.width
        case 180:  // 180°
            relativeX = 1 - (point.x / imageSize.width)
            relativeY = 1 - (point.y / imageSize.height)
        case 270:  // 시계방향 270°
            relativeX = point.y / imageSize.height
            relativeY = 1 - (point.x / imageSize.width)
        default:   // 0°
            relativeX = point.x / imageSize.width
            relativeY = point.y / imageSize.height
        }

        let result = CGPoint(
            x: imageOrigin.x + relativeX * scaledDisplaySize.width,
            y: imageOrigin.y + relativeY * scaledDisplaySize.height
        )

        print("🔵 [convertImageToViewCoordinates] OUTPUT - result: \(result)")

        return result
    }

    private func convertViewToImageCoordinates(_ location: CGPoint, in viewSize: CGSize) -> CGPoint {
        // rotation 값을 정규화 (0/90/180/270)
        let normalizedRotation = ((Int(rotation) % 360) + 360) % 360
        let isRotated90or270 = (normalizedRotation == 90 || normalizedRotation == 270)

        // rotation 반영한 표시 크기
        let displayedWidth = isRotated90or270 ? imageSize.height : imageSize.width
        let displayedHeight = isRotated90or270 ? imageSize.width : imageSize.height
        let imageAspect = displayedWidth / displayedHeight

        // padding을 고려한 실제 표시 영역
        let availableSize = CGSize(
            width: viewSize.width - padding * 2,
            height: viewSize.height - padding * 2
        )
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

        // 뷰 좌표 → 표시 이미지 내 상대 좌표 (0~1)
        let relativeX = (location.x - imageOrigin.x) / scaledDisplaySize.width
        let relativeY = (location.y - imageOrigin.y) / scaledDisplaySize.height

        // rotation 역변환하여 원본 이미지 좌표 계산
        let imageX: CGFloat
        let imageY: CGFloat
        switch normalizedRotation {
        case 90:   // 시계방향 90°
            imageX = imageSize.width * (1 - relativeY)
            imageY = imageSize.height * relativeX
        case 180:  // 180°
            imageX = imageSize.width * (1 - relativeX)
            imageY = imageSize.height * (1 - relativeY)
        case 270:  // 시계방향 270°
            imageX = imageSize.width * relativeY
            imageY = imageSize.height * (1 - relativeX)
        default:   // 0°
            imageX = imageSize.width * relativeX
            imageY = imageSize.height * relativeY
        }

        return CGPoint(x: imageX, y: imageY)
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
    @Previewable @State var anchors: [MeasurementAnchor] = []
    @Previewable @State var isEditing = false
    let previewImage = UIImage(systemName: "photo")!

    ZoomableImageView(
        image: previewImage,
        imageSize: previewImage.size,
        rotation: 0,
        measurementAnchors: $anchors,
        isEditingAnchors: $isEditing,
        activeAnchorID: nil,
        onTap: { point in
            let anchor = MeasurementAnchor(
                position: point,
                measurementType: .totalLength
            )
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

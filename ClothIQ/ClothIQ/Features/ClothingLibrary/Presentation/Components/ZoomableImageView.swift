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

    /// 탭 위치를 이미지 좌표로 변환 (rotation 및 imagePadding 반영)
    private func convertTapLocation(_ location: CGPoint, in viewSize: CGSize) -> CGPoint {
        let scale = finalScale * currentScale
        let offset = CGSize(
            width: finalOffset.width + currentOffset.width,
            height: finalOffset.height + currentOffset.height
        )
        let converter = CoordinateConverter(imageSize: imageSize, rotation: rotation)
        return converter.viewToImage(location, in: viewSize, scale: scale, offset: offset, padding: imagePadding)
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

// MARK: - Coordinate Converter

/// 이미지 좌표계 ↔ 뷰 좌표계 변환기
///
/// rotation이 적용된 이미지의 좌표 변환을 중앙에서 관리합니다.
/// 저장 좌표계: SwiftUI 기준 (top-left origin, Y 증가 = 아래방향)
///
/// 정방향 변환 (imageToView) 공식 (nx = x/W, ny = y/H):
/// - 0°:   dx = nx,   dy = ny
/// - 90°:  dx = 1-ny, dy = nx
/// - 180°: dx = 1-nx, dy = 1-ny
/// - 270°: dx = ny,   dy = 1-nx
///
/// 역방향 변환 (viewToImage = imageToView의 역함수):
/// - 0°:   nx = dx,   ny = dy
/// - 90°:  nx = dy,   ny = 1-dx
/// - 180°: nx = 1-dx, ny = 1-dy
/// - 270°: nx = 1-dy, ny = dx
struct CoordinateConverter {

    // MARK: - Properties

    let imageSize: CGSize
    let rotation: Double

    private var normalizedRotation: Int {
        ((Int(rotation) % 360) + 360) % 360
    }

    private var isRotated90or270: Bool {
        normalizedRotation == 90 || normalizedRotation == 270
    }

    // MARK: - Private Helpers

    /// 표시 영역에서의 스케일된 이미지 크기와 원점을 계산합니다.
    private func scaledLayout(
        in viewSize: CGSize,
        scale: CGFloat,
        offset: CGSize,
        padding: CGFloat
    ) -> (size: CGSize, origin: CGPoint) {
        // padding을 고려한 실제 이미지 표시 가능 영역
        let availableSize = CGSize(
            width: viewSize.width - padding * 2,
            height: viewSize.height - padding * 2
        )

        // rotation 반영한 이미지 종횡비 (90°/270°이면 width/height 교환)
        let displayedWidth = isRotated90or270 ? imageSize.height : imageSize.width
        let displayedHeight = isRotated90or270 ? imageSize.width : imageSize.height
        let imageAspect = displayedWidth / displayedHeight
        let availableAspect = availableSize.width / availableSize.height

        let baseDisplaySize: CGSize
        if imageAspect > availableAspect {
            // 이미지가 더 넓음 → 너비 기준 fit
            baseDisplaySize = CGSize(
                width: availableSize.width,
                height: availableSize.width / imageAspect
            )
        } else {
            // 이미지가 더 높음 → 높이 기준 fit
            baseDisplaySize = CGSize(
                width: availableSize.height * imageAspect,
                height: availableSize.height
            )
        }

        let scaledSize = CGSize(
            width: baseDisplaySize.width * scale,
            height: baseDisplaySize.height * scale
        )

        let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let origin = CGPoint(
            x: center.x - scaledSize.width / 2 + offset.width,
            y: center.y - scaledSize.height / 2 + offset.height
        )

        return (scaledSize, origin)
    }

    // MARK: - Public Methods

    /// 이미지 좌표 → 뷰 좌표 변환 (정방향)
    ///
    /// - Parameters:
    ///   - point: 이미지 좌표 (원본 이미지 픽셀 기준, SwiftUI 좌표계)
    ///   - viewSize: 뷰의 크기
    ///   - scale: 확대/축소 배율
    ///   - offset: 패닝 오프셋
    ///   - padding: 이미지 여백 (기본값: 0)
    /// - Returns: 뷰 좌표
    func imageToView(
        _ point: CGPoint,
        in viewSize: CGSize,
        scale: CGFloat,
        offset: CGSize,
        padding: CGFloat = 0
    ) -> CGPoint {
        let (scaledSize, origin) = scaledLayout(in: viewSize, scale: scale, offset: offset, padding: padding)

        let nx = point.x / imageSize.width
        let ny = point.y / imageSize.height

        let dx: CGFloat
        let dy: CGFloat
        switch normalizedRotation {
        case 90:   // 시계방향 90°: dx = 1-ny, dy = nx
            dx = 1 - ny
            dy = nx
        case 180:  // 180°: dx = 1-nx, dy = 1-ny
            dx = 1 - nx
            dy = 1 - ny
        case 270:  // 시계방향 270°: dx = ny, dy = 1-nx
            dx = ny
            dy = 1 - nx
        default:   // 0°: dx = nx, dy = ny
            dx = nx
            dy = ny
        }

        return CGPoint(
            x: origin.x + dx * scaledSize.width,
            y: origin.y + dy * scaledSize.height
        )
    }

    /// 뷰 좌표 → 이미지 좌표 변환 (역방향, imageToView의 역함수)
    ///
    /// - Parameters:
    ///   - point: 뷰 좌표
    ///   - viewSize: 뷰의 크기
    ///   - scale: 확대/축소 배율
    ///   - offset: 패닝 오프셋
    ///   - padding: 이미지 여백 (기본값: 0)
    /// - Returns: 이미지 좌표 (원본 이미지 픽셀 기준, SwiftUI 좌표계)
    func viewToImage(
        _ point: CGPoint,
        in viewSize: CGSize,
        scale: CGFloat,
        offset: CGSize,
        padding: CGFloat = 0
    ) -> CGPoint {
        let (scaledSize, origin) = scaledLayout(in: viewSize, scale: scale, offset: offset, padding: padding)

        let dx = (point.x - origin.x) / scaledSize.width
        let dy = (point.y - origin.y) / scaledSize.height

        let nx: CGFloat
        let ny: CGFloat
        switch normalizedRotation {
        case 90:   // 역변환: nx = dy, ny = 1-dx
            nx = dy
            ny = 1 - dx
        case 180:  // 역변환: nx = 1-dx, ny = 1-dy
            nx = 1 - dx
            ny = 1 - dy
        case 270:  // 역변환: nx = 1-dy, ny = dx
            nx = 1 - dy
            ny = dx
        default:   // 0° 역변환: nx = dx, ny = dy
            nx = dx
            ny = dy
        }

        return CGPoint(
            x: nx * imageSize.width,
            y: ny * imageSize.height
        )
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
        GeometryReader { geometry in
            ZStack {
                // 투명한 배경으로 터치 통과
                Color.clear
                    .allowsHitTesting(false)

                if anchors.count == 2 {
                    // 드래그 중인 앵커는 draggingPosition(뷰 좌표)을 사용하여
                    // 원과 선 끝점이 정확히 일치하도록 함
                    let point1: CGPoint = {
                        if anchors[0].id == draggingAnchorID, let dragPos = draggingPosition {
                            return dragPos
                        }
                        return convertImageToViewCoordinates(anchors[0].position, in: geometry.size)
                    }()
                    let point2: CGPoint = {
                        if anchors[1].id == draggingAnchorID, let dragPos = draggingPosition {
                            return dragPos
                        }
                        return convertImageToViewCoordinates(anchors[1].position, in: geometry.size)
                    }()

                    Path { path in
                        path.move(to: point1)
                        path.addLine(to: point2)
                    }
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
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
            .allowsHitTesting(!anchors.isEmpty)  // anchors가 있을 때만 터치 활성화
        }
    }

    private func anchorLabel(for anchor: MeasurementAnchor) -> String {
        guard let index = anchors.firstIndex(where: { $0.id == anchor.id }) else { return "" }
        return "\(index + 1)"
    }

    private func convertImageToViewCoordinates(_ point: CGPoint, in viewSize: CGSize) -> CGPoint {
        let converter = CoordinateConverter(imageSize: imageSize, rotation: rotation)
        return converter.imageToView(point, in: viewSize, scale: scale, offset: offset, padding: padding)
    }

    private func convertViewToImageCoordinates(_ location: CGPoint, in viewSize: CGSize) -> CGPoint {
        let converter = CoordinateConverter(imageSize: imageSize, rotation: rotation)
        return converter.viewToImage(location, in: viewSize, scale: scale, offset: offset, padding: padding)
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

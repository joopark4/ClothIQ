//
//  PhotoMeasurementViewModel.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  사진 기반 측정 화면의 ViewModel입니다.
//  Depth map을 활용한 정확한 3D 거리 측정을 담당합니다.
//

import Foundation
import SwiftUI
import SwiftData
import CoreVideo
import Combine
import simd
import Vision

/// 사진 기반 측정 ViewModel
@MainActor
final class PhotoMeasurementViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 표시할 이미지
    @Published var image: UIImage

    /// 회전 각도 (도)
    @Published var rotationDegrees: CGFloat = 0

    /// 측정 포인트 앵커 (이미지 픽셀 좌표)
    @Published var measurementAnchors: [MeasurementAnchor] = []

    /// 앵커 업데이트 버전 (뷰 강제 새로고침용)
    @Published var anchorsVersion: Int = 0

    /// 현재 드래그 중인 포인트
    @Published var activeAnchorID: UUID?

    /// 앵커 편집 중 여부 (기본값 true: 측정 포인트 활성화)
    @Published var isEditingAnchors: Bool = true

    /// 선택된 측정 타입
    @Published var selectedMeasurementType: MeasurementType?

    /// 측정 결과 (임시)
    @Published var currentMeasurementResult: PhotoMeasurementCalculator.MeasurementResult?

    /// 에러 메시지
    @Published var errorMessage: String?

    /// 성공 메시지
    @Published var successMessage: String?

    /// 감지된 키포인트들
    @Published var detectedKeypoints: [MeasurementKeypoint] = []

    /// 키포인트 시각화 활성화
    @Published var showKeypoints: Bool = false

    /// 자동 측정 모드 활성화
    @Published var isAutoMeasurementMode: Bool = false

    /// ML 모드 활성화
    @Published var isMLModeEnabled: Bool = false

    /// ML 감지 진행 중
    @Published var isMLProcessing: Bool = false

    /// ML 모델 신뢰도
    @Published var mlConfidence: Float = 0.0

    /// 사용자가 앵커를 수정했는지 추적
    @Published var hasUserModifiedAnchors: Bool = false

    /// 학습 데이터 수집 활성화
    @Published var isCollectingTrainingData: Bool = true

    // MARK: - Dependencies

    let item: ClothingItemModel
    private let modelContext: ModelContext
    private let depthMap: CVPixelBuffer?
    private let originalImageSize: CGSize?
    private let processedImageSize: CGSize?
    private let cropRect: CGRect?
    private let cameraIntrinsics: simd_float3x3?
    private let cameraResolution: CGSize?

    // MARK: - Computed Properties

    /// 앵커 좌표 계산에 사용되는 실제 이미지 크기
    /// (저장/로드 시 사용하는 imageSize와 동일해야 함)
    var effectiveImageSize: CGSize {
        processedImageSize ?? image.size
    }

    // MARK: - Initialization

    init(item: ClothingItemModel, modelContext: ModelContext) {
        self.item = item
        self.modelContext = modelContext

        // 이미지 로드 및 orientation 정규화
        // 중요: JPEG orientation 메타데이터가 있으면 loadImage()가 회전된 이미지를 반환할 수 있으므로
        // 반드시 normalizedOrientation()을 호출하여 물리적으로 회전시킵니다.
        let loadedImage = item.loadImage() ?? UIImage()
        let resolvedImage = loadedImage.normalizedOrientation()

        let resolvedOriginalSize = item.originalImageSize
        let resolvedProcessedSize = item.processedImageSize ?? resolvedImage.size
        let resolvedCropRect = item.cropRect
        let resolvedIntrinsics = item.cameraIntrinsicsMatrix
        let resolvedCameraResolution = item.cameraResolutionSize

        self.image = resolvedImage
        self.originalImageSize = resolvedOriginalSize
        self.processedImageSize = resolvedProcessedSize
        self.cropRect = resolvedCropRect
        self.cameraIntrinsics = resolvedIntrinsics
        self.cameraResolution = resolvedCameraResolution

        print("🖼️ [PhotoMeasurementViewModel] 이미지 정규화 완료:")
        print("   - 로드된 이미지 크기: \(loadedImage.size) (orientation: \(loadedImage.imageOrientation.rawValue))")
        print("   - 정규화된 이미지 크기: \(resolvedImage.size) (orientation: \(resolvedImage.imageOrientation.rawValue))")
        print("   - processedImageSize: \(resolvedProcessedSize)")
        print("   - cropRect: \(String(describing: resolvedCropRect))")

        // Depth map 로드
        let loadedDepthMap: CVPixelBuffer?
        if let depthMapPath = item.depthMapPath {
            loadedDepthMap = DepthDataProcessor.loadDepthMap(from: depthMapPath)
        } else {
            loadedDepthMap = nil
        }
        self.depthMap = loadedDepthMap
    }

    // MARK: - Actions

    /// 이미지 회전 (90도씩)
    func rotateImage() {
        withAnimation(.easeInOut(duration: 0.3)) {
            rotationDegrees += 90
            if rotationDegrees >= 360 {
                rotationDegrees = 0
            }
        }

        // 측정 포인트 초기화
        measurementAnchors.removeAll()
        currentMeasurementResult = nil
    }

    /// 측정 포인트 추가
    func addMeasurementPoint(_ point: CGPoint) {
        print("🔵 [PhotoMeasurement] addMeasurementPoint 호출됨: \(point)")
        print("  - Depth map: \(depthMap != nil ? "있음" : "없음")")
        print("  - 선택된 측정 타입: \(selectedMeasurementType?.displayName ?? "없음")")

        guard let depthMap = depthMap else {
            print("❌ [PhotoMeasurement] Depth map이 없어서 실패")
            showError("Depth map이 없어 측정할 수 없습니다")
            return
        }

        guard selectedMeasurementType != nil else {
            print("❌ [PhotoMeasurement] 측정 타입이 선택되지 않아서 실패")
            showError("측정 항목을 먼저 선택해주세요")
            return
        }

        let depthImageSize = originalImageSize ?? CGSize(width: image.size.width, height: image.size.height)
        print("  - depthImageSize: \(depthImageSize)")
        print("  - image.size: \(image.size)")

        let clamped = clampedPosition(point)
        print("  - clamped: \(clamped)")

        let depthPoint = convertToOriginalImagePoint(clamped)
        print("  - depthPoint (original): \(depthPoint)")

        let isValid = PhotoMeasurementCalculator.isValidMeasurementPoint(
            depthPoint,
            depthMap: depthMap,
            imageSize: depthImageSize
        )
        print("  - isValid: \(isValid)")

        guard isValid else {
            print("❌ [PhotoMeasurement] 유효하지 않은 측정 포인트")
            showError("이 지점은 측정할 수 없습니다\n(Depth 데이터 없음)")
            return
        }

        // 2개 초과 시 초기화
        if measurementAnchors.count == 2, let activeID = activeAnchorID, let index = measurementAnchors.firstIndex(where: { $0.id == activeID }) {
            print("✏️ [PhotoMeasurement] 기존 앵커 업데이트 (index: \(index))")
            measurementAnchors[index].position = clamped
            anchorsVersion += 1  // 버전 증가
            print("🔢 [PhotoMeasurement] anchorsVersion 증가: \(anchorsVersion)")
            calculateDistance()
            return
        }

        if measurementAnchors.count >= 2 {
            print("🔄 [PhotoMeasurement] 2개 이상 - 초기화")
            measurementAnchors.removeAll()
            currentMeasurementResult = nil
            activeAnchorID = nil
            isEditingAnchors = false
            anchorsVersion += 1  // 버전 증가
            print("🔢 [PhotoMeasurement] anchorsVersion 증가 (초기화): \(anchorsVersion)")
        }

        let measurementType = selectedMeasurementType ?? .totalLength
        let anchor = MeasurementAnchor(
            position: clamped,
            measurementType: measurementType
        )
        measurementAnchors.append(anchor)
        activeAnchorID = anchor.id
        anchorsVersion += 1  // 버전 증가
        print("✅ [PhotoMeasurement] 앵커 추가됨 - 총 개수: \(measurementAnchors.count)")
        print("🔢 [PhotoMeasurement] anchorsVersion 증가: \(anchorsVersion)")

        // UI 업데이트 강제 트리거
        objectWillChange.send()

        if measurementAnchors.count == 2 {
            print("📏 [PhotoMeasurement] 2개 포인트 - 거리 계산 시작")
            calculateDistance()
        }
    }

    /// 거리 계산
    private func calculateDistance() {
        print("🔷 [calculateDistance] 시작")
        guard let depthMap = depthMap,
              measurementAnchors.count == 2 else {
            print("❌ [calculateDistance] 조건 미충족 - depthMap: \(depthMap != nil), anchors: \(measurementAnchors.count)")
            currentMeasurementResult = nil
            return
        }

        let imageSize = originalImageSize ?? CGSize(width: image.size.width, height: image.size.height)
        let point1 = convertToOriginalImagePoint(measurementAnchors[0].position)
        let point2 = convertToOriginalImagePoint(measurementAnchors[1].position)

        print("  - imageSize: \(imageSize)")
        print("  - point1: \(point1)")
        print("  - point2: \(point2)")
        print("  - cameraIntrinsics: \(cameraIntrinsics != nil ? "있음" : "없음")")
        print("  - cameraResolution: \(cameraResolution?.debugDescription ?? "없음")")

        // 교정 파라미터 준비
        let measurementType = selectedMeasurementType
        let clothingType = ClothingType(rawValue: item.type ?? "")

        print("  - measurementType: \(measurementType?.displayName ?? "없음")")
        print("  - clothingType: \(clothingType?.displayName ?? "없음")")

        guard let result = PhotoMeasurementCalculator.calculateDistance(
            from: point1,
            to: point2,
            depthMap: depthMap,
            imageSize: imageSize,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: measurementType,
            clothingType: clothingType
        ) else {
            print("❌ [calculateDistance] 거리 계산 실패")
            showError("거리 계산에 실패했습니다")
            return
        }

        // PhotoMeasurementCalculator 내부에서 이미 교정 적용됨
        let correctedDistance = result.distance

        // 보정된 거리로 결과 업데이트
        let correctedResult = PhotoMeasurementCalculator.MeasurementResult(
            distance: correctedDistance,
            confidence: result.confidence,
            point1Depth: result.point1Depth,
            point2Depth: result.point2Depth,
            distance3D: result.distance3D
        )
        currentMeasurementResult = correctedResult
        print("✅ [calculateDistance] 성공 - 거리: \(correctedDistance)cm, 신뢰도: \(result.confidence)")

        // 결과 표시
        let distanceText = String(format: "%.1f cm", correctedDistance)
        let confidenceText = String(format: "%.0f%%", result.confidence * 100)
        showSuccess("\(distanceText) (신뢰도: \(confidenceText))")
    }

    /// 측정값 저장
    func saveMeasurement() {
        guard let measurementType = selectedMeasurementType else {
            showError("측정 항목이 선택되지 않았습니다")
            return
        }

        guard let result = currentMeasurementResult else {
            showError("저장할 측정값이 없습니다")
            return
        }

        guard measurementAnchors.count == 2 else {
            showError("측정 포인트가 부족합니다")
            return
        }

        let normalizedStart = normalizeFinalImagePoint(measurementAnchors[0].position)
        let normalizedEnd = normalizeFinalImagePoint(measurementAnchors[1].position)

        print("💾 [saveMeasurement] 저장 시작:")
        print("  - type: \(measurementType.rawValue)")
        print("  - distance: \(result.distance)cm")
        print("  - confidence: \(result.confidence)")
        print("  - anchor[0]: \(measurementAnchors[0].position)")
        print("  - anchor[1]: \(measurementAnchors[1].position)")
        print("  - normalizedStart: \(normalizedStart)")
        print("  - normalizedEnd: \(normalizedEnd)")
        print("  - item.measurements 개수 (저장 전): \(item.measurements.count)")

        // 기존 측정값 확인
        if let existingMeasurement = item.measurements.first(where: { $0.type == measurementType.rawValue }) {
            // 업데이트
            existingMeasurement.value = result.distance
            existingMeasurement.confidence = result.confidence
            existingMeasurement.measuredAt = Date()
            existingMeasurement.startPointX = Double(normalizedStart.x)
            existingMeasurement.startPointY = Double(normalizedStart.y)
            existingMeasurement.endPointX = Double(normalizedEnd.x)
            existingMeasurement.endPointY = Double(normalizedEnd.y)
            print("  - 기존 측정값 업데이트 완료")
        } else {
            // 새로 추가
            let measurement = MeasurementModel(
                type: measurementType.rawValue,
                value: result.distance,
                unit: "cm",
                confidence: result.confidence,
                measuredAt: Date(),
                startPointX: Double(normalizedStart.x),
                startPointY: Double(normalizedStart.y),
                endPointX: Double(normalizedEnd.x),
                endPointY: Double(normalizedEnd.y)
            )
            item.measurements.append(measurement)
            measurement.clothingItem = item
            print("  - 새 측정값 추가 완료")
        }

        // 업데이트 시간 갱신
        item.updatedAt = Date()

        // 저장
        do {
            try modelContext.save()
            print("✅ [saveMeasurement] 저장 성공 - item.measurements 개수: \(item.measurements.count)")
            showSuccess("\(measurementType.displayName): \(String(format: "%.1f", result.distance))cm 저장됨")

            // 초기화 (다음 측정 준비)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.resetPoints()
                self.selectedMeasurementType = nil
            }
        } catch {
            print("❌ [saveMeasurement] 저장 실패: \(error)")
            showError("저장 실패: \(error.localizedDescription)")
        }
    }

    /// 포인트 초기화
    func resetPoints() {
        measurementAnchors.removeAll()
        currentMeasurementResult = nil
        activeAnchorID = nil
        isEditingAnchors = false
    }

    /// 기존 측정값을 편집용으로 로드
    func loadAnchors(for type: MeasurementType) {
        print("📂 [loadAnchors] 시작 - type: \(type.displayName)")
        measurementAnchors.removeAll()
        currentMeasurementResult = nil

        guard let existing = item.measurements.first(where: { $0.type == type.rawValue }) else {
            print("  - 기존 측정값 없음")
            activeAnchorID = nil
            isEditingAnchors = false
            return
        }

        let imageSize = processedImageSize ?? image.size
        print("  🔍🔍🔍 [loadAnchors] 이미지 크기 정보:")
        print("    - processedImageSize: \(processedImageSize?.debugDescription ?? "nil")")
        print("    - image.size: \(image.size)")
        print("    - 선택된 imageSize: \(imageSize)")

        // ⚠️ 크기 불일치 경고!
        if let savedSize = processedImageSize {
            let widthDiff = abs(savedSize.width - image.size.width)
            let heightDiff = abs(savedSize.height - image.size.height)
            if widthDiff > 1.0 || heightDiff > 1.0 {
                print("    ⚠️⚠️⚠️ 크기 불일치 감지!")
                print("    - 저장된 크기: \(savedSize)")
                print("    - 로드된 크기: \(image.size)")
                print("    - 차이: width=\(widthDiff), height=\(heightDiff)")
                print("    - 좌표 변환 오류 발생 가능!")
            }
        } else {
            print("    ⚠️ processedImageSize가 저장되지 않음! image.size 사용")
        }

        guard imageSize.width > 0, imageSize.height > 0 else {
            print("  ❌ 이미지 크기가 0")
            return
        }

        if let start = existing.startPoint, let end = existing.endPoint {
            print("  📍 [loadAnchors] 저장된 정규화 좌표 (크롭 이미지 기준):")
            print("    - start (정규화): \(start)")
            print("    - end (정규화): \(end)")
            print("    - 측정 타입: \(type.displayName)")

            // 정규화된 좌표 (0-1) → 픽셀 좌표 변환
            // SwiftUI 좌표계 (top-left origin) 기준으로 저장/로드
            let startPosition = CGPoint(
                x: start.x * imageSize.width,
                y: start.y * imageSize.height
            )
            let endPosition = CGPoint(
                x: end.x * imageSize.width,
                y: end.y * imageSize.height
            )

            print("  ✅ [loadAnchors] 복원된 픽셀 좌표 (SwiftUI - top-left origin):")
            print("    - startPosition: \(startPosition)")
            print("    - endPosition: \(endPosition)")
            print("    - 거리 (픽셀): \(hypot(endPosition.x - startPosition.x, endPosition.y - startPosition.y))")

            // 좌표 검증
            let isValid = startPosition.x >= 0 && startPosition.x <= imageSize.width &&
                         startPosition.y >= 0 && startPosition.y <= imageSize.height &&
                         endPosition.x >= 0 && endPosition.x <= imageSize.width &&
                         endPosition.y >= 0 && endPosition.y <= imageSize.height
            print("  - 좌표 유효성: \(isValid ? "✅ 유효" : "❌ 범위 벗어남")")

            let measurementType = selectedMeasurementType ?? .totalLength
            let startAnchor = MeasurementAnchor(
                position: startPosition,
                measurementType: measurementType
            )
            let endAnchor = MeasurementAnchor(
                position: endPosition,
                measurementType: measurementType
            )
            measurementAnchors = [startAnchor, endAnchor]
            activeAnchorID = endAnchor.id
            isEditingAnchors = false

            // anchorsVersion 증가로 UI 강제 업데이트
            anchorsVersion += 1
            print("  - 앵커 로드 완료 - anchorsVersion: \(anchorsVersion)")

            // UI 업데이트를 위한 명시적 트리거
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }

            calculateDistance()
        } else {
            print("  - startPoint 또는 endPoint가 nil")
            activeAnchorID = nil
            isEditingAnchors = false
        }
    }

    /// 포인트 위치 갱신
    func updateAnchorPosition(id: UUID, to newPosition: CGPoint, shouldRecalculate: Bool) {
        guard let index = measurementAnchors.firstIndex(where: { $0.id == id }) else {
            return
        }

        let clamped = clampedPosition(newPosition)

        measurementAnchors[index].position = clamped
        activeAnchorID = id

        // 사용자가 앵커를 수정했음을 추적
        hasUserModifiedAnchors = true

        if shouldRecalculate {
            calculateDistance()
        }
    }

    private func clampedPosition(_ point: CGPoint) -> CGPoint {
        let imageSize = processedImageSize ?? image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return point }
        let x = max(0, min(imageSize.width, point.x))
        let y = max(0, min(imageSize.height, point.y))
        return CGPoint(x: x, y: y)
    }

    /// 회전된 이미지 저장 확인
    func confirmSaveRotatedImage() -> Bool {
        return rotationDegrees != 0
    }

    private func convertToOriginalImagePoint(_ point: CGPoint) -> CGPoint {
        guard
            let cropRect = cropRect,
            let originalSize = originalImageSize
        else {
            return point
        }

        let processedSize = processedImageSize ?? image.size
        guard processedSize.width > 0, processedSize.height > 0 else {
            return point
        }

        let scaleX = cropRect.width / processedSize.width
        let scaleY = cropRect.height / processedSize.height

        let originalX = cropRect.origin.x + point.x * scaleX
        let originalY = cropRect.origin.y + point.y * scaleY

        return CGPoint(
            x: clamp(originalX, min: 0, max: originalSize.width),
            y: clamp(originalY, min: 0, max: originalSize.height)
        )
    }

    private func normalizeFinalImagePoint(_ point: CGPoint) -> CGPoint {
        let size = processedImageSize ?? image.size
        guard size.width > 0, size.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        // SwiftUI 픽셀 좌표 (top-left origin) → 정규화 좌표 (0~1)
        // loadAnchors, MeasurementLinesOverlay 모두 SwiftUI 좌표계 (top-left origin) 기준
        // Y축 반전하지 않음
        return CGPoint(
            x: clamp(point.x / size.width, min: 0, max: 1),
            y: clamp(point.y / size.height, min: 0, max: 1)
        )
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        max(minValue, min(value, maxValue))
    }

    /// 회전된 이미지 저장
    ///
    /// 이미지를 회전하여 저장하고, 저장된 측정 앵커 좌표도 함께 변환합니다.
    func saveRotatedImage() {
        guard rotationDegrees != 0 else { return }

        // 이미지 회전
        guard let rotatedImage = rotateUIImage(image, degrees: rotationDegrees) else {
            showError("이미지 회전 실패")
            return
        }

        // 기존 이미지 삭제
        if let imagePath = item.imagePath {
            try? ImageFileManager.shared.deleteImage(at: imagePath)
        }

        // 새 이미지 저장
        do {
            let newPath = try ImageFileManager.shared.saveImage(rotatedImage, quality: .high)
            item.imagePath = newPath

            // 저장된 측정 앵커 좌표를 회전 변환
            transformMeasurementCoordinates(byDegrees: rotationDegrees)

            item.updatedAt = Date()
            try modelContext.save()
        } catch {
            showError("이미지 저장 실패: \(error.localizedDescription)")
        }
    }

    /// 측정 앵커 좌표를 회전 변환합니다.
    ///
    /// 정규화된 좌표(0-1)에 대한 회전 변환:
    /// - 90° CW:  (x, y) → (1-y, x)
    /// - 180°:    (x, y) → (1-x, 1-y)
    /// - 270° CW: (x, y) → (y, 1-x)
    ///
    /// - Parameter degrees: 회전 각도 (도)
    private func transformMeasurementCoordinates(byDegrees degrees: CGFloat) {
        let normalizedDegrees = ((Int(degrees) % 360) + 360) % 360
        guard normalizedDegrees != 0 else { return }

        for measurement in item.measurements {
            if let sx = measurement.startPointX, let sy = measurement.startPointY {
                let (newX, newY) = rotateNormalizedPoint(x: sx, y: sy, degrees: normalizedDegrees)
                measurement.startPointX = newX
                measurement.startPointY = newY
            }
            if let ex = measurement.endPointX, let ey = measurement.endPointY {
                let (newX, newY) = rotateNormalizedPoint(x: ex, y: ey, degrees: normalizedDegrees)
                measurement.endPointX = newX
                measurement.endPointY = newY
            }
        }
    }

    /// 정규화된 좌표를 회전 변환합니다.
    ///
    /// - Parameters:
    ///   - x: 정규화된 X 좌표 (0-1)
    ///   - y: 정규화된 Y 좌표 (0-1)
    ///   - degrees: 회전 각도 (0, 90, 180, 270)
    /// - Returns: 변환된 (x, y) 좌표
    private func rotateNormalizedPoint(x: Double, y: Double, degrees: Int) -> (Double, Double) {
        switch degrees {
        case 90:
            return (1.0 - y, x)
        case 180:
            return (1.0 - x, 1.0 - y)
        case 270:
            return (y, 1.0 - x)
        default:
            return (x, y)
        }
    }

    // MARK: - Helpers

    private func showError(_ message: String) {
        errorMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.errorMessage = nil
        }
    }

    private func showSuccess(_ message: String) {
        successMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.successMessage = nil
        }
    }

    private func rotateUIImage(_ image: UIImage, degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180

        let rotatedSize = CGSize(
            width: abs(cos(radians)) * image.size.width + abs(sin(radians)) * image.size.height,
            height: abs(sin(radians)) * image.size.width + abs(cos(radians)) * image.size.height
        )

        let renderer = UIGraphicsImageRenderer(size: rotatedSize)
        return renderer.image { context in
            context.cgContext.translateBy(
                x: rotatedSize.width / 2,
                y: rotatedSize.height / 2
            )
            context.cgContext.rotate(by: radians)
            image.draw(in: CGRect(
                x: -image.size.width / 2,
                y: -image.size.height / 2,
                width: image.size.width,
                height: image.size.height
            ))
        }
    }

    // MARK: - Computed Properties

    /// 이미 측정된 항목들
    var existingMeasurementTypes: [String] {
        item.measurements.map { $0.type }
    }

    /// Depth map 사용 가능 여부
    var hasDepthMap: Bool {
        depthMap != nil
    }

    func existingMeasurementValue(for type: MeasurementType) -> Double? {
        item.measurements.first(where: { $0.type == type.rawValue })?.value
    }

    // MARK: - Keypoint Detection

    /// 키포인트 자동 감지 (ML 모드 지원)
    func detectKeypoints() {
        print("🎯 [PhotoMeasurement] 키포인트 자동 감지 시작 (ML 모드: \(isMLModeEnabled))")

        guard let depthMap = depthMap else {
            errorMessage = "Depth map이 없어 키포인트 감지가 불가능합니다"
            return
        }

        let clothingTypeString = item.type
        guard let clothingType = ClothingType(rawValue: clothingTypeString) else {
            errorMessage = "의류 타입을 확인할 수 없습니다"
            return
        }

        // 이미지를 CVPixelBuffer로 변환
        guard let pixelBuffer = image.pixelBuffer() else {
            errorMessage = "이미지 변환 실패"
            return
        }

        Task {
            do {
                var keypoints: [MeasurementKeypoint] = []

                if isMLModeEnabled {
                    // ML 모드: VisionMLService 사용
                    await MainActor.run {
                        isMLProcessing = true
                    }

                    let mlService = VisionMLService.shared

                    // 윤곽선 감지 (하이브리드 모드용)
                    let measurementService = AutoMeasurementService()
                    let contour = try? await measurementService.detectClothingContour(
                        from: pixelBuffer,
                        depthMap: depthMap
                    )

                    // 하이브리드 키포인트 감지 (ML + 휴리스틱)
                    keypoints = try await mlService.detectKeypointsHybrid(
                        from: image,
                        contour: contour,
                        clothingType: clothingType
                    )

                    // ML 신뢰도 계산
                    let avgConfidence = keypoints.isEmpty ? 0.0 :
                        keypoints.reduce(Float(0)) { $0 + $1.confidence } / Float(keypoints.count)

                    await MainActor.run {
                        self.mlConfidence = avgConfidence
                        isMLProcessing = false
                    }

                } else {
                    // 기존 휴리스틱 모드
                    let measurementService = AutoMeasurementService()

                    // 윤곽선 감지
                    guard let contour = try await measurementService.detectClothingContour(
                        from: pixelBuffer,
                        depthMap: depthMap
                    ) else {
                        await MainActor.run {
                            errorMessage = "의류 윤곽선을 감지할 수 없습니다"
                        }
                        return
                    }

                    // 특징점 추출
                    let featurePoints = measurementService.extractFeaturePoints(
                        from: contour,
                        clothingType: clothingType
                    )

                    // 키포인트 감지
                    let keypointDetector = ClothingKeypointDetector()
                    keypoints = keypointDetector.detectKeypoints(
                        from: contour,
                        clothingType: clothingType,
                        featurePoints: featurePoints
                    )
                }

                await MainActor.run {
                    self.detectedKeypoints = keypoints
                    self.showKeypoints = true
                    self.successMessage = "\(keypoints.count)개의 키포인트를 감지했습니다 (ML: \(isMLModeEnabled ? "ON" : "OFF"))"
                    print("✅ [PhotoMeasurement] 키포인트 감지 완료: \(keypoints.count)개")

                    // 키포인트를 앵커로 변환 (자동 측정 모드인 경우)
                    if isAutoMeasurementMode {
                        convertKeypointsToAnchors(keypoints, clothingType: clothingType)
                    }

                    // 학습 데이터 수집 (사용자가 수정하지 않은 자동 감지 결과)
                    if isMLModeEnabled {
                        collectTrainingData()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "키포인트 감지 실패: \(error.localizedDescription)"
                    isMLProcessing = false
                }
            }
        }
    }

    /// 키포인트를 측정 앵커로 변환
    private func convertKeypointsToAnchors(_ keypoints: [MeasurementKeypoint], clothingType: ClothingType) {
        print("🔄 [PhotoMeasurement] 키포인트를 측정 앵커로 변환")

        // 키포인트 쌍을 측정 라인으로 변환
        let keypointDetector = ClothingKeypointDetector()
        let measurementLines = keypointDetector.generateMeasurementLines(
            from: keypoints,
            clothingType: clothingType
        )

        // 측정 앵커 초기화
        measurementAnchors.removeAll()

        // 각 측정 라인을 앵커 쌍으로 추가
        for line in measurementLines {
            let startAnchor = MeasurementAnchor(
                position: CGPoint(
                    x: line.start.x * effectiveImageSize.width,
                    y: (1.0 - line.start.y) * effectiveImageSize.height  // Vision→SwiftUI Y축 반전
                ),
                measurementType: line.type
            )
            let endAnchor = MeasurementAnchor(
                position: CGPoint(
                    x: line.end.x * effectiveImageSize.width,
                    y: (1.0 - line.end.y) * effectiveImageSize.height  // Vision→SwiftUI Y축 반전
                ),
                measurementType: line.type
            )

            measurementAnchors.append(startAnchor)
            measurementAnchors.append(endAnchor)

            // 해당 측정 타입 선택
            selectedMeasurementType = line.type

            // 측정 수행 (depthMap이 있는 경우)
            if depthMap != nil {
                calculateDistance()
            }

            // 첫 번째 측정만 처리 (단일 측정 모드)
            break
        }

        anchorsVersion += 1
        print("✅ [PhotoMeasurement] 앵커 변환 완료: \(measurementAnchors.count)개 앵커")
    }

    /// 키포인트 표시 토글
    func toggleKeypointDisplay() {
        showKeypoints.toggle()
        if showKeypoints && detectedKeypoints.isEmpty {
            detectKeypoints()
        }
    }

    /// 자동 측정 모드 토글
    func toggleAutoMeasurementMode() {
        isAutoMeasurementMode.toggle()
        if isAutoMeasurementMode {
            detectKeypoints()
        }
    }

    /// ML 모드 토글
    func toggleMLMode() {
        isMLModeEnabled.toggle()
        successMessage = "ML 모드: \(isMLModeEnabled ? "활성화" : "비활성화")"

        if isMLModeEnabled && showKeypoints {
            // ML 모드 활성화 시 키포인트 재감지
            detectKeypoints()
        }
    }

    /// 학습 데이터 수집
    private func collectTrainingData() {
        let clothingTypeString = item.type
        guard let clothingType = ClothingType(rawValue: clothingTypeString) else {
            return
        }

        // 사용자 수정 여부 결정
        let isUserCorrected = hasUserModifiedAnchors

        // 키포인트 결정: 사용자가 수정한 경우 앵커를 키포인트로 변환
        var keypointsToCollect = detectedKeypoints
        if isUserCorrected && !measurementAnchors.isEmpty {
            let convertedKeypoints = convertAnchorsToKeypoints()
            if !convertedKeypoints.isEmpty {
                keypointsToCollect = convertedKeypoints
            }
        }

        // 학습 데이터 수집기 호출
        MLTrainingDataCollector.shared.collectTrainingData(
            image: image,
            keypoints: keypointsToCollect,
            clothingType: clothingType,
            isUserCorrected: isUserCorrected
        )

        print("📊 [PhotoMeasurement] 학습 데이터 수집 완료 (사용자 수정: \(isUserCorrected))")
    }

    /// 사용자가 앵커를 수정했을 때 호출
    func onUserModifiedAnchors() {
        // 사용자 수정 데이터를 학습 데이터로 수집
        if isMLModeEnabled && !measurementAnchors.isEmpty {
            // 앵커를 키포인트로 변환
            let modifiedKeypoints = convertAnchorsToKeypoints()
            if !modifiedKeypoints.isEmpty {
                detectedKeypoints = modifiedKeypoints
                hasUserModifiedAnchors = true
                collectTrainingData()
            }
        }
    }

    /// 앵커를 키포인트로 변환 (학습용)
    private func convertAnchorsToKeypoints() -> [MeasurementKeypoint] {
        guard let measurementType = selectedMeasurementType,
              measurementAnchors.count >= 2 else {
            return []
        }

        var keypoints: [MeasurementKeypoint] = []

        // 측정 타입에 따라 키포인트 타입 결정
        switch measurementType {
        case .shoulderWidth:
            if measurementAnchors.count >= 2 {
                keypoints.append(MeasurementKeypoint(
                    type: .leftShoulder,
                    position: CGPoint(
                        x: measurementAnchors[0].position.x / effectiveImageSize.width,
                        y: 1.0 - (measurementAnchors[0].position.y / effectiveImageSize.height)  // SwiftUI→Vision Y축 반전
                    ),
                    confidence: 1.0  // 사용자 수정이므로 신뢰도 최대
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .rightShoulder,
                    position: CGPoint(
                        x: measurementAnchors[1].position.x / effectiveImageSize.width,
                        y: 1.0 - (measurementAnchors[1].position.y / effectiveImageSize.height)  // SwiftUI→Vision Y축 반전
                    ),
                    confidence: 1.0
                ))
            }
        case .chestCircumference:
            if measurementAnchors.count >= 2 {
                keypoints.append(MeasurementKeypoint(
                    type: .chestLeft,
                    position: CGPoint(
                        x: measurementAnchors[0].position.x / effectiveImageSize.width,
                        y: 1.0 - (measurementAnchors[0].position.y / effectiveImageSize.height)  // SwiftUI→Vision Y축 반전
                    ),
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .chestRight,
                    position: CGPoint(
                        x: measurementAnchors[1].position.x / effectiveImageSize.width,
                        y: 1.0 - (measurementAnchors[1].position.y / effectiveImageSize.height)  // SwiftUI→Vision Y축 반전
                    ),
                    confidence: 1.0
                ))
            }
        case .totalLength:
            if measurementAnchors.count >= 2 {
                keypoints.append(MeasurementKeypoint(
                    type: .neckline,
                    position: CGPoint(
                        x: measurementAnchors[0].position.x / effectiveImageSize.width,
                        y: 1.0 - (measurementAnchors[0].position.y / effectiveImageSize.height)  // SwiftUI→Vision Y축 반전
                    ),
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .hemCenter,
                    position: CGPoint(
                        x: measurementAnchors[1].position.x / effectiveImageSize.width,
                        y: 1.0 - (measurementAnchors[1].position.y / effectiveImageSize.height)  // SwiftUI→Vision Y축 반전
                    ),
                    confidence: 1.0
                ))
            }
        default:
            break
        }

        return keypoints
    }

    /// 학습 데이터 통계 조회
    func getTrainingStatistics() -> TrainingDataStatistics {
        return MLTrainingDataCollector.shared.getTrainingDataStatistics()
    }
}

// MARK: - UIImage Extension

extension UIImage {
    /// UIImage를 CVPixelBuffer로 변환
    func pixelBuffer() -> CVPixelBuffer? {
        let width = Int(self.size.width)
        let height = Int(self.size.height)

        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          width,
                                          height,
                                          kCVPixelFormatType_32BGRA,
                                          attrs,
                                          &pixelBuffer)

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        }

        let pixelData = CVPixelBufferGetBaseAddress(buffer)

        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pixelData,
                                       width: width,
                                       height: height,
                                       bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: rgbColorSpace,
                                       bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            return nil
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)

        UIGraphicsPushContext(context)
        self.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()

        return buffer
    }
}

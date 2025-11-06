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

/// 사진 기반 측정 ViewModel
@MainActor
final class PhotoMeasurementViewModel: ObservableObject {

    struct MeasurementAnchor: Identifiable, Equatable {
        let id: UUID
        var position: CGPoint

        init(id: UUID = UUID(), position: CGPoint) {
            self.id = id
            self.position = position
        }
    }

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

    /// 앵커 편집 중 여부
    @Published var isEditingAnchors: Bool = false

    /// 선택된 측정 타입
    @Published var selectedMeasurementType: MeasurementType?

    /// 측정 결과 (임시)
    @Published var currentMeasurementResult: PhotoMeasurementCalculator.MeasurementResult?

    /// 에러 메시지
    @Published var errorMessage: String?

    /// 성공 메시지
    @Published var successMessage: String?

    // MARK: - Dependencies

    let item: ClothingItemModel
    private let modelContext: ModelContext
    private let depthMap: CVPixelBuffer?
    private let originalImageSize: CGSize?
    private let processedImageSize: CGSize?
    private let cropRect: CGRect?
    private let cameraIntrinsics: simd_float3x3?
    private let cameraResolution: CGSize?

    // MARK: - Initialization

    init(item: ClothingItemModel, modelContext: ModelContext) {
        self.item = item
        self.modelContext = modelContext

        let resolvedImage = item.loadImage() ?? UIImage()
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

        let anchor = MeasurementAnchor(position: clamped)
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

        guard let result = PhotoMeasurementCalculator.calculateDistance(
            from: point1,
            to: point2,
            depthMap: depthMap,
            imageSize: imageSize,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution
        ) else {
            print("❌ [calculateDistance] 거리 계산 실패")
            showError("거리 계산에 실패했습니다")
            return
        }

        // 교정 계수 적용
        let originalDistance = result.distance
        let correctedDistance: Double

        if let measurementType = selectedMeasurementType,
           let clothingType = ClothingType(rawValue: item.type ?? "") {
            correctedDistance = MeasurementSettings.shared.applyCorrectionFactor(
                type: measurementType,
                clothingType: clothingType,
                value: originalDistance
            )

            if MeasurementSettings.shared.useCalibration && correctedDistance != originalDistance {
                print("🔧 [calculateDistance] 교정 적용")
                print("  - 원본 측정값: \(String(format: "%.1f", originalDistance))cm")
                print("  - 보정 후 측정값: \(String(format: "%.1f", correctedDistance))cm")
                print("  - 보정 계수: \(String(format: "%.4f", correctedDistance / originalDistance))")
            } else {
                print("ℹ️ [calculateDistance] 교정 미적용 (useCalibration: \(MeasurementSettings.shared.useCalibration))")
            }
        } else {
            correctedDistance = originalDistance
            print("ℹ️ [calculateDistance] 교정 계수 없음")
        }

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
        }

        // 업데이트 시간 갱신
        item.updatedAt = Date()

        // 저장
        do {
            try modelContext.save()
            showSuccess("저장되었습니다")

            // 초기화 (다음 측정 준비)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.resetPoints()
                self.selectedMeasurementType = nil
            }
        } catch {
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
        print("  - imageSize: \(imageSize)")

        guard imageSize.width > 0, imageSize.height > 0 else {
            print("  - 이미지 크기가 0")
            return
        }

        if let start = existing.startPoint, let end = existing.endPoint {
            print("  - 저장된 정규화 좌표:")
            print("    - start: \(start)")
            print("    - end: \(end)")

            // 정규화된 좌표 → 픽셀 좌표 변환
            // 저장 시 Y축이 반전되었으므로 (1.0 - y), 로드 시 다시 반전 필요
            let startPosition = CGPoint(
                x: start.x * imageSize.width,
                y: (1.0 - start.y) * imageSize.height  // Y축 반전 복원
            )
            let endPosition = CGPoint(
                x: end.x * imageSize.width,
                y: (1.0 - end.y) * imageSize.height  // Y축 반전 복원
            )

            print("  - 복원된 픽셀 좌표:")
            print("    - startPosition: \(startPosition)")
            print("    - endPosition: \(endPosition)")

            let startAnchor = MeasurementAnchor(position: startPosition)
            let endAnchor = MeasurementAnchor(position: endPosition)
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

        // SwiftUI 좌표계 (top-left origin) → Vision 좌표계 (bottom-left origin) 변환
        // SwiftUI: y=0이 상단, y=height가 하단
        // Vision: y=0이 하단, y=1이 상단
        // 따라서 Y축 반전 필요: 1.0 - (y / height)
        return CGPoint(
            x: clamp(point.x / size.width, min: 0, max: 1),
            y: clamp(1.0 - (point.y / size.height), min: 0, max: 1)
        )
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        max(minValue, min(value, maxValue))
    }

    /// 회전된 이미지 저장
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
            item.updatedAt = Date()
            try modelContext.save()
        } catch {
            showError("이미지 저장 실패: \(error.localizedDescription)")
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
}

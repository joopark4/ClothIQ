//
//  PhotoMeasurementViewModel+Actions.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  PhotoMeasurementViewModel의 사용자 액션 메서드 확장입니다.
//  회전, 포인트 추가, 거리 계산, 저장 등을 담당합니다.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

// MARK: - User Actions

extension PhotoMeasurementViewModel {

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
    func calculateDistance() {
        print("🔷 [calculateDistance] 시작")
        guard let depthMap = depthMap,
              measurementAnchors.count == 2 else {
            print("❌ [calculateDistance] 조건 미충족 - depthMap: \(depthMap != nil), anchors: \(measurementAnchors.count)")
            currentMeasurementResult = nil
            return
        }

        let imageSize = originalImageSize ?? CGSize(width: image.size.width, height: image.size.height)
        let measurementType = selectedMeasurementType
        let clothingType = ClothingType(rawValue: item.type)
        let point1 = convertToOriginalImagePoint(measurementAnchors[0].position)
        let point2 = convertToOriginalImagePoint(measurementAnchors[1].position)

        print("  - imageSize: \(imageSize)")
        print("  - point1: \(point1)")
        print("  - point2: \(point2)")
        print("  - cameraIntrinsics: \(cameraIntrinsics != nil ? "있음" : "없음")")
        print("  - cameraResolution: \(cameraResolution?.debugDescription ?? "없음")")

        print("  - measurementType: \(measurementType?.displayName ?? "없음")")
        print("  - clothingType: \(clothingType?.displayName ?? "없음")")

        let result = PhotoMeasurementCalculator.calculateDistance(
            from: point1,
            to: point2,
            depthMap: depthMap,
            imageSize: imageSize,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: measurementType,
            clothingType: clothingType
        )

        guard let result else {
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

        let hadExistingMeasurement = item.measurements.contains { $0.type == measurementType.rawValue }
        item.upsertMeasurement(
            type: measurementType,
            value: result.distance,
            confidence: result.confidence,
            measuredAt: Date(),
            startPoint: normalizedStart,
            endPoint: normalizedEnd,
            method: .photo,
            modelContext: modelContext
        )
        print(hadExistingMeasurement ? "  - 기존 측정값 업데이트 완료" : "  - 새 측정값 추가 완료")

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

        guard let existing = item.measurement(for: type) else {
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

            let measurementType = selectedMeasurementType ?? type
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

    /// 회전된 이미지 저장 확인
    func confirmSaveRotatedImage() -> Bool {
        return rotationDegrees != 0
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

    // MARK: - Computed Properties

    /// 이미 측정된 항목들
    var existingMeasurementTypes: [String] {
        item.displayMeasurements.map { $0.type }
    }

    /// 사진 측정 화면 진입 시 우선 보여줄 기존 측정값
    var preferredInitialMeasurement: MeasurementModel? {
        item.displayMeasurements.max { lhs, rhs in
            lhs.measuredAt < rhs.measuredAt
        }
    }

    /// Depth map 사용 가능 여부
    var hasDepthMap: Bool {
        depthMap != nil
    }

    func existingMeasurement(for type: MeasurementType) -> MeasurementModel? {
        item.measurement(for: type)
    }

    func existingMeasurementValue(for type: MeasurementType) -> Double? {
        existingMeasurement(for: type)?.value
    }

    // MARK: - Internal Helpers

    func clampedPosition(_ point: CGPoint) -> CGPoint {
        let imageSize = processedImageSize ?? image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return point }
        let x = max(0, min(imageSize.width, point.x))
        let y = max(0, min(imageSize.height, point.y))
        return CGPoint(x: x, y: y)
    }

    func convertToOriginalImagePoint(_ point: CGPoint) -> CGPoint {
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
            x: clampValue(originalX, min: 0, max: originalSize.width),
            y: clampValue(originalY, min: 0, max: originalSize.height)
        )
    }

    func normalizeFinalImagePoint(_ point: CGPoint) -> CGPoint {
        let size = processedImageSize ?? image.size
        guard size.width > 0, size.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        // SwiftUI 픽셀 좌표 (top-left origin) → 정규화 좌표 (0~1)
        // loadAnchors, MeasurementLinesOverlay 모두 SwiftUI 좌표계 (top-left origin) 기준
        // Y축 반전하지 않음
        return CGPoint(
            x: clampValue(point.x / size.width, min: 0, max: 1),
            y: clampValue(point.y / size.height, min: 0, max: 1)
        )
    }

    func clampValue(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        max(minValue, min(value, maxValue))
    }

    func showError(_ message: String) {
        errorMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.errorMessage = nil
        }
    }

    func showSuccess(_ message: String) {
        successMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.successMessage = nil
        }
    }

    // MARK: - Private Helpers

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
}

//
//  MeasurementViewModel+DataPersistence.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  데이터 저장을 담당하는 extension입니다.
//
//  Key Responsibilities:
//  - SwiftData 저장
//  - 세션 초기화
//  - 좌표 변환 유틸리티
//

import Foundation
import ARKit
import SwiftData

// MARK: - SwiftData Save

extension MeasurementViewModelRefactored {

    /// 의류 타입 선택 후 즉시 저장
    ///
    /// - Parameters:
    ///   - clothingType: 저장할 의류 타입
    ///   - measurementsToSave: 저장할 측정 항목 목록 (nil이면 completedMeasurements 사용)
    /// - Returns: 저장 성공 여부
    @discardableResult
    func saveWithClothingType(
        _ clothingType: ClothingType,
        measurementsToSave: [CompletedMeasurement]? = nil
    ) -> Bool {
        guard let modelContext = modelContext else {
            showError("데이터 저장 환경이 준비되지 않았습니다")
            return false
        }

        guard let processedImage = processedImageToSave else {
            showError("저장할 이미지가 없습니다")
            return false
        }

        // 의류 타입 설정
        session.clothingType = clothingType

        // ClothingItemModel 생성
        let clothingItem = ClothingItemModel(
            type: clothingType.rawValue,
            imagePath: nil,
            notes: nil
        )

        // 이미지 저장
        do {
            let relativePath = try imageFileManager.saveImage(processedImage, quality: .high)
            clothingItem.imagePath = relativePath
        } catch {
            // 이미지 저장 실패해도 계속 진행
        }

        // Depth map 저장 (있는 경우)
        if let depthMap = capturedDepthMap {
            do {
                let depthFilename = clothingItem.id.uuidString
                let depthPath = try DepthDataProcessor.saveDepthMap(depthMap, filename: depthFilename)
                clothingItem.depthMapPath = depthPath
                print("✅ [ClothIQ-Save] Depth map 저장 성공: \(depthPath)")

                // 메모리 해제 (CVPixelBuffer는 큰 메모리 객체이므로 즉시 해제)
                self.capturedDepthMap = nil
            } catch {
                print("❌ [ClothIQ-Save] Depth map 저장 실패: \(error.localizedDescription)")
                // 저장 실패해도 메모리 해제
                self.capturedDepthMap = nil
            }
        } else {
            print("⚠️ [ClothIQ-Save] Depth map이 없어서 저장 건너뜀")
        }

        // 메타데이터 저장
        if let originalSize = capturedOriginalImageSize {
            clothingItem.originalImageWidth = Double(originalSize.width)
            clothingItem.originalImageHeight = Double(originalSize.height)
        }

        if let processedSize = capturedProcessedImageSize ?? processedImageToSave?.size {
            clothingItem.processedImageWidth = Double(processedSize.width)
            clothingItem.processedImageHeight = Double(processedSize.height)
        }

        if let cropRect = capturedCropRect {
            clothingItem.cropOriginX = Double(cropRect.origin.x)
            clothingItem.cropOriginY = Double(cropRect.origin.y)
            clothingItem.cropWidth = Double(cropRect.size.width)
            clothingItem.cropHeight = Double(cropRect.size.height)
        }

        if let intrinsics = capturedCameraIntrinsics {
            clothingItem.cameraIntrinsicsData = encodeIntrinsicsMatrix(intrinsics)
        }

        if let resolution = capturedCameraResolution {
            clothingItem.cameraResolutionWidth = Double(resolution.width)
            clothingItem.cameraResolutionHeight = Double(resolution.height)
        }

        // 측정값이 있다면 추가
        let measurements = measurementsToSave ?? completedMeasurements
        let coordinateContext = makeSavedMeasurementCoordinateContext(
            measurements: measurements,
            processedImage: processedImage
        )
        for completed in measurements {
            let normalizedPoints = coordinateContext.mapToNormalizedPair(for: completed)
            clothingItem.upsertMeasurement(
                type: completed.type,
                value: completed.distanceInCm,
                confidence: completed.confidence,
                startPoint: normalizedPoints?.start,
                endPoint: normalizedPoints?.end,
                method: completed.measurementMethod
            )
        }

        // SwiftData에 저장
        modelContext.insert(clothingItem)

        do {
            try modelContext.save()
            successMessage = "저장되었습니다"

            // 저장된 아이템 설정 (상세보기 화면 이동용)
            self.savedClothingItem = clothingItem

            // 메타데이터 정리
            self.capturedOriginalImageSize = nil
            self.capturedProcessedImageSize = nil
            self.capturedCropRect = nil
            self.capturedCameraIntrinsics = nil
            self.capturedCameraResolution = nil

            // 저장 후 정리
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.successMessage = nil
                self.processedImageToSave = nil
            }
            return true
        } catch {
            showError("저장에 실패했습니다: \(error.localizedDescription)")
            return false
        }
    }

    /// 측정 데이터를 SwiftData에 저장 (기존 메서드, 측정 완료 시 사용)
    func saveToSwiftData() {
        guard let modelContext = modelContext else {
            showError("데이터 저장 환경이 준비되지 않았습니다")
            return
        }

        guard let clothingType = session.clothingType else {
            showError("의류 타입이 선택되지 않았습니다")
            return
        }

        // ClothingItemModel 생성
        let clothingItem = ClothingItemModel(
            type: clothingType.rawValue,
            imagePath: nil,
            notes: nil
        )

        // 이미지 저장
        if let capturedImage = capturedImage {
            do {
                let relativePath = try imageFileManager.saveImage(capturedImage, quality: .high)
                clothingItem.imagePath = relativePath
            } catch {
                // 이미지 저장 실패해도 측정값은 저장 계속
            }
        }

        // Depth map 저장 (있는 경우)
        if let depthMap = capturedDepthMap {
            do {
                let depthFilename = clothingItem.id.uuidString
                let depthPath = try DepthDataProcessor.saveDepthMap(depthMap, filename: depthFilename)
                clothingItem.depthMapPath = depthPath

                // 메모리 해제 (CVPixelBuffer는 큰 메모리 객체이므로 즉시 해제)
                self.capturedDepthMap = nil
            } catch {
                // 저장 실패해도 메모리 해제
                self.capturedDepthMap = nil
            }
        }

        if let originalSize = capturedOriginalImageSize {
            clothingItem.originalImageWidth = Double(originalSize.width)
            clothingItem.originalImageHeight = Double(originalSize.height)
        }

        if let processedSize = capturedProcessedImageSize ?? processedImageToSave?.size {
            clothingItem.processedImageWidth = Double(processedSize.width)
            clothingItem.processedImageHeight = Double(processedSize.height)
        }

        if let cropRect = capturedCropRect {
            clothingItem.cropOriginX = Double(cropRect.origin.x)
            clothingItem.cropOriginY = Double(cropRect.origin.y)
            clothingItem.cropWidth = Double(cropRect.size.width)
            clothingItem.cropHeight = Double(cropRect.size.height)
        }

        if let intrinsics = capturedCameraIntrinsics {
            clothingItem.cameraIntrinsicsData = encodeIntrinsicsMatrix(intrinsics)
        }

        if let resolution = capturedCameraResolution {
            clothingItem.cameraResolutionWidth = Double(resolution.width)
            clothingItem.cameraResolutionHeight = Double(resolution.height)
        }

        // 측정값들을 MeasurementModel로 변환
        for (type, value) in session.measurements {
            clothingItem.upsertMeasurement(
                type: type,
                value: value,
                confidence: Double(overallConfidence),
                method: .ar
            )
        }

        // SwiftData에 저장
        modelContext.insert(clothingItem)

        do {
            try modelContext.save()
            showSuccess("의류 아이템이 저장되었습니다!")

            capturedOriginalImageSize = nil
            capturedProcessedImageSize = nil
            capturedCropRect = nil
            capturedCameraIntrinsics = nil
            capturedCameraResolution = nil

            // 저장 후 세션 초기화
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.resetSession()
            }
        } catch {
            showError("데이터 저장에 실패했습니다: \(error.localizedDescription)")
        }
    }

    /// 세션 초기화
    func resetSession() {
        session = MeasurementSession(clothingType: session.clothingType)
        measurementPoints.removeAll()
        completedMeasurements.removeAll()
        capturedImage = nil
        currentMeasurementType = session.clothingType?.requiredMeasurements.first
        capturedDepthMap = nil
        capturedOriginalImageSize = nil
        capturedProcessedImageSize = nil
        capturedCropRect = nil
        capturedCameraIntrinsics = nil
        capturedCameraResolution = nil
    }
}

// MARK: - Coordinate Utilities

extension MeasurementViewModelRefactored {

    private func makeSavedMeasurementCoordinateContext(
        measurements: [CompletedMeasurement],
        processedImage: UIImage
    ) -> SavedMeasurementCoordinateContext {
        let processedSize = capturedProcessedImageSize ?? processedImageToSave?.size ?? processedImage.size
        let originalSize = capturedOriginalImageSize ?? capturedCameraResolution ?? processedSize
        let cropRect = capturedCropRect ?? CGRect(origin: .zero, size: originalSize)
        let sourceSize = capturedCameraResolution ?? originalSize

        let allPoints = measurements.flatMap { [$0.startPoint.screenPosition, $0.endPoint.screenPosition] }
        let transform = SavedMeasurementCoordinateTransform.best(
            for: allPoints,
            sourceSize: sourceSize,
            originalSize: originalSize,
            cropRect: cropRect,
            processedSize: processedSize
        )

        return SavedMeasurementCoordinateContext(
            sourceSize: sourceSize,
            originalSize: originalSize,
            cropRect: cropRect,
            processedSize: processedSize,
            transform: transform
        )
    }

    private enum SavedMeasurementCoordinateTransform: CaseIterable {
        case direct
        case rotateRight
        case rotateLeft
        case rotate180

        static func best(
            for points: [CGPoint],
            sourceSize: CGSize,
            originalSize: CGSize,
            cropRect: CGRect,
            processedSize: CGSize
        ) -> SavedMeasurementCoordinateTransform {
            guard !points.isEmpty else { return .direct }
            var bestTransform: SavedMeasurementCoordinateTransform = .direct
            var bestScore = Int.min

            for transform in SavedMeasurementCoordinateTransform.allCases {
                let score = points.reduce(into: 0) { partialResult, point in
                    guard let mapped = transform.mapToProcessed(
                        point,
                        sourceSize: sourceSize,
                        originalSize: originalSize,
                        cropRect: cropRect,
                        processedSize: processedSize,
                        clampToBounds: false
                    ) else {
                        return
                    }
                    if mapped.x >= 0, mapped.y >= 0,
                       mapped.x <= processedSize.width, mapped.y <= processedSize.height {
                        partialResult += 1
                    }
                }

                if score > bestScore {
                    bestScore = score
                    bestTransform = transform
                }
            }
            return bestTransform
        }

        fileprivate func mapToProcessed(
            _ point: CGPoint,
            sourceSize: CGSize,
            originalSize: CGSize,
            cropRect: CGRect,
            processedSize: CGSize,
            clampToBounds: Bool
        ) -> CGPoint? {
            guard sourceSize.width > 0, sourceSize.height > 0,
                  originalSize.width > 0, originalSize.height > 0,
                  processedSize.width > 0, processedSize.height > 0 else {
                return nil
            }

            let normalized = normalizedPoint(point, sourceSize: sourceSize)
            let originalPoint = CGPoint(
                x: normalized.x * originalSize.width,
                y: normalized.y * originalSize.height
            )

            let validCropRect: CGRect = {
                if cropRect.width > 0, cropRect.height > 0 {
                    return cropRect
                }
                return CGRect(origin: .zero, size: originalSize)
            }()

            let scaleX = processedSize.width / max(validCropRect.width, 1)
            let scaleY = processedSize.height / max(validCropRect.height, 1)

            var mapped = CGPoint(
                x: (originalPoint.x - validCropRect.minX) * scaleX,
                y: (originalPoint.y - validCropRect.minY) * scaleY
            )

            if clampToBounds {
                mapped.x = Swift.max(0, Swift.min(mapped.x, processedSize.width))
                mapped.y = Swift.max(0, Swift.min(mapped.y, processedSize.height))
            }

            return mapped
        }

        private func normalizedPoint(_ point: CGPoint, sourceSize: CGSize) -> CGPoint {
            let x = point.x / sourceSize.width
            let y = point.y / sourceSize.height

            switch self {
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
    }

    private struct SavedMeasurementCoordinateContext {
        let sourceSize: CGSize
        let originalSize: CGSize
        let cropRect: CGRect
        let processedSize: CGSize
        let transform: SavedMeasurementCoordinateTransform

        func mapToNormalizedPair(for completed: CompletedMeasurement) -> (start: CGPoint, end: CGPoint)? {
            switch completed.coordinateSpace {
            case .cameraImagePixels:
                return mapCameraPixelsToNormalizedPair(
                    start: completed.startPoint.screenPosition,
                    end: completed.endPoint.screenPosition
                )

            case .processedImagePixels:
                return normalizeProcessedImagePixels(
                    start: completed.startPoint.screenPosition,
                    end: completed.endPoint.screenPosition
                )

            case .processedImageNormalized:
                let start = clampNormalized(completed.startPoint.screenPosition)
                let end = clampNormalized(completed.endPoint.screenPosition)
                return (start, end)
            }
        }

        func mapToNormalizedPair(start: CGPoint, end: CGPoint) -> (start: CGPoint, end: CGPoint)? {
            mapCameraPixelsToNormalizedPair(start: start, end: end)
        }

        private func mapCameraPixelsToNormalizedPair(start: CGPoint, end: CGPoint) -> (start: CGPoint, end: CGPoint)? {
            guard
                let mappedStart = transform.mapToProcessed(
                    start,
                    sourceSize: sourceSize,
                    originalSize: originalSize,
                    cropRect: cropRect,
                    processedSize: processedSize,
                    clampToBounds: true
                ),
                let mappedEnd = transform.mapToProcessed(
                    end,
                    sourceSize: sourceSize,
                    originalSize: originalSize,
                    cropRect: cropRect,
                    processedSize: processedSize,
                    clampToBounds: true
                ),
                processedSize.width > 0,
                processedSize.height > 0
            else {
                return nil
            }

            let normalizedStart = CGPoint(
                x: Swift.max(0, Swift.min(mappedStart.x / processedSize.width, 1)),
                y: Swift.max(0, Swift.min(mappedStart.y / processedSize.height, 1))
            )
            let normalizedEnd = CGPoint(
                x: Swift.max(0, Swift.min(mappedEnd.x / processedSize.width, 1)),
                y: Swift.max(0, Swift.min(mappedEnd.y / processedSize.height, 1))
            )
            return (normalizedStart, normalizedEnd)
        }

        private func normalizeProcessedImagePixels(start: CGPoint, end: CGPoint) -> (start: CGPoint, end: CGPoint)? {
            guard processedSize.width > 0, processedSize.height > 0 else {
                return nil
            }

            let normalizedStart = CGPoint(
                x: Swift.max(0, Swift.min(start.x / processedSize.width, 1)),
                y: Swift.max(0, Swift.min(start.y / processedSize.height, 1))
            )
            let normalizedEnd = CGPoint(
                x: Swift.max(0, Swift.min(end.x / processedSize.width, 1)),
                y: Swift.max(0, Swift.min(end.y / processedSize.height, 1))
            )
            return (normalizedStart, normalizedEnd)
        }

        private func clampNormalized(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: Swift.max(0, Swift.min(point.x, 1)),
                y: Swift.max(0, Swift.min(point.y, 1))
            )
        }
    }


    func encodeIntrinsicsMatrix(_ matrix: simd_float3x3) -> Data {
        var mutableMatrix = matrix
        return Data(bytes: &mutableMatrix, count: MemoryLayout<simd_float3x3>.size)
    }
}

//
//  PhotoMeasurementViewModel+Keypoint.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  PhotoMeasurementViewModel의 ML 키포인트 감지 및 변환 로직 확장입니다.
//

import Foundation
import SwiftUI
import CoreVideo
import Vision

// MARK: - Keypoint Detection

extension PhotoMeasurementViewModel {

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

                    // 저장된 배경 제거 이미지에서는 Vision contour가 배경/크롭 외곽을 잡는 경우가 있어
                    // 실제 전경 픽셀 기반 특징점을 우선 하이브리드 감지에 사용합니다.
                    let foregroundFeaturePoints = measurementService.extractForegroundFeaturePoints(
                        from: image,
                        clothingType: clothingType
                    )

                    // 하이브리드 키포인트 감지 (ML + 휴리스틱)
                    keypoints = try await mlService.detectKeypointsHybrid(
                        from: image,
                        contour: contour,
                        clothingType: clothingType,
                        featurePointsOverride: foregroundFeaturePoints
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
                    let contourFeaturePoints = measurementService.extractFeaturePoints(
                        from: contour,
                        clothingType: clothingType
                    )
                    let featurePoints = measurementService.extractForegroundFeaturePoints(
                        from: image,
                        clothingType: clothingType
                    ) ?? contourFeaturePoints

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

                    // 키포인트를 현재 측정 항목 앵커로 변환
                    if isAutoMeasurementMode ||
                        (measurementAnchors.isEmpty && selectedMeasurementType != nil) {
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

        if hasDepthMap {
            showKeypoints = true
            detectedKeypoints.removeAll()
            detectKeypoints()
        }
    }

    /// 사용자가 앵커를 수정했을 때 호출
    func onUserModifiedAnchors() {
        guard isCollectingTrainingData, !measurementAnchors.isEmpty else {
            return
        }

        let modifiedKeypoints = keypointsForCurrentAnchors()
        if !modifiedKeypoints.isEmpty {
            detectedKeypoints = modifiedKeypoints
            hasUserModifiedAnchors = true
            collectTrainingData()
        }
    }

    /// 학습 데이터 통계 조회
    func getTrainingStatistics() -> TrainingDataStatistics {
        return MLTrainingDataCollector.shared.getTrainingDataStatistics()
    }

    /// 기존 저장 앵커가 있더라도 하의 밑위/밑단은 최신 감지 라인으로 화면 앵커를 맞춥니다.
    func refreshDetectedAnchorsForCurrentSelectionIfNeeded() {
        guard
            let clothingType = item.clothingType,
            !detectedKeypoints.isEmpty,
            shouldPreferDetectedBottomAnchors(clothingType: clothingType)
        else {
            return
        }

        convertKeypointsToAnchors(detectedKeypoints, clothingType: clothingType)
    }

    // MARK: - Private Keypoint Helpers

    private func shouldPreferDetectedBottomAnchors(clothingType: ClothingType) -> Bool {
        guard clothingType.category == .bottom,
              let selectedMeasurementType,
              !hasUserModifiedAnchors else {
            return false
        }

        switch selectedMeasurementType {
        case .rise, .hem:
            return true
        default:
            return false
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

        let selectedLine: (type: MeasurementType, start: CGPoint, end: CGPoint)?
        if let selectedMeasurementType {
            guard let matchingLine = measurementLines.first(where: { $0.type == selectedMeasurementType }) else {
                errorMessage = "\(selectedMeasurementType.displayName) 키포인트를 찾을 수 없습니다"
                return
            }
            selectedLine = matchingLine
        } else {
            selectedLine = measurementLines.first
        }

        guard let line = selectedLine else {
            return
        }

        // 측정 앵커 초기화는 적용할 라인을 확인한 뒤에만 수행합니다.
        measurementAnchors.removeAll()

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

        anchorsVersion += 1
        print("✅ [PhotoMeasurement] 앵커 변환 완료: \(measurementAnchors.count)개 앵커")
    }

    /// 학습 데이터 수집
    private func collectTrainingData() {
        guard isCollectingTrainingData else {
            return
        }

        let clothingTypeString = item.type
        guard let clothingType = ClothingType(rawValue: clothingTypeString) else {
            return
        }

        // 사용자 수정 여부 결정
        let isUserCorrected = hasUserModifiedAnchors

        // 키포인트 결정: 사용자가 수정한 경우 앵커를 키포인트로 변환
        var keypointsToCollect = detectedKeypoints
        if isUserCorrected && !measurementAnchors.isEmpty {
            let convertedKeypoints = keypointsForCurrentAnchors()
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

    /// 앵커를 키포인트로 변환 (학습용)
    func keypointsForCurrentAnchors() -> [MeasurementKeypoint] {
        guard let measurementType = selectedMeasurementType,
              measurementAnchors.count >= 2 else {
            return []
        }

        var keypoints: [MeasurementKeypoint] = []
        let start = measurementAnchors[0].position
        let end = measurementAnchors[1].position

        func normalizedVisionPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x / effectiveImageSize.width,
                y: 1.0 - (point.y / effectiveImageSize.height)
            )
        }

        // 측정 타입에 따라 키포인트 타입 결정
        switch measurementType {
        case .shoulderWidth:
            if measurementAnchors.count >= 2 {
                keypoints.append(MeasurementKeypoint(
                    type: .leftShoulder,
                    position: normalizedVisionPoint(start),
                    confidence: 1.0  // 사용자 수정이므로 신뢰도 최대
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .rightShoulder,
                    position: normalizedVisionPoint(end),
                    confidence: 1.0
                ))
            }
        case .chestCircumference:
            if measurementAnchors.count >= 2 {
                keypoints.append(MeasurementKeypoint(
                    type: .chestLeft,
                    position: normalizedVisionPoint(start),
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .chestRight,
                    position: normalizedVisionPoint(end),
                    confidence: 1.0
                ))
            }
        case .totalLength:
            if measurementAnchors.count >= 2 {
                let startType: KeypointType = item.clothingType?.category == .bottom ? .waistLeft : .neckline
                keypoints.append(MeasurementKeypoint(
                    type: startType,
                    position: normalizedVisionPoint(start),
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .hemCenter,
                    position: normalizedVisionPoint(end),
                    confidence: 1.0
                ))
            }
        case .sleeveLength:
            if measurementAnchors.count >= 2 {
                keypoints.append(MeasurementKeypoint(
                    type: .leftShoulder,
                    position: normalizedVisionPoint(start),
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .leftSleeveEnd,
                    position: normalizedVisionPoint(end),
                    confidence: 1.0
                ))
            }
        case .armCircumference:
            if measurementAnchors.count >= 2 {
                keypoints.append(MeasurementKeypoint(
                    type: .leftSleeveEnd,
                    position: normalizedVisionPoint(start),
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .rightSleeveEnd,
                    position: normalizedVisionPoint(end),
                    confidence: 1.0
                ))
            }
        case .neckCircumference:
            if measurementAnchors.count >= 2 {
                let left = normalizedVisionPoint(start)
                let right = normalizedVisionPoint(end)
                keypoints.append(MeasurementKeypoint(
                    type: .leftShoulder,
                    position: left,
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .rightShoulder,
                    position: right,
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .neckline,
                    position: CGPoint(
                        x: (left.x + right.x) * 0.5,
                        y: (left.y + right.y) * 0.5
                    ),
                    confidence: 1.0
                ))
            }
        case .cuffCircumference:
            if measurementAnchors.count >= 2 {
                keypoints.append(MeasurementKeypoint(
                    type: .leftSleeveEnd,
                    position: normalizedVisionPoint(start),
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .rightSleeveEnd,
                    position: normalizedVisionPoint(end),
                    confidence: 1.0
                ))
            }
        case .waistCircumference:
            if measurementAnchors.count >= 2 {
                keypoints.append(MeasurementKeypoint(
                    type: .waistLeft,
                    position: normalizedVisionPoint(start),
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .waistRight,
                    position: normalizedVisionPoint(end),
                    confidence: 1.0
                ))
            }
        case .hipCircumference:
            if measurementAnchors.count >= 2 {
                keypoints.append(MeasurementKeypoint(
                    type: .hipLeft,
                    position: normalizedVisionPoint(start),
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .hipRight,
                    position: normalizedVisionPoint(end),
                    confidence: 1.0
                ))
            }
        case .rise:
            if measurementAnchors.count >= 2 {
                keypoints.append(MeasurementKeypoint(
                    type: .waistLeft,
                    position: normalizedVisionPoint(start),
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .crotch,
                    position: normalizedVisionPoint(end),
                    confidence: 1.0
                ))
            }
        case .hem:
            if measurementAnchors.count >= 2 {
                let left = normalizedVisionPoint(start)
                let right = normalizedVisionPoint(end)
                keypoints.append(MeasurementKeypoint(
                    type: .leftHem,
                    position: left,
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .rightHem,
                    position: right,
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .hemCenter,
                    position: CGPoint(
                        x: (left.x + right.x) * 0.5,
                        y: (left.y + right.y) * 0.5
                    ),
                    confidence: 1.0
                ))
            }
        case .thighCircumference:
            if measurementAnchors.count >= 2 {
                let left = normalizedVisionPoint(start)
                let right = normalizedVisionPoint(end)
                keypoints.append(MeasurementKeypoint(
                    type: .hipLeft,
                    position: left,
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .hipRight,
                    position: right,
                    confidence: 1.0
                ))
                keypoints.append(MeasurementKeypoint(
                    type: .crotch,
                    position: CGPoint(
                        x: (left.x + right.x) * 0.5,
                        y: (left.y + right.y) * 0.5
                    ),
                    confidence: 1.0
                ))
            }
        }

        return keypoints
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

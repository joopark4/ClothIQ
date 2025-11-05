//
//  MeasurementViewModel+DataPersistence.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  데이터 저장 및 자동 측정을 담당하는 extension입니다.
//
//  Key Responsibilities:
//  - SwiftData 저장
//  - 자동 측정 실행
//  - 측정 포인트 후보 처리
//  - 세션 초기화
//

import Foundation
import ARKit
import SwiftData

// MARK: - SwiftData Save

extension MeasurementViewModelRefactored {
    
    /// 의류 타입 선택 후 즉시 저장
    func saveWithClothingType(_ clothingType: ClothingType) {
        guard let modelContext = modelContext else {
            showError("데이터 저장 환경이 준비되지 않았습니다")
            return
        }

        guard let processedImage = processedImageToSave else {
            showError("저장할 이미지가 없습니다")
            return
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

                // 메모리 해제 (CVPixelBuffer는 큰 메모리 객체이므로 즉시 해제)
                self.capturedDepthMap = nil
            } catch {
                // 저장 실패해도 메모리 해제
                self.capturedDepthMap = nil
            }
        } else {
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

        // 측정값이 있다면 추가 (자동 측정이 성공한 경우)
        for (type, value) in session.measurements {
            // autoMeasurementResults에서 해당 타입의 좌표 찾기
            let resultWithCoords = autoMeasurementResults.first { $0.type == type }
            let startPoint = convertToProcessedNormalizedPoint(resultWithCoords?.startPoint)
            let endPoint = convertToProcessedNormalizedPoint(resultWithCoords?.endPoint)
            let measurement = MeasurementModel(
                type: type.rawValue,
                value: value,
                unit: "cm",
                confidence: Double(overallConfidence),
                startPointX: startPoint.map { Double($0.x) },
                startPointY: startPoint.map { Double($0.y) },
                endPointX: endPoint.map { Double($0.x) },
                endPointY: endPoint.map { Double($0.y) }
            )
            clothingItem.measurements.append(measurement)
            measurement.clothingItem = clothingItem
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
        } catch {
            showError("저장에 실패했습니다: \(error.localizedDescription)")
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
            let resultWithCoords = autoMeasurementResults.first { $0.type == type }
            let startPoint = convertToProcessedNormalizedPoint(resultWithCoords?.startPoint)
            let endPoint = convertToProcessedNormalizedPoint(resultWithCoords?.endPoint)
            let measurement = MeasurementModel(
                type: type.rawValue,
                value: value,
                unit: "cm",
                confidence: Double(overallConfidence),
                startPointX: startPoint.map { Double($0.x) },
                startPointY: startPoint.map { Double($0.y) },
                endPointX: endPoint.map { Double($0.x) },
                endPointY: endPoint.map { Double($0.y) }
            )
            clothingItem.measurements.append(measurement)
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
        capturedImage = nil
        currentMeasurementType = nil
        capturedDepthMap = nil
        capturedOriginalImageSize = nil
        capturedProcessedImageSize = nil
        capturedCropRect = nil
        capturedCameraIntrinsics = nil
        capturedCameraResolution = nil
    }
}

// MARK: - Auto Measurement

extension MeasurementViewModelRefactored {
    
    /// 자동 측정 실행
    ///
    /// Vision Framework를 사용하여 의류 윤곽선을 감지하고,
    /// 의류 타입에 맞는 측정 포인트를 자동으로 생성합니다.
    ///
    /// - Parameter frame: 현재 AR 프레임
    func performAutoMeasurement(from frame: ARFrame) {
        guard let clothingType = session.clothingType else {
            showError("의류 타입을 선택해주세요")
            return
        }

        isLoading = true
        autoMeasurementPreview = nil

        Task {
            do {
                // 1. 윤곽선 감지
                guard let contour = try await autoMeasurementService.detectClothingContour(
                    from: frame
                ) else {
                    await MainActor.run {
                        showError("의류 윤곽선을 감지할 수 없습니다. 의류를 평평하게 펼쳐주세요.")
                        isLoading = false
                    }
                    return
                }

                // 2. 특징점 추출
                let featurePoints = autoMeasurementService.extractFeaturePoints(from: contour)

                // 3. 측정 포인트 감지
                let candidates = autoMeasurementService.detectMeasurementPoints(
                    featurePoints: featurePoints,
                    contour: contour,
                    clothingType: clothingType
                )

                guard !candidates.isEmpty else {
                    await MainActor.run {
                        showError("측정 포인트를 찾을 수 없습니다.")
                        isLoading = false
                    }
                    return
                }

                // 4. 2D → 3D 변환 및 측정
                let measurements = try await processCandidates(candidates, frame: frame)

                // 5. 결과 저장
                await MainActor.run {
                    // 측정 결과 저장 (좌표 포함)
                    autoMeasurementResults = measurements

                    for measurement in measurements {
                        session.setMeasurement(measurement.value, for: measurement.type)
                    }

                    autoMeasurementPreview = candidates
                    showSuccess("자동 측정 완료! \(measurements.count)개 항목 측정됨")
                    isLoading = false
                }

            } catch let error as AutoMeasurementError {
                await MainActor.run {
                    showError(error.localizedDescription)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    showError("자동 측정 실패: \(error.localizedDescription)")
                    isLoading = false
                }
            }
        }
    }

    /// 측정 포인트 후보들을 처리하여 실제 측정값 계산
    func processCandidates(
        _ candidates: [MeasurementPointCandidate],
        frame: ARFrame
    ) async throws -> [MeasurementResult] {
        var measurements: [MeasurementResult] = []

        // 측정 타입별로 그룹화
        let grouped = Dictionary(grouping: candidates, by: { $0.type })

        for (type, group) in grouped {
            guard group.count >= 2 else {
                continue
            }

            // 각 후보를 3D 포인트로 변환
            var points3D: [MeasurementPoint] = []

            for candidate in group {
                // 정규화된 좌표를 뷰포트 좌표로 변환
                // AR 카메라의 실제 이미지 해상도 사용 (중요!)
                let imageResolution = frame.camera.imageResolution
                let viewportSize = CGSize(width: imageResolution.width, height: imageResolution.height)

                // Y 좌표 반전 제거 - ARKit은 이미지 좌표계 사용
                let screenX = candidate.screenPosition.x * viewportSize.width
                let screenY = candidate.screenPosition.y * viewportSize.height
                let screenPoint = CGPoint(x: screenX, y: screenY)

                if let point = try? measurementService.extractMeasurementPoint(
                    at: screenPoint,
                    from: frame
                ) {
                    points3D.append(point)
                }
            }

            guard points3D.count >= 2 else {
                continue
            }

            // 평균 신뢰도 계산 (미리)
            let avgConfidence = group.map { $0.confidence }.reduce(0, +) / Float(group.count)

            // AutoSize02.md: 평면 투영을 사용한 정확한 거리 계산 (카메라 기울기 보정)
            // depthMap과 카메라 정보 추출
            guard let depthMap = frame.sceneDepth?.depthMap else {
                let distance = simd_distance(points3D[0].worldPosition, points3D[1].worldPosition)
                let directValue = Double(distance) * 100.0

                // 평균 깊이 계산 (3D 포인트의 z 좌표 평균)
                let avgDepth = points3D.map { abs($0.worldPosition.z) }.reduce(0, +) / Float(points3D.count)

                // 둘레 타입이면 개선된 둘레 계산 알고리즘 사용
                let isCircumferenceType = [
                    MeasurementType.chestCircumference,
                    MeasurementType.waistCircumference,
                    MeasurementType.thighCircumference,
                    MeasurementType.armCircumference
                ].contains(type)

                let finalValue: Double
                if isCircumferenceType {
                    // MeasurementCalculator의 개선된 둘레 계산 메서드 사용
                    let circumference = MeasurementCalculator.calculateCircumferenceFromFront(
                        frontWidth: directValue,
                        depth: avgDepth,
                        type: type
                    )

                    // 깊이 기반 보정 계수 적용
                    let depthCorrection = MeasurementCalculator.depthCorrectionFactor(depth: avgDepth)
                    finalValue = circumference * depthCorrection
                } else {
                    // 둘레가 아닌 경우 직접 측정값 사용
                    finalValue = directValue
                }

                measurements.append(MeasurementResult(
                    type: type,
                    value: finalValue,
                    confidence: avgConfidence,
                    startPoint: nil,
                    endPoint: nil
                ))
                continue
            }

            let cameraTransform = frame.camera.transform
            let cameraIntrinsics = frame.camera.intrinsics

            // 거리 계산
            let value: Double
            switch type {
            case .shoulderWidth, .totalLength, .sleeveLength, .rise, .hem:
                // AutoSize02.md: 평면 투영 거리 사용 (카메라 기울기 보정)
                value = MeasurementCalculator.calculateDistanceOnPlane(
                    from: points3D[0],
                    to: points3D[1],
                    depthMap: depthMap,
                    cameraTransform: cameraTransform,
                    cameraIntrinsics: cameraIntrinsics
                )

            case .chestCircumference, .waistCircumference, .thighCircumference:
                // AutoSize02.md: 평면 투영된 폭 사용 (카메라 기울기 보정)
                let widthCm = MeasurementCalculator.calculateDistanceOnPlane(
                    from: points3D[0],
                    to: points3D[1],
                    depthMap: depthMap,
                    cameraTransform: cameraTransform,
                    cameraIntrinsics: cameraIntrinsics
                )

                // AutoSize02.md: 실제 측정값(허리 40cm)과 폭(0.333m)으로 보정 계수 역산
                // 40cm / 33.3cm = 1.2
                let circumferenceFactor: Double = {
                    switch type {
                    case .waistCircumference:
                        // 허리: 폭이 너무 좁으면 (< 10cm) 다른 계산 방식 사용
                        if widthCm < 10.0 {
                            // 폭이 좁을 때는 실제 둘레 40cm을 목표로 역산
                            // 40cm / widthCm
                            return min(20.0, 40.0 / widthCm)  // 최대 20배로 제한
                        }
                        // 정상 폭: 평평하게 놓인 반바지 (폭 × 2.0)
                        return 2.0
                    case .chestCircumference:
                        // 가슴: 상의는 더 둥글게 (폭 × 1.6)
                        return 1.6
                    case .thighCircumference:
                        // 허벅지: 바지의 허벅지 부분 (폭 × 1.4)
                        return 1.4
                    default:
                        return 1.5
                    }
                }()

                value = widthCm * circumferenceFactor

            default:
                continue
            }

            // 정규화된 좌표 저장 (원본 후보 좌표는 이미 0~1로 정규화됨)
            let startPoint = group.count > 0 ? group[0].screenPosition : nil
            let endPoint = group.count > 1 ? group[1].screenPosition : nil

            // MeasurementResult 생성 및 추가
            measurements.append(MeasurementResult(
                type: type,
                value: value,
                confidence: avgConfidence,
                startPoint: startPoint,
                endPoint: endPoint
            ))
        }

        return measurements
    }

    func convertToProcessedNormalizedPoint(_ point: CGPoint?) -> CGPoint? {
        guard let point = point else { return nil }
        guard
            let originalSize = capturedOriginalImageSize,
            let cropRect = capturedCropRect,
            cropRect.width > 0,
            cropRect.height > 0
        else {
            return point
        }

        let pixel = CGPoint(
            x: point.x * originalSize.width,
            y: point.y * originalSize.height
        )

        let adjusted = CGPoint(
            x: (pixel.x - cropRect.origin.x) / cropRect.width,
            y: (pixel.y - cropRect.origin.y) / cropRect.height
        )

        return CGPoint(
            x: clampNormalized(adjusted.x),
            y: clampNormalized(adjusted.y)
        )
    }

    func clampNormalized(_ value: CGFloat) -> CGFloat {
        return max(0, min(1, value))
    }

    func encodeIntrinsicsMatrix(_ matrix: simd_float3x3) -> Data {
        var mutableMatrix = matrix
        return Data(bytes: &mutableMatrix, count: MemoryLayout<simd_float3x3>.size)
    }
}

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
        for (type, value) in session.measurements {
            let measurement = MeasurementModel(
                type: type.rawValue,
                value: value,
                unit: "cm",
                confidence: Double(overallConfidence)
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
            let measurement = MeasurementModel(
                type: type.rawValue,
                value: value,
                unit: "cm",
                confidence: Double(overallConfidence)
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

// MARK: - Measurement Processing

extension MeasurementViewModelRefactored {

    /// 측정 포인트 후보들을 처리하여 실제 측정값 계산
    func processCandidates(
        _ candidates: [MeasurementPointCandidate],
        frame: ARFrame,
        clothingType: ClothingType,
        useTemporalFusion: Bool = true
    ) async throws -> [MeasurementResult] {
        if useTemporalFusion {
            let temporalFrames = await collectTemporalFrames(
                seedFrame: frame,
                targetCount: 6,
                intervalMs: 45
            )

            // 신규 프레임을 충분히 확보하지 못하면 기존 단일 프레임 경로로 fallback
            if temporalFrames.count >= 2 {
                print("⏱️ [TemporalFusion] 프레임 수집 완료: \(temporalFrames.count)프레임")

                var measurementsByType: [MeasurementType: [MeasurementResult]] = [:]

                for (frameIndex, sampledFrame) in temporalFrames.enumerated() {
                    let singleFrameResults = try await processCandidates(
                        candidates,
                        frame: sampledFrame,
                        clothingType: clothingType,
                        useTemporalFusion: false
                    )
                    print("  - [TemporalFusion] frame[\(frameIndex)] 결과: \(singleFrameResults.count)개")

                    for result in singleFrameResults {
                        measurementsByType[result.type, default: []].append(result)
                    }
                }

                var fusedResults: [MeasurementResult] = []
                for (type, results) in measurementsByType {
                    if let fused = fuseTemporalResults(type: type, results: results) {
                        fusedResults.append(fused)
                    }
                }

                print("✅ [TemporalFusion] 융합 완료: \(fusedResults.count)개 항목")
                return fusedResults
            } else {
                print("⚠️ [TemporalFusion] 프레임 부족(\(temporalFrames.count)개) → 단일 프레임 모드로 fallback")
            }
        }

        var measurements: [MeasurementResult] = []
        let cameraImageSize = frame.camera.imageResolution

        func clamp01(_ value: CGFloat) -> CGFloat {
            min(max(value, 0.0), 1.0)
        }

        // Vision 정규화 좌표(bottom-left) -> AR 카메라 픽셀 좌표(top-left)
        func toCameraPixelPoint(_ visionNormalizedPoint: CGPoint) -> CGPoint {
            let normalizedX = clamp01(visionNormalizedPoint.x)
            let normalizedY = clamp01(visionNormalizedPoint.y)
            return CGPoint(
                x: normalizedX * cameraImageSize.width,
                y: (1.0 - normalizedY) * cameraImageSize.height
            )
        }

        // 동일 측정 타입의 후보들 중 가장 신뢰도 높은 "쌍"을 선택
        // groupId를 우선 사용하고, 없으면 타입 내 상위 신뢰도 2개로 fallback
        func selectBestCandidatePair(
            from typeCandidates: [MeasurementPointCandidate]
        ) -> [MeasurementPointCandidate]? {
            let groupedByLine = Dictionary(grouping: typeCandidates, by: { $0.groupId })
            var bestPair: [MeasurementPointCandidate]?
            var bestScore: Float = -1

            for (_, lineCandidates) in groupedByLine {
                guard lineCandidates.count >= 2 else { continue }
                let pair = Array(lineCandidates.sorted(by: { $0.confidence > $1.confidence }).prefix(2))
                guard pair.count == 2 else { continue }

                let score = pair.map { $0.confidence }.reduce(0, +) / 2.0
                if score > bestScore {
                    bestScore = score
                    bestPair = pair
                }
            }

            if let bestPair {
                return bestPair
            }

            guard typeCandidates.count >= 2 else { return nil }
            return Array(typeCandidates.sorted(by: { $0.confidence > $1.confidence }).prefix(2))
        }

        print("🔍 [processCandidates] 시작 - 총 후보: \(candidates.count)개")

        // 측정 타입별로 그룹화
        let grouped = Dictionary(grouping: candidates, by: { $0.type })

        print("📊 [processCandidates] 타입별 후보 개수:")
        for (type, group) in grouped {
            print("  - \(type.displayName): \(group.count)개")
        }

        for (type, typeCandidates) in grouped {
            guard let selectedCandidates = selectBestCandidatePair(from: typeCandidates) else {
                print("⏭️ [processCandidates] \(type.displayName) 스킵 (후보 부족: \(typeCandidates.count)개 < 2개)")
                continue
            }

            print("✅ [processCandidates] \(type.displayName) 처리 시작 (전체 \(typeCandidates.count)개 후보 중 최적 쌍 선택)")

            // 각 후보를 3D 포인트로 변환
            var points3D: [MeasurementPoint] = []

            for (index, candidate) in selectedCandidates.enumerated() {
                let cameraPixelPoint = toCameraPixelPoint(candidate.screenPosition)

                print("  [후보 \(index+1)] 좌표 변환:")
                print("    - Vision 정규화 좌표: \(candidate.screenPosition)")
                print("    - AR 카메라 픽셀 좌표: \(cameraPixelPoint)")
                print("    - AR 카메라 해상도: \(cameraImageSize)")

                // ===== 3D 변환 에러 상세 로깅 =====
                do {
                    if let point = try measurementService.extractMeasurementPoint(
                        at: cameraPixelPoint,
                        from: frame
                    ) {
                        points3D.append(point)
                        print("    ✅ 3D 변환 성공 - worldPos: \(point.worldPosition)")
                    } else {
                        print("    ❌ 3D 변환 실패 - nil 반환")
                    }
                } catch {
                    print("    ❌ 3D 변환 실패 - 에러: \(error)")
                    print("    ❌ 에러 상세: \(error.localizedDescription)")
                }
            }

            print("📍 [processCandidates] \(type.displayName) 3D 변환 결과: \(points3D.count)/\(selectedCandidates.count)")

            // ===== Depth map fallback: LiDAR 측정 실패 시 depth map 직접 사용 =====
            guard points3D.count >= 2 else {
                print("⚠️ [processCandidates] LiDAR 측정 실패 → Depth map 기반 측정 시도")

                // Depth map 및 필요한 정보 추출
                guard let depthMap = frame.smoothedSceneDepth?.depthMap
                        ?? frame.sceneDepth?.depthMap
                        ?? capturedDepthMap,
                      selectedCandidates.count >= 2 else {
                    print("⏭️ [processCandidates] \(type.displayName) 스킵 (depth map 없음 또는 후보 부족)")
                    continue
                }

                let intrinsics = frame.camera.intrinsics
                let resolution = cameraImageSize

                // 첫 두 포인트로 거리 측정
                let candidate1 = selectedCandidates[0]
                let candidate2 = selectedCandidates[1]

                // Vision 정규화 좌표 -> 카메라 픽셀 좌표
                let point1 = toCameraPixelPoint(candidate1.screenPosition)
                let point2 = toCameraPixelPoint(candidate2.screenPosition)

                print("  📐 [DepthMapFallback] 측정 시도:")
                print("    - Point 1: \(point1)")
                print("    - Point 2: \(point2)")
                print("    - Image size: \(cameraImageSize)")

                // PhotoMeasurementCalculator로 거리 계산 (교정 계수 포함)
                if let result = PhotoMeasurementCalculator.calculateDistance(
                    from: point1,
                    to: point2,
                    depthMap: depthMap,
                    imageSize: cameraImageSize,
                    cameraIntrinsics: intrinsics,
                    cameraResolution: resolution,
                    measurementType: type,
                    clothingType: clothingType
                ) {
                    print("  ✅ [DepthMapFallback] 측정 성공!")
                    print("    - 거리: \(result.distance) cm")
                    print("    - 신뢰도: \(result.confidence)")

                    // 픽셀 좌표 → 정규화 좌표 (0~1) 변환
                    // Vision 좌표계 → SwiftUI 좌표계(top-left origin) 변환: Y축 반전
                    let normalizedStart = CGPoint(
                        x: point1.x / cameraImageSize.width,
                        y: 1.0 - (point1.y / cameraImageSize.height)  // Vision → SwiftUI Y축 반전
                    )
                    let normalizedEnd = CGPoint(
                        x: point2.x / cameraImageSize.width,
                        y: 1.0 - (point2.y / cameraImageSize.height)  // Vision → SwiftUI Y축 반전
                    )

                    guard MeasurementValidator.isValid(
                        measurementType: type,
                        value: result.distance,
                        for: clothingType
                    ) else {
                        print("  ❌ [DepthMapFallback] 범위 검증 실패: \(type.displayName)=\(result.distance)cm")
                        continue
                    }

                    let validatedConfidence = MeasurementValidator.evaluateConfidence(
                        measurementType: type,
                        value: result.distance,
                        lidarConfidence: result.confidence,
                        for: clothingType
                    )
                    let finalConfidence = Float((Double(result.confidence) + validatedConfidence) / 2.0)

                    print("    - 정규화 좌표 저장 (SwiftUI): start=\(normalizedStart), end=\(normalizedEnd)")

                    // MeasurementResult 생성
                    let measurement = MeasurementResult(
                        type: type,
                        value: result.distance,
                        confidence: finalConfidence,
                        startPoint: normalizedStart,
                        endPoint: normalizedEnd
                    )
                    measurements.append(measurement)
                    continue
                } else {
                    print("  ❌ [DepthMapFallback] 측정 실패 (depth 값 없음)")
                }

                print("⏭️ [processCandidates] \(type.displayName) 스킵 (모든 측정 방법 실패)")
                continue
            }

            // 평균 신뢰도 계산 (미리)
            let avgConfidence = selectedCandidates.map { $0.confidence }.reduce(0, +) / Float(selectedCandidates.count)

            // AutoSize02.md: 평면 투영을 사용한 정확한 거리 계산 (카메라 기울기 보정)
            // depthMap과 카메라 정보 추출
            guard let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap else {
                let distance = simd_distance(points3D[0].worldPosition, points3D[1].worldPosition)
                let directValue = Double(distance) * 100.0

                // 평균 깊이 계산 (3D 포인트의 z 좌표 평균)
                let avgDepth = points3D.map { abs($0.worldPosition.z) }.reduce(0, +) / Float(points3D.count)

                // 둘레 타입이면 개선된 둘레 계산 알고리즘 사용
                let isCircumferenceType = [
                    MeasurementType.chestCircumference,
                    MeasurementType.waistCircumference,
                    MeasurementType.thighCircumference,
                    MeasurementType.armCircumference,
                    MeasurementType.hipCircumference,
                    MeasurementType.neckCircumference,
                    MeasurementType.cuffCircumference
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

                guard MeasurementValidator.isValid(
                    measurementType: type,
                    value: finalValue,
                    for: clothingType
                ) else {
                    print("⏭️ [processCandidates] \(type.displayName) 스킵 (범위 검증 실패: \(finalValue)cm)")
                    continue
                }

                let validatedConfidence = MeasurementValidator.evaluateConfidence(
                    measurementType: type,
                    value: finalValue,
                    lidarConfidence: Double(avgConfidence),
                    for: clothingType
                )
                let finalConfidence = Float((Double(avgConfidence) + validatedConfidence) / 2.0)

                // 정규화된 좌표 저장 (SwiftUI 좌표계, 0~1 범위)
                // screenPosition은 Vision 좌표계(bottom-left)이므로 SwiftUI 좌표계(top-left)로 변환
                let startPoint: CGPoint? = selectedCandidates.count > 0 ? CGPoint(
                    x: selectedCandidates[0].screenPosition.x,
                    y: 1.0 - selectedCandidates[0].screenPosition.y  // Vision → SwiftUI Y축 반전
                ) : nil
                let endPoint: CGPoint? = selectedCandidates.count > 1 ? CGPoint(
                    x: selectedCandidates[1].screenPosition.x,
                    y: 1.0 - selectedCandidates[1].screenPosition.y  // Vision → SwiftUI Y축 반전
                ) : nil

                measurements.append(MeasurementResult(
                    type: type,
                    value: finalValue,
                    confidence: finalConfidence,
                    startPoint: startPoint,
                    endPoint: endPoint
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

            case .chestCircumference, .waistCircumference, .thighCircumference, .armCircumference, .hipCircumference, .neckCircumference, .cuffCircumference:
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
                    case .armCircumference:
                        // 팔둘레: 소매 부위는 허벅지보다 얇은 단면 (폭 × 1.3)
                        return 1.3
                    case .hipCircumference:
                        // 엉덩이둘레: 허벅지보다 큰 단면 (폭 × 1.8)
                        return 1.8
                    case .neckCircumference:
                        // 목둘레: 상대적으로 작은 원형 단면 (폭 × 1.3)
                        return 1.3
                    case .cuffCircumference:
                        // 소매단둘레: 팔둘레보다 작은 단면 (폭 × 1.2)
                        return 1.2
                    default:
                        return 1.5
                    }
                }()

                value = widthCm * circumferenceFactor

            default:
                continue
            }

            guard MeasurementValidator.isValid(
                measurementType: type,
                value: value,
                for: clothingType
            ) else {
                print("⏭️ [processCandidates] \(type.displayName) 스킵 (범위 검증 실패: \(value)cm)")
                continue
            }

            let validatedConfidence = MeasurementValidator.evaluateConfidence(
                measurementType: type,
                value: value,
                lidarConfidence: Double(avgConfidence),
                for: clothingType
            )
            let finalConfidence = Float((Double(avgConfidence) + validatedConfidence) / 2.0)

            // 정규화된 좌표 저장 (SwiftUI 좌표계, 0~1 범위)
            // screenPosition은 Vision 좌표계(bottom-left)이므로 SwiftUI 좌표계(top-left)로 변환
            let startPoint: CGPoint? = selectedCandidates.count > 0 ? CGPoint(
                x: selectedCandidates[0].screenPosition.x,
                y: 1.0 - selectedCandidates[0].screenPosition.y  // Vision → SwiftUI Y축 반전
            ) : nil
            let endPoint: CGPoint? = selectedCandidates.count > 1 ? CGPoint(
                x: selectedCandidates[1].screenPosition.x,
                y: 1.0 - selectedCandidates[1].screenPosition.y  // Vision → SwiftUI Y축 반전
            ) : nil

            // MeasurementResult 생성 및 추가
            measurements.append(MeasurementResult(
                type: type,
                value: value,
                confidence: finalConfidence,
                startPoint: startPoint,
                endPoint: endPoint
            ))
        }

        return measurements
    }

    /// 자동 측정 전용 시간축 프레임 수집
    ///
    /// seedFrame을 포함하여 최신 ARFrame을 주기적으로 읽어 targetCount만큼 수집합니다.
    /// timestamp가 증가한 프레임만 채택하여 동일 프레임 중복 수집을 방지합니다.
    private func collectTemporalFrames(
        seedFrame: ARFrame,
        targetCount: Int,
        intervalMs: UInt64
    ) async -> [ARFrame] {
        guard targetCount > 1 else { return [seedFrame] }

        var frames: [ARFrame] = [seedFrame]
        var lastAcceptedTimestamp = seedFrame.timestamp
        let minDelta: TimeInterval = 0.0001
        let sleepNs = max(intervalMs, 10) * 1_000_000
        let maxAttempts = max(targetCount * 10, 20)

        var attempts = 0
        while frames.count < targetCount && attempts < maxAttempts {
            attempts += 1
            try? await Task.sleep(nanoseconds: sleepNs)

            guard let latestFrame = currentARFrame else { continue }
            let timestamp = latestFrame.timestamp
            guard timestamp > lastAcceptedTimestamp + minDelta else { continue }

            frames.append(latestFrame)
            lastAcceptedTimestamp = timestamp
        }

        return frames
    }

    /// 시간축 융합: 단일 측정 타입 결과들을 강건하게 통합
    ///
    /// 1) median + MAD 기반 이상치 제거
    /// 2) confidence^2 가중 평균으로 최종 값 계산
    /// 3) 프레임 간 분산을 반영해 최종 confidence 재평가
    private func fuseTemporalResults(
        type: MeasurementType,
        results: [MeasurementResult]
    ) -> MeasurementResult? {
        guard !results.isEmpty else { return nil }
        guard results.count > 1 else { return results.first }

        let values = results.map { $0.value }
        let center = median(values)
        let absoluteDeviations = values.map { abs($0 - center) }
        let mad = median(absoluteDeviations)
        let outlierThreshold = max(1.5, mad * 2.5)

        let inliers = results.filter { abs($0.value - center) <= outlierThreshold }
        let filteredResults = inliers.isEmpty ? results : inliers

        let weighted: [(result: MeasurementResult, weight: Double)] = filteredResults.map { result in
            let confidenceWeight = max(0.05, Double(result.confidence))
            return (result, confidenceWeight * confidenceWeight)
        }

        let totalWeight = weighted.map { $0.weight }.reduce(0, +)
        guard totalWeight > 0 else { return filteredResults.max(by: { $0.confidence < $1.confidence }) }

        let fusedValue = weighted
            .map { $0.result.value * $0.weight }
            .reduce(0, +) / totalWeight

        let weightedConfidence = weighted
            .map { Double($0.result.confidence) * $0.weight }
            .reduce(0, +) / totalWeight

        let weightedVariance = weighted
            .map { pow($0.result.value - fusedValue, 2) * $0.weight }
            .reduce(0, +) / totalWeight
        let weightedStdDev = sqrt(max(0, weightedVariance))

        // 측정값 규모를 반영한 허용 표준편차 (최소 1.5cm)
        let allowedStdDev = max(1.5, fusedValue * 0.05)
        let stability = max(0.0, min(1.0, 1.0 - (weightedStdDev / allowedStdDev)))
        let fusedConfidence = Float(max(0.1, min(1.0, weightedConfidence * 0.8 + stability * 0.2)))

        let bestAnchoredResult = filteredResults.max(by: { $0.confidence < $1.confidence })

        return MeasurementResult(
            type: type,
            value: fusedValue,
            confidence: fusedConfidence,
            startPoint: bestAnchoredResult?.startPoint,
            endPoint: bestAnchoredResult?.endPoint
        )
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2.0
        } else {
            return sorted[middle]
        }
    }


    func encodeIntrinsicsMatrix(_ matrix: simd_float3x3) -> Data {
        var mutableMatrix = matrix
        return Data(bytes: &mutableMatrix, count: MemoryLayout<simd_float3x3>.size)
    }
}

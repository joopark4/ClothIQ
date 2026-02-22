//
//  AutoMeasurementService.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  자동 측정 서비스입니다.
//  Vision Framework를 활용하여 의류 윤곽선을 감지하고,
//  특징점을 추출하여 측정 포인트를 자동으로 생성합니다.
//
//  Key Responsibilities:
//  - 의류 윤곽선 자동 감지
//  - 특징점 추출 (최상단, 최하단, 좌우 끝 등)
//  - 측정 포인트 후보 생성
//

import Foundation
import Vision
import ARKit
import CoreImage
import simd

/// 자동 측정 서비스
final class AutoMeasurementService {

    // MARK: - Properties

    private let foregroundService = ForegroundSegmentationService()
    private let featureAnalyzer = ClothingFeatureAnalyzer()
    private let keypointDetector = ClothingKeypointDetector()

    // MARK: - Public Methods

    /// 키포인트 기반 자동 측정 수행 (개선된 버전)
    ///
    /// - Parameters:
    ///   - contour: 감지된 윤곽선
    ///   - clothingType: 의류 타입
    ///   - depthMap: Depth map
    ///   - imageSize: 이미지 크기
    ///   - cameraIntrinsics: 카메라 intrinsics (옵션)
    ///   - cameraResolution: 카메라 해상도 (옵션)
    /// - Returns: 자동 측정 결과 (측정 타입별 거리 맵)
    func performKeypointBasedMeasurement(
        contour: VNContoursObservation,
        clothingType: ClothingType,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?
    ) -> [MeasurementType: AutoMeasurementResult] {
        return autoreleasepool {
            print("🎯 [KeypointMeasurement] 키포인트 기반 자동 측정 시작")
            print("  - 의류 타입: \(clothingType.displayName)")
            print("  - 이미지 크기: \(imageSize)")

            // 1. 기본 특징점 추출
            let featurePoints = extractFeaturePoints(from: contour, clothingType: clothingType)
            print("  - 기본 특징점 추출 완료")

            // 2. 키포인트 감지
            var keypoints = keypointDetector.detectKeypoints(
                from: contour,
                clothingType: clothingType,
                featurePoints: featurePoints
            )
            print("  - 키포인트 감지 완료: \(keypoints.count)개")

            // 2.5 Depth 기반 주름 필터링
            keypoints = filterKeypointsByDepthConsistency(
                keypoints: keypoints,
                depthMap: depthMap,
                imageSize: imageSize
            )
            print("  - Depth 필터링 후: \(keypoints.count)개")

            // 3. 측정 라인 생성
            let measurementLines = keypointDetector.generateMeasurementLines(
                from: keypoints,
                clothingType: clothingType
            )
            print("  - 측정 라인 생성 완료: \(measurementLines.count)개")

            // 4. 각 라인에 대한 거리 측정
            var measurements: [MeasurementType: AutoMeasurementResult] = [:]

            for line in measurementLines {
                if let result = measureDistance(
                    from: line.start,
                    to: line.end,
                    depthMap: depthMap,
                    imageSize: imageSize,
                    confidence: 0.8,
                    cameraIntrinsics: cameraIntrinsics,
                    cameraResolution: cameraResolution,
                    measurementType: line.type,
                    clothingType: clothingType
                ) {
                    measurements[line.type] = result
                    print("  - \(line.type.displayName): \(String(format: "%.1f", result.distance))cm")
                }
            }

            print("✅ [KeypointMeasurement] 키포인트 기반 자동 측정 완료: \(measurements.count)개 항목")
            return measurements
        }
    }

    /// 윤곽선 기반 자동 측정 수행
    ///
    /// - Parameters:
    ///   - contour: 감지된 윤곽선
    ///   - clothingType: 의류 타입
    ///   - depthMap: Depth map
    ///   - imageSize: 이미지 크기
    ///   - cameraIntrinsics: 카메라 intrinsics (옵션)
    ///   - cameraResolution: 카메라 해상도 (옵션)
    /// - Returns: 자동 측정 결과 (측정 타입별 거리 맵)
    func performAutoMeasurement(
        contour: VNContoursObservation,
        clothingType: ClothingType,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?
    ) -> [MeasurementType: AutoMeasurementResult] {
        // LiDAR_SIZE_Ref.md: autoreleasepool을 사용한 메모리 관리
        return autoreleasepool {
            print("🤖 [AutoMeasurement] 자동 측정 시작")
            print("  - 의류 타입: \(clothingType.displayName)")
            print("  - 이미지 크기: \(imageSize)")

            // 1. 특징점 추출
            let featurePoints = extractFeaturePoints(from: contour, clothingType: clothingType)
            print("  - 특징점 추출 완료")

            // 2. 의류 타입별 측정 항목 추출
            let measurements = extractMeasurementsForClothingType(
                featurePoints: featurePoints,
                clothingType: clothingType,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution
            )

            print("✅ [AutoMeasurement] 자동 측정 완료: \(measurements.count)개 항목")
            return measurements
        }
    }

    // MARK: - Public Methods

    /// 의류 윤곽선 감지
    ///
    /// - Parameters:
    ///   - capturedImage: 캡처된 이미지
    ///   - depthMap: LiDAR depth map (선택)
    /// - Returns: 감지된 윤곽선, 없으면 nil
    func detectClothingContour(
        from capturedImage: CVPixelBuffer,
        depthMap: CVPixelBuffer?
    ) async throws -> VNContoursObservation? {
        print("🔍 [윤곽선 감지 시작]")

        // 1. 전경 마스크 생성 (검증 용도)
        guard let foregroundMask = foregroundService.generateForegroundMask(
            from: capturedImage,
            depthMap: depthMap
        ) else {
            print("❌ 전경 마스크 생성 실패")
            throw AutoMeasurementError.foregroundSegmentationFailed
        }

        print("✅ 전경 마스크 생성 성공")

        // 2. 원본 이미지에서 직접 윤곽선 감지 (중요!)
        let contour = try await detectContourFromOriginal(capturedImage)

        if contour == nil {
            print("⚠️ 원본에서 윤곽선 감지 실패, 마스크에서 재시도")
            // 대체 경로: 마스크에서 윤곽선 추출 시도
            return try await detectContour(from: foregroundMask)
        }

        // 3. 윤곽선 기반 특징 분석 (디버깅/로깅용)
        if let contour = contour {
            print("✅ 윤곽선 감지 성공, 특징 분석 시작")

            let features = featureAnalyzer.extractFeatures(from: contour)
            let detectedType = featureAnalyzer.detectClothingCategory(from: features)

            let sleeveTypeStr: String = {
                switch features.sleeveDetection.sleeveType {
                case .none: return "없음"
                case .short: return "반팔"
                case .long: return "긴팔"
                }
            }()

            print("📊 [ClothIQ-Contour] 윤곽 기반 분석 결과:")
            print("  - 감지된 타입: \(detectedType.displayName)")
            print("  - 종횡비: \(String(format: "%.2f", features.aspectRatio))")
            print("  - 소매: \(features.sleeveDetection.hasSleeves ? "있음" : "없음") (\(sleeveTypeStr))")
            print("  - 밑단: \(features.hemlineShape.isVShaped ? "V자형" : "평평")")
            print("  - 상단: \(features.topRegionShape.isNarrow ? "좁음(목선)" : features.topRegionShape.isWide ? "넓음(허리)" : "중간")")
            print("  - 신뢰도: \(String(format: "%.1f%%", features.confidence * 100))")
        } else {
            print("❌ 윤곽선 감지 실패")
        }

        return contour
    }

    /// 원본 이미지에서 윤곽선 감지
    private func detectContourFromOriginal(_ pixelBuffer: CVPixelBuffer) async throws -> VNContoursObservation? {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectContoursRequest { request, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }

                guard let results = request.results as? [VNContoursObservation],
                      !results.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                // 가장 큰 윤곽선 선택
                let largestContour = results.max(by: { $0.contourCount < $1.contourCount })
                continuation.resume(returning: largestContour)
            }

            // 원본 이미지용 파라미터 설정
            request.contrastAdjustment = 2.0  // 대비 더 강화해서 노이즈 감소
            request.detectsDarkOnLight = true  // 밝은 배경에 어두운 의류
            request.maximumImageDimension = 512  // 해상도 낮춰서 노이즈 감소 (512)
            request.contrastPivot = 0.5  // 대비 중심점

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// 윤곽선에서 특징점 추출
    ///
    /// - Parameters:
    ///   - contour: 윤곽선
    ///   - clothingType: 의류 타입 (템플릿 선택용)
    /// - Returns: 추출된 특징점
    func extractFeaturePoints(from contour: VNContoursObservation, clothingType: ClothingType) -> ClothingFeaturePoints {
        // AutoSize02.md: boundingBox 면적 기준으로 최대 윤곽 선택
        var bestContour: VNContour?
        var bestArea: CGFloat = 0

        for i in 0..<contour.contourCount {
            if let childContour = try? contour.contour(at: i) {
                let points = childContour.normalizedPath.points()

                // 포인트가 너무 적으면 노이즈
                guard points.count >= 8 else {
                    continue
                }

                // 윤곽선의 바운딩 박스 계산
                let minX = points.map { $0.x }.min() ?? 0
                let maxX = points.map { $0.x }.max() ?? 1
                let minY = points.map { $0.y }.min() ?? 0
                let maxY = points.map { $0.y }.max() ?? 1

                let width = maxX - minX
                let height = maxY - minY
                let area = width * height

                // 너무 작은 윤곽선 제외 (면적 기준)
                if area < 0.02 {  // 2% 미만
                    continue
                }

                // AutoSize02.md: 면적 기준으로 최대 윤곽 선택
                // 의류가 이미지를 거의 채울 수 있으므로 높이 100% 조건 제거
                if area > bestArea {
                    bestArea = area
                    bestContour = childContour
                }
            }
        }

        guard let selectedContour = bestContour else {
            return ClothingFeaturePoints(
                topPoint: CGPoint(x: 0.5, y: 1.0),
                bottomPoint: CGPoint(x: 0.5, y: 0.0),
                leftmostPoint: CGPoint(x: 0.0, y: 0.5),
                rightmostPoint: CGPoint(x: 1.0, y: 0.5),
                allPoints: []
            )
        }

        // 선택된 윤곽선의 포인트 추출
        let normalizedPoints = selectedContour.normalizedPath.points()

        guard !normalizedPoints.isEmpty else {
            return ClothingFeaturePoints(
                topPoint: CGPoint(x: 0.5, y: 1.0),
                bottomPoint: CGPoint(x: 0.5, y: 0.0),
                leftmostPoint: CGPoint(x: 0.0, y: 0.5),
                rightmostPoint: CGPoint(x: 1.0, y: 0.5),
                allPoints: []
            )
        }

        // 극값 찾기
        let topPoint = normalizedPoints.max(by: { $0.y < $1.y }) ?? CGPoint(x: 0.5, y: 1.0)
        let bottomPoint = normalizedPoints.min(by: { $0.y < $1.y }) ?? CGPoint(x: 0.5, y: 0.0)
        let leftmostPoint = normalizedPoints.min(by: { $0.x < $1.x }) ?? CGPoint(x: 0.0, y: 0.5)
        let rightmostPoint = normalizedPoints.max(by: { $0.x < $1.x }) ?? CGPoint(x: 1.0, y: 0.5)

        // 템플릿 기반 특징점 생성 (종횡비에 따라 자동 템플릿 선택)
        return ClothingFeaturePoints.withTemplate(
            topPoint: topPoint,
            bottomPoint: bottomPoint,
            leftmostPoint: leftmostPoint,
            rightmostPoint: rightmostPoint,
            allPoints: normalizedPoints,
            clothingType: clothingType
        )
    }

    /// 측정 포인트 감지
    ///
    /// - Parameters:
    ///   - featurePoints: 특징점
    ///   - contour: 윤곽선
    ///   - clothingType: 의류 타입
    /// - Returns: 감지된 측정 포인트 후보들
    func detectMeasurementPoints(
        featurePoints: ClothingFeaturePoints,
        contour: VNContoursObservation,
        clothingType: ClothingType
    ) -> [MeasurementPointCandidate] {
        let detector = createDetector(for: clothingType)
        var candidates = detector.detectPoints(
            featurePoints: featurePoints,
            contour: contour
        )

        // 카메라 기반 키포인트 라인 후보를 추가로 결합
        let keypointCandidates = generateCandidatesFromKeypoints(
            contour: contour,
            featurePoints: featurePoints,
            clothingType: clothingType
        )
        candidates.append(contentsOf: keypointCandidates)

        return candidates
    }

    // MARK: - Private Methods

    /// 마스크에서 윤곽선 감지
    private func detectContour(from mask: CVPixelBuffer) async throws -> VNContoursObservation? {
        return try await withCheckedThrowingContinuation { continuation in
            // CIImage로 변환
            let ciImage = CIImage(cvPixelBuffer: mask)

            // 윤곽선 감지 요청
            let request = VNDetectContoursRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNContoursObservation] else {
                    continuation.resume(throwing: AutoMeasurementError.noContourDetected)
                    return
                }

                guard let largestContour = results.max(by: { $0.contourCount < $1.contourCount }) else {
                    continuation.resume(throwing: AutoMeasurementError.noContourDetected)
                    return
                }

                continuation.resume(returning: largestContour)
            }

            // 윤곽선 감지 파라미터 설정
            request.contrastAdjustment = 1.0  // 대비 조정
            request.detectsDarkOnLight = true  // 밝은 배경(테이블, 바닥)에 어두운 객체(의류)

            // 요청 실행
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// 의류 타입에 맞는 감지기 생성
    private func createDetector(for type: ClothingType) -> MeasurementPointDetector {
        switch type {
        case .shortSleeve, .longSleeve, .shirt, .polo, .hoodie, .vest, .cardigan:
            return TopMeasurementDetector()
        case .pants, .shorts, .jeans, .leggings:
            return BottomMeasurementDetector()
        case .skirt:
            return SkirtMeasurementDetector()
        case .jacket, .coat:
            return TopMeasurementDetector()  // 아우터도 상의 감지기 사용
        case .dress, .jumpsuit:
            return TopMeasurementDetector()  // 원피스류는 상의 감지기로 시작
        }
    }

    /// 키포인트 감지 결과(측정 라인)를 MeasurementPointCandidate로 변환
    private func generateCandidatesFromKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints,
        clothingType: ClothingType
    ) -> [MeasurementPointCandidate] {
        let keypoints = keypointDetector.detectKeypoints(
            from: contour,
            clothingType: clothingType,
            featurePoints: featurePoints
        )
        let lines = keypointDetector.generateMeasurementLines(
            from: keypoints,
            clothingType: clothingType
        )

        guard !lines.isEmpty else { return [] }

        // 동일 좌표의 키포인트 신뢰도를 lookup 하기 위한 맵
        func pointKey(_ point: CGPoint) -> String {
            let qx = Int((point.x * 1000).rounded())
            let qy = Int((point.y * 1000).rounded())
            return "\(qx)_\(qy)"
        }

        var confidenceByPoint: [String: Float] = [:]
        for keypoint in keypoints {
            let key = pointKey(keypoint.position)
            let existing = confidenceByPoint[key] ?? 0
            confidenceByPoint[key] = max(existing, keypoint.confidence)
        }

        var candidates: [MeasurementPointCandidate] = []
        for line in lines {
            // 단일 포인트 placeholder 라인은 실제 거리 측정에 사용하지 않음
            let lineLength = hypot(line.end.x - line.start.x, line.end.y - line.start.y)
            guard lineLength > 0.005 else { continue }

            let groupId = UUID().uuidString
            let startConfidence = confidenceByPoint[pointKey(line.start)] ?? 0.75
            let endConfidence = confidenceByPoint[pointKey(line.end)] ?? 0.75
            let lineConfidence = max(0.5, min(1.0, (startConfidence + endConfidence) / 2.0))

            candidates.append(MeasurementPointCandidate(
                type: line.type,
                screenPosition: line.start,
                confidence: lineConfidence,
                groupId: groupId
            ))
            candidates.append(MeasurementPointCandidate(
                type: line.type,
                screenPosition: line.end,
                confidence: lineConfidence,
                groupId: groupId
            ))
        }

        return candidates
    }

    /// 의류 타입별 측정 항목 추출
    private func extractMeasurementsForClothingType(
        featurePoints: ClothingFeaturePoints,
        clothingType: ClothingType,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?
    ) -> [MeasurementType: AutoMeasurementResult] {
        var measurements: [MeasurementType: AutoMeasurementResult] = [:]

        switch clothingType {
        case .shortSleeve, .longSleeve, .shirt, .polo, .hoodie, .vest, .cardigan, .jacket, .coat, .dress, .jumpsuit:
            // 상의 측정: 어깨너비, 가슴둘레, 총길이, 소매길이
            if let shoulderWidth = measureShoulderWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType
            ) {
                measurements[.shoulderWidth] = shoulderWidth
            }

            if let chestWidth = measureChestWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType
            ) {
                measurements[.chestCircumference] = chestWidth
            }

            if let totalLength = measureTotalLength(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType
            ) {
                measurements[.totalLength] = totalLength
            }

        case .pants, .shorts, .jeans, .leggings:
            // 하의 측정: 허리둘레, 엉덩이둘레, 총길이
            if let waistWidth = measureWaistWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType
            ) {
                measurements[.waistCircumference] = waistWidth
            }

            // TODO: hipCircumference를 MeasurementType enum에 추가 필요
            // if let hipWidth = measureHipWidth(...) {
            //     measurements[.hipCircumference] = hipWidth
            // }

            if let totalLength = measureTotalLength(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType
            ) {
                measurements[.totalLength] = totalLength
            }

        case .skirt:
            // 치마 측정: 허리둘레, 총길이
            if let waistWidth = measureWaistWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType
            ) {
                measurements[.waistCircumference] = waistWidth
            }

            // TODO: hipCircumference를 MeasurementType enum에 추가 필요
            // if let hipWidth = measureHipWidth(...) {
            //     measurements[.hipCircumference] = hipWidth
            // }

            if let totalLength = measureTotalLength(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType
            ) {
                measurements[.totalLength] = totalLength
            }
        }

        return measurements
    }

    // MARK: - Depth Filtering

    /// Depth 기반 주름 필터링
    ///
    /// 각 키포인트 주변의 depth 분산을 계산하여
    /// 주름/접힌 부분(분산 큰 곳)에 위치한 키포인트를 제거하거나 신뢰도 하향
    private func filterKeypointsByDepthConsistency(
        keypoints: [MeasurementKeypoint],
        depthMap: CVPixelBuffer,
        imageSize: CGSize
    ) -> [MeasurementKeypoint] {
        guard !keypoints.isEmpty else { return [] }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        guard depthWidth > 0, depthHeight > 0 else { return keypoints }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return keypoints
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        var filteredKeypoints: [MeasurementKeypoint] = []
        let kernelRadius = 2  // 5x5 커널

        for keypoint in keypoints {
            // 정규화 좌표 → depth map 픽셀 좌표
            let depthU = Int(keypoint.position.x * CGFloat(depthWidth - 1))
            let depthV = Int((1.0 - keypoint.position.y) * CGFloat(depthHeight - 1))  // Y축 반전

            let clampedU = max(0, min(depthWidth - 1, depthU))
            let clampedV = max(0, min(depthHeight - 1, depthV))

            // 커널 내 depth 값 수집
            var depthValues: [Float] = []
            for offsetY in -kernelRadius...kernelRadius {
                for offsetX in -kernelRadius...kernelRadius {
                    let u = clampedU + offsetX
                    let v = clampedV + offsetY
                    guard u >= 0, u < depthWidth, v >= 0, v < depthHeight else { continue }

                    let row = baseAddress + v * bytesPerRow
                    let depth = row.assumingMemoryBound(to: Float32.self)[u]

                    if depth.isFinite && depth >= 0.2 && depth <= 5.0 {
                        depthValues.append(depth)
                    }
                }
            }

            // depth 값이 충분하지 않으면 그대로 유지
            guard depthValues.count >= 3 else {
                filteredKeypoints.append(keypoint)
                continue
            }

            // 표준편차 계산
            let mean = depthValues.reduce(0, +) / Float(depthValues.count)
            let variance = depthValues.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(depthValues.count)
            let stdDev = sqrt(variance)

            if stdDev > 0.05 {
                // 5cm 이상 분산: 명백한 노이즈 → 제거
                print("  ⛔ [DepthFilter] \(keypoint.type.displayName) 제거 (depth stdDev: \(String(format: "%.3f", stdDev))m)")
                continue
            } else if stdDev > 0.02 {
                // 2cm 이상 분산: 주름 위 포인트 → 신뢰도 하향
                let adjusted = MeasurementKeypoint(
                    type: keypoint.type,
                    position: keypoint.position,
                    confidence: min(keypoint.confidence, 0.3)
                )
                print("  ⚠️ [DepthFilter] \(keypoint.type.displayName) 신뢰도 하향 (depth stdDev: \(String(format: "%.3f", stdDev))m)")
                filteredKeypoints.append(adjusted)
            } else {
                // 정상 포인트
                filteredKeypoints.append(keypoint)
            }
        }

        // 최소 2개 키포인트 보장
        if filteredKeypoints.count < 2 && keypoints.count >= 2 {
            print("  ⚠️ [DepthFilter] 최소 키포인트 보장: 신뢰도 상위 2개 복원")
            let sorted = keypoints.sorted { $0.confidence > $1.confidence }
            filteredKeypoints = Array(sorted.prefix(max(2, filteredKeypoints.count)))
        }

        return filteredKeypoints
    }

    // MARK: - Individual Measurement Methods

    /// 어깨너비 측정
    private func measureShoulderWidth(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType
    ) -> AutoMeasurementResult? {
        // 상단 5% 영역에서 최대 너비 찾기
        guard let (left, right, confidence) = featurePoints.robustHorizontalSpan(
            at: featurePoints.topPoint.y - featurePoints.height * 0.02,
            halfSpans: [0.01, 0.02, 0.03]
        ) else {
            return nil
        }

        return measureDistance(
            from: left,
            to: right,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: confidence,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .shoulderWidth,
            clothingType: clothingType
        )
    }

    /// 가슴둘레 측정 (실제로는 가슴 너비)
    private func measureChestWidth(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType
    ) -> AutoMeasurementResult? {
        // 가슴 위치에서 최대 너비 찾기
        guard let (left, right, confidence) = featurePoints.robustHorizontalSpan(
            at: featurePoints.chestY,
            halfSpans: [0.02, 0.03, 0.04]
        ) else {
            return nil
        }

        return measureDistance(
            from: left,
            to: right,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: confidence,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .chestCircumference,
            clothingType: clothingType
        )
    }

    /// 허리둘레 측정 (실제로는 허리 너비)
    private func measureWaistWidth(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType
    ) -> AutoMeasurementResult? {
        // 허리 위치에서 너비 찾기 (하의는 상단 10% 근처가 허리)
        guard let (left, right, confidence) = featurePoints.robustHorizontalSpan(
            at: featurePoints.waistY,
            halfSpans: [0.02, 0.03, 0.04]
        ) else {
            return nil
        }

        return measureDistance(
            from: left,
            to: right,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: confidence,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .waistCircumference,
            clothingType: clothingType
        )
    }

    /// 엉덩이둘레 측정 (실제로는 엉덩이 너비)
    private func measureHipWidth(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType
    ) -> AutoMeasurementResult? {
        // 엉덩이 위치에서 최대 너비 찾기
        guard let (left, right, confidence) = featurePoints.robustHorizontalSpan(
            at: featurePoints.hipY,
            halfSpans: [0.02, 0.03, 0.04]
        ) else {
            return nil
        }

        return measureDistance(
            from: left,
            to: right,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: confidence,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .hipCircumference,
            clothingType: clothingType
        )
    }

    /// 총길이 측정
    private func measureTotalLength(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType
    ) -> AutoMeasurementResult? {
        return measureDistance(
            from: featurePoints.topPoint,
            to: featurePoints.bottomPoint,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: 0.9, // 상하 끝점은 신뢰도 높음
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .totalLength,
            clothingType: clothingType
        )
    }

    /// 두 정규화 좌표 간 거리 측정
    private func measureDistance(
        from normalizedPoint1: CGPoint,
        to normalizedPoint2: CGPoint,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        confidence: Float,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        measurementType: MeasurementType,
        clothingType: ClothingType
    ) -> AutoMeasurementResult? {
        // 정규화 좌표 → 픽셀 좌표
        let pixelPoint1 = CGPoint(
            x: normalizedPoint1.x * imageSize.width,
            y: (1.0 - normalizedPoint1.y) * imageSize.height  // Y축 반전 (Vision 좌표계 → UIKit 좌표계)
        )
        let pixelPoint2 = CGPoint(
            x: normalizedPoint2.x * imageSize.width,
            y: (1.0 - normalizedPoint2.y) * imageSize.height
        )

        // PhotoMeasurementCalculator 활용 (교정 계수 포함)
        guard let result = PhotoMeasurementCalculator.calculateDistance(
            from: pixelPoint1,
            to: pixelPoint2,
            depthMap: depthMap,
            imageSize: imageSize,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: measurementType,
            clothingType: clothingType
        ) else {
            return nil
        }

        return AutoMeasurementResult(
            distance: result.distance,
            confidence: Double(confidence) * result.confidence,
            point1: pixelPoint1,
            point2: pixelPoint2
        )
    }
}

// MARK: - Auto Measurement Result

/// 자동 측정 결과
struct AutoMeasurementResult {
    /// 측정 거리 (센티미터)
    let distance: Double

    /// 측정 신뢰도 (0.0 ~ 1.0)
    let confidence: Double

    /// 시작 포인트 (픽셀 좌표)
    let point1: CGPoint

    /// 끝 포인트 (픽셀 좌표)
    let point2: CGPoint
}

// MARK: - Auto Measurement Error

/// 자동 측정 에러
enum AutoMeasurementError: LocalizedError {
    case foregroundSegmentationFailed
    case noContourDetected
    case insufficientFeaturePoints
    case invalidClothingType

    var errorDescription: String? {
        switch self {
        case .foregroundSegmentationFailed:
            return "의류 전경 분리에 실패했습니다. 의류를 더 선명하게 촬영해주세요."
        case .noContourDetected:
            return "의류 윤곽선을 감지할 수 없습니다. 의류를 평평하게 펼쳐주세요."
        case .insufficientFeaturePoints:
            return "특징점이 충분하지 않습니다. 의류 전체가 보이도록 촬영해주세요."
        case .invalidClothingType:
            return "지원하지 않는 의류 타입입니다."
        }
    }
}

// MARK: - CGPath Extension

extension CGPath {
    /// CGPath의 모든 점을 배열로 반환
    func points() -> [CGPoint] {
        var points: [CGPoint] = []

        self.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                points.append(element.pointee.points[0])
            case .addQuadCurveToPoint:
                points.append(element.pointee.points[0])
                points.append(element.pointee.points[1])
            case .addCurveToPoint:
                points.append(element.pointee.points[0])
                points.append(element.pointee.points[1])
                points.append(element.pointee.points[2])
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }

        return points
    }
}

//
//  AutoMeasurementService+Detection.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  AutoMeasurementService의 윤곽선 감지 및 특징 분석 확장입니다.
//  원본/마스크 이미지에서 윤곽선을 감지하고,
//  키포인트 후보 생성 및 Depth 기반 필터링을 수행합니다.
//

import Foundation
import Vision
import ARKit
import CoreImage
import UIKit
import simd

// MARK: - Contour Detection & Feature Analysis

extension AutoMeasurementService {

    /// 배경 제거가 완료된 처리 이미지에서 전경 픽셀만 사용해 특징점을 추출합니다.
    ///
    /// Vision contour가 밝은 배경/크롭 외곽선을 큰 윤곽으로 선택하는 경우가 있어,
    /// 저장된 처리 이미지의 배경색을 직접 추정한 뒤 의류 픽셀의 외곽을 다시 구성합니다.
    func extractForegroundFeaturePoints(
        from image: UIImage,
        clothingType: ClothingType
    ) -> ClothingFeaturePoints? {
        guard let cgImage = image.normalizedOrientation().cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 4, height > 4 else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let sampleStep = max(1, max(width, height) / 512)
        let background = estimatedBackgroundColor(
            pixelData: pixelData,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow,
            sampleStep: sampleStep
        )
        let edgeInset = max(sampleStep * 2, Int(CGFloat(width) * 0.04))

        let minimumRowPixels = max(3, Int(CGFloat(width / sampleStep) * 0.025))
        let minimumSegmentPixels = max(2, Int(CGFloat(width / sampleStep) * 0.010))
        var rowSummaries: [ForegroundRowSummary] = []
        var allPoints: [CGPoint] = []

        for y in stride(from: 0, to: height, by: sampleStep) {
            var segments: [(left: Int, right: Int, count: Int)] = []
            var segmentStart: Int?
            var segmentEnd = 0
            var segmentCount = 0
            var rowCount = 0

            for x in stride(from: 0, to: width, by: sampleStep) {
                if isForegroundPixel(
                    pixelData: pixelData,
                    x: x,
                    y: y,
                    bytesPerRow: bytesPerRow,
                    background: background
                ) {
                    if segmentStart == nil {
                        segmentStart = x
                    }
                    segmentEnd = x
                    segmentCount += 1
                    rowCount += 1
                } else if let start = segmentStart {
                    if segmentCount >= minimumSegmentPixels {
                        segments.append((start, segmentEnd, segmentCount))
                    }
                    segmentStart = nil
                    segmentEnd = 0
                    segmentCount = 0
                }
            }

            if let start = segmentStart, segmentCount >= minimumSegmentPixels {
                segments.append((start, segmentEnd, segmentCount))
            }

            guard rowCount >= minimumRowPixels,
                  let first = segments.first,
                  let last = segments.last else {
                continue
            }

            let normalizedY = 1.0 - CGFloat(y) / CGFloat(max(height - 1, 1))
            let left = max(first.left, edgeInset)
            let right = min(last.right, max(edgeInset + 1, width - 1 - edgeInset))
            guard right > left else { continue }

            let rowWidth = CGFloat(right - left) / CGFloat(max(width - 1, 1))

            for segment in segments {
                let segmentLeft = max(segment.left, edgeInset)
                let segmentRight = min(segment.right, max(edgeInset + 1, width - 1 - edgeInset))
                guard segmentRight > segmentLeft else { continue }

                allPoints.append(normalizedPoint(x: segmentLeft, y: y, width: width, height: height))
                allPoints.append(normalizedPoint(x: segmentRight, y: y, width: width, height: height))
            }

            rowSummaries.append(ForegroundRowSummary(
                y: normalizedY,
                leftX: CGFloat(left) / CGFloat(max(width - 1, 1)),
                rightX: CGFloat(right) / CGFloat(max(width - 1, 1)),
                width: rowWidth,
                count: rowCount
            ))
        }

        guard rowSummaries.count >= 8, allPoints.count >= 16 else {
            return nil
        }

        let maxRowWidth = rowSummaries.map(\.width).max() ?? 0
        let representativeRows = rowSummaries.filter {
            $0.width >= max(maxRowWidth * 0.24, 0.08)
        }
        guard !representativeRows.isEmpty else {
            return nil
        }

        let topRow = representativeRows.max(by: { $0.y < $1.y }) ?? rowSummaries.max(by: { $0.y < $1.y })!
        let bottomRow = representativeRows.min(by: { $0.y < $1.y }) ?? rowSummaries.min(by: { $0.y < $1.y })!

        let topPoint = CGPoint(
            x: (topRow.leftX + topRow.rightX) * 0.5,
            y: topRow.y
        )
        let bottomPoint = CGPoint(
            x: (bottomRow.leftX + bottomRow.rightX) * 0.5,
            y: bottomRow.y
        )
        let leftmostPoint = allPoints.min(by: { $0.x < $1.x }) ?? CGPoint(x: topRow.leftX, y: topRow.y)
        let rightmostPoint = allPoints.max(by: { $0.x < $1.x }) ?? CGPoint(x: topRow.rightX, y: topRow.y)

        let featurePoints = ClothingFeaturePoints.withTemplate(
            topPoint: topPoint,
            bottomPoint: bottomPoint,
            leftmostPoint: leftmostPoint,
            rightmostPoint: rightmostPoint,
            allPoints: allPoints,
            clothingType: clothingType
        )

        print("✅ [ForegroundFeaturePoints] 처리 이미지 기반 특징점 추출 완료")
        print("  - rows: \(rowSummaries.count), points: \(allPoints.count)")
        print("  - top: \(String(format: "%.3f", topPoint.x)), \(String(format: "%.3f", topPoint.y))")
        print("  - bottom: \(String(format: "%.3f", bottomPoint.x)), \(String(format: "%.3f", bottomPoint.y))")
        return featurePoints
    }

    /// 원본 이미지에서 윤곽선 감지
    func detectContourFromOriginal(_ pixelBuffer: CVPixelBuffer) async throws -> VNContoursObservation? {
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

    /// 마스크에서 윤곽선 감지
    func detectContour(from mask: CVPixelBuffer) async throws -> VNContoursObservation? {
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

    /// 키포인트 감지 결과(측정 라인)를 MeasurementPointCandidate로 변환
    func generateCandidatesFromKeypoints(
        contour: VNContoursObservation,
        featurePoints: ClothingFeaturePoints,
        clothingType: ClothingType
    ) -> [MeasurementPointCandidate] {
        let keypoints = keypointDetector.detectKeypoints(
            from: contour,
            clothingType: clothingType,
            featurePoints: featurePoints
        )
        let allowedMeasurementTypes = Set(clothingType.requiredMeasurements + clothingType.optionalMeasurements)
        let lines = keypointDetector.generateMeasurementLines(
            from: keypoints,
            clothingType: clothingType
        ).filter { allowedMeasurementTypes.contains($0.type) }

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

    // MARK: - Depth Filtering

    /// Depth 기반 주름 필터링
    ///
    /// 각 키포인트 주변의 depth 분산을 계산하여
    /// 주름/접힌 부분(분산 큰 곳)에 위치한 키포인트를 제거하거나 신뢰도 하향
    func filterKeypointsByDepthConsistency(
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

    private struct ForegroundRowSummary {
        let y: CGFloat
        let leftX: CGFloat
        let rightX: CGFloat
        let width: CGFloat
        let count: Int
    }

    private struct EstimatedBackgroundColor {
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
        let brightness: CGFloat
    }

    private func estimatedBackgroundColor(
        pixelData: [UInt8],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        sampleStep: Int
    ) -> EstimatedBackgroundColor {
        let marginX = max(sampleStep, width / 20)
        let marginY = max(sampleStep, height / 20)
        var rTotal: CGFloat = 0
        var gTotal: CGFloat = 0
        var bTotal: CGFloat = 0
        var count: CGFloat = 0

        func includePixel(x: Int, y: Int) {
            let index = y * bytesPerRow + x * 4
            guard index + 2 < pixelData.count else { return }
            rTotal += CGFloat(pixelData[index])
            gTotal += CGFloat(pixelData[index + 1])
            bTotal += CGFloat(pixelData[index + 2])
            count += 1
        }

        for y in stride(from: 0, to: height, by: sampleStep) where y < marginY || y >= height - marginY {
            for x in stride(from: 0, to: width, by: sampleStep) {
                includePixel(x: x, y: y)
            }
        }

        for x in stride(from: 0, to: width, by: sampleStep) where x < marginX || x >= width - marginX {
            for y in stride(from: marginY, to: max(marginY, height - marginY), by: sampleStep) {
                includePixel(x: x, y: y)
            }
        }

        guard count > 0 else {
            return EstimatedBackgroundColor(r: 245, g: 245, b: 245, brightness: 245)
        }

        let r = rTotal / count
        let g = gTotal / count
        let b = bTotal / count
        return EstimatedBackgroundColor(
            r: r,
            g: g,
            b: b,
            brightness: (r + g + b) / 3.0
        )
    }

    private func isForegroundPixel(
        pixelData: [UInt8],
        x: Int,
        y: Int,
        bytesPerRow: Int,
        background: EstimatedBackgroundColor
    ) -> Bool {
        let index = y * bytesPerRow + x * 4
        guard index + 3 < pixelData.count else { return false }

        let r = CGFloat(pixelData[index])
        let g = CGFloat(pixelData[index + 1])
        let b = CGFloat(pixelData[index + 2])
        let alpha = CGFloat(pixelData[index + 3])
        guard alpha > 16 else { return false }

        let dr = r - background.r
        let dg = g - background.g
        let db = b - background.b
        let colorDistance = sqrt(dr * dr + dg * dg + db * db)
        let brightness = (r + g + b) / 3.0
        let saturation = max(r, g, b) - min(r, g, b)
        let brightnessDelta = abs(brightness - background.brightness)

        return colorDistance >= 48 && (brightnessDelta >= 28 || saturation >= 18)
    }

    private func normalizedPoint(
        x: Int,
        y: Int,
        width: Int,
        height: Int
    ) -> CGPoint {
        CGPoint(
            x: CGFloat(x) / CGFloat(max(width - 1, 1)),
            y: 1.0 - CGFloat(y) / CGFloat(max(height - 1, 1))
        )
    }
}

//
//  ForegroundSegmentationService+Validation.swift
//  ClothIQ
//
//  Created on 2025-01-23
//
//  Description:
//  ForegroundSegmentationService의 검증 및 분류 관련 메서드 확장입니다.
//

import Foundation
import Vision
import CoreImage
import UIKit
import ARKit
import CoreVideo

extension ForegroundSegmentationService {

    // MARK: - Object Detection & Classification

    /// 이미지에서 일반 객체를 감지합니다.
    ///
    /// VNClassifyImageRequest를 사용하여 이미지 내용을 분류합니다.
    ///
    /// - Parameter pixelBuffer: 입력 이미지
    /// - Returns: 객체 감지 여부
    func detectObject(in pixelBuffer: CVPixelBuffer) -> Bool {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])

            guard let results = request.results, !results.isEmpty else {
                lastDetectionResult = ObjectDetectionResult(
                    isObjectDetected: false,
                    detectedCategory: nil,
                    confidence: 0,
                    message: "이미지 분석 실패"
                )
                return false
            }

            // 상위 결과 확인 (신뢰도 10% 이상)
            if let topResult = results.first, topResult.confidence >= 0.10 {
                lastDetectionResult = ObjectDetectionResult(
                    isObjectDetected: true,
                    detectedCategory: topResult.identifier,
                    confidence: topResult.confidence,
                    message: "📦 \(topResult.identifier) 감지됨"
                )
                return true
            }

            lastDetectionResult = ObjectDetectionResult(
                isObjectDetected: false,
                detectedCategory: nil,
                confidence: 0,
                message: "객체를 찾을 수 없습니다"
            )
            return false

        } catch {
            lastDetectionResult = ObjectDetectionResult(
                isObjectDetected: false,
                detectedCategory: nil,
                confidence: 0,
                message: "이미지 분류 오류"
            )
            return false
        }
    }

    /// 이미지에 의류가 포함되어 있는지 확인
    ///
    /// VNClassifyImageRequest를 사용하여 이미지 내용을 분류하고
    /// 의류 관련 카테고리가 있는지 확인합니다.
    ///
    /// - Parameter pixelBuffer: 입력 이미지
    /// - Returns: 의류 감지 여부
    func isClothingDetected(in pixelBuffer: CVPixelBuffer) -> Bool {
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])

            guard let results = request.results else {
                lastDetectionResult = ObjectDetectionResult(
                    isObjectDetected: false,
                    detectedCategory: nil,
                    confidence: 0,
                    message: "이미지 분석 실패"
                )
                return false
            }

            // 의류 관련 키워드
            let clothingKeywords = [
                "shirt", "t-shirt", "tshirt", "polo",
                "pants", "trousers", "jeans", "shorts",
                "dress", "skirt",
                "jacket", "coat", "sweater", "hoodie", "blouse",
                "clothing", "apparel", "garment",
                "textile", "fabric", "cloth",
                "sleeve", "collar", "wear"
            ]

            // 의류 관련 카테고리 확인
            for observation in results {
                let identifier = observation.identifier.lowercased()
                let confidence = observation.confidence

                // 신뢰도가 일정 수준 이상인 것만 확인 (15% 이상으로 완화)
                guard confidence >= 0.15 else { continue }

                // 키워드 매칭
                if clothingKeywords.contains(where: { identifier.contains($0) }) {
                    lastDetectionResult = ObjectDetectionResult(
                        isObjectDetected: true,
                        detectedCategory: observation.identifier,
                        confidence: confidence,
                        message: "✅ \(observation.identifier) 감지됨"
                    )
                    return true
                }
            }

            // 상위 3개 결과 로그 및 저장
            var topResults: [String] = []
            for observation in results.prefix(3) {
                topResults.append("\(observation.identifier): \(Int(observation.confidence * 100))%")
            }

            lastDetectionResult = ObjectDetectionResult(
                isObjectDetected: false,
                detectedCategory: results.first?.identifier,
                confidence: results.first?.confidence ?? 0,
                message: "❌ 의류가 아닌 것 같습니다\n감지됨: \(topResults.joined(separator: ", "))"
            )

            return false

        } catch {
            lastDetectionResult = ObjectDetectionResult(
                isObjectDetected: false,
                detectedCategory: nil,
                confidence: 0,
                message: "이미지 분류 오류"
            )
            return false
        }
    }

    // MARK: - Validation

    /// 전경 객체 검증 (일반 객체용)
    ///
    /// 다음 기준으로 검증:
    /// 1. 적절한 크기인지 (너무 작거나 크지 않음)
    /// 2. 적절한 깊이 범위인지 (0.2m ~ 5.0m)
    /// 3. 마스크 커버리지가 적절한지 (1% ~ 95%)
    ///
    /// - Parameters:
    ///   - mask: 검증할 마스크
    ///   - depthMap: LiDAR depth map (선택, ARFrame 참조 없이 전달)
    func validateAsObject(_ mask: CVPixelBuffer?, depthMap: CVPixelBuffer?) -> CVPixelBuffer? {
        guard let mask = mask else { return nil }

        // 1. 마스크 커버리지 확인
        let coverage = calculateMaskCoverage(mask)

        // 너무 작으면 잡음 (기준 대폭 완화: 1% ~ 95%)
        guard coverage >= Constants.objectMinimumCoverage && coverage <= Constants.objectMaximumCoverage else {
            return nil
        }

        // 2. 깊이 데이터 확인 (선택적)
        guard let depthMap = depthMap else {
            return mask  // 깊이 데이터가 없어도 마스크는 반환
        }

        let avgDepth = calculateAverageDepth(in: mask, depthMap: depthMap)

        // 측정에 적합한 거리인지 확인 (0.2m ~ 5.0m로 확대)
        if avgDepth > 0 && (avgDepth < Constants.objectMinimumDepth || avgDepth > Constants.objectMaximumDepth) {
            // 경고만 하고 마스크는 반환
        }

        return mask
    }

    /// 전경 객체가 의류인지 검증 (의류 전용, 엄격한 기준)
    ///
    /// 다음 기준으로 검증:
    /// 1. 평면 위에 놓여있는지 (ARPlaneAnchor)
    /// 2. 적절한 크기인지 (너무 작거나 크지 않음)
    /// 3. 적절한 깊이 범위인지 (0.3m ~ 2.0m)
    /// 4. 마스크 커버리지가 적절한지 (5% ~ 60%)
    func validateAsClothing(_ mask: CVPixelBuffer?, frame: ARFrame) -> CVPixelBuffer? {
        guard let mask = mask else { return nil }

        // 1. 마스크 커버리지 확인
        let coverage = calculateMaskCoverage(mask)

        // 너무 작으면 잡음, 너무 크면 배경
        guard coverage >= Constants.clothingMinimumCoverage && coverage <= Constants.clothingMaximumCoverage else {
            return nil
        }

        // 2. 평면 감지 확인 (의류는 평평한 곳에 놓임)
        _ = frame.anchors.contains { anchor in
            anchor is ARPlaneAnchor
        }

        // 3. 깊이 데이터 확인
        guard let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap else {
            return nil
        }

        let avgDepth = calculateAverageDepth(in: mask, depthMap: depthMap)

        // 의류 측정에 적합한 거리인지 확인
        guard avgDepth >= Constants.clothingMinimumDepth && avgDepth <= Constants.clothingMaximumDepth else {
            return nil
        }

        return mask
    }

    /// 마스크 영역의 평균 깊이 계산
    func calculateAverageDepth(in mask: CVPixelBuffer, depthMap: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(mask, .readOnly)
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        guard let maskAddress = CVPixelBufferGetBaseAddress(mask),
              let depthAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return 0
        }

        let maskBytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let maskBuffer = maskAddress.assumingMemoryBound(to: UInt8.self)
        let depthBuffer = depthAddress.assumingMemoryBound(to: Float32.self)

        var totalDepth: Float = 0
        var count = 0

        for y in 0..<maskHeight {
            for x in 0..<maskWidth {
                let maskIndex = y * maskBytesPerRow + x

                if maskBuffer[maskIndex] > 128 {  // 전경 픽셀
                    // 깊이 맵 좌표로 변환
                    let depthX = (x * depthWidth) / maskWidth
                    let depthY = (y * depthHeight) / maskHeight
                    let depthIndex = depthY * (depthBytesPerRow / 4) + depthX

                    let depth = depthBuffer[depthIndex]
                    if depth > 0 && depth.isFinite {
                        totalDepth += depth
                        count += 1
                    }
                }
            }
        }

        return count > 0 ? totalDepth / Float(count) : 0
    }

    // MARK: - Helper Methods

    /// 마스크를 이진화 (0 또는 255)
    func binarizeMask(_ mask: CVPixelBuffer, threshold: UInt8 = 128) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(mask, [])
        defer { CVPixelBufferUnlockBaseAddress(mask, []) }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)

        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else {
            return nil
        }

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * bytesPerRow + x
                buffer[index] = buffer[index] >= threshold ? 255 : 0
            }
        }

        return mask
    }

    /// 마스크 영역의 비율 계산
    func calculateMaskCoverage(_ mask: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let totalPixels = width * height

        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else {
            return 0.0
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var foregroundPixels = 0
        let threshold: UInt8 = 128  // 더 명확한 임계값

        for y in 0..<height {
            for x in 0..<width {
                let index = y * bytesPerRow + x
                if buffer[index] > threshold {
                    foregroundPixels += 1
                }
            }
        }

        let coverage = Float(foregroundPixels) / Float(totalPixels)

        return coverage
    }
}

//
//  ForegroundSegmentationService.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  Vision Framework를 사용하여 전경(의류)을 배경에서 분리하는 서비스입니다.
//

import Foundation
import Vision
import CoreImage
import UIKit
import ARKit

/// 전경 분리 서비스
///
/// VNGenerateForegroundInstanceMaskRequest를 사용하여
/// 의류와 같은 전경 객체를 배경에서 분리합니다.
///

/// 간단한 객체 감지 결과 (전경 분리용)
struct ObjectDetectionResult {
    let isObjectDetected: Bool
    let detectedCategory: String?
    let confidence: Float
    let message: String
}

final class ForegroundSegmentationService {

    // MARK: - Properties

    private let context = CIContext()
    private var lastProcessedTime: Date?
    private let processingInterval: TimeInterval = 0.033  // 33ms마다 처리 (30fps, 더 빠른 감지)

    // 마지막 감지 결과 (UI에 표시용)
    var lastDetectionResult: ObjectDetectionResult?

    // 의류 감지 모드 (false로 설정 시 모든 전경 객체 감지)
    var strictClothingDetection: Bool = false
    /// 객체 분류 수행 여부 (기본값: false, 필요 시 사용)
    var enableObjectClassification: Bool = false

    // 처리 중 플래그 (ARFrame retention 방지)
    private var isProcessing: Bool = false

    // MARK: - Foreground Detection

    /// 캡처된 이미지에서 의류 마스크를 생성합니다.
    ///
    /// - Parameters:
    ///   - pixelBuffer: 카메라가 캡처한 이미지 버퍼
    ///   - depthMap: 선택적 깊이 데이터
    /// - Returns: 의류 마스크 (CVPixelBuffer), 실패 시 nil
    func generateForegroundMask(
        from pixelBuffer: CVPixelBuffer,
        depthMap: CVPixelBuffer?
    ) -> CVPixelBuffer? {
        // 처리 중이면 건너뛰기 (ARFrame retention 방지)
        guard !isProcessing else {
            return nil
        }

        // 프레임 레이트 제한
        if let lastTime = lastProcessedTime,
           Date().timeIntervalSince(lastTime) < processingInterval {
            return nil
        }
        lastProcessedTime = Date()

        print("\n🔄 [감지 파이프라인 시작] ========================================")

        print("📸 프레임 크기: \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))")

        // 처리 시작
        isProcessing = true
        defer { isProcessing = false }  // 함수 종료 시 자동으로 플래그 해제

        // 1. 전경 분리 (먼저 수행)
        print("1️⃣ 사각형 감지 시작...")
        guard let foregroundMask = extractForeground(from: pixelBuffer) else {
            print("❌ [파이프라인 중단] 사각형 감지 실패")
            print("💡 해결 방법: 의류를 평평하게 펼치고 화면에 맞춰주세요")
            return nil
        }

        // 2. 기본 검증 (크기, 깊이 등)
        print("2️⃣ 마스크 검증 시작...")
        guard let validatedMask = validateAsObject(foregroundMask, depthMap: depthMap) else {
            print("❌ [파이프라인 중단] 마스크 검증 실패")
            return nil
        }

        // 3. 의류 확인 (strictClothingDetection이 true일 때만)
        print("3️⃣ 의류 분류 시작...")
        if enableObjectClassification {
            if strictClothingDetection {
                guard isClothingDetected(in: pixelBuffer) else {
                    print("❌ [파이프라인 중단] 의류가 아님")
                    return nil
                }
            } else {
                // 모든 전경 객체를 감지하고 분류 정보 업데이트
                let detected = detectObject(in: pixelBuffer)
                print("   객체 분류: \(detected ? "성공" : "실패")")
            }
        }

        print("✅ [감지 파이프라인 완료] 마스크 생성 성공")
        print("=============================================================\n")
        return validatedMask
    }

    /// 이미지에서 일반 객체를 감지합니다.
    ///
    /// VNClassifyImageRequest를 사용하여 이미지 내용을 분류합니다.
    ///
    /// - Parameter pixelBuffer: 입력 이미지
    /// - Returns: 객체 감지 여부
    private func detectObject(in pixelBuffer: CVPixelBuffer) -> Bool {
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
                print("📦 객체 감지: \(topResult.identifier) (신뢰도: \(Int(topResult.confidence * 100))%)")
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
            print("❌ Image classification failed: \(error)")
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
    private func isClothingDetected(in pixelBuffer: CVPixelBuffer) -> Bool {
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
                    print("✅ 의류 감지: \(observation.identifier) (신뢰도: \(Int(confidence * 100))%)")
                    return true
                }
            }

            // 상위 3개 결과 로그 및 저장
            var topResults: [String] = []
            for observation in results.prefix(3) {
                topResults.append("\(observation.identifier): \(Int(observation.confidence * 100))%")
                print("  📊 \(observation.identifier): \(Int(observation.confidence * 100))%")
            }

            lastDetectionResult = ObjectDetectionResult(
                isObjectDetected: false,
                detectedCategory: results.first?.identifier,
                confidence: results.first?.confidence ?? 0,
                message: "❌ 의류가 아닌 것 같습니다\n감지됨: \(topResults.joined(separator: ", "))"
            )

            return false

        } catch {
            print("❌ Image classification failed: \(error)")
            lastDetectionResult = ObjectDetectionResult(
                isObjectDetected: false,
                detectedCategory: nil,
                confidence: 0,
                message: "이미지 분류 오류"
            )
            return false
        }
    }

    // MARK: - Private Methods

    /// 전경 객체 추출 (사각형 감지 기반)
    ///
    /// 윤곽 기반 전경 마스크 생성 (실패 시 사각형 기반으로 대체)
    private func extractForeground(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        print("1️⃣ 윤곽 기반 감지 시도...")
        if let contourMask = extractUsingContours(from: pixelBuffer) {
            return contourMask
        }

        print("⚠️ 윤곽 감지 실패 - 사각형 기반 감지로 대체합니다.")
        return extractUsingRectangle(from: pixelBuffer)
    }

    /// 컨투어 기반 전경 마스크 추출
    private func extractUsingContours(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 768

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])

            guard let observation = request.results?.first,
                  observation.contourCount > 0 else {
                print("❌ 윤곽 감지 결과 없음")
                return nil
            }

            print("🔍 윤곽 감지 성공 - 컨투어 수: \(observation.contourCount)")

            let mask = createMaskFromContours(
                observation,
                imageSize: CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )
            )

            if mask != nil {
                print("✅ 윤곽 마스크 생성 성공")
            } else {
                print("❌ 윤곽 마스크 생성 실패")
            }

            return mask

        } catch {
            print("❌ 윤곽 감지 중 오류: \(error)")
            return nil
        }
    }

    /// 사각형 기반 전경 마스크 추출 (윤곽 감지 실패 시 사용)
    private func extractUsingRectangle(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 3.0
        request.minimumSize = 0.05
        request.maximumObservations = 10
        request.minimumConfidence = 0.4

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])

            guard let observations = request.results as? [VNRectangleObservation],
                  !observations.isEmpty else {
                print("❌ 사각형 감지 결과 없음 - 의류를 평평하게 펼쳐주세요")
                return nil
            }

            print("🔳 감지된 사각형 수: \(observations.count)")

            guard let largestRectangle = observations.max(by: { rect1, rect2 in
                let area1 = rect1.boundingBox.width * rect1.boundingBox.height
                let area2 = rect2.boundingBox.width * rect2.boundingBox.height
                return area1 < area2
            }) else {
                print("❌ 유효한 사각형 없음")
                return nil
            }

            let area = largestRectangle.boundingBox.width * largestRectangle.boundingBox.height
            print("📐 가장 큰 사각형 - 크기: \(Int(area * 100))%, 신뢰도: \(Int(largestRectangle.confidence * 100))%")

            let maskBuffer = createMaskFromRectangle(
                largestRectangle,
                imageSize: CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )
            )

            if maskBuffer != nil {
                print("✅ 사각형 마스크 생성 성공")
            } else {
                print("❌ 사각형 마스크 생성 실패")
            }

            return maskBuffer

        } catch {
            print("❌ Rectangle detection failed: \(error)")
            return nil
        }
    }

    /// 컨투어 결과를 픽셀 버퍼 마스크로 변환
    private func createMaskFromContours(
        _ observation: VNContoursObservation,
        imageSize: CGSize
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let width = Int(imageSize.width)
        let height = Int(imageSize.height)

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        memset(baseAddress, 0, bytesPerRow * height)

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.setFillColor(UIColor.white.cgColor)
        context.setShouldAntialias(true)

        let combinedPath = CGMutablePath()

        if let dominantContour = observation.topLevelContours.max(by: { contourArea($0) < contourArea($1) }) {
            append(contour: dominantContour, to: combinedPath, width: width, height: height)
        } else {
            observation.topLevelContours.forEach { contour in
                append(contour: contour, to: combinedPath, width: width, height: height)
            }
        }

        context.addPath(combinedPath)
        context.fillPath(using: .evenOdd)

        return buffer
    }

    /// 컨투어를 Path에 추가
    private func append(
        contour: VNContour,
        to path: CGMutablePath,
        width: Int,
        height: Int
    ) {
        guard !contour.normalizedPoints.isEmpty else { return }

        let convertedPoints = contour.normalizedPoints.map { point -> CGPoint in
            let normalizedX = CGFloat(point.x)
            let normalizedY = CGFloat(point.y)

            return CGPoint(
                x: normalizedX * CGFloat(width),
                y: (1.0 as CGFloat - normalizedY) * CGFloat(height)
            )
        }

        let contourPath = CGMutablePath()

        if let firstPoint = convertedPoints.first {
            contourPath.move(to: firstPoint)
            for point in convertedPoints.dropFirst() {
                contourPath.addLine(to: point)
            }
            contourPath.closeSubpath()
        }

        path.addPath(contourPath)

        contour.childContours.forEach { child in
            append(contour: child, to: path, width: width, height: height)
        }
    }

    /// 컨투어 면적 계산 (정규화 좌표 기준)
    private func contourArea(_ contour: VNContour) -> CGFloat {
        // Normalized points를 실제 픽셀 좌표로 변환하지 않고
        // 정규화된 공간에서 면적 계산 (0-1 범위)
        let points = contour.normalizedPoints.map { vector_float2 in
            CGPoint(x: CGFloat(vector_float2.x), y: CGFloat(vector_float2.y))
        }
        guard points.count >= 3 else { return 0 }

        var area: CGFloat = 0
        for i in 0..<points.count {
            let current = points[i]
            let next = points[(i + 1) % points.count]
            area += (current.x * next.y) - (next.x * current.y)
        }

        // 정규화된 면적 (0-1 범위의 비율)
        // 예: 0.1 = 전체 이미지의 10%를 차지
        return abs(area) * 0.5
    }

    /// 사각형 관찰 결과를 픽셀 버퍼 마스크로 변환
    private func createMaskFromRectangle(
        _ rectangle: VNRectangleObservation,
        imageSize: CGSize
    ) -> CVPixelBuffer? {
        // CVPixelBuffer 생성
        var pixelBuffer: CVPixelBuffer?
        let width = Int(imageSize.width)
        let height = Int(imageSize.height)

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)

        // 전체를 0(검정)으로 초기화
        memset(baseAddress, 0, bytesPerRow * height)

        // 사각형 영역을 255(흰색)로 채우기
        let bbox = rectangle.boundingBox

        // Vision 좌표계 (원점이 좌측 하단) -> 이미지 좌표계 (원점이 좌측 상단) 변환
        let minX = max(0, Int(bbox.minX * CGFloat(width)))
        let maxX = min(width, Int(bbox.maxX * CGFloat(width)))

        // Y축 반전 및 정확한 순서 보장
        // Vision: minY(bottom) < maxY(top) -> Image: top < bottom
        let topY = Int((1.0 - bbox.maxY) * CGFloat(height))  // bbox.maxY(Vision top) -> image top
        let bottomY = Int((1.0 - bbox.minY) * CGFloat(height))  // bbox.minY(Vision bottom) -> image bottom

        // 안전한 범위 설정 (topY < bottomY 보장)
        let minY = max(0, min(topY, bottomY))
        let maxY = min(height, max(topY, bottomY))

        for y in minY..<maxY {
            guard y >= 0, y < height else { continue }
            for x in minX..<maxX {
                guard x >= 0, x < width else { continue }
                let index = y * bytesPerRow + x
                pixels[index] = 255  // 전경
            }
        }

        return buffer
    }

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
    private func validateAsObject(_ mask: CVPixelBuffer?, depthMap: CVPixelBuffer?) -> CVPixelBuffer? {
        guard let mask = mask else { return nil }

        // 1. 마스크 커버리지 확인
        let coverage = calculateMaskCoverage(mask)
        print("📊 마스크 커버리지: \(Int(coverage * 100))%")

        // 너무 작으면 잡음 (기준 대폭 완화: 1% ~ 95%)
        guard coverage >= 0.01 && coverage <= 0.95 else {
            print("❌ 마스크 커버리지 부적합: \(Int(coverage * 100))% (1~95% 필요)")
            return nil
        }

        // 2. 깊이 데이터 확인 (선택적)
        guard let depthMap = depthMap else {
            print("⚠️  깊이 데이터 없음 - 마스크만으로 진행")
            return mask  // 깊이 데이터가 없어도 마스크는 반환
        }

        let avgDepth = calculateAverageDepth(in: mask, depthMap: depthMap)
        print("📏 평균 깊이: \(String(format: "%.2f", avgDepth))m")

        // 측정에 적합한 거리인지 확인 (0.2m ~ 5.0m로 확대)
        if avgDepth > 0 && (avgDepth < 0.2 || avgDepth > 5.0) {
            print("⚠️  깊이 경고: \(String(format: "%.1f", avgDepth))m (0.2~5.0m 권장)")
            // 경고만 하고 마스크는 반환
        }

        print("✅ 객체 감지 성공 - 커버리지: \(Int(coverage * 100))%, 깊이: \(String(format: "%.2f", avgDepth))m")
        return mask
    }

    /// 전경 객체가 의류인지 검증 (의류 전용, 엄격한 기준)
    ///
    /// 다음 기준으로 검증:
    /// 1. 평면 위에 놓여있는지 (ARPlaneAnchor)
    /// 2. 적절한 크기인지 (너무 작거나 크지 않음)
    /// 3. 적절한 깊이 범위인지 (0.3m ~ 2.0m)
    /// 4. 마스크 커버리지가 적절한지 (5% ~ 60%)
    private func validateAsClothing(_ mask: CVPixelBuffer?, frame: ARFrame) -> CVPixelBuffer? {
        guard let mask = mask else { return nil }

        // 1. 마스크 커버리지 확인
        let coverage = calculateMaskCoverage(mask)

        // 너무 작으면 잡음, 너무 크면 배경
        guard coverage >= 0.05 && coverage <= 0.6 else {
            print("❌ 마스크 커버리지 부적합: \(Int(coverage * 100))% (5~60% 필요)")
            return nil
        }

        // 2. 평면 감지 확인 (의류는 평평한 곳에 놓임)
        let hasPlane = frame.anchors.contains { anchor in
            anchor is ARPlaneAnchor
        }

        if !hasPlane {
            print("⚠️  평면이 감지되지 않았습니다. 의류를 평평한 곳에 펼쳐주세요.")
        }

        // 3. 깊이 데이터 확인
        guard let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap else {
            return nil
        }

        let avgDepth = calculateAverageDepth(in: mask, depthMap: depthMap)

        // 의류 측정에 적합한 거리인지 확인
        guard avgDepth >= 0.3 && avgDepth <= 2.0 else {
            print("❌ 깊이 부적합: \(String(format: "%.1f", avgDepth))m (0.3~2.0m 필요)")
            return nil
        }

        print("✅ 의류 감지 성공 - 커버리지: \(Int(coverage * 100))%, 깊이: \(String(format: "%.1f", avgDepth))m")
        return mask
    }

    /// 마스크 영역의 평균 깊이 계산
    private func calculateAverageDepth(in mask: CVPixelBuffer, depthMap: CVPixelBuffer) -> Float {
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

    /// UIImage에서 전경 마스크를 생성합니다.
    ///
    /// - Parameter image: 입력 이미지
    /// - Returns: 전경 마스크 이미지, 실패 시 nil
    func generateForegroundMask(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])

            guard let result = request.results?.first else {
                return nil
            }

            let maskBuffer = try result.generateScaledMaskForImage(
                forInstances: result.allInstances,
                from: handler
            )

            // CVPixelBuffer를 UIImage로 변환
            return convertMaskToImage(maskBuffer)

        } catch {
            print("Foreground segmentation failed: \(error)")
            return nil
        }
    }

    // MARK: - Helper Methods

    /// CVPixelBuffer 마스크를 UIImage로 변환
    private func convertMaskToImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

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
            print("❌ 마스크 베이스 주소 획득 실패")
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
        print("🎯 전경 픽셀: \(foregroundPixels) / 전체: \(totalPixels) = \(Int(coverage * 100))%")

        return coverage
    }
}

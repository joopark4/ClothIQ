//
//  ObjectCaptureService+MaskProcessing.swift
//  ClothIQ
//
//  Created on 2025-01-23
//
//  Description:
//  ObjectCaptureService의 마스크 생성 및 분석 관련 메서드 확장입니다.
//

import UIKit
import Vision
import CoreImage
import CoreVideo
import CoreGraphics

extension ObjectCaptureService {

    // MARK: - Mask Analysis

    /// CGImage 마스크 통계 분석 (디버깅용)
    ///
    /// - Parameter maskImage: 분석할 마스크 CGImage
    /// - Returns: 마스크 통계 (평균 밝기, 흰색 비율)
    ///
    func analyzeMaskStats(_ maskImage: CGImage) -> (avgBrightness: Double, whiteRatio: Double) {
        let width = maskImage.width
        let height = maskImage.height
        let totalPixels = width * height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return (0, 0)
        }

        context.draw(maskImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return (0, 0)
        }

        let buffer = data.assumingMemoryBound(to: UInt8.self)
        var totalBrightness: Int = 0
        var whitePixels = 0

        for i in 0..<totalPixels {
            let value = buffer[i]
            totalBrightness += Int(value)
            if value > 200 {  // 임계값
                whitePixels += 1
            }
        }

        let avgBrightness = Double(totalBrightness) / Double(totalPixels) / 255.0
        let whiteRatio = Double(whitePixels) / Double(totalPixels)

        return (avgBrightness, whiteRatio)
    }

    /// Vision 마스크에서 흰색(전경) 픽셀의 비율을 계산합니다.
    ///
    /// - Parameters:
    ///   - maskBuffer: Vision이 생성한 마스크 버퍼
    ///   - threshold: 전경으로 간주할 임계값 (기본: 200)
    /// - Returns: 흰색 픽셀 비율 (0.0 ~ 1.0)
    ///
    func calculateWhitePixelRatio(in maskBuffer: CVPixelBuffer, threshold: UInt8 = 200) -> Double {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)

        guard width > 0, height > 0,
              let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else {
            return 0.0
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var whitePixelCount = 0

        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                if buffer[rowStart + x] >= threshold {
                    whitePixelCount += 1
                }
            }
        }

        let totalPixels = max(1, width * height)
        return Double(whitePixelCount) / Double(totalPixels)
    }

    /// 마스크 픽셀을 이진화하여 선명한 경계를 생성합니다.
    ///
    /// - Parameters:
    ///   - maskBuffer: Vision이 생성한 원본 마스크
    ///   - threshold: 전경으로 간주할 임계값 (0~255)
    /// - Returns: 이진화된 마스크 이미지
    ///
    func createBinaryMaskImage(
        from maskBuffer: CVPixelBuffer,
        threshold: UInt8
    ) -> CIImage? {
        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)

        guard width > 0, height > 0 else {
            return nil
        }

        var binaryBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &binaryBuffer
        )

        guard status == kCVReturnSuccess, let binaryBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(binaryBuffer, [])

        defer {
            CVPixelBufferUnlockBaseAddress(binaryBuffer, [])
            CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly)
        }

        guard let sourcePointer = CVPixelBufferGetBaseAddress(maskBuffer),
              let destinationPointer = CVPixelBufferGetBaseAddress(binaryBuffer) else {
            return nil
        }

        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        let destinationBytesPerRow = CVPixelBufferGetBytesPerRow(binaryBuffer)

        let sourceBuffer = sourcePointer.assumingMemoryBound(to: UInt8.self)
        let destinationBuffer = destinationPointer.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            let sourceRow = sourceBuffer + y * sourceBytesPerRow
            let destinationRow = destinationBuffer + y * destinationBytesPerRow

            for x in 0..<width {
                destinationRow[x] = sourceRow[x] >= threshold ? 255 : 0
            }
        }

        return CIImage(cvPixelBuffer: binaryBuffer)
    }

    // MARK: - Mask Creation

    /// LiDAR Depth map 기반 마스크 생성 (최우선 방법)
    ///
    /// - Parameters:
    ///   - depthBuffer: LiDAR depth map
    ///   - imageSize: 원본 이미지 크기
    /// - Returns: 마스크 CIImage (흰색=전경/사물, 검은색=배경)
    ///
    /// ## Algorithm
    /// 1. Depth 값 분석하여 평균/중앙값 계산
    /// 2. 가까운 객체 (평균 depth + 오프셋) = 전경
    /// 3. 먼 배경 = 배경
    /// 4. Morphological 연산으로 정제
    ///
    func createDepthMask(from depthBuffer: CVPixelBuffer, imageSize: CGSize) -> CIImage {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            return createCenterMask(imageSize: imageSize)
        }

        // Depth 값은 Float32 형식 (미터 단위)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: Float32.self)

        // 1. Depth 값 분석
        var validDepths: [Float32] = []
        for y in 0..<height {
            let rowStart = y * bytesPerRow / MemoryLayout<Float32>.stride
            for x in 0..<width {
                let depth = buffer[rowStart + x]
                if depth > 0 && depth < 10.0 {  // 유효 범위: 0~10m
                    validDepths.append(depth)
                }
            }
        }

        guard !validDepths.isEmpty else {
            return createCenterMask(imageSize: imageSize)
        }

        // 2. 임계값 계산: 중앙값 기준 (평균보다 robust)
        validDepths.sort()
        let medianDepth = validDepths[validDepths.count / 2]

        // 의류는 바닥보다 약간 가까움 (5cm 이내)
        let foregroundThreshold = medianDepth - 0.05  // 중앙값 - 5cm


        // 3. 이진 마스크 생성
        var binaryMaskBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &binaryMaskBuffer
        )

        guard status == kCVReturnSuccess, let maskBuffer = binaryMaskBuffer else {
            return createCenterMask(imageSize: imageSize)
        }

        CVPixelBufferLockBaseAddress(maskBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, []) }

        guard let maskAddress = CVPixelBufferGetBaseAddress(maskBuffer) else {
            return createCenterMask(imageSize: imageSize)
        }

        let maskBytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        let maskPixels = maskAddress.assumingMemoryBound(to: UInt8.self)

        // 픽셀별로 전경/배경 판단
        var foregroundCount = 0
        for y in 0..<height {
            let depthRowStart = y * bytesPerRow / MemoryLayout<Float32>.stride
            let maskRowStart = y * maskBytesPerRow

            for x in 0..<width {
                let depth = buffer[depthRowStart + x]

                // 전경: depth < 임계값 (더 가까움)
                // 배경: depth >= 임계값 (더 멀거나 유효하지 않음)
                let isForeground = (depth > 0) && (depth < foregroundThreshold + 0.02)  // ±2cm 허용

                maskPixels[maskRowStart + x] = isForeground ? 255 : 0
                if isForeground {
                    foregroundCount += 1
                }
            }
        }

        // 4. CIImage로 변환 및 정제
        var ciMask = CIImage(cvPixelBuffer: maskBuffer)

        // Morphological 연산으로 마스크 정제 (Vision과 결합 시 작은 값 사용)
        // Dilation: 전경 영역 약간 확장
        if let morphologyMax = CIFilter(name: "CIMorphologyMaximum") {
            morphologyMax.setValue(ciMask, forKey: kCIInputImageKey)
            morphologyMax.setValue(2.0, forKey: kCIInputRadiusKey)  // 4 → 2로 감소
            if let dilated = morphologyMax.outputImage {
                ciMask = dilated
            }
        }

        // Erosion: 배경 노이즈 제거
        if let morphologyMin = CIFilter(name: "CIMorphologyMinimum") {
            morphologyMin.setValue(ciMask, forKey: kCIInputImageKey)
            morphologyMin.setValue(1.5, forKey: kCIInputRadiusKey)  // 3 → 1.5로 감소
            if let eroded = morphologyMin.outputImage {
                ciMask = eroded
            }
        }

        // 5. 이미지 크기에 맞게 스케일 조정
        let scaleX = imageSize.width / CGFloat(width)
        let scaleY = imageSize.height / CGFloat(height)
        let scaledMask = ciMask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: imageSize))

        return scaledMask
    }

    /// Saliency map을 이진 마스크로 변환
    ///
    /// - Parameters:
    ///   - saliencyBuffer: Saliency detection 결과 픽셀 버퍼
    ///   - imageSize: 원본 이미지 크기
    /// - Returns: 마스크 CIImage (흰색=전경/사물, 검은색=배경)
    ///
    func createSaliencyMask(from saliencyBuffer: CVPixelBuffer, imageSize: CGSize) -> CIImage {
        // Saliency map은 grayscale float 값 (0.0 ~ 1.0)
        // 높은 값 = 주목도 높음 (전경), 낮은 값 = 배경

        let ciSaliency = CIImage(cvPixelBuffer: saliencyBuffer)

        // Saliency map 크기 확인
        let saliencyExtent = ciSaliency.extent

        // 1. 임계값 적용하여 이진화 (threshold: 0.5)
        // Saliency 값이 0.5 이상이면 전경(흰색), 미만이면 배경(검은색)
        guard let thresholdFilter = CIFilter(name: "CIColorControls") else {
            return createCenterMask(imageSize: imageSize)
        }

        // 대비를 높여서 경계를 선명하게
        thresholdFilter.setValue(ciSaliency, forKey: kCIInputImageKey)
        thresholdFilter.setValue(3.0, forKey: kCIInputContrastKey)  // 대비 증가
        thresholdFilter.setValue(0.3, forKey: kCIInputBrightnessKey)  // 밝기 조정

        guard let contrastedSaliency = thresholdFilter.outputImage else {
            return createCenterMask(imageSize: imageSize)
        }

        // 2. Morphological 연산으로 마스크 정제 (노이즈 제거)
        var refinedMask = contrastedSaliency

        // Dilation: 전경 영역 확장 (의류의 작은 구멍 메우기)
        if let morphologyMax = CIFilter(name: "CIMorphologyMaximum") {
            morphologyMax.setValue(refinedMask, forKey: kCIInputImageKey)
            morphologyMax.setValue(3.0, forKey: kCIInputRadiusKey)
            if let dilated = morphologyMax.outputImage {
                refinedMask = dilated
            }
        }

        // Erosion: 배경 영역 확장 (불필요한 전경 제거)
        if let morphologyMin = CIFilter(name: "CIMorphologyMinimum") {
            morphologyMin.setValue(refinedMask, forKey: kCIInputImageKey)
            morphologyMin.setValue(2.0, forKey: kCIInputRadiusKey)
            if let eroded = morphologyMin.outputImage {
                refinedMask = eroded
            }
        }

        // 3. 이미지 크기에 맞게 스케일 조정
        let scaleX = imageSize.width / saliencyExtent.width
        let scaleY = imageSize.height / saliencyExtent.height
        let scaledMask = refinedMask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: imageSize))

        return scaledMask
    }

    /// 중앙 영역 마스크 생성 (폴백)
    ///
    /// - Parameter imageSize: 이미지 크기
    /// - Returns: 마스크 CIImage (중앙 80% = 전경)
    ///
    func createCenterMask(imageSize: CGSize) -> CIImage {
        let margin = Constants.centerMargin
        let maskRect = CGRect(
            x: imageSize.width * margin,
            y: imageSize.height * margin,
            width: imageSize.width * (1.0 - 2 * margin),
            height: imageSize.height * (1.0 - 2 * margin)
        )

        // 검은색 배경
        let blackBackground = CIImage(color: CIColor.black)
            .cropped(to: CGRect(origin: .zero, size: imageSize))

        // 흰색 중앙 영역
        let whiteCenter = CIImage(color: CIColor.white)
            .cropped(to: maskRect)
            .transformed(by: CGAffineTransform(translationX: maskRect.origin.x, y: maskRect.origin.y))

        let mask = whiteCenter.composited(over: blackBackground)
        return mask
    }

    /// 중앙 영역 마스크 생성 (CGImage 버전)
    ///
    /// - Parameter cgImage: 원본 CGImage
    /// - Returns: 마스크 CIImage
    ///
    func createCenterMask(for cgImage: CGImage) -> CIImage {
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        return createCenterMask(imageSize: imageSize)
    }

    /// 사각형 기반 마스크 생성 (레거시)
    ///
    /// - Parameters:
    ///   - cgImage: 원본 CGImage
    ///   - rectangle: 감지된 사각형 (nil이면 중앙 80% 영역 사용)
    /// - Returns: 마스크 CIImage (흰색=전경, 검은색=배경)
    ///
    func createRectangleMask(
        for cgImage: CGImage,
        rectangle: VNRectangleObservation?
    ) -> CIImage {
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // 마스크 영역 계산
        let maskRect: CGRect
        if let rect = rectangle {
            // Vision 좌표 (bottom-left origin)를 이미지 좌표로 변환
            maskRect = VNImageRectForNormalizedRect(
                rect.boundingBox,
                Int(imageSize.width),
                Int(imageSize.height)
            )
        } else {
            // 사각형 미감지 시 중앙 80% 영역을 전경으로 가정
            let margin = Constants.centerMargin
            maskRect = CGRect(
                x: imageSize.width * margin,
                y: imageSize.height * margin,
                width: imageSize.width * (1.0 - 2 * margin),
                height: imageSize.height * (1.0 - 2 * margin)
            )
        }

        // 검은색 배경 생성
        let blackBackground = CIImage(color: CIColor.black)
            .cropped(to: CGRect(origin: .zero, size: imageSize))

        // 흰색 사각형 생성 (전경)
        let whiteRectangle = CIImage(color: CIColor.white)
            .cropped(to: maskRect)
            .transformed(by: CGAffineTransform(translationX: maskRect.origin.x, y: maskRect.origin.y))

        // 합성
        let mask = whiteRectangle.composited(over: blackBackground)

        return mask
    }
}

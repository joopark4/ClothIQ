//
//  ObjectCaptureService+ObjectDetection.swift
//  ClothIQ
//
//  Created on 2025-01-23
//
//  Description:
//  ObjectCaptureService의 객체 감지 및 크롭 관련 메서드 확장입니다.
//

import UIKit
import Vision
import CoreImage
import CoreVideo
import CoreGraphics

extension ObjectCaptureService {

    // MARK: - Object Detection & Cropping

    /// 크롭 결과 (이미지 + 크롭 영역 정보)
    struct CropResult {
        let image: UIImage
        let cropRect: CGRect?
        let originalImageSize: CGSize
    }

    /// 이미지에서 객체를 감지하고 정사각형으로 크롭합니다 (크롭 영역 정보 포함).
    ///
    /// - Parameter image: 처리할 원본 이미지
    /// - Returns: 크롭 결과 (이미지 + 크롭 영역)
    /// - Throws: Vision 요청 실패 시 에러
    ///
    func detectAndCropObjectWithRect(in image: UIImage) throws -> CropResult {
        guard let cgImage = image.cgImage else {
            throw ObjectCaptureError.invalidImage
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // Vision Framework를 사용하여 객체 감지
        if let objectBounds = detectObjectBounds(in: cgImage) {
            // 객체의 실제 바운딩 박스에 여백 추가 (10-15%)
            let padding = Constants.objectDetectionPadding
            let paddingX = objectBounds.width * padding
            let paddingY = objectBounds.height * padding

            // 객체 중심을 유지하면서 여백이 추가된 크롭 영역 계산
            let objectCenterX = objectBounds.midX
            let objectCenterY = objectBounds.midY
            let expandedWidth = objectBounds.width + (paddingX * 2)
            let expandedHeight = objectBounds.height + (paddingY * 2)

            // 객체 중심을 기준으로 크롭 영역 설정
            var cropX = objectCenterX - expandedWidth / 2.0
            var cropY = objectCenterY - expandedHeight / 2.0
            var cropWidth = expandedWidth
            var cropHeight = expandedHeight

            // 이미지 경계를 벗어나는 경우에만 조정 (객체 중심은 최대한 유지)
            if cropX < 0 {
                cropX = 0
                if cropX + cropWidth > imageSize.width {
                    cropWidth = imageSize.width
                }
            } else if cropX + cropWidth > imageSize.width {
                cropX = max(0, imageSize.width - cropWidth)
            }

            if cropY < 0 {
                cropY = 0
                if cropY + cropHeight > imageSize.height {
                    cropHeight = imageSize.height
                }
            } else if cropY + cropHeight > imageSize.height {
                cropY = max(0, imageSize.height - cropHeight)
            }

            let cropRect = CGRect(
                x: cropX,
                y: cropY,
                width: cropWidth,
                height: cropHeight
            )

            guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
                // 크롭 실패 시 폴백: 중앙 정사각형
                return try fallbackCenterCrop(cgImage: cgImage, imageSize: imageSize)
            }

            let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
            return CropResult(
                image: croppedImage,
                cropRect: cropRect,
                originalImageSize: imageSize
            )
        } else {
            // 객체 감지 실패 시 폴백: 중앙 정사각형
            return try fallbackCenterCrop(cgImage: cgImage, imageSize: imageSize)
        }
    }

    /// 폴백: 중앙 정사각형 크롭
    func fallbackCenterCrop(cgImage: CGImage, imageSize: CGSize) throws -> CropResult {
        let squareSize = min(imageSize.width, imageSize.height)
        let cropRect = CGRect(
            x: (imageSize.width - squareSize) / 2,
            y: (imageSize.height - squareSize) / 2,
            width: squareSize,
            height: squareSize
        )

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            throw ObjectCaptureError.cropFailed
        }

        let croppedImage = UIImage(cgImage: croppedCGImage, scale: 1.0, orientation: .up)
        return CropResult(
            image: croppedImage,
            cropRect: cropRect,
            originalImageSize: imageSize
        )
    }

    /// Vision Framework를 사용하여 객체의 바운딩 박스 감지
    func detectObjectBounds(in cgImage: CGImage) -> CGRect? {
        // 전경 마스크 감지
        guard let maskBuffer = detectForegroundMask(cgImage: cgImage) else {
            return nil
        }

        // 마스크에서 객체 영역 계산
        return calculateObjectBoundingBox(from: maskBuffer, imageSize: CGSize(width: cgImage.width, height: cgImage.height))
    }

    /// 마스크에서 객체의 실제 바운딩 박스 계산
    func calculateObjectBoundingBox(from maskBuffer: CVPixelBuffer, imageSize: CGSize) -> CGRect? {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else { return nil }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)

        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)

        // 객체 픽셀의 최소/최대 좌표 찾기
        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        let threshold = Constants.maskThreshold

        for y in 0..<height {
            for x in 0..<width {
                let index = y * bytesPerRow + x
                if pixels[index] > threshold {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        // 객체를 찾지 못한 경우
        if minX > maxX || minY > maxY {
            return nil
        }

        // 마스크 좌표를 이미지 좌표로 변환
        let scaleX = imageSize.width / CGFloat(width)
        let scaleY = imageSize.height / CGFloat(height)

        return CGRect(
            x: CGFloat(minX) * scaleX,
            y: CGFloat(minY) * scaleY,
            width: CGFloat(maxX - minX + 1) * scaleX,
            height: CGFloat(maxY - minY + 1) * scaleY
        )
    }

    /// 이미지에서 객체를 감지하고 정사각형으로 크롭합니다 (레거시).
    ///
    /// - Parameter image: 처리할 원본 이미지
    /// - Returns: 크롭된 이미지 (객체 미감지 시 nil)
    /// - Throws: Vision 요청 실패 시 에러
    ///
    /// ## Detection Strategy
    /// 1. 전경 객체 마스크 생성 (VNGenerateForegroundInstanceMaskRequest)
    /// 2. 객체 경계 박스 계산
    /// 3. 정사각형 크롭 영역 계산 (객체를 포함하는 최소 정사각형)
    /// 4. 이미지 크롭 수행
    ///
    func detectAndCropObject(in image: UIImage) throws -> UIImage? {
        guard let cgImage = image.cgImage else {
            throw ObjectCaptureError.invalidImage
        }

        // Vision 요청 핸들러 생성 (클로저에서 사용하기 위해 먼저 선언)
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        // Vision 요청을 위한 세마포어 (동기 처리)
        let semaphore = DispatchSemaphore(value: 0)
        var detectedBoundingBox: CGRect?
        var detectionError: Error?

        // VNGenerateForegroundInstanceMaskRequest (iOS 17+)
        // 전경 객체의 인스턴스 마스크를 생성합니다.
        let request = VNGenerateForegroundInstanceMaskRequest { request, error in
            defer { semaphore.signal() }

            if let error = error {
                detectionError = error
                return
            }

            // 감지된 객체들을 처리
            guard let results = request.results as? [VNInstanceMaskObservation],
                  let firstResult = results.first else {
                return
            }

            // VNInstanceMaskObservation에서 실제 객체 경계 박스 계산
            // 픽셀 버퍼를 분석하여 전경 마스크의 실제 영역을 찾습니다
            if let maskBuffer = try? firstResult.generateMaskedImage(
                ofInstances: firstResult.allInstances,
                from: handler,
                croppedToInstancesExtent: false
            ) {
                detectedBoundingBox = self.calculateBoundingBox(from: maskBuffer)
            } else {
                // 마스크 생성 실패 시 전체 이미지 사용
                detectedBoundingBox = CGRect(x: 0, y: 0, width: 1, height: 1)
            }
        }

        // Vision 요청 실행
        try handler.perform([request])

        // 결과 대기
        _ = semaphore.wait(timeout: .now() + 5.0)

        if let error = detectionError {
            throw error
        }

        guard let boundingBox = detectedBoundingBox else {
            // 객체 감지 실패 시 전체 이미지를 정사각형으로 크롭
            return cropToSquare(image: image, focusCenter: nil)
        }

        // Vision 좌표계 (bottom-left origin)를 UIKit 좌표계 (top-left origin)로 변환
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let clampedX = max(0.0, min(1.0, boundingBox.origin.x))
        let clampedY = max(0.0, min(1.0, boundingBox.origin.y))
        let clampedWidth = max(0.0, min(1.0 - clampedX, boundingBox.width))
        let clampedHeight = max(0.0, min(1.0 - clampedY, boundingBox.height))

        let normalizedBoundingBox = CGRect(
            x: clampedX,
            y: 1.0 - clampedY - clampedHeight,
            width: clampedWidth,
            height: clampedHeight
        )
        let convertedBox = VNImageRectForNormalizedRect(
            normalizedBoundingBox,
            Int(imageSize.width),
            Int(imageSize.height)
        )

        // 정사각형 크롭 영역 계산
        let squareCropRect = calculateSquareCrop(for: convertedBox, imageSize: imageSize)

        // 이미지 크롭
        guard let croppedCGImage = cgImage.cropping(to: squareCropRect) else {
            throw ObjectCaptureError.cropFailed
        }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Depth map을 이미지와 같은 영역으로 크롭합니다.
    ///
    /// - Parameters:
    ///   - depthMap: 원본 depth map
    ///   - cropRect: 크롭 영역 (이미지 좌표계)
    ///   - originalImageSize: 원본 이미지 크기
    /// - Returns: 크롭된 depth map
    ///
    func cropDepthMap(_ depthMap: CVPixelBuffer, to cropRect: CGRect, originalImageSize: CGSize) -> CVPixelBuffer? {
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        // Depth map과 이미지의 스케일 비율 계산
        let scaleX = CGFloat(depthWidth) / originalImageSize.width
        let scaleY = CGFloat(depthHeight) / originalImageSize.height

        // 크롭 영역을 depth map 좌표로 변환
        let depthCropRect = CGRect(
            x: cropRect.origin.x * scaleX,
            y: cropRect.origin.y * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        )


        // CIImage로 변환하여 크롭
        let ciDepth = CIImage(cvPixelBuffer: depthMap)
        let croppedCI = ciDepth.cropped(to: depthCropRect)

        // CVPixelBuffer로 다시 변환
        var croppedBuffer: CVPixelBuffer?
        let width = Int(depthCropRect.width)
        let height = Int(depthCropRect.height)

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            nil,
            &croppedBuffer
        )

        guard status == kCVReturnSuccess, let outputBuffer = croppedBuffer else {
            return nil
        }

        // CIContext로 렌더링
        ciContext.render(croppedCI, to: outputBuffer)

        return outputBuffer
    }

    /// 크롭된 이미지를 임시 디렉토리에 JPEG로 저장합니다.
    ///
    /// - Parameter image: 저장할 이미지
    /// - Returns: 생성된 임시 파일 URL
    /// - Throws: 파일 저장 실패 시 에러
    func saveTemporaryJPEG(_ image: UIImage) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "clothiq_capture_\(UUID().uuidString).jpg"
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        guard let jpegData = image.jpegData(compressionQuality: Constants.jpegCompressionQuality) else {
            throw ObjectCaptureError.processingFailed
        }

        try jpegData.write(to: fileURL, options: .atomic)
        return fileURL
    }

    /// 객체 경계 박스를 포함하는 정사각형 크롭 영역을 계산합니다.
    ///
    /// - Parameters:
    ///   - boundingBox: 객체의 경계 박스
    ///   - imageSize: 원본 이미지 크기
    /// - Returns: 정사각형 크롭 영역
    ///
    /// ## Algorithm
    /// 1. 경계 박스의 긴 쪽을 기준으로 정사각형 크기 결정
    /// 2. 객체 중심을 기준으로 정사각형 배치
    /// 3. 이미지 경계를 벗어나지 않도록 조정
    /// 4. 여백 추가 (객체 크기의 30% - 객체가 잘리지 않도록)
    ///
    func calculateSquareCrop(for boundingBox: CGRect, imageSize: CGSize) -> CGRect {
        // 여백 추가 (30% - 객체가 잘리는 것 방지)
        let margin = Constants.cropMargin

        // 객체의 원래 중심을 유지 (중요!)
        let objectCenterX = boundingBox.midX
        let objectCenterY = boundingBox.midY

        // 여백을 포함한 크기 계산
        let expandedWidth = boundingBox.width * margin
        let expandedHeight = boundingBox.height * margin

        // 정사각형 크기 결정 (긴 쪽 기준)
        let desiredSize = max(expandedWidth, expandedHeight)

        // 객체를 중심에 유지하면서 크롭 영역 계산
        var squareSize = desiredSize
        var squareX = objectCenterX - squareSize / 2.0
        var squareY = objectCenterY - squareSize / 2.0

        // 이미지 경계를 벗어나는 경우 크롭 크기 조정 (위치는 조정하지 않음)
        if squareX < 0 || squareY < 0 ||
           squareX + squareSize > imageSize.width ||
           squareY + squareSize > imageSize.height {

            // 각 방향의 여유 공간 계산
            let leftSpace = objectCenterX
            let rightSpace = imageSize.width - objectCenterX
            let topSpace = objectCenterY
            let bottomSpace = imageSize.height - objectCenterY

            // 가장 제한적인 방향에 맞춰 크기 조정
            let maxHalfWidth = min(leftSpace, rightSpace)
            let maxHalfHeight = min(topSpace, bottomSpace)
            let maxHalfSize = min(maxHalfWidth, maxHalfHeight)

            squareSize = maxHalfSize * 2.0
            squareX = objectCenterX - maxHalfSize
            squareY = objectCenterY - maxHalfSize
        }

        // 최종 크롭 영역 (경계 내로 제한)
        return CGRect(
            x: max(0, squareX),
            y: max(0, squareY),
            width: min(squareSize, imageSize.width - max(0, squareX)),
            height: min(squareSize, imageSize.height - max(0, squareY))
        ).integral
    }

    /// 이미지를 정사각형으로 크롭합니다 (객체 미감지 시 대체 방법).
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - focusCenter: 포커스 중심 (nil이면 이미지 중심 사용)
    /// - Returns: 정사각형으로 크롭된 이미지
    ///
    func cropToSquare(image: UIImage, focusCenter: CGPoint?) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let squareSize = min(imageSize.width, imageSize.height)

        let center = focusCenter ?? CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)

        let cropRect = CGRect(
            x: center.x - squareSize / 2,
            y: center.y - squareSize / 2,
            width: squareSize,
            height: squareSize
        )

        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// 픽셀 버퍼에서 전경 마스크의 경계 박스를 계산합니다.
    ///
    /// - Parameter maskBuffer: 전경 마스크 픽셀 버퍼
    /// - Returns: 정규화된 경계 박스 (0.0 ~ 1.0)
    ///
    func calculateBoundingBox(from maskBuffer: CVPixelBuffer) -> CGRect {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(maskBuffer) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0

        // 마스크 픽셀을 스캔하여 전경 영역 찾기
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x
                if buffer[pixelIndex] > 128 {  // 전경 픽셀 (임계값 128)
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        // 유효한 경계 박스가 없으면 전체 이미지 반환
        guard minX < maxX, minY < maxY else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        // 정규화된 좌표로 변환
        let normalizedX = CGFloat(minX) / CGFloat(width)
        let normalizedY = CGFloat(minY) / CGFloat(height)
        let normalizedWidth = CGFloat(maxX - minX) / CGFloat(width)
        let normalizedHeight = CGFloat(maxY - minY) / CGFloat(height)

        return CGRect(
            x: normalizedX,
            y: normalizedY,
            width: normalizedWidth,
            height: normalizedHeight
        )
    }
}

//
//  ObjectCaptureService.swift
//  ClothIQ
//
//  Created on 2025-01-23
//
//  Description:
//  의류 객체 캡처를 위한 서비스입니다.
//  Vision Framework를 활용하여 객체 감지, 정사각형 크롭, 배경 제거를 수행합니다.
//
//  Key Responsibilities:
//  - 이미지에서 주요 객체(의류) 감지
//  - 객체를 포함하는 최소 정사각형 영역 계산
//  - Vision Framework를 사용한 배경 제거
//  - 처리된 이미지를 Photos 앱에 저장
//

import UIKit
import Vision
import CoreImage
import CoreVideo
import CoreGraphics

/// 객체 캡처 및 처리 서비스
///
/// 이미지에서 의류 객체를 감지하고, 정사각형으로 크롭한 후 배경을 제거합니다.
///
/// ## Topics
///
/// ### 객체 처리
/// - ``processImage(_:completion:)``
/// - ``detectAndCropObject(in:)``
/// - ``removeBackground(from:)``
///
/// ### 크롭 계산
/// - ``calculateSquareCrop(for:imageSize:)``
///
final class ObjectCaptureService {

    // MARK: - Types

    /// 캡처 후 처리 파이프라인 결과
    struct PostCaptureWorkflowResult {
        /// 1:1 정사각형으로 크롭된 이미지
        let croppedImage: UIImage
        /// 디스크에 임시 저장된 JPEG 파일 경로
        let temporaryJPEGURL: URL
        /// 배경 제거가 완료된 최종 이미지
        let backgroundRemovedImage: UIImage
        /// 전체 처리 시간 (초)
        let processingTime: TimeInterval
    }

    // MARK: - Properties

    /// Vision 요청 처리를 위한 큐
    private let processingQueue = DispatchQueue(label: "com.clothiq.objectcapture", qos: .userInitiated)

    /// Core Image 컨텍스트
    private let ciContext: CIContext

    // MARK: - Initialization

    init() {
        // GPU 가속 및 색공간 보존 설정
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: true,
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),  // RGB 색공간 보존
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()    // 출력도 RGB 유지
        ])
    }

    // MARK: - Public Methods

    /// 이미지를 1:1 정사각형으로 크롭합니다 (배경 제거 없음).
    ///
    /// - Parameters:
    ///   - image: 처리할 원본 이미지
    ///   - completion: 처리 완료 콜백 (성공 시 크롭된 이미지, 실패 시 에러)
    ///
    /// ## Processing Pipeline
    /// 1. 중앙 기준 1:1 정사각형 크롭만 수행
    /// 2. 배경 제거는 수행하지 않음
    ///
    /// - Note: 백그라운드 큐에서 처리 후 메인 스레드에서 콜백 호출
    ///
    func cropImageToSquare(_ image: UIImage, completion: @escaping (Result<UIImage, Error>) -> Void) {

        processingQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(.failure(ObjectCaptureError.processingFailed))
                }
                return
            }

            do {
                let cropResult = try self.detectAndCropObjectWithRect(in: image)
                let croppedImage = cropResult.image

                DispatchQueue.main.async {
                    completion(.success(croppedImage))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// 이미지를 처리하여 객체를 감지하고 배경을 제거합니다.
    ///
    /// - Parameters:
    ///   - image: 처리할 원본 이미지
    ///   - depthMap: LiDAR depth map (배경 분리에 사용, 선택)
    ///   - completion: 처리 완료 콜백 (성공 시 처리된 이미지, 실패 시 에러)
    ///
    /// ## Processing Pipeline
    /// 1. 객체 감지 및 정사각형 크롭 (백그라운드 큐)
    /// 2. 배경 제거 (LiDAR depth 우선, 실패 시 Saliency)
    /// 3. 이미지 최적화
    ///
    /// - Note: Vision 작업은 백그라운드에서, Core Image 작업은 메인 스레드에서 수행됩니다.
    ///
    struct ProcessedImageResult {
        let finalImage: UIImage
        let cropRect: CGRect
        let originalImageSize: CGSize
    }

    func processImage(
        _ image: UIImage,
        depthMap: CVPixelBuffer? = nil,
        completion: @escaping (Result<ProcessedImageResult, Error>) -> Void
    ) {
        // 가장 먼저 orientation 정규화
        let normalizedImage = image.normalizedOrientation()


        // Step 1: 객체 감지 및 크롭 (백그라운드 가능)
        processingQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(.failure(ObjectCaptureError.processingFailed))
                }
                return
            }

            do {
                // 객체 감지 및 정사각형 크롭 (크롭 영역 정보 반환) - 정규화된 이미지 사용
                let cropResult = try self.detectAndCropObjectWithRect(in: normalizedImage)
                let croppedImage = cropResult.image

                // Depth map도 같은 영역으로 크롭
                var croppedDepthMap: CVPixelBuffer?
                if let depth = depthMap, let cropRect = cropResult.cropRect {
                    croppedDepthMap = self.cropDepthMap(
                        depth,
                        to: cropRect,
                        originalImageSize: cropResult.originalImageSize
                    )
                } else {
                }

                // Step 2: 배경 제거는 메인 스레드에서 수행 (GPU 작업)
                DispatchQueue.main.async {

                    do {
                        // 배경 제거 시도 (크롭된 depth map 사용)
                        guard let cropRect = cropResult.cropRect else {
                            throw ObjectCaptureError.cropFailed
                        }

                        if let finalImage = try self.removeBackground(from: croppedImage, depthMap: croppedDepthMap) {
                            completion(.success(ProcessedImageResult(
                                finalImage: finalImage,
                                cropRect: cropRect,
                                originalImageSize: cropResult.originalImageSize
                            )))
                        } else {
                            // 배경 제거 실패 시 크롭된 이미지라도 반환 (폴백)
                            completion(.success(ProcessedImageResult(
                                finalImage: croppedImage,
                                cropRect: cropRect,
                                originalImageSize: cropResult.originalImageSize
                            )))
                        }
                    } catch {
                        // 배경 제거 중 에러 발생 시에도 크롭된 이미지 반환 (폴백)
                        if let cropRect = cropResult.cropRect {
                            completion(.success(ProcessedImageResult(
                                finalImage: croppedImage,
                                cropRect: cropRect,
                                originalImageSize: cropResult.originalImageSize
                            )))
                        } else {
                            completion(.failure(error))
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    /// 캡처 후 워크플로우를 실행합니다.
    ///
    /// - Parameters:
    ///   - image: AR에서 캡처한 원본 이미지
    ///   - depthMap: LiDAR depth map (선택)
    ///   - completion: 처리 완료 콜백
    ///
    /// ## Workflow
    /// 1. 객체 중심 1:1 크롭
    /// 2. 크롭 이미지를 JPEG로 임시 저장
    /// 3. 임시 JPEG를 기반으로 배경 제거
    /// 4. 최종 이미지를 반환
    ///
    func runPostCaptureWorkflow(
        from image: UIImage,
        depthMap: CVPixelBuffer? = nil,
        completion: @escaping (Result<PostCaptureWorkflowResult, Error>) -> Void
    ) {
        let workflowStart = Date()

        processingQueue.async { [weak self] in
            autoreleasepool {
                guard let self = self else {
                    DispatchQueue.main.async {
                        completion(.failure(ObjectCaptureError.processingFailed))
                    }
                    return
                }

                do {
                    let cropResult = try self.detectAndCropObjectWithRect(in: image)
                    let croppedImage = cropResult.image

                    let tempURL = try self.saveTemporaryJPEG(croppedImage)

                    guard let tempImage = UIImage(contentsOfFile: tempURL.path) else {
                        throw ObjectCaptureError.processingFailed
                    }

                    var croppedDepthMap: CVPixelBuffer?
                    if let depth = depthMap, let cropRect = cropResult.cropRect {
                        croppedDepthMap = self.cropDepthMap(
                            depth,
                            to: cropRect,
                            originalImageSize: cropResult.originalImageSize
                        )
                    } else {
                    }

                    guard let finalImage = try self.removeBackground(
                        from: tempImage,
                        depthMap: croppedDepthMap
                    ) else {
                        throw ObjectCaptureError.backgroundRemovalFailed
                    }

                    let result = PostCaptureWorkflowResult(
                        croppedImage: croppedImage,
                        temporaryJPEGURL: tempURL,
                        backgroundRemovedImage: finalImage,
                        processingTime: Date().timeIntervalSince(workflowStart)
                    )
                    DispatchQueue.main.async {
                        completion(.success(result))
                    }
                } catch {
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            }
        }
    }

    // MARK: - Object Detection & Cropping

    /// 크롭 결과 (이미지 + 크롭 영역 정보)
    private struct CropResult {
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
    private func detectAndCropObjectWithRect(in image: UIImage) throws -> CropResult {
        guard let cgImage = image.cgImage else {
            throw ObjectCaptureError.invalidImage
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        // Vision Framework를 사용하여 객체 감지
        if let objectBounds = detectObjectBounds(in: cgImage) {
            print("🎯 객체 감지 성공: \(objectBounds)")

            // 객체의 실제 바운딩 박스에 여백 추가 (10-15%)
            let padding: CGFloat = 0.1  // 10% 여백
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

            print("📐 크롭 영역: \(cropRect)")
            print("📏 비율: \(cropRect.width)x\(cropRect.height) = \(cropRect.width/cropRect.height)")

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
            print("⚠️ 객체 감지 실패, 중앙 크롭 사용")
            return try fallbackCenterCrop(cgImage: cgImage, imageSize: imageSize)
        }
    }

    /// 폴백: 중앙 정사각형 크롭
    private func fallbackCenterCrop(cgImage: CGImage, imageSize: CGSize) throws -> CropResult {
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
    private func detectObjectBounds(in cgImage: CGImage) -> CGRect? {
        // 전경 마스크 감지
        guard let maskBuffer = detectForegroundMask(cgImage: cgImage) else {
            print("❌ 마스크 생성 실패")
            return nil
        }

        // 마스크에서 객체 영역 계산
        return calculateObjectBoundingBox(from: maskBuffer, imageSize: CGSize(width: cgImage.width, height: cgImage.height))
    }

    /// 마스크에서 객체의 실제 바운딩 박스 계산
    private func calculateObjectBoundingBox(from maskBuffer: CVPixelBuffer, imageSize: CGSize) -> CGRect? {
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
        let threshold: UInt8 = 100  // 전경/배경 임계값

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
    private func detectAndCropObject(in image: UIImage) throws -> UIImage? {
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
    private func cropDepthMap(_ depthMap: CVPixelBuffer, to cropRect: CGRect, originalImageSize: CGSize) -> CVPixelBuffer? {
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
    private func saveTemporaryJPEG(_ image: UIImage) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "clothiq_capture_\(UUID().uuidString).jpg"
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
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
    private func calculateSquareCrop(for boundingBox: CGRect, imageSize: CGSize) -> CGRect {
        // 여백 추가 (30% - 객체가 잘리는 것 방지)
        let margin: CGFloat = 1.3

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
    private func cropToSquare(image: UIImage, focusCenter: CGPoint?) -> UIImage? {
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

    // MARK: - Background Removal

    /// 이미지에서 배경을 제거합니다.
    ///
    /// - Parameters:
    ///   - image: 크롭된 이미지
    ///   - depthMap: LiDAR depth map (우선 사용)
    /// - Returns: 배경이 제거된 이미지 (실패 시 nil)
    /// - Throws: Vision 요청 실패 시 에러
    ///
    /// ## Background Removal Process (우선순위)
    /// 1. **Vision 단독** (최우선) - VNGenerateForegroundInstanceMaskRequest (iOS 17+)
    /// 2. **LiDAR + Vision 하이브리드** (폴백1) - Depth로 영역 구분 + Vision으로 윤곽 정제
    /// 3. Saliency Detection (폴백2) - 시각적 주목도 기반
    /// 4. 중앙 80% 영역 (최종 폴백)
    ///
    /// - Note: 배경은 밝은 그레이(RGB 245)로 처리됩니다.
    ///
    private func removeBackground(from image: UIImage, depthMap: CVPixelBuffer?) throws -> UIImage? {
        // 이미 정규화된 이미지가 전달됨 (processImage에서 정규화)
        guard let cgImage = image.cgImage else {
            throw ObjectCaptureError.invalidImage
        }


        // 마스크 생성 우선순위
        let maskBuffer: CVPixelBuffer?

        // 1. Vision 단독 (최우선) - iOS의 강력한 전경 분리 기능
        if let visionMask = detectForegroundMask(cgImage: cgImage) {

            // Vision 마스크를 그대로 사용 (Depth 결합 비활성화)
            // 이유: Depth와 AND 연산 시 마스크가 축소되어 객체가 제거되는 문제 발생
            maskBuffer = visionMask

            // Depth 정보는 로깅만 수행
            if let depth = depthMap {
                _ = createDepthMask(from: depth, imageSize: CGSize(width: cgImage.width, height: cgImage.height))
            }
        }
        // 2. LiDAR 기반 (폴백1)
        else if let depth = depthMap {
            let depthMask = createDepthMask(from: depth, imageSize: CGSize(width: cgImage.width, height: cgImage.height))
            maskBuffer = convertCIImageToPixelBuffer(depthMask)
        }
        // 3. Saliency Detection (폴백2)
        else {
            if let saliency = detectSaliency(cgImage: cgImage) {
                maskBuffer = saliency
            }
            // 4. 중앙 영역 (최종 폴백)
            else {
                let centerMask = createCenterMask(for: cgImage)
                maskBuffer = convertCIImageToPixelBuffer(centerMask)
            }
        }

        guard let finalMask = maskBuffer else {
            return nil
        }


        // 마스크를 사용하여 배경을 밝은 그레이로 변경
        let result = applyMask(to: image, mask: finalMask)

        if result != nil {
        } else {
        }

        return result
    }

    /// Saliency Detection 수행 (헬퍼 메서드)
    private func detectSaliency(cgImage: CGImage) -> CVPixelBuffer? {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let semaphore = DispatchSemaphore(value: 0)
        var saliencyMap: CVPixelBuffer?

        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
            defer { semaphore.signal() }

            guard error == nil,
                  let results = request.results as? [VNSaliencyImageObservation],
                  let firstResult = results.first else {
                return
            }

            saliencyMap = firstResult.pixelBuffer
        }

        try? handler.perform([saliencyRequest])
        _ = semaphore.wait(timeout: .now() + 3.0)

        return saliencyMap
    }

    /// Vision Framework로 전경 마스크 감지 (정밀한 윤곽)
    ///
    /// generateScaledMaskForImage를 사용하여 고해상도 마스크 생성
    /// 마스크 후처리를 통해 품질 개선
    private func detectForegroundMask(cgImage: CGImage) -> CVPixelBuffer? {
        // 이미지는 이미 정규화되어 있으므로 orientation은 .up
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(.up), options: [:])
        let semaphore = DispatchSemaphore(value: 0)
        var foregroundMask: CVPixelBuffer?

        let maskRequest = VNGenerateForegroundInstanceMaskRequest { request, error in
            defer { semaphore.signal() }

            guard error == nil,
                  let results = request.results as? [VNInstanceMaskObservation],
                  let firstResult = results.first else {
                return
            }

            // 고해상도 마스크 생성 (generateScaledMaskForImage 사용)
            do {
                let scaledMask = try firstResult.generateScaledMaskForImage(
                    forInstances: firstResult.allInstances,
                    from: handler
                )

                // 마스크 통계 출력
                _ = CVPixelBufferGetWidth(scaledMask)
                _ = CVPixelBufferGetHeight(scaledMask)

                // 마스크 품질 분석
                _ = self.calculateWhitePixelRatio(in: scaledMask, threshold: 100)

                foregroundMask = scaledMask

            } catch {
                // 폴백: 저해상도 마스크 사용
                foregroundMask = firstResult.instanceMask
            }
        }

        try? handler.perform([maskRequest])
        _ = semaphore.wait(timeout: .now() + 5.0)  // Vision mask는 시간이 더 걸림

        // 마스크 후처리: Morphological 연산으로 품질 개선
        if let mask = foregroundMask {
            return refineMaskQuality(mask)
        }

        return foregroundMask
    }

    /// 마스크 품질 개선 (Morphological 연산 + 이진화)
    ///
    /// - Parameter mask: 원본 마스크
    /// - Returns: 개선된 마스크
    ///
    /// Closing 연산(Dilation → Erosion)으로 마스크 내부의 작은 구멍을 메우고
    /// 노이즈를 제거한 후, 이진화하여 명확한 경계를 만듭니다.
    ///
    /// ## Processing Pipeline
    /// 1. Dilation (radius: 6) → 구멍 메우기
    /// 2. Erosion (radius: 5) → 약간의 확장 유지 (순 확장: 1픽셀)
    /// 3. Binarization (contrast: 10) → 0 또는 255로 명확히 구분
    /// 4. Quality Check → 전경 비율 검증
    ///
    private func refineMaskQuality(_ mask: CVPixelBuffer) -> CVPixelBuffer {
        let ciMask = CIImage(cvPixelBuffer: mask)
        var refinedMask = ciMask


        // 1. Dilation: 전경 영역 확장 (더 큰 구멍 메우기)
        if let morphologyMax = CIFilter(name: "CIMorphologyMaximum") {
            morphologyMax.setValue(refinedMask, forKey: kCIInputImageKey)
            morphologyMax.setValue(10.0, forKey: kCIInputRadiusKey)  // 6 → 10 증가
            if let dilated = morphologyMax.outputImage {
                refinedMask = dilated
            }
        }

        // 2. Erosion: 확장된 영역 복원 (순 확장 2픽셀 유지)
        if let morphologyMin = CIFilter(name: "CIMorphologyMinimum") {
            morphologyMin.setValue(refinedMask, forKey: kCIInputImageKey)
            morphologyMin.setValue(8.0, forKey: kCIInputRadiusKey)  // 5 → 8 증가
            if let eroded = morphologyMin.outputImage {
                refinedMask = eroded
            }
        }

        // 3. Gaussian Blur: 가장자리 부드럽게 (anti-aliasing 효과)
        if let gaussianBlur = CIFilter(name: "CIGaussianBlur") {
            gaussianBlur.setValue(refinedMask, forKey: kCIInputImageKey)
            gaussianBlur.setValue(1.5, forKey: kCIInputRadiusKey)  // 작은 blur로 가장자리 부드럽게
            if let blurred = gaussianBlur.outputImage {
                refinedMask = blurred
            }
        }

        // 4. 마스크 이진화 (부드러운 contrast 적용)
        // 중간 회색 값을 부드럽게 0 또는 255로 구분
        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(refinedMask, forKey: kCIInputImageKey)
            colorControls.setValue(6.0, forKey: kCIInputContrastKey)  // 10 → 6 감소 (덜 날카롭게)
            if let binarized = colorControls.outputImage {
                refinedMask = binarized
            }
        }

        // CIImage를 CVPixelBuffer로 변환
        if let refinedBuffer = convertCIImageToPixelBuffer(refinedMask) {

            // 최종 마스크 통계 확인
            let finalWhiteRatio = calculateWhitePixelRatio(in: refinedBuffer, threshold: 100)

            // 마스크 품질 검증
            if finalWhiteRatio < 0.05 {
            } else if finalWhiteRatio > 0.8 {
            }

            return refinedBuffer
        } else {
            return mask
        }
    }

    /// Vision 마스크를 Depth 정보로 개선 (선택적)
    ///
    /// - Parameters:
    ///   - visionMask: Vision 기반 마스크 (정밀한 윤곽)
    ///   - depthMask: LiDAR depth 기반 마스크 (거친 영역 구분)
    /// - Returns: 개선된 마스크
    ///
    /// Vision 마스크를 우선 사용하되, Depth 정보로 false positive를 제거
    ///
    private func refineVisionMaskWithDepth(visionMask: CVPixelBuffer, depthMask: CIImage) -> CVPixelBuffer {

        // Vision 마스크를 CIImage로 변환
        let visionCIMask = CIImage(cvPixelBuffer: visionMask)

        // Depth 마스크를 Vision 마스크와 같은 크기로 스케일
        let visionWidth = CVPixelBufferGetWidth(visionMask)
        let visionHeight = CVPixelBufferGetHeight(visionMask)
        let imageSize = CGSize(width: visionWidth, height: visionHeight)

        let maskExtent = depthMask.extent
        let scaleX = imageSize.width / maskExtent.width
        let scaleY = imageSize.height / maskExtent.height

        let scaledDepthMask = depthMask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: imageSize))

        // Vision 마스크와 Depth 마스크를 곱셈(AND 연산)으로 결합
        // 두 마스크 모두 전경인 영역만 선택
        guard let multiplyFilter = CIFilter(name: "CIMultiplyBlendMode") else {
            return visionMask
        }

        multiplyFilter.setValue(visionCIMask, forKey: kCIInputImageKey)
        multiplyFilter.setValue(scaledDepthMask, forKey: kCIInputBackgroundImageKey)

        guard let combinedMask = multiplyFilter.outputImage else {
            return visionMask
        }

        // CIImage를 CVPixelBuffer로 변환
        if let refinedBuffer = convertCIImageToPixelBuffer(combinedMask) {
            return refinedBuffer
        } else {
            return visionMask
        }
    }

    /// CIImage를 CVPixelBuffer로 변환
    private func convertCIImageToPixelBuffer(_ ciImage: CIImage) -> CVPixelBuffer? {
        let width = Int(ciImage.extent.width)
        let height = Int(ciImage.extent.height)

        var pixelBuffer: CVPixelBuffer?
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

        // CIImage를 렌더링
        ciContext.render(ciImage, to: buffer)
        return buffer
    }

    /// 마스크를 적용하여 배경을 밝은 그레이로 변경합니다 (픽셀 단위 블렌딩).
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - mask: CIImage 마스크 (흰색=전경, 검은색=배경)
    /// - Returns: 배경이 밝은 그레이로 처리된 이미지
    ///
    private func applyMask(to image: UIImage, mask: CIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }


        // 마스크를 CGImage로 변환
        let maskExtent = mask.extent
        guard let maskCGImage = ciContext.createCGImage(mask, from: maskExtent) else {
            return nil
        }

        // 마스크와 이미지 해상도 검증
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        let maskWidth = maskCGImage.width
        let maskHeight = maskCGImage.height

        let finalMask: CGImage

        // 해상도가 다른 경우에만 리사이즈
        if maskWidth != imageWidth || maskHeight != imageHeight {
            print("⚠️ 마스크 해상도 불일치: 마스크(\(maskWidth)x\(maskHeight)) vs 이미지(\(imageWidth)x\(imageHeight))")
            print("📐 마스크 리사이징 시작...")

            guard let resized = resizeMask(maskCGImage, to: CGSize(width: imageWidth, height: imageHeight)) else {
                print("❌ 마스크 리사이징 실패")
                return nil
            }
            finalMask = resized
            print("✅ 마스크 리사이징 완료")
        } else {
            // 해상도가 같으면 리사이즈 건너뛰기
            print("✅ 마스크 해상도 일치: \(maskWidth)x\(maskHeight)")
            finalMask = maskCGImage
        }

        // 마스크 통계 분석 (디버깅)
        let maskStats = analyzeMaskStats(finalMask)

        // 픽셀 단위로 마스크 적용
        let result = applyMaskPixelByPixel(image: cgImage, mask: finalMask)

        if result != nil {
        } else {
        }

        return result.map { UIImage(cgImage: $0, scale: 1.0, orientation: .up) }
    }

    /// 마스크를 특정 크기로 리사이즈
    private func resizeMask(_ mask: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)

        // Grayscale 컬러 스페이스 명시
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray) else {
            return nil
        }

        // bytesPerRow를 0으로 설정하면 시스템이 자동으로 적절한 값 계산
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,  // 시스템이 자동으로 alignment를 고려하여 계산
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(mask, in: CGRect(origin: .zero, size: size))

        guard let resizedImage = context.makeImage() else {
            return nil
        }

        return resizedImage
    }

    /// 픽셀 단위로 마스크를 적용하여 배경을 회색으로 변경
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - mask: 마스크 (흰색=전경, 검은색=배경)
    /// - Returns: 배경이 회색으로 처리된 CGImage
    ///
    /// ## Threshold Strategy
    /// 마스크 임계값을 100으로 낮춰서 더 많은 전경 픽셀을 보존합니다.
    /// (이전 128 → 현재 100)
    ///
    private func applyMaskPixelByPixel(image: CGImage, mask: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height

        // RGB 컨텍스트 생성 (알파 없음)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            return nil
        }

        // 원본 이미지 그리기
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let imageData = context.data else {
            return nil
        }

        // 마스크 데이터 읽기
        // bytesPerRow를 0으로 설정하여 시스템이 자동으로 alignment를 고려한 값을 계산하도록 함
        guard let maskColorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let maskContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,  // 시스템이 자동으로 alignment를 고려하여 계산
                space: maskColorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return nil
        }

        maskContext.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let maskData = maskContext.data else {
            return nil
        }

        let imageBuffer = imageData.assumingMemoryBound(to: UInt8.self)
        let maskBuffer = maskData.assumingMemoryBound(to: UInt8.self)

        // 실제 mask의 bytesPerRow 가져오기 (alignment 포함)
        let maskBytesPerRow = maskContext.bytesPerRow

        let backgroundColor: (r: UInt8, g: UInt8, b: UInt8) = (245, 245, 245)

        // 임계값을 128로 설정 (이진화된 마스크에 최적)
        // 이유: 마스크가 이진화되어 0 또는 255 값만 가지므로 중간 값 128이 적절
        let threshold: UInt8 = 100  // 128 → 100 (더 많은 전경 픽셀 보존)

        var foregroundPixels = 0
        var backgroundPixels = 0

        // 픽셀 단위로 블렌딩
        for y in 0..<height {
            for x in 0..<width {
                // 수정: maskBytesPerRow를 사용하여 정확한 픽셀 위치 계산
                let maskIndex = y * maskBytesPerRow + x
                let imageIndex = (y * width + x) * 4

                let maskValue = maskBuffer[maskIndex]

                // 마스크가 임계값보다 작으면 배경으로 처리
                if maskValue < threshold {
                    imageBuffer[imageIndex] = backgroundColor.r      // R
                    imageBuffer[imageIndex + 1] = backgroundColor.g  // G
                    imageBuffer[imageIndex + 2] = backgroundColor.b  // B
                    // imageBuffer[imageIndex + 3]은 이미 255 (불투명)
                    backgroundPixels += 1
                } else {
                    // 마스크가 임계값 이상이면 원본 유지
                    foregroundPixels += 1
                }
            }
        }

        let totalPixels = width * height

        return context.makeImage()
    }

    /// 마스크를 적용하여 배경을 밝은 그레이로 변경합니다 (CVPixelBuffer 버전).
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - mask: Vision에서 생성된 마스크
    /// - Returns: 배경이 밝은 그레이로 처리된 이미지
    ///
    private func applyMask(to image: UIImage, mask: CVPixelBuffer) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }


        // CVPixelBuffer를 CGImage로 변환
        let maskCIImage = CIImage(cvPixelBuffer: mask)
        guard let maskCGImage = ciContext.createCGImage(maskCIImage, from: maskCIImage.extent) else {
            return nil
        }

        // 마스크를 이미지 크기에 맞게 리사이즈
        let resizedMask = resizeMask(maskCGImage, to: CGSize(width: cgImage.width, height: cgImage.height))
        guard let finalMask = resizedMask else {
            return nil
        }

        // 마스크 통계 분석 (디버깅)
        let whiteRatio = calculateWhitePixelRatio(in: mask)

        let maskStats = analyzeMaskStats(finalMask)

        // Vision 마스크는 흰색=전경, 검은색=배경이므로 반전 불필요
        // (Vision Framework가 제공하는 마스크를 그대로 신뢰)

        // 픽셀 단위로 마스크 적용
        let result = applyMaskPixelByPixel(image: cgImage, mask: finalMask)

        if result != nil {
        } else {
        }

        return result.map { UIImage(cgImage: $0, scale: 1.0, orientation: .up) }
    }

    /// 마스크를 반전 (흰색↔검은색)
    private func invertMask(_ mask: CGImage) -> CGImage? {
        let width = mask.width
        let height = mask.height

        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return nil
        }

        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }

        let buffer = data.assumingMemoryBound(to: UInt8.self)
        let totalPixels = width * height

        // 픽셀 반전
        for i in 0..<totalPixels {
            buffer[i] = 255 - buffer[i]
        }

        return context.makeImage()
    }

    // MARK: - Mask Analysis

    /// CGImage 마스크 통계 분석 (디버깅용)
    ///
    /// - Parameter maskImage: 분석할 마스크 CGImage
    /// - Returns: 마스크 통계 (평균 밝기, 흰색 비율)
    ///
    private func analyzeMaskStats(_ maskImage: CGImage) -> (avgBrightness: Double, whiteRatio: Double) {
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
    private func calculateWhitePixelRatio(in maskBuffer: CVPixelBuffer, threshold: UInt8 = 200) -> Double {
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
    private func createBinaryMaskImage(
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

    // MARK: - Bounding Box Calculation

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
    private func createDepthMask(from depthBuffer: CVPixelBuffer, imageSize: CGSize) -> CIImage {
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

        let foregroundRatio = Double(foregroundCount) / Double(width * height)

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
    private func createSaliencyMask(from saliencyBuffer: CVPixelBuffer, imageSize: CGSize) -> CIImage {
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
    private func createCenterMask(imageSize: CGSize) -> CIImage {
        let margin: CGFloat = 0.1
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
    private func createCenterMask(for cgImage: CGImage) -> CIImage {
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
    private func createRectangleMask(
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
            let margin: CGFloat = 0.1
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

    /// 픽셀 버퍼에서 전경 마스크의 경계 박스를 계산합니다.
    ///
    /// - Parameter maskBuffer: 전경 마스크 픽셀 버퍼
    /// - Returns: 정규화된 경계 박스 (0.0 ~ 1.0)
    ///
    private func calculateBoundingBox(from maskBuffer: CVPixelBuffer) -> CGRect {
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

// MARK: - Error Types

/// 객체 캡처 처리 중 발생할 수 있는 에러
enum ObjectCaptureError: LocalizedError {
    case invalidImage
    case objectNotDetected
    case cropFailed
    case maskGenerationFailed
    case backgroundRemovalFailed
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "유효하지 않은 이미지입니다."
        case .objectNotDetected:
            return "이미지에서 객체를 감지할 수 없습니다."
        case .cropFailed:
            return "이미지 크롭에 실패했습니다."
        case .maskGenerationFailed:
            return "마스크 생성에 실패했습니다."
        case .backgroundRemovalFailed:
            return "배경 제거에 실패했습니다."
        case .processingFailed:
            return "이미지 처리에 실패했습니다."
        }
    }
}

// MARK: - CGImagePropertyOrientation Extension

extension CGImagePropertyOrientation {
    /// UIImage.Orientation을 CGImagePropertyOrientation으로 변환
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

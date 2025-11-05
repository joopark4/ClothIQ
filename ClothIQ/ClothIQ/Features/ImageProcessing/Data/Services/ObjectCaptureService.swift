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

    /// 처리된 이미지 결과
    struct ProcessedImageResult {
        let finalImage: UIImage
        let cropRect: CGRect
        let originalImageSize: CGSize
    }

    // MARK: - Constants

    /// 이미지 처리 관련 상수
    enum Constants {
        // MARK: Object Detection & Cropping
        /// 객체 감지 시 적용할 패딩 비율 (0.1 = 10%)
        static let objectDetectionPadding: CGFloat = 0.1

        /// 크롭 영역 마진 배율
        static let cropMargin: CGFloat = 1.3

        // MARK: Background Removal
        /// 마스크 이진화 임계값 (0-255)
        static let maskThreshold: UInt8 = 100

        /// Morphological Dilation 반경
        static let morphologyDilationRadius: CGFloat = 10.0

        /// Morphological Erosion 반경
        static let morphologyErosionRadius: CGFloat = 8.0

        /// Gaussian Blur 반경
        static let gaussianBlurRadius: CGFloat = 2.0

        /// Color Controls 밝기 조정값
        static let colorControlsBrightness: CGFloat = 0.05

        // MARK: Coverage Thresholds
        /// 최소 마스크 커버리지 (1%)
        static let minimumMaskCoverage: Double = 0.01

        /// 최대 마스크 커버리지 (95%)
        static let maximumMaskCoverage: Double = 0.95

        /// 중앙 영역 크롭 비율 (폴백용, 80%)
        static let centerCropRatio: CGFloat = 0.8

        /// 중앙 영역 마진 (10% = 중앙 80% 영역 사용)
        static let centerMargin: CGFloat = 0.1

        // MARK: Image Quality
        /// JPEG 압축 품질 (90%)
        static let jpegCompressionQuality: CGFloat = 0.9
    }

    // MARK: - Properties

    /// Vision 요청 처리를 위한 큐
    private let processingQueue = DispatchQueue(label: "com.clothiq.objectcapture", qos: .userInitiated)

    /// Core Image 컨텍스트
    let ciContext: CIContext

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

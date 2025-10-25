//
//  ImageCaptureUtility.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  이미지 캡처 및 처리 유틸리티입니다.
//  AR 화면 스크린샷, 이미지 압축, 파일 저장 등을 제공합니다.
//
//  Key Responsibilities:
//  - UIView/ARView 스크린샷 캡처
//  - 이미지 압축 및 최적화
//  - 이미지 메타데이터 추가
//

import UIKit
import ARKit
import RealityKit

/// 이미지 캡처 유틸리티
///
/// 화면 캡처, 이미지 처리, 저장 관련 기능을 제공합니다.
///
struct ImageCaptureUtility {

    // MARK: - Screenshot Capture

    /// UIView의 스크린샷 캡처
    ///
    /// - Parameter view: 캡처할 뷰
    /// - Returns: 캡처된 이미지
    static func captureScreenshot(of view: UIView) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        return renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    /// ARView의 현재 프레임 캡처
    ///
    /// - Parameter arView: AR 뷰
    /// - Returns: 캡처된 이미지
    static func captureARFrame(from arView: ARView) -> UIImage? {
        guard let currentFrame = arView.session.currentFrame else {
            return nil
        }

        return captureImage(from: currentFrame)
    }

    /// ARFrame에서 이미지 캡처
    ///
    /// - Parameter frame: AR 프레임
    /// - Returns: 캡처된 이미지
    static func captureImage(from frame: ARFrame) -> UIImage? {
        let pixelBuffer = frame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        // 올바른 방향으로 회전
        let orientation = UIImage.Orientation.right // Portrait 모드 기준
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }

    // MARK: - Image Processing

    /// 이미지 압축
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - quality: 압축 품질 (0.0 ~ 1.0)
    /// - Returns: 압축된 이미지 데이터
    static func compressImage(
        _ image: UIImage,
        quality: CGFloat = 0.8
    ) -> Data? {
        return image.jpegData(compressionQuality: quality)
    }

    /// 이미지 리사이즈
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - targetSize: 목표 크기
    /// - Returns: 리사이즈된 이미지
    static func resizeImage(
        _ image: UIImage,
        to targetSize: CGSize
    ) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// 이미지 크기 최적화
    ///
    /// 최대 크기 제한을 적용하여 이미지를 리사이즈합니다.
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - maxDimension: 최대 너비 또는 높이
    /// - Returns: 최적화된 이미지
    static func optimizeImageSize(
        _ image: UIImage,
        maxDimension: CGFloat = 1920
    ) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else {
            return image
        }

        let aspectRatio = size.width / size.height
        let targetSize: CGSize

        if size.width > size.height {
            targetSize = CGSize(
                width: maxDimension,
                height: maxDimension / aspectRatio
            )
        } else {
            targetSize = CGSize(
                width: maxDimension * aspectRatio,
                height: maxDimension
            )
        }

        return resizeImage(image, to: targetSize) ?? image
    }

    // MARK: - Image Annotation

    /// 이미지에 측정 포인트 오버레이
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - points: 측정 포인트 목록
    /// - Returns: 주석이 추가된 이미지
    static func annotateImage(
        _ image: UIImage,
        with points: [MeasurementPoint]
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)

        return renderer.image { context in
            // 원본 이미지 그리기
            image.draw(at: .zero)

            let cgContext = context.cgContext

            // 측정 포인트 그리기
            for (index, point) in points.enumerated() {
                let position = point.screenPosition

                // 포인트 원 그리기
                let circleRect = CGRect(
                    x: position.x - 20,
                    y: position.y - 20,
                    width: 40,
                    height: 40
                )

                // 신뢰도에 따른 색상
                let color = confidenceColor(for: point.confidence)
                cgContext.setStrokeColor(color)
                cgContext.setLineWidth(3.0)
                cgContext.strokeEllipse(in: circleRect)

                // 포인트 번호 그리기
                let numberText = "\(index + 1)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 16),
                    .foregroundColor: UIColor.white
                ]

                let textSize = numberText.size(withAttributes: attributes)
                let textRect = CGRect(
                    x: position.x - textSize.width / 2,
                    y: position.y - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )

                numberText.draw(in: textRect, withAttributes: attributes)
            }

            // 연결선 그리기
            if points.count >= 2 {
                cgContext.setStrokeColor(UIColor.systemBlue.cgColor)
                cgContext.setLineWidth(2.0)
                cgContext.setLineDash(phase: 0, lengths: [5, 3])

                for i in 0..<points.count - 1 {
                    let start = points[i].screenPosition
                    let end = points[i + 1].screenPosition

                    cgContext.move(to: start)
                    cgContext.addLine(to: end)
                }

                cgContext.strokePath()
            }
        }
    }

    /// 신뢰도에 따른 색상 반환
    private static func confidenceColor(for confidence: Float) -> CGColor {
        switch confidence {
        case 0.9...1.0:
            return UIColor.systemGreen.cgColor
        case 0.7..<0.9:
            return UIColor.systemBlue.cgColor
        case 0.5..<0.7:
            return UIColor.systemOrange.cgColor
        default:
            return UIColor.systemRed.cgColor
        }
    }

    // MARK: - Metadata

    /// 이미지에 메타데이터 추가
    ///
    /// - Parameters:
    ///   - imageData: 이미지 데이터
    ///   - metadata: 추가할 메타데이터
    /// - Returns: 메타데이터가 추가된 이미지 데이터
    static func addMetadata(
        to imageData: Data,
        metadata: [String: Any]
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let imageType = CGImageSourceGetType(source),
              let mutableData = CFDataCreateMutable(nil, 0) as? NSMutableData else {
            return nil
        }

        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            imageType,
            1,
            nil
        ) else {
            return nil
        }

        // 기존 메타데이터 가져오기
        var imageMetadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]

        // 새 메타데이터 추가
        imageMetadata.merge(metadata) { _, new in new }

        // 이미지 추가
        if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            CGImageDestinationAddImage(destination, cgImage, imageMetadata as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }

    // MARK: - Thumbnail Generation

    /// 썸네일 생성
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - size: 썸네일 크기
    /// - Returns: 썸네일 이미지
    static func generateThumbnail(
        from image: UIImage,
        size: CGSize = CGSize(width: 200, height: 200)
    ) -> UIImage? {
        return resizeImage(image, to: size)
    }
}

// MARK: - Image Quality Presets

extension ImageCaptureUtility {
    /// 이미지 품질 프리셋
    enum ImageQuality {
        case low
        case medium
        case high
        case original

        var compressionQuality: CGFloat {
            switch self {
            case .low:
                return 0.3
            case .medium:
                return 0.6
            case .high:
                return 0.8
            case .original:
                return 1.0
            }
        }

        var maxDimension: CGFloat {
            switch self {
            case .low:
                return 1024
            case .medium:
                return 1920
            case .high:
                return 2560
            case .original:
                return .greatestFiniteMagnitude
            }
        }
    }

    /// 프리셋을 사용한 이미지 최적화
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - quality: 품질 프리셋
    /// - Returns: 최적화된 이미지 데이터
    static func optimizeImage(
        _ image: UIImage,
        quality: ImageQuality = .high
    ) -> Data? {
        let optimizedImage = optimizeImageSize(image, maxDimension: quality.maxDimension)
        return compressImage(optimizedImage, quality: quality.compressionQuality)
    }
}

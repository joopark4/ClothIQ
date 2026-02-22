//
//  ObjectCaptureService+Helpers.swift
//  ClothIQ
//
//  Created on 2025-01-23
//
//  Description:
//  ObjectCaptureService의 유틸리티 메서드 확장입니다.
//

import UIKit
import CoreImage
import CoreVideo

extension ObjectCaptureService {

    // MARK: - Helper Methods

    /// CIImage를 CVPixelBuffer로 변환합니다.
    ///
    /// - Parameter ciImage: 변환할 CIImage
    /// - Returns: 변환된 CVPixelBuffer, 실패 시 nil
    func convertCIImageToPixelBuffer(_ ciImage: CIImage) -> CVPixelBuffer? {
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
}

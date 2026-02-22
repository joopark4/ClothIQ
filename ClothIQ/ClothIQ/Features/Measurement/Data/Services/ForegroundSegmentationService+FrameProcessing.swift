//
//  ForegroundSegmentationService+FrameProcessing.swift
//  ClothIQ
//
//  Created on 2025-01-23
//
//  Description:
//  ForegroundSegmentationService의 프레임 처리 및 마스크 생성 관련 메서드 확장입니다.
//

import Foundation
import Vision
import CoreImage
import UIKit
import CoreVideo

extension ForegroundSegmentationService {

    // MARK: - Frame Processing

    /// 전경 객체 추출 (사각형 감지 기반)
    ///
    /// 윤곽 기반 전경 마스크 생성 (실패 시 사각형 기반으로 대체)
    func extractForeground(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        if let contourMask = extractUsingContours(from: pixelBuffer) {
            return contourMask
        }

        return extractUsingRectangle(from: pixelBuffer)
    }

    /// 컨투어 기반 전경 마스크 추출
    func extractUsingContours(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 768

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])

            guard let observation = request.results?.first,
                  observation.contourCount > 0 else {
                return nil
            }

            let mask = createMaskFromContours(
                observation,
                imageSize: CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )
            )

            return mask

        } catch {
            return nil
        }
    }

    /// 사각형 기반 전경 마스크 추출 (윤곽 감지 실패 시 사용)
    func extractUsingRectangle(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = Constants.rectangleMinimumAspectRatio
        request.maximumAspectRatio = 3.0
        request.minimumSize = Constants.rectangleMinimumSize
        request.maximumObservations = 10
        request.minimumConfidence = 0.4

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])

            guard let observations = request.results,
                  !observations.isEmpty else {
                return nil
            }

            guard let largestRectangle = observations.max(by: { rect1, rect2 in
                let area1 = rect1.boundingBox.width * rect1.boundingBox.height
                let area2 = rect2.boundingBox.width * rect2.boundingBox.height
                return area1 < area2
            }) else {
                return nil
            }

            let maskBuffer = createMaskFromRectangle(
                largestRectangle,
                imageSize: CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )
            )

            return maskBuffer

        } catch {
            return nil
        }
    }

    // MARK: - Mask Creation

    /// 컨투어 결과를 픽셀 버퍼 마스크로 변환
    func createMaskFromContours(
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
    func append(
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
    func contourArea(_ contour: VNContour) -> CGFloat {
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
    func createMaskFromRectangle(
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

    /// CVPixelBuffer 마스크를 UIImage로 변환
    func convertMaskToImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

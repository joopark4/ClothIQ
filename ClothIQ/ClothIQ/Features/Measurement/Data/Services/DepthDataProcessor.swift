//
//  DepthDataProcessor.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  LiDAR 깊이 데이터 처리 유틸리티입니다.
//  ARFrame의 Scene Depth 데이터를 추출하고 처리합니다.
//
//  Key Responsibilities:
//  - 깊이 맵에서 값 샘플링
//  - 신뢰도 맵 처리
//  - 화면 좌표 → 깊이 데이터 변환
//

import Foundation
import ARKit
import CoreVideo
import UIKit
import CoreGraphics

/// 깊이 데이터 처리 유틸리티
///
/// LiDAR Scene Depth 데이터를 처리하는 헬퍼 클래스입니다.
///
struct DepthDataProcessor {

    // MARK: - Depth Extraction

    /// 화면 좌표에서 깊이 값을 추출합니다.
    ///
    /// - Parameters:
    ///   - point: 화면 좌표
    ///   - depthMap: 깊이 맵 (CVPixelBuffer)
    /// - Returns: 깊이 값 (미터), 실패 시 nil
    static func extractDepth(
        at point: CGPoint,
        from depthMap: CVPixelBuffer
    ) -> Float? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        // 화면 좌표를 깊이 맵 좌표로 변환 (이미 정규화되어 있다고 가정)
        // point.x, point.y는 0~1 범위의 normalized 좌표
        // AutoSize02.md: 경계값 처리를 위해 0...(resolution-1) 범위로 clamp
        let u = max(0, min(width - 1, Int(point.x * CGFloat(width))))
        let v = max(0, min(height - 1, Int(point.y * CGFloat(height))))

        // 픽셀 버퍼 잠금
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        // 깊이 값 읽기
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        let rowData = baseAddress + v * bytesPerRow
        let depth = rowData.assumingMemoryBound(to: Float32.self)[u]

        // 유효하지 않은 깊이 값 필터링
        guard depth > 0 && depth.isFinite else {
            return nil
        }

        return depth
    }

    // MARK: - Confidence Extraction

    /// 화면 좌표에서 신뢰도 값을 추출합니다.
    ///
    /// - Parameters:
    ///   - point: 화면 좌표
    ///   - confidenceMap: 신뢰도 맵 (CVPixelBuffer)
    /// - Returns: 신뢰도 (0.0 ~ 1.0), 실패 시 nil
    static func extractConfidence(
        at point: CGPoint,
        from confidenceMap: CVPixelBuffer?
    ) -> Float? {
        guard let confidenceMap = confidenceMap else {
            return 0.7 // 기본값
        }

        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)

        let normalizedX = Float(point.x) / Float(width)
        let normalizedY = Float(point.y) / Float(height)

        // AutoSize02.md: 경계값 처리를 위해 0...(resolution-1) 범위로 clamp
        let u = max(0, min(width - 1, Int(normalizedX * Float(width))))
        let v = max(0, min(height - 1, Int(normalizedY * Float(height))))

        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
            return nil
        }

        let rowData = baseAddress + v * bytesPerRow
        let confidenceValue = rowData.assumingMemoryBound(to: UInt8.self)[u]

        // ARConfidenceLevel: 0 (low), 1 (medium), 2 (high)
        // 0.0 ~ 1.0 범위로 정규화
        return Float(confidenceValue) / 2.0
    }

    // MARK: - World Position Calculation

    /// 화면 좌표와 깊이를 사용하여 3D 월드 좌표를 계산합니다.
    ///
    /// 카메라 intrinsics를 사용하여 정확한 3D 좌표를 계산합니다.
    ///
    /// - Parameters:
    ///   - screenPoint: 화면 좌표 (픽셀 좌표)
    ///   - depth: 깊이 값 (미터)
    ///   - camera: AR 카메라
    ///   - viewportSize: 뷰포트 크기
    /// - Returns: 월드 좌표
    static func calculateWorldPosition(
        screenPoint: CGPoint,
        depth: Float,
        camera: ARCamera,
        viewportSize: CGSize
    ) -> SIMD3<Float> {
        // 카메라 내부 파라미터 (intrinsics)
        let intrinsics = camera.intrinsics
        let imageResolution = camera.imageResolution

        // 화면 좌표를 이미지 해상도 좌표계로 변환
        let scaleX = imageResolution.width / viewportSize.width
        let scaleY = imageResolution.height / viewportSize.height

        let imagePoint = CGPoint(
            x: screenPoint.x * scaleX,
            y: screenPoint.y * scaleY
        )

        // Camera intrinsics에서 파라미터 추출
        let fx = intrinsics[0, 0]  // focal length X
        let fy = intrinsics[1, 1]  // focal length Y
        let cx = intrinsics[2, 0]  // principal point X
        let cy = intrinsics[2, 1]  // principal point Y

        // 카메라 좌표계에서 3D 위치 계산 (핀홀 카메라 모델)
        let x = (Float(imagePoint.x) - cx) * depth / fx
        let y = (Float(imagePoint.y) - cy) * depth / fy
        let z = -depth  // ARKit은 카메라가 -Z 방향을 바라봄

        let cameraSpacePosition = SIMD3<Float>(x, y, z)

        // 카메라 좌표계 → 월드 좌표계 변환
        let cameraTransform = camera.transform
        let worldPosition4 = cameraTransform * SIMD4<Float>(cameraSpacePosition, 1.0)
        let worldPosition = SIMD3<Float>(worldPosition4.x, worldPosition4.y, worldPosition4.z)

        print("📍 좌표 변환: 화면(\(screenPoint.x), \(screenPoint.y)) → 이미지(\(imagePoint.x), \(imagePoint.y)) → 카메라(\(x), \(y), \(z)) → 월드(\(worldPosition.x), \(worldPosition.y), \(worldPosition.z)) @ \(depth)m")

        return worldPosition
    }


    // MARK: - Quality Assessment

    /// 깊이 데이터의 품질을 평가합니다.
    ///
    /// - Parameter depthMap: 깊이 맵
    /// - Returns: 품질 점수 (0.0 ~ 1.0)
    static func assessDepthQuality(depthMap: CVPixelBuffer) -> Float {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let totalPixels = width * height

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return 0.0
        }

        var validPixelCount = 0
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        for y in 0..<height {
            let rowData = baseAddress + y * bytesPerRow
            let pixels = rowData.assumingMemoryBound(to: Float32.self)

            for x in 0..<width {
                let depth = pixels[x]
                if depth > 0 && depth.isFinite {
                    validPixelCount += 1
                }
            }
        }

        // 유효한 픽셀 비율
        let coverage = Float(validPixelCount) / Float(totalPixels)

        // 더 관대한 평가 기준: 20% 이상이면 충분
        if coverage >= 0.2 {
            return min(coverage * 2.5, 1.0)
        } else if coverage >= 0.1 {
            return 0.5
        } else {
            return coverage * 5.0
        }
    }

    // MARK: - Depth Map Storage

    /// Depth map을 PNG 파일로 저장합니다.
    ///
    /// Float32 depth 값을 16-bit grayscale PNG로 저장합니다.
    /// 값 범위: 0.0m ~ 10.0m를 0 ~ 65535로 매핑
    ///
    /// - Parameters:
    ///   - depthMap: 저장할 depth map (CVPixelBuffer)
    ///   - filename: 파일명 (확장자 제외)
    /// - Returns: 저장된 파일의 상대 경로, 실패 시 nil
    /// - Throws: 파일 저장 실패 시 에러
    static func saveDepthMap(_ depthMap: CVPixelBuffer, filename: String) throws -> String {
        // CVPixelBuffer를 UIImage로 변환
        guard let depthImage = depthMapToImage(depthMap) else {
            throw NSError(
                domain: "DepthDataProcessor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Depth map을 이미지로 변환할 수 없습니다"]
            )
        }

        // depth_maps 디렉토리 생성
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(
                domain: "DepthDataProcessor",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Documents 디렉토리를 찾을 수 없습니다"]
            )
        }

        let depthMapsDirectory = documentsPath.appendingPathComponent("depth_maps")
        try fileManager.createDirectory(at: depthMapsDirectory, withIntermediateDirectories: true)

        // 파일 저장
        let fileURL = depthMapsDirectory.appendingPathComponent("\(filename).png")
        guard let pngData = depthImage.pngData() else {
            throw NSError(
                domain: "DepthDataProcessor",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "PNG 데이터를 생성할 수 없습니다"]
            )
        }

        try pngData.write(to: fileURL, options: .atomic)

        // 상대 경로 반환
        return "depth_maps/\(filename).png"
    }

    /// PNG 파일에서 depth map을 로드합니다.
    ///
    /// - Parameter relativePath: Documents 디렉토리 기준 상대 경로
    /// - Returns: Depth map (CVPixelBuffer), 실패 시 nil
    static func loadDepthMap(from relativePath: String) -> CVPixelBuffer? {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let fileURL = documentsPath.appendingPathComponent(relativePath)
        guard let depthImage = UIImage(contentsOfFile: fileURL.path) else {
            return nil
        }

        return imageToDepthMap(depthImage)
    }

    // MARK: - Private Helpers

    /// CVPixelBuffer depth map을 grayscale UIImage로 변환합니다.
    ///
    /// Float32 값을 16-bit grayscale로 변환 (0.0m~10.0m → 0~65535)
    ///
    /// - Parameter depthMap: Depth map (CVPixelBuffer, Float32)
    /// - Returns: Grayscale UIImage, 실패 시 nil
    private static func depthMapToImage(_ depthMap: CVPixelBuffer) -> UIImage? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return nil
        }

        // 16-bit grayscale 이미지 데이터 생성
        var pixels = [UInt16](repeating: 0, count: width * height)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        for y in 0..<height {
            let rowData = baseAddress + y * bytesPerRow
            let floatPixels = rowData.assumingMemoryBound(to: Float32.self)

            for x in 0..<width {
                let depthValue = floatPixels[x]
                // 0.0m ~ 10.0m 범위를 0 ~ 65535로 매핑
                let normalizedValue = min(max(depthValue / 10.0, 0.0), 1.0)
                pixels[y * width + x] = UInt16(normalizedValue * 65535.0)
            }
        }

        // CGImage 생성
        let data = Data(bytes: &pixels, count: pixels.count * MemoryLayout<UInt16>.size)
        let provider = CGDataProvider(data: data as CFData)!

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            .union(.byteOrder16Little)

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 16,
            bytesPerRow: width * 2,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    /// Grayscale UIImage를 CVPixelBuffer depth map으로 변환합니다.
    ///
    /// 16-bit grayscale을 Float32로 변환 (0~65535 → 0.0m~10.0m)
    ///
    /// - Parameter image: Grayscale UIImage
    /// - Returns: Depth map (CVPixelBuffer, Float32), 실패 시 nil
    private static func imageToDepthMap(_ image: UIImage) -> CVPixelBuffer? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        // CVPixelBuffer 생성 (Float32)
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let depthBuffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(depthBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        let floatPointer = baseAddress.assumingMemoryBound(to: Float32.self)

        // CGImage에서 픽셀 데이터 추출
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            .union(.byteOrder16Little)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 16,
            bytesPerRow: width * 2,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return nil
        }

        let uint16Pointer = data.assumingMemoryBound(to: UInt16.self)

        // UInt16 → Float32 변환 (0~65535 → 0.0m~10.0m)
        for y in 0..<height {
            let rowOffset = y * (bytesPerRow / MemoryLayout<Float32>.size)
            for x in 0..<width {
                let grayValue = uint16Pointer[y * width + x]
                let normalizedValue = Float(grayValue) / 65535.0
                let depthValue = normalizedValue * 10.0  // 0~10m 범위로 복원
                floatPointer[rowOffset + x] = depthValue
            }
        }

        return depthBuffer
    }
}

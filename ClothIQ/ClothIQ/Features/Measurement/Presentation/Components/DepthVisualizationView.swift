//
//  DepthVisualizationView.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  LiDAR 깊이 데이터를 녹색 반투명으로 시각화하는 뷰입니다.
//  측정 대상 객체를 실시간으로 하이라이트합니다.
//

import SwiftUI
import ARKit

// MARK: - SwiftUI-based Depth Visualization

/// 간단한 깊이 시각화 오버레이
///
/// 전경 마스크와 깊이 데이터를 결합하여 의류 영역만 표시
///
struct SimpleDepthOverlay: View {
    let depthData: CVPixelBuffer?
    let foregroundMask: CVPixelBuffer?
    let isEnabled: Bool
    let depthRange: ClosedRange<Float>

    var body: some View {
        if isEnabled, let depthData = depthData {
            GeometryReader { geometry in
                Canvas { context, size in
                    // 깊이 데이터와 전경 마스크를 결합하여 시각화
                    if let depthImage = createDepthVisualizationWithMask(
                        depthData: depthData,
                        mask: foregroundMask,
                        size: size,
                        depthRange: depthRange
                    ) {
                        context.draw(depthImage, in: CGRect(origin: .zero, size: size))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// 전경 마스크와 깊이 데이터를 결합한 시각화 생성
    private func createDepthVisualizationWithMask(
        depthData: CVPixelBuffer,
        mask: CVPixelBuffer?,
        size: CGSize,
        depthRange: ClosedRange<Float>
    ) -> Image? {
        // 마스크가 없으면 기존 방식 사용
        guard let mask = mask else {
            return createDepthVisualization(depthData: depthData, size: size, depthRange: depthRange)
        }

        CVPixelBufferLockBaseAddress(depthData, .readOnly)
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthData, .readOnly)
            CVPixelBufferUnlockBaseAddress(mask, .readOnly)
        }

        let depthWidth = CVPixelBufferGetWidth(depthData)
        let depthHeight = CVPixelBufferGetHeight(depthData)
        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)

        guard let depthAddress = CVPixelBufferGetBaseAddress(depthData),
              let maskAddress = CVPixelBufferGetBaseAddress(mask) else {
            return nil
        }

        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthData)
        let maskBytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let depthValues = depthAddress.assumingMemoryBound(to: Float32.self)
        let maskValues = maskAddress.assumingMemoryBound(to: UInt8.self)

        // RGBA 이미지 생성
        var pixelData = [UInt8](repeating: 0, count: depthWidth * depthHeight * 4)

        for y in 0..<depthHeight {
            for x in 0..<depthWidth {
                let depthIndex = y * (depthBytesPerRow / 4) + x
                let depth = depthValues[depthIndex]

                // 마스크 좌표 계산 (크기가 다를 수 있음)
                let maskX = (x * maskWidth) / depthWidth
                let maskY = (y * maskHeight) / depthHeight
                let maskIndex = maskY * maskBytesPerRow + maskX
                let isForeground = maskValues[maskIndex] > 50  // 임계값 낮춤 (128 -> 50)

                // 전경이면서 깊이 범위 내에 있을 때만 표시
                if isForeground && depthRange.contains(depth) && depth > 0 {
                    let pixelIndex = (y * depthWidth + x) * 4
                    pixelData[pixelIndex] = 0       // R
                    pixelData[pixelIndex + 1] = 255 // G
                    pixelData[pixelIndex + 2] = 0   // B
                    pixelData[pixelIndex + 3] = 77  // A (30% 투명도)
                }
            }
        }

        // CGImage 생성
        guard let provider = CGDataProvider(data: Data(pixelData) as CFData) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)

        guard let cgImage = CGImage(
            width: depthWidth,
            height: depthHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: depthWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return Image(decorative: cgImage, scale: 1.0)
    }

    /// 기존 깊이 시각화 (전경 마스크 없이)
    private func createDepthVisualization(
        depthData: CVPixelBuffer,
        size: CGSize,
        depthRange: ClosedRange<Float>
    ) -> Image? {
        CVPixelBufferLockBaseAddress(depthData, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthData, .readOnly) }

        let width = CVPixelBufferGetWidth(depthData)
        let height = CVPixelBufferGetHeight(depthData)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthData) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthData)
        let depthValues = baseAddress.assumingMemoryBound(to: Float32.self)

        // RGBA 이미지 생성
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * (bytesPerRow / 4) + x
                let depth = depthValues[index]

                // 깊이 범위 내의 값만 녹색으로 표시
                if depthRange.contains(depth) && depth > 0 {
                    let pixelIndex = (y * width + x) * 4
                    pixelData[pixelIndex] = 0       // R
                    pixelData[pixelIndex + 1] = 255 // G
                    pixelData[pixelIndex + 2] = 0   // B
                    pixelData[pixelIndex + 3] = 77  // A (30% 투명도)
                }
            }
        }

        // CGImage 생성
        guard let provider = CGDataProvider(data: Data(pixelData) as CFData) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return Image(decorative: cgImage, scale: 1.0)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SimpleDepthOverlay(
            depthData: nil,
            foregroundMask: nil,
            isEnabled: true,
            depthRange: 0.3...2.0
        )
    }
}

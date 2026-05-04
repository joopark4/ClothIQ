//
//  BackgroundRemovalTests.swift
//  ClothIQTests
//

import Testing
import CoreGraphics
import CoreVideo
import UIKit
@testable import ClothIQ

struct BackgroundRemovalTests {

    @Test func softLowConfidenceMaskPixelsBecomeCleanBackground() throws {
        let service = ObjectCaptureService()
        let image = try #require(Self.makeImage(
            width: 3,
            height: 1,
            pixels: [
                (220, 40, 40, 255),
                (25, 140, 230, 255),
                (25, 140, 230, 255)
            ]
        ))
        let mask = try Self.makeMask(
            width: 3,
            height: 1,
            values: [255, 96, 0]
        )

        let output = try #require(service.applyMask(to: image, mask: mask))
        let pixels = try #require(Self.readPixels(from: output))

        #expect(abs(Int(pixels[0].r) - 220) <= 2)
        #expect(abs(Int(pixels[0].g) - 40) <= 2)
        #expect(abs(Int(pixels[0].b) - 40) <= 2)
        #expect(abs(Int(pixels[1].r) - 245) <= 2)
        #expect(abs(Int(pixels[1].g) - 245) <= 2)
        #expect(abs(Int(pixels[1].b) - 245) <= 2)
        #expect(abs(Int(pixels[2].r) - 245) <= 2)
        #expect(abs(Int(pixels[2].g) - 245) <= 2)
        #expect(abs(Int(pixels[2].b) - 245) <= 2)
    }

    private static func makeImage(
        width: Int,
        height: Int,
        pixels: [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]
    ) -> UIImage? {
        guard pixels.count == width * height,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        var data = pixels.flatMap { [$0.r, $0.g, $0.b, $0.a] }
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = context.makeImage() else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private static func makeMask(
        width: Int,
        height: Int,
        values: [UInt8]
    ) throws -> CVPixelBuffer {
        #expect(values.count == width * height)

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            nil,
            &pixelBuffer
        )

        let buffer = try #require(status == kCVReturnSuccess ? pixelBuffer : nil)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            Issue.record("CVPixelBuffer base address is nil")
            return buffer
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let destination = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            let row = destination + y * bytesPerRow
            for x in 0..<width {
                row[x] = values[y * width + x]
            }
        }

        return buffer
    }

    private static func readPixels(
        from image: UIImage
    ) -> [(r: UInt8, g: UInt8, b: UInt8, a: UInt8)]? {
        guard let cgImage = image.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return stride(from: 0, to: data.count, by: 4).map { index in
            (r: data[index], g: data[index + 1], b: data[index + 2], a: data[index + 3])
        }
    }
}

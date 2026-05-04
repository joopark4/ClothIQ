//
//  PhotoMeasurementDisplayTests.swift
//  ClothIQTests
//

import Testing
import Foundation
import CoreGraphics
import CoreVideo
import SwiftData
import UIKit
@testable import ClothIQ

struct PhotoMeasurementDisplayTests {

    @MainActor
    @Test func measurementLookupPrefersLatestDuplicateMeasurement() async throws {
        let item = ClothingItemModel(type: ClothingType.shorts.rawValue)
        let oldHem = MeasurementModel(
            type: MeasurementType.hem.rawValue,
            value: 18,
            measuredAt: Date(timeIntervalSince1970: 100),
            startPointX: 0.62,
            startPointY: 0.83,
            endPointX: 0.87,
            endPointY: 0.71,
            measurementMethodRaw: MeasurementMethod.photo.rawValue
        )
        let latestHem = MeasurementModel(
            type: MeasurementType.hem.rawValue,
            value: 22,
            measuredAt: Date(timeIntervalSince1970: 200),
            startPointX: 0.10,
            startPointY: 0.88,
            endPointX: 0.49,
            endPointY: 0.88,
            measurementMethodRaw: MeasurementMethod.photo.rawValue
        )
        item.measurements.append(contentsOf: [oldHem, latestHem])

        let selected = try #require(item.measurement(for: .hem))

        #expect(selected.id == latestHem.id)
        #expect(selected.value == 22)
        #expect(item.displayMeasurements.map(\.id) == [latestHem.id])
    }

    @MainActor
    @Test func photoMeasurementLoadsLatestDuplicateAnchors() async throws {
        let container = try makeInMemoryContainer()
        let item = ClothingItemModel(
            type: ClothingType.shorts.rawValue,
            processedImageWidth: 1000,
            processedImageHeight: 800
        )
        let staleHem = MeasurementModel(
            type: MeasurementType.hem.rawValue,
            value: 18,
            measuredAt: Date(timeIntervalSince1970: 100),
            startPointX: 0.62,
            startPointY: 0.83,
            endPointX: 0.87,
            endPointY: 0.71,
            measurementMethodRaw: MeasurementMethod.photo.rawValue
        )
        let latestHem = MeasurementModel(
            type: MeasurementType.hem.rawValue,
            value: 22,
            measuredAt: Date(timeIntervalSince1970: 200),
            startPointX: 0.10,
            startPointY: 0.88,
            endPointX: 0.49,
            endPointY: 0.88,
            measurementMethodRaw: MeasurementMethod.photo.rawValue
        )
        item.measurements.append(contentsOf: [staleHem, latestHem])
        container.mainContext.insert(item)

        let viewModel = PhotoMeasurementViewModel(item: item, modelContext: container.mainContext)
        viewModel.selectedMeasurementType = .hem
        viewModel.loadAnchors(for: .hem)

        #expect(viewModel.measurementAnchors.count == 2)
        #expect(abs(viewModel.measurementAnchors[0].position.x - 100) < 0.001)
        #expect(abs(viewModel.measurementAnchors[0].position.y - 704) < 0.001)
        #expect(abs(viewModel.measurementAnchors[1].position.x - 490) < 0.001)
        #expect(abs(viewModel.measurementAnchors[1].position.y - 704) < 0.001)
    }

    @MainActor
    @Test func photoMeasurementPersistsCurrentResultConfidence() async throws {
        let container = try makeInMemoryContainer()
        let item = ClothingItemModel(
            type: ClothingType.shorts.rawValue,
            processedImageWidth: 1000,
            processedImageHeight: 800
        )
        let staleHem = MeasurementModel(
            type: MeasurementType.hem.rawValue,
            value: 18,
            confidence: 0.2,
            measuredAt: Date(timeIntervalSince1970: 100),
            startPointX: 0.62,
            startPointY: 0.83,
            endPointX: 0.87,
            endPointY: 0.71,
            pathPointsJSON: #"[{"x":0.62,"y":0.83},{"x":0.72,"y":0.70},{"x":0.87,"y":0.71}]"#,
            measurementMethodRaw: MeasurementMethod.photo.rawValue
        )
        item.measurements.append(staleHem)
        container.mainContext.insert(item)

        let viewModel = PhotoMeasurementViewModel(item: item, modelContext: container.mainContext)
        viewModel.selectedMeasurementType = .hem
        viewModel.measurementAnchors = [
            MeasurementAnchor(position: CGPoint(x: 100, y: 704), measurementType: .hem),
            MeasurementAnchor(position: CGPoint(x: 490, y: 704), measurementType: .hem)
        ]
        viewModel.currentMeasurementResult = PhotoMeasurementCalculator.MeasurementResult(
            distance: 22.4,
            confidence: 0.73,
            point1Depth: 1.0,
            point2Depth: 1.0,
            distance3D: 0.224
        )

        viewModel.saveMeasurement()

        let saved = try #require(viewModel.existingMeasurement(for: .hem))
        #expect(item.displayMeasurements.count == 1)
        #expect(abs(saved.value - 22.4) < 0.001)
        #expect(abs(saved.confidence - 0.73) < 0.001)
        #expect(saved.measurementMethod == .photo)
        #expect(abs((saved.startPoint?.x ?? 0) - 0.1) < 0.001)
        #expect(abs((saved.endPoint?.x ?? 0) - 0.49) < 0.001)
        #expect(saved.pathPoints == nil)
    }

    @Test func photoMeasurementConfidenceReflectsDepthConsistency() throws {
        let sameDepthMap = try makeDepthMap(
            width: 11,
            height: 11,
            fill: 1.0
        )
        let consistent = try #require(PhotoMeasurementCalculator.calculateDistance(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 10, y: 0),
            depthMap: sameDepthMap,
            imageSize: CGSize(width: 10, height: 10),
            cameraIntrinsics: nil,
            cameraResolution: nil
        ))

        let mixedDepthMap = try makeDepthMap(
            width: 11,
            height: 11,
            fill: 1.0,
            overrides: [(x: 10, y: 0, depth: 2.0)]
        )
        let inconsistent = try #require(PhotoMeasurementCalculator.calculateDistance(
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: 10, y: 0),
            depthMap: mixedDepthMap,
            imageSize: CGSize(width: 10, height: 10),
            cameraIntrinsics: nil,
            cameraResolution: nil
        ))

        #expect(abs(consistent.confidence - 0.85) < 0.001)
        #expect(abs(inconsistent.confidence - 0.595) < 0.001)
        #expect(inconsistent.confidence < consistent.confidence)
    }

    @MainActor
    @Test func coordinateConverterUsesRenderedImageAspectForOverlayLayout() async throws {
        let converter = CoordinateConverter(
            imageSize: CGSize(width: 1000, height: 500),
            renderedImageSize: CGSize(width: 500, height: 500),
            rotation: 0
        )
        let viewSize = CGSize(width: 300, height: 300)
        let imagePoint = CGPoint(x: 500, y: 500)

        let viewPoint = converter.imageToView(
            imagePoint,
            in: viewSize,
            scale: 1,
            offset: .zero
        )
        let roundTrip = converter.viewToImage(
            viewPoint,
            in: viewSize,
            scale: 1,
            offset: .zero
        )

        #expect(abs(viewPoint.x - 150) < 0.001)
        #expect(abs(viewPoint.y - 300) < 0.001)
        #expect(abs(roundTrip.x - imagePoint.x) < 0.001)
        #expect(abs(roundTrip.y - imagePoint.y) < 0.001)
    }

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            ClothingItemModel.self,
            MeasurementModel.self,
            TagModel.self,
            CalibrationProfile.self,
            CalibrationFactor.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeDepthMap(
        width: Int,
        height: Int,
        fill: Float,
        overrides: [(x: Int, y: Int, depth: Float)] = []
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw NSError(domain: "PhotoMeasurementDisplayTests", code: Int(status))
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw NSError(domain: "PhotoMeasurementDisplayTests", code: -1)
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            let row = baseAddress
                .advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                row[x] = fill
            }
        }

        for override in overrides {
            guard override.x >= 0, override.x < width, override.y >= 0, override.y < height else {
                continue
            }
            let row = baseAddress
                .advanced(by: override.y * bytesPerRow)
                .assumingMemoryBound(to: Float32.self)
            row[override.x] = override.depth
        }

        return buffer
    }
}

//
//  ClothIQTests.swift
//  ClothIQTests
//
//  Created by EUN YEON on 10/22/25.
//

import Testing
import Foundation
import CoreGraphics
import SwiftData
import simd
import UIKit
@testable import ClothIQ

struct ClothIQTests {

    @MainActor
    @Test func captureImageAllowsCaptureWithoutPreselectedTypeOrMeasurements() async throws {
        let viewModel = MeasurementViewModelRefactored(clothingType: nil, modelContext: nil)

        #expect(viewModel.session.clothingType == nil)
        #expect(viewModel.currentMeasurementType == nil)
        #expect(viewModel.completedMeasurements.isEmpty)

        viewModel.captureImage()

        #expect(viewModel.captureRequested)
        #expect(viewModel.errorMessage == nil)
    }

    @MainActor
    @Test func completedMeasurementPreservesAutomaticMeasurementMetadata() async throws {
        let start = measurementPoint(
            x: 120,
            y: 240,
            confidence: 0.4
        )
        let end = measurementPoint(
            x: 520,
            y: 240,
            confidence: 0.8
        )

        let manualMeasurement = CompletedMeasurement(
            type: .waistCircumference,
            startPoint: start,
            endPoint: end,
            distanceInCm: 40.0
        )

        #expect(abs(manualMeasurement.confidence - 0.6) < 0.0001)
        #expect(manualMeasurement.coordinateSpace == .cameraImagePixels)
        #expect(manualMeasurement.measurementMethod == .ar)

        let automaticMeasurement = CompletedMeasurement(
            type: .waistCircumference,
            startPoint: start,
            endPoint: end,
            distanceInCm: 40.0,
            confidence: 0.73,
            coordinateSpace: .processedImagePixels,
            measurementMethod: .photo
        )

        #expect(automaticMeasurement.confidence == 0.73)
        #expect(automaticMeasurement.coordinateSpace == .processedImagePixels)
        #expect(automaticMeasurement.measurementMethod == .photo)
    }

    @MainActor
    @Test func saveWithClothingTypePersistsAutomaticMeasurementAnchors() async throws {
        let container = try makeInMemoryContainer()
        let viewModel = MeasurementViewModelRefactored(
            clothingType: nil,
            modelContext: container.mainContext
        )
        viewModel.processedImageToSave = solidImage(size: CGSize(width: 1000, height: 1000))
        viewModel.capturedProcessedImageSize = CGSize(width: 1000, height: 1000)

        let start = measurementPoint(
            x: 100,
            y: 250,
            confidence: 0.7
        )
        let end = measurementPoint(
            x: 700,
            y: 250,
            confidence: 0.7
        )
        let measurement = CompletedMeasurement(
            type: .waistCircumference,
            startPoint: start,
            endPoint: end,
            distanceInCm: 40,
            confidence: 0.82,
            coordinateSpace: .processedImagePixels,
            measurementMethod: .photo
        )

        #expect(viewModel.saveWithClothingType(.shorts, measurementsToSave: [measurement]))
        #expect(viewModel.session.clothingType == .shorts)

        let items = try container.mainContext.fetch(FetchDescriptor<ClothingItemModel>())
        #expect(items.count == 1)
        let savedItem = try #require(items.first)
        #expect(savedItem.type == ClothingType.shorts.rawValue)
        let savedMeasurement = try #require(savedItem.measurement(for: .waistCircumference))

        #expect(savedMeasurement.value == 40)
        #expect(savedMeasurement.confidence == 0.82)
        #expect(savedMeasurement.measurementMethodRaw == MeasurementMethod.photo.rawValue)
        #expect(savedMeasurement.startPointX == 0.1)
        #expect(savedMeasurement.startPointY == 0.25)
        #expect(savedMeasurement.endPointX == 0.7)
        #expect(savedMeasurement.endPointY == 0.25)
    }

    @MainActor
    @Test func measurementUpsertUpdatesExistingMeasurementInsteadOfAppending() async throws {
        let container = try makeInMemoryContainer()
        let item = ClothingItemModel(type: ClothingType.shorts.rawValue)
        let existing = MeasurementModel(
            type: MeasurementType.hem.rawValue,
            value: 18,
            confidence: 0.6,
            startPointX: 0.1,
            startPointY: 0.7,
            endPointX: 0.4,
            endPointY: 0.7,
            measurementMethodRaw: MeasurementMethod.photo.rawValue
        )
        item.measurements.append(existing)
        existing.clothingItem = item
        container.mainContext.insert(item)

        let updated = item.upsertMeasurement(
            type: .hem,
            value: 22,
            confidence: 0.91,
            startPoint: CGPoint(x: 0.2, y: 0.8),
            endPoint: CGPoint(x: 0.5, y: 0.8),
            method: .photo,
            modelContext: container.mainContext
        )
        try container.mainContext.save()

        #expect(item.measurements.count == 1)
        #expect(updated.id == existing.id)
        #expect(existing.value == 22)
        #expect(existing.confidence == 0.91)
        #expect(existing.startPointX == 0.2)
        #expect(existing.startPointY == 0.8)
        #expect(existing.endPointX == 0.5)
        #expect(existing.endPointY == 0.8)
    }

    @MainActor
    @Test func measurementUpsertCollapsesDuplicateExistingMeasurements() async throws {
        let container = try makeInMemoryContainer()
        let item = ClothingItemModel(type: ClothingType.shorts.rawValue)
        let oldRise = MeasurementModel(type: MeasurementType.rise.rawValue, value: 20)
        let duplicateRise = MeasurementModel(type: MeasurementType.rise.rawValue, value: 21)
        let hem = MeasurementModel(type: MeasurementType.hem.rawValue, value: 18)
        item.measurements.append(contentsOf: [oldRise, duplicateRise, hem])
        oldRise.clothingItem = item
        duplicateRise.clothingItem = item
        hem.clothingItem = item
        container.mainContext.insert(item)

        item.upsertMeasurement(
            type: .rise,
            value: 30,
            confidence: 0.88,
            startPoint: CGPoint(x: 0.5, y: 0.2),
            endPoint: CGPoint(x: 0.5, y: 0.65),
            method: .photo,
            modelContext: container.mainContext
        )
        try container.mainContext.save()

        let riseMeasurements = item.measurements.filter { $0.type == MeasurementType.rise.rawValue }
        #expect(item.measurements.count == 2)
        #expect(riseMeasurements.count == 1)
        #expect(riseMeasurements.first?.id == oldRise.id)
        #expect(riseMeasurements.first?.value == 30)
        #expect(item.measurements.contains { $0.id == hem.id })
    }

    @MainActor
    @Test func prepareMeasurementPreviewUsesAutomaticMeasurementsAndKeypoints() async throws {
        let viewModel = MeasurementViewModelRefactored(clothingType: nil, modelContext: nil)
        viewModel.session.clothingType = .shortSleeve
        let image = solidImage(size: CGSize(width: 800, height: 800))
        let shoulder = CompletedMeasurement(
            type: .shoulderWidth,
            startPoint: measurementPoint(x: 120, y: 200, confidence: 0.9),
            endPoint: measurementPoint(x: 680, y: 200, confidence: 0.9),
            distanceInCm: 42,
            confidence: 0.91,
            coordinateSpace: .processedImagePixels,
            measurementMethod: .photo
        )
        let chest = CompletedMeasurement(
            type: .chestCircumference,
            startPoint: measurementPoint(x: 150, y: 320, confidence: 0.8),
            endPoint: measurementPoint(x: 650, y: 320, confidence: 0.8),
            distanceInCm: 50,
            confidence: 0.84,
            coordinateSpace: .processedImagePixels,
            measurementMethod: .photo
        )
        let keypoint = MeasurementKeypoint(
            type: .leftShoulder,
            position: CGPoint(x: 0.2, y: 0.25),
            confidence: 0.88
        )

        viewModel.prepareMeasurementPreview(
            with: image,
            measurements: [chest, shoulder],
            keypoints: [keypoint]
        )

        #expect(viewModel.showingMeasurementPreview)
        #expect(viewModel.previewImage === image)
        #expect(viewModel.draftMeasurements.map(\.type) == [.shoulderWidth, .chestCircumference])
        #expect(viewModel.draftMeasurements.allSatisfy { $0.measurementMethod == .photo })
        #expect(viewModel.draftMeasurements.allSatisfy { $0.coordinateSpace == .processedImagePixels })
        #expect(viewModel.draftKeypoints.count == 1)
        #expect(viewModel.draftKeypoints.first?.type == .leftShoulder)
    }

    @MainActor
    @Test func automaticClassificationKeepsShortsForSleevelessLandscapeContour() async throws {
        let classifierResult = ClothingClassificationResult(
            type: .shorts,
            confidence: 0.83,
            method: .aspectRatio
        )
        let contourFeatures = ClothingFeatures(
            sleeveDetection: SleeveDetection(
                hasSleeves: false,
                leftProtrusionRatio: 0,
                rightProtrusionRatio: 0
            ),
            hemlineShape: HemlineShape(
                isVShaped: false,
                isFlat: true,
                centerY: 0.098,
                leftY: 0.102,
                rightY: 0.093
            ),
            topRegionShape: TopRegionShape(
                isNarrow: true,
                isWide: false,
                topWidthRatio: 0.28
            ),
            aspectRatio: 0.60
        )

        let resolved = AutomaticClothingTypeResolver.resolve(
            classifierResult: classifierResult,
            contourType: .shortSleeve,
            contourFeatures: contourFeatures
        )

        #expect(resolved.type == .shorts)
        #expect(abs(resolved.confidence - 0.83) < 0.0001)
    }

    @MainActor
    @Test func visionClassifierTreatsWideLandscapeShortsAsShorts() async throws {
        let image = solidImage(size: CGSize(width: 1000, height: 600))

        let result = VisionClothingClassifier().classify(image: image)

        #expect(result.type == .shorts)
        #expect(result.confidence >= 0.72)
    }

    @MainActor
    @Test func automaticClassificationKeepsShortsForFalseSleeveLandscapeContour() async throws {
        let classifierResult = ClothingClassificationResult(
            type: .shorts,
            confidence: 0.84,
            method: .aspectRatio
        )
        let contourFeatures = ClothingFeatures(
            sleeveDetection: SleeveDetection(
                hasSleeves: true,
                leftProtrusionRatio: 0.20,
                rightProtrusionRatio: 0.19
            ),
            hemlineShape: HemlineShape(
                isVShaped: false,
                isFlat: true,
                centerY: 0.10,
                leftY: 0.10,
                rightY: 0.10
            ),
            topRegionShape: TopRegionShape(
                isNarrow: true,
                isWide: false,
                topWidthRatio: 0.42
            ),
            aspectRatio: 0.60
        )

        let resolved = AutomaticClothingTypeResolver.resolve(
            classifierResult: classifierResult,
            contourType: .shortSleeve,
            contourFeatures: contourFeatures
        )

        #expect(resolved.type == .shorts)
        #expect(abs(resolved.confidence - 0.84) < 0.0001)
    }

    @MainActor
    @Test func clearCaptureSessionPreservesOnlyLockedEntryType() async throws {
        let automaticViewModel = MeasurementViewModelRefactored(clothingType: nil, modelContext: nil)
        automaticViewModel.session.clothingType = .shortSleeve

        automaticViewModel.clearCurrentCaptureSession()

        #expect(automaticViewModel.session.clothingType == nil)
        #expect(automaticViewModel.currentMeasurementType == nil)

        let lockedViewModel = MeasurementViewModelRefactored(clothingType: .shorts, modelContext: nil)
        lockedViewModel.session.clothingType = .shortSleeve

        lockedViewModel.clearCurrentCaptureSession()

        #expect(lockedViewModel.session.clothingType == .shorts)
        #expect(lockedViewModel.currentMeasurementType == ClothingType.shorts.requiredMeasurements.first)
    }

    @MainActor
    @Test func robustBottomWaistSpanSkipsNarrowTopProtrusion() async throws {
        let points = [
            CGPoint(x: 0.49, y: 1.00),
            CGPoint(x: 0.51, y: 1.00),
            CGPoint(x: 0.20, y: 0.82),
            CGPoint(x: 0.80, y: 0.82),
            CGPoint(x: 0.22, y: 0.76),
            CGPoint(x: 0.78, y: 0.76),
            CGPoint(x: 0.30, y: 0.10),
            CGPoint(x: 0.70, y: 0.10)
        ]
        let featurePoints = ClothingFeaturePoints(
            topPoint: CGPoint(x: 0.50, y: 1.00),
            bottomPoint: CGPoint(x: 0.50, y: 0.10),
            leftmostPoint: CGPoint(x: 0.20, y: 0.82),
            rightmostPoint: CGPoint(x: 0.80, y: 0.82),
            allPoints: points
        )

        let waistSpan = try #require(featurePoints.robustBottomWaistSpan())

        #expect(waistSpan.left.x <= 0.22)
        #expect(waistSpan.right.x >= 0.78)
        #expect(waistSpan.left.y >= 0.80)
        #expect(waistSpan.right.y >= 0.80)
        #expect((waistSpan.right.x - waistSpan.left.x) >= 0.55)
    }

    @MainActor
    @Test func bottomWaistSpanUsesUpperStableEdge() async throws {
        let featurePoints = ClothingFeaturePoints(
            topPoint: CGPoint(x: 0.50, y: 0.96),
            bottomPoint: CGPoint(x: 0.50, y: 0.10),
            leftmostPoint: CGPoint(x: 0.10, y: 0.55),
            rightmostPoint: CGPoint(x: 0.90, y: 0.55),
            allPoints: [
                CGPoint(x: 0.49, y: 0.96),
                CGPoint(x: 0.51, y: 0.96),
                CGPoint(x: 0.18, y: 0.88),
                CGPoint(x: 0.82, y: 0.88),
                CGPoint(x: 0.16, y: 0.72),
                CGPoint(x: 0.84, y: 0.72),
                CGPoint(x: 0.10, y: 0.55),
                CGPoint(x: 0.90, y: 0.55),
                CGPoint(x: 0.24, y: 0.10),
                CGPoint(x: 0.74, y: 0.10)
            ]
        )

        let waistSpan = try #require(featurePoints.robustBottomWaistSpan())

        #expect(abs(waistSpan.left.y - 0.88) < 0.001)
        #expect(abs(waistSpan.right.y - 0.88) < 0.001)
        #expect(abs(waistSpan.left.x - 0.18) < 0.001)
        #expect(abs(waistSpan.right.x - 0.82) < 0.001)
    }

    @MainActor
    @Test func foregroundFeaturePointsPlaceShortsAnchorsOnGarment() async throws {
        let image = syntheticShortsImage()
        let service = AutoMeasurementService()
        let featurePoints = try #require(service.extractForegroundFeaturePoints(from: image, clothingType: .shorts))

        let waistSpan = try #require(featurePoints.robustBottomWaistSpan())
        #expect(waistSpan.left.x > 0.14)
        #expect(waistSpan.left.x < 0.30)
        #expect(waistSpan.right.x > 0.70)
        #expect(waistSpan.right.x < 0.86)
        #expect(waistSpan.left.y < 0.90)
        #expect(waistSpan.left.y > 0.66)

        let lengthLine = try #require(featurePoints.bestBottomTotalLengthLine())
        #expect(lengthLine.start.y > lengthLine.end.y)
        #expect(lengthLine.start.x > 0.14)
        #expect(lengthLine.start.x < 0.86)
        #expect(lengthLine.end.x > 0.14)
        #expect(lengthLine.end.x < 0.86)
        #expect(abs(lengthLine.start.x - lengthLine.end.x) < 0.30)

        let crotch = try #require(featurePoints.robustBottomCrotchPoint())
        #expect(crotch.point.x > 0.42)
        #expect(crotch.point.x < 0.58)
        #expect(crotch.point.y < waistSpan.left.y)

        let hemSpan = try #require(featurePoints.robustBottomHemSpan())
        let hemWidth = abs(hemSpan.right.x - hemSpan.left.x)
        #expect(hemWidth > 0.12)
        #expect(hemWidth < 0.45)
        #expect(hemSpan.left.y < waistSpan.left.y)
        #expect(hemSpan.right.y < waistSpan.right.y)
    }

    @MainActor
    @Test func bottomHemSpanPrefersLowerRepresentativeOpeningOverHighWideInterior() async throws {
        let featurePoints = ClothingFeaturePoints(
            topPoint: CGPoint(x: 0.50, y: 0.92),
            bottomPoint: CGPoint(x: 0.50, y: 0.10),
            leftmostPoint: CGPoint(x: 0.10, y: 0.29),
            rightmostPoint: CGPoint(x: 0.90, y: 0.29),
            allPoints: [
                CGPoint(x: 0.20, y: 0.82),
                CGPoint(x: 0.80, y: 0.82),
                CGPoint(x: 0.15, y: 0.55),
                CGPoint(x: 0.45, y: 0.55),
                CGPoint(x: 0.55, y: 0.55),
                CGPoint(x: 0.85, y: 0.55),
                CGPoint(x: 0.10, y: 0.12),
                CGPoint(x: 0.43, y: 0.12),
                CGPoint(x: 0.55, y: 0.28),
                CGPoint(x: 0.90, y: 0.28)
            ]
        )

        let hemSpan = try #require(featurePoints.robustBottomHemSpan())

        #expect(abs(hemSpan.left.y - 0.12) < 0.001)
        #expect(abs(hemSpan.right.y - 0.12) < 0.001)
        #expect(abs(hemSpan.left.x - 0.10) < 0.001)
        #expect(abs(hemSpan.right.x - 0.43) < 0.001)
    }

    @MainActor
    @Test func bottomMeasurementLinesUseWaistCenterAndSingleLegHem() async throws {
        let detector = ClothingKeypointDetector()
        let keypoints = [
            MeasurementKeypoint(type: .waistLeft, position: CGPoint(x: 0.20, y: 0.80), confidence: 0.9),
            MeasurementKeypoint(type: .waistRight, position: CGPoint(x: 0.80, y: 0.80), confidence: 0.9),
            MeasurementKeypoint(type: .crotch, position: CGPoint(x: 0.50, y: 0.42), confidence: 0.8),
            MeasurementKeypoint(type: .leftHem, position: CGPoint(x: 0.22, y: 0.12), confidence: 0.8),
            MeasurementKeypoint(type: .rightHem, position: CGPoint(x: 0.45, y: 0.12), confidence: 0.8),
            MeasurementKeypoint(type: .hemCenter, position: CGPoint(x: 0.335, y: 0.12), confidence: 0.8)
        ]

        let lines = detector.generateMeasurementLines(from: keypoints, clothingType: .shorts)

        let rise = try #require(lines.first { $0.type == .rise })
        #expect(abs(rise.start.x - 0.50) < 0.0001)
        #expect(abs(rise.start.y - 0.80) < 0.0001)
        #expect(abs(rise.end.x - 0.50) < 0.0001)

        let hem = try #require(lines.first { $0.type == .hem })
        #expect(abs((hem.end.x - hem.start.x) - 0.23) < 0.0001)

        let totalLength = try #require(lines.first { $0.type == .totalLength })
        #expect(abs(totalLength.start.x - totalLength.end.x) < 0.08)
    }

    @MainActor
    @Test func bottomRiseLineStartsAboveDetectedCrotchWhenWaistSpanIsSkewed() async throws {
        let detector = ClothingKeypointDetector()
        let keypoints = [
            MeasurementKeypoint(type: .waistLeft, position: CGPoint(x: 0.16, y: 0.82), confidence: 0.9),
            MeasurementKeypoint(type: .waistRight, position: CGPoint(x: 0.72, y: 0.82), confidence: 0.9),
            MeasurementKeypoint(type: .crotch, position: CGPoint(x: 0.53, y: 0.36), confidence: 0.8),
            MeasurementKeypoint(type: .leftHem, position: CGPoint(x: 0.10, y: 0.10), confidence: 0.8),
            MeasurementKeypoint(type: .rightHem, position: CGPoint(x: 0.48, y: 0.10), confidence: 0.8),
            MeasurementKeypoint(type: .hemCenter, position: CGPoint(x: 0.29, y: 0.10), confidence: 0.8)
        ]

        let lines = detector.generateMeasurementLines(from: keypoints, clothingType: .shorts)
        let rise = try #require(lines.first { $0.type == .rise })

        #expect(abs(rise.start.x - 0.53) < 0.0001)
        #expect(abs(rise.start.y - 0.82) < 0.0001)
        #expect(abs(rise.end.x - 0.53) < 0.0001)
        #expect(abs(rise.end.y - 0.36) < 0.0001)
    }

    @MainActor
    @Test func photoMeasurementRefreshesExistingBottomHemAnchorsFromDetectedKeypoints() async throws {
        let container = try makeInMemoryContainer()
        let item = ClothingItemModel(
            type: ClothingType.shorts.rawValue,
            processedImageWidth: 1000,
            processedImageHeight: 800
        )
        container.mainContext.insert(item)

        let viewModel = PhotoMeasurementViewModel(item: item, modelContext: container.mainContext)
        viewModel.selectedMeasurementType = .hem
        viewModel.measurementAnchors = [
            MeasurementAnchor(position: CGPoint(x: 620, y: 660), measurementType: .hem),
            MeasurementAnchor(position: CGPoint(x: 870, y: 570), measurementType: .hem)
        ]
        viewModel.detectedKeypoints = [
            MeasurementKeypoint(type: .leftHem, position: CGPoint(x: 0.10, y: 0.12), confidence: 0.8),
            MeasurementKeypoint(type: .rightHem, position: CGPoint(x: 0.48, y: 0.12), confidence: 0.8),
            MeasurementKeypoint(type: .hemCenter, position: CGPoint(x: 0.29, y: 0.12), confidence: 0.8)
        ]

        viewModel.refreshDetectedAnchorsForCurrentSelectionIfNeeded()

        #expect(viewModel.measurementAnchors.count == 2)
        #expect(abs(viewModel.measurementAnchors[0].position.x - 100) < 0.001)
        #expect(abs(viewModel.measurementAnchors[0].position.y - 704) < 0.001)
        #expect(abs(viewModel.measurementAnchors[1].position.x - 480) < 0.001)
        #expect(abs(viewModel.measurementAnchors[1].position.y - 704) < 0.001)
    }

    @MainActor
    @Test func photoMeasurementDoesNotReplaceUserModifiedBottomAnchors() async throws {
        let container = try makeInMemoryContainer()
        let item = ClothingItemModel(
            type: ClothingType.shorts.rawValue,
            processedImageWidth: 1000,
            processedImageHeight: 800
        )
        container.mainContext.insert(item)

        let viewModel = PhotoMeasurementViewModel(item: item, modelContext: container.mainContext)
        viewModel.selectedMeasurementType = .rise
        viewModel.hasUserModifiedAnchors = true
        viewModel.measurementAnchors = [
            MeasurementAnchor(position: CGPoint(x: 410, y: 150), measurementType: .rise),
            MeasurementAnchor(position: CGPoint(x: 430, y: 520), measurementType: .rise)
        ]
        viewModel.detectedKeypoints = [
            MeasurementKeypoint(type: .waistLeft, position: CGPoint(x: 0.18, y: 0.82), confidence: 0.9),
            MeasurementKeypoint(type: .waistRight, position: CGPoint(x: 0.82, y: 0.82), confidence: 0.9),
            MeasurementKeypoint(type: .crotch, position: CGPoint(x: 0.53, y: 0.36), confidence: 0.8)
        ]

        viewModel.refreshDetectedAnchorsForCurrentSelectionIfNeeded()

        #expect(viewModel.measurementAnchors[0].position == CGPoint(x: 410, y: 150))
        #expect(viewModel.measurementAnchors[1].position == CGPoint(x: 430, y: 520))
    }

    @MainActor
    @Test func bottomRepairPolicyRepairsInitialDiagonalHem() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_775_000_000)
        let measurement = MeasurementModel(
            type: MeasurementType.hem.rawValue,
            value: 18,
            confidence: 0.8,
            measuredAt: createdAt.addingTimeInterval(1),
            startPointX: 0.6254,
            startPointY: 0.8302,
            endPointX: 0.8728,
            endPointY: 0.7150,
            measurementMethodRaw: MeasurementMethod.photo.rawValue
        )

        let shouldRepair = BottomMeasurementAnchorRepairPolicy.shouldRepair(
            measurement: measurement,
            replacementStart: CGPoint(x: 0.1015, y: 0.8863),
            replacementEnd: CGPoint(x: 0.4878, y: 0.8863),
            itemCreatedAt: createdAt
        )

        #expect(shouldRepair)
    }

    @MainActor
    @Test func bottomRepairPolicyKeepsLaterUserRiseCorrection() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_775_000_000)
        let measurement = MeasurementModel(
            type: MeasurementType.rise.rawValue,
            value: 28,
            confidence: 1,
            measuredAt: createdAt.addingTimeInterval(120),
            startPointX: 0.52,
            startPointY: 0.20,
            endPointX: 0.53,
            endPointY: 0.64,
            measurementMethodRaw: MeasurementMethod.photo.rawValue
        )

        let shouldRepair = BottomMeasurementAnchorRepairPolicy.shouldRepair(
            measurement: measurement,
            replacementStart: CGPoint(x: 0.20, y: 0.82),
            replacementEnd: CGPoint(x: 0.80, y: 0.18),
            itemCreatedAt: createdAt
        )

        #expect(!shouldRepair)
    }

    @MainActor
    @Test func bottomRepairPolicyRepairsInitialRiseShiftedOffCrotch() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_775_000_000)
        let measurement = MeasurementModel(
            type: MeasurementType.rise.rawValue,
            value: 30.8,
            confidence: 0.8,
            measuredAt: createdAt.addingTimeInterval(1),
            startPointX: 0.4948,
            startPointY: 0.1854,
            endPointX: 0.5212,
            endPointY: 0.6480,
            measurementMethodRaw: MeasurementMethod.photo.rawValue
        )

        let shouldRepair = BottomMeasurementAnchorRepairPolicy.shouldRepair(
            measurement: measurement,
            replacementStart: CGPoint(x: 0.5219, y: 0.1947),
            replacementEnd: CGPoint(x: 0.5219, y: 0.6464),
            itemCreatedAt: createdAt
        )

        #expect(shouldRepair)
    }

    @MainActor
    @Test func bottomRepairPolicyRepairsInitialTotalLengthUsingOldHem() async throws {
        let createdAt = Date(timeIntervalSince1970: 1_775_000_000)
        let measurement = MeasurementModel(
            type: MeasurementType.totalLength.rawValue,
            value: 40.6,
            confidence: 0.8,
            measuredAt: createdAt.addingTimeInterval(1),
            startPointX: 0.7060,
            startPointY: 0.1854,
            endPointX: 0.6254,
            endPointY: 0.8302,
            measurementMethodRaw: MeasurementMethod.photo.rawValue
        )

        let shouldRepair = BottomMeasurementAnchorRepairPolicy.shouldRepair(
            measurement: measurement,
            replacementStart: CGPoint(x: 0.1015, y: 0.1947),
            replacementEnd: CGPoint(x: 0.1015, y: 0.8863),
            itemCreatedAt: createdAt
        )

        #expect(shouldRepair)
    }

    @MainActor
    @Test func bottomRepairPolicyAppliesNormalizedPhotoAnchors() async throws {
        let measurement = MeasurementModel(
            type: MeasurementType.rise.rawValue,
            value: 10,
            confidence: 0.2,
            startPointX: 0.1,
            startPointY: 0.1,
            endPointX: 0.2,
            endPointY: 0.2,
            measurementMethodRaw: MeasurementMethod.photo.rawValue
        )
        let measuredAt = Date(timeIntervalSince1970: 1_775_000_000)
        let result = AutoMeasurementResult(
            distance: 31.5,
            confidence: 0.88,
            point1: CGPoint(x: 520, y: 160),
            point2: CGPoint(x: 520, y: 520)
        )

        let didApply = BottomMeasurementAnchorRepairPolicy.apply(
            result: result,
            to: measurement,
            imageSize: CGSize(width: 1000, height: 800),
            measuredAt: measuredAt
        )

        #expect(didApply)
        #expect(measurement.value == 31.5)
        #expect(measurement.confidence == 0.88)
        #expect(measurement.measuredAt == measuredAt)
        #expect(measurement.startPointX == 0.52)
        #expect(measurement.startPointY == 0.2)
        #expect(measurement.endPointX == 0.52)
        #expect(measurement.endPointY == 0.65)
        #expect(measurement.measurementMethodRaw == MeasurementMethod.photo.rawValue)
    }

    private func measurementPoint(
        x: CGFloat,
        y: CGFloat,
        confidence: Float
    ) -> MeasurementPoint {
        MeasurementPoint(
            worldPosition: SIMD3<Float>(0, 0, 0),
            screenPosition: CGPoint(x: x, y: y),
            depth: 1.0,
            confidence: confidence
        )
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

    @MainActor
    private func solidImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func syntheticShortsImage(size: CGSize = CGSize(width: 1000, height: 800)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 245.0 / 255.0, alpha: 1).setFill()
            context.fill(rect)

            let cloth = UIColor(red: 0.58, green: 0.54, blue: 0.39, alpha: 1)
            cloth.setFill()

            let waist = UIBezierPath(roundedRect: CGRect(x: 180, y: 110, width: 640, height: 105), cornerRadius: 16)
            waist.fill()

            let leftLeg = UIBezierPath()
            leftLeg.move(to: CGPoint(x: 175, y: 180))
            leftLeg.addLine(to: CGPoint(x: 505, y: 180))
            leftLeg.addLine(to: CGPoint(x: 465, y: 690))
            leftLeg.addLine(to: CGPoint(x: 245, y: 690))
            leftLeg.addLine(to: CGPoint(x: 145, y: 275))
            leftLeg.close()
            leftLeg.fill()

            let rightLeg = UIBezierPath()
            rightLeg.move(to: CGPoint(x: 495, y: 180))
            rightLeg.addLine(to: CGPoint(x: 825, y: 180))
            rightLeg.addLine(to: CGPoint(x: 755, y: 690))
            rightLeg.addLine(to: CGPoint(x: 535, y: 690))
            rightLeg.addLine(to: CGPoint(x: 495, y: 180))
            rightLeg.close()
            rightLeg.fill()

            UIColor(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 245.0 / 255.0, alpha: 1).setFill()
            let centerGap = UIBezierPath()
            centerGap.move(to: CGPoint(x: 465, y: 440))
            centerGap.addLine(to: CGPoint(x: 500, y: 700))
            centerGap.addLine(to: CGPoint(x: 535, y: 440))
            centerGap.close()
            centerGap.fill()
        }
    }
}

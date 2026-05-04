//
//  MLFeatureTests.swift
//  ClothIQTests
//

import Testing
import CoreGraphics
import SwiftData
import UIKit
import Vision
@testable import ClothIQ

struct MLFeatureTests {

    @MainActor
    @Test func visionClassifierTreatsVeryWideShortsAsShorts() async throws {
        let image = solidImage(size: CGSize(width: 1000, height: 350))

        let result = VisionClothingClassifier().classify(image: image)

        #expect(result.type == .shorts)
        #expect(result.confidence >= 0.72)
    }

    @MainActor
    @Test func contourCategoryKeepsLowProfileSleevelessShapeAsShorts() async throws {
        let features = ClothingFeatures(
            sleeveDetection: SleeveDetection(
                hasSleeves: false,
                leftProtrusionRatio: 0,
                rightProtrusionRatio: 0
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
                topWidthRatio: 0.40
            ),
            aspectRatio: 0.62
        )

        let type = ClothingFeatureAnalyzer().detectClothingCategory(from: features)

        #expect(type == .shorts)
    }

    @MainActor
    @Test func photoMeasurementConvertsBottomUserHemCorrectionToTrainingKeypoints() async throws {
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
            MeasurementAnchor(position: CGPoint(x: 100, y: 704), measurementType: .hem),
            MeasurementAnchor(position: CGPoint(x: 480, y: 704), measurementType: .hem)
        ]

        let keypoints = viewModel.keypointsForCurrentAnchors()

        #expect(keypoints.map(\.type) == [.leftHem, .rightHem, .hemCenter])
        #expect(abs(keypoints[0].position.x - 0.10) < 0.001)
        #expect(abs(keypoints[0].position.y - 0.12) < 0.001)
        #expect(abs(keypoints[2].position.x - 0.29) < 0.001)
        #expect(abs(keypoints[2].position.y - 0.12) < 0.001)
    }

    @MainActor
    @Test func photoMeasurementConvertsBottomUserRiseCorrectionToTrainingKeypoints() async throws {
        let container = try makeInMemoryContainer()
        let item = ClothingItemModel(
            type: ClothingType.shorts.rawValue,
            processedImageWidth: 1000,
            processedImageHeight: 800
        )
        container.mainContext.insert(item)

        let viewModel = PhotoMeasurementViewModel(item: item, modelContext: container.mainContext)
        viewModel.selectedMeasurementType = .rise
        viewModel.measurementAnchors = [
            MeasurementAnchor(position: CGPoint(x: 520, y: 160), measurementType: .rise),
            MeasurementAnchor(position: CGPoint(x: 520, y: 512), measurementType: .rise)
        ]

        let keypoints = viewModel.keypointsForCurrentAnchors()

        #expect(keypoints.map(\.type) == [.waistLeft, .crotch])
        #expect(abs(keypoints[0].position.x - 0.52) < 0.001)
        #expect(abs(keypoints[0].position.y - 0.80) < 0.001)
        #expect(abs(keypoints[1].position.x - 0.52) < 0.001)
        #expect(abs(keypoints[1].position.y - 0.36) < 0.001)
    }

    @MainActor
    @Test func photoMeasurementDoesNotOverwriteExistingAnchorsWhenDetectedKeypointsRefresh() async throws {
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
            MeasurementAnchor(position: CGPoint(x: 100, y: 704), measurementType: .hem),
            MeasurementAnchor(position: CGPoint(x: 480, y: 704), measurementType: .hem)
        ]
        viewModel.detectedKeypoints = [
            MeasurementKeypoint(type: .leftHem, position: CGPoint(x: 0.70, y: 0.70), confidence: 0.95),
            MeasurementKeypoint(type: .rightHem, position: CGPoint(x: 0.92, y: 0.70), confidence: 0.95)
        ]

        viewModel.refreshDetectedAnchorsForCurrentSelectionIfNeeded()

        #expect(viewModel.measurementAnchors.count == 2)
        #expect(abs(viewModel.measurementAnchors[0].position.x - 100) < 0.001)
        #expect(abs(viewModel.measurementAnchors[0].position.y - 704) < 0.001)
        #expect(abs(viewModel.measurementAnchors[1].position.x - 480) < 0.001)
        #expect(abs(viewModel.measurementAnchors[1].position.y - 704) < 0.001)
    }

    @MainActor
    @Test func photoMeasurementCanCreateAnchorsFromDetectedBottomKeypointsWhenEmpty() async throws {
        let container = try makeInMemoryContainer()
        let item = ClothingItemModel(
            type: ClothingType.shorts.rawValue,
            processedImageWidth: 1000,
            processedImageHeight: 800
        )
        container.mainContext.insert(item)

        let viewModel = PhotoMeasurementViewModel(item: item, modelContext: container.mainContext)
        viewModel.selectedMeasurementType = .hem
        viewModel.detectedKeypoints = [
            MeasurementKeypoint(type: .leftHem, position: CGPoint(x: 0.10, y: 0.12), confidence: 0.95),
            MeasurementKeypoint(type: .rightHem, position: CGPoint(x: 0.48, y: 0.12), confidence: 0.95)
        ]

        viewModel.refreshDetectedAnchorsForCurrentSelectionIfNeeded()

        #expect(viewModel.measurementAnchors.count == 2)
        #expect(abs(viewModel.measurementAnchors[0].position.x - 100) < 0.001)
        #expect(abs(viewModel.measurementAnchors[0].position.y - 704) < 0.001)
        #expect(abs(viewModel.measurementAnchors[1].position.x - 480) < 0.001)
        #expect(abs(viewModel.measurementAnchors[1].position.y - 704) < 0.001)
    }

    @MainActor
    @Test func keypointLinesCoverEverySupportedClothingTypeMeasurement() async throws {
        let detector = ClothingKeypointDetector()
        let canonicalKeypoints = representativeGarmentKeypoints()

        for clothingType in ClothingType.allCases {
            let lines = detector.generateMeasurementLines(
                from: canonicalKeypoints,
                clothingType: clothingType
            )
            let lineTypes = lines.map(\.type)
            let expectedMeasurements = clothingType.requiredMeasurements + clothingType.optionalMeasurements

            for expectedMeasurement in expectedMeasurements {
                #expect(lineTypes.contains(expectedMeasurement))
            }

            for line in lines where expectedMeasurements.contains(line.type) {
                let length = hypot(line.end.x - line.start.x, line.end.y - line.start.y)
                #expect(length > 0.005)
                #expect((0.0...1.0).contains(line.start.x))
                #expect((0.0...1.0).contains(line.start.y))
                #expect((0.0...1.0).contains(line.end.x))
                #expect((0.0...1.0).contains(line.end.y))
            }
        }
    }

    @MainActor
    @Test func photoMeasurementConvertsSpecialUserCorrectionsToTrainingKeypoints() async throws {
        let scenarios: [(MeasurementType, ClothingType, [KeypointType])] = [
            (.armCircumference, .longSleeve, [.leftSleeveEnd, .rightSleeveEnd]),
            (.neckCircumference, .shirt, [.leftShoulder, .rightShoulder, .neckline]),
            (.cuffCircumference, .jacket, [.leftSleeveEnd, .rightSleeveEnd]),
            (.thighCircumference, .pants, [.hipLeft, .hipRight, .crotch])
        ]

        for scenario in scenarios {
            let container = try makeInMemoryContainer()
            let item = ClothingItemModel(
                type: scenario.1.rawValue,
                processedImageWidth: 1000,
                processedImageHeight: 800
            )
            container.mainContext.insert(item)

            let viewModel = PhotoMeasurementViewModel(item: item, modelContext: container.mainContext)
            viewModel.selectedMeasurementType = scenario.0
            viewModel.measurementAnchors = [
                MeasurementAnchor(position: CGPoint(x: 260, y: 320), measurementType: scenario.0),
                MeasurementAnchor(position: CGPoint(x: 520, y: 320), measurementType: scenario.0)
            ]

            let keypoints = viewModel.keypointsForCurrentAnchors()
            let keypointTypes = keypoints.map(\.type)

            #expect(!keypoints.isEmpty)
            for expectedType in scenario.2 {
                #expect(keypointTypes.contains(expectedType))
            }
        }
    }

    @MainActor
    @Test func mlTrainingGuidanceUsesExternalCompiledModelWorkflow() async throws {
        let collector = MLTrainingDataCollector.shared
        let deploymentStatus = collector.getModelDeploymentStatus()

        #expect(collector.trainingNotSupportedMessage.contains("scripts/ml_training_workflow.sh --per-type"))
        #expect(collector.trainingNotSupportedMessage.contains("ClothingKeypointDetector_<type>.mlmodelc"))
        #expect(collector.createMLExportPathDescription == "Documents/MLTrainingData/createml_data.json")
        #expect(deploymentStatus.compiledModelPathDescription == collector.documentsModelDeploymentPathDescription)
        #expect(MLTrainingError.trainingNotSupported.recoverySuggestion?.contains("ClothingKeypointDetector_<type>.mlmodelc") == true)
    }

    @MainActor
    @Test func mlKeypointModelUsesFullImageScalingForTrainingCoordinateSpace() async throws {
        #expect(VisionMLService.keypointModelCropAndScaleOption == .scaleFill)
    }

    @MainActor
    @Test func mlKeypointDetectionDoesNotUseContourFallbackWhenModelIsMissing() async throws {
        let status = VisionMLModelLoader.shared.currentModelStatus(for: .shortSleeve)
        guard !status.isLoaded else {
            return
        }

        var didThrowModelNotFound = false
        do {
            _ = try await VisionMLService.shared.detectKeypointsWithML(
                from: solidImage(size: CGSize(width: 600, height: 800)),
                clothingType: .shortSleeve
            )
        } catch VisionMLError.modelNotFound {
            didThrowModelNotFound = true
        } catch {
            Issue.record("Unexpected ML detection error: \(error.localizedDescription)")
        }

        #expect(didThrowModelNotFound)
    }

    @MainActor
    @Test func hybridMLDoesNotUseSaliencyAloneWithoutModelOrContour() async throws {
        let status = VisionMLModelLoader.shared.currentModelStatus(for: .shortSleeve)
        guard !status.isLoaded else {
            return
        }

        let keypoints = try await VisionMLService.shared.detectKeypointsHybrid(
            from: solidImage(size: CGSize(width: 600, height: 800)),
            contour: nil,
            clothingType: .shortSleeve
        )

        #expect(keypoints.isEmpty)
    }

    @MainActor
    @Test func hybridMLUsesForegroundFeatureOverrideWithoutContour() async throws {
        let featurePoints = representativeFeaturePoints(for: .shorts)

        let keypoints = try await VisionMLService.shared.detectKeypointsHybrid(
            from: solidImage(size: CGSize(width: 600, height: 800)),
            contour: nil,
            clothingType: .shorts,
            featurePointsOverride: featurePoints
        )
        let keypointTypes = Set(keypoints.map(\.type))

        #expect(keypointTypes.contains(.waistLeft))
        #expect(keypointTypes.contains(.waistRight))
        #expect(keypointTypes.contains(.leftHem))
        #expect(keypointTypes.contains(.rightHem))
    }

    @MainActor
    @Test func typeSpecificCoreMLModelNamesUseClothingRawValue() async throws {
        #expect(VisionMLModelLoader.modelResourceName(for: nil) == "ClothingKeypointDetector")
        #expect(VisionMLModelLoader.modelResourceName(for: .shorts) == "ClothingKeypointDetector_shorts")
        #expect(MLTrainingDataCollector.shared.documentsModelDeploymentPathDescription(for: .shirt) == "Documents/MLTrainingData/Models/ClothingKeypointDetector_shirt.mlmodelc")
    }

    @MainActor
    @Test func clothingTypeMeasurementPriorCompletesRequiredMeasurementLinesForEveryType() async throws {
        let detector = ClothingKeypointDetector()

        for clothingType in ClothingType.allCases {
            let featurePoints = representativeFeaturePoints(for: clothingType)
            let keypoints = ClothingTypeMeasurementPrior.refine(
                [],
                clothingType: clothingType,
                featurePoints: featurePoints,
                learnedKeypoints: [:]
            )
            let lines = detector.generateMeasurementLines(
                from: keypoints,
                clothingType: clothingType
            )
            let lineTypes = lines.map(\.type)

            for measurement in clothingType.requiredMeasurements + clothingType.optionalMeasurements {
                #expect(lineTypes.contains(measurement))
            }

            for line in lines {
                let length = hypot(line.end.x - line.start.x, line.end.y - line.start.y)
                #expect(length > 0.005)
                #expect((0.0...1.0).contains(line.start.x))
                #expect((0.0...1.0).contains(line.start.y))
                #expect((0.0...1.0).contains(line.end.x))
                #expect((0.0...1.0).contains(line.end.y))
            }
        }
    }

    @MainActor
    @Test func learnedMeasurementPriorUsesCollectedSamplesForClothingType() async throws {
        let featurePoints = representativeFeaturePoints(for: .shorts)
        let samples = [
            shortsTrainingSample(idSeed: 1, leftHemX: 0.30, rightHemX: 0.62),
            shortsTrainingSample(idSeed: 2, leftHemX: 0.31, rightHemX: 0.63),
            shortsTrainingSample(idSeed: 3, leftHemX: 0.29, rightHemX: 0.61)
        ]

        let learnedKeypoints = ClothingTypeLearnedMeasurementPrior.projectedKeypoints(
            from: samples,
            clothingType: .shorts,
            featurePoints: featurePoints
        )
        let refinedKeypoints = ClothingTypeMeasurementPrior.refine(
            [],
            clothingType: .shorts,
            featurePoints: featurePoints,
            learnedKeypoints: learnedKeypoints
        )

        let byType = Dictionary(uniqueKeysWithValues: refinedKeypoints.map { ($0.type, $0) })
        let leftHem = try #require(byType[.leftHem])
        let rightHem = try #require(byType[.rightHem])

        #expect(leftHem.position.x < 0.245)
        #expect(rightHem.position.x > 0.64)
        #expect(leftHem.confidence > 0.70)
        #expect(rightHem.confidence > 0.70)
    }

    @MainActor
    @Test func typeTrainingReadinessSeparatesPriorAndModelTrainingStates() async throws {
        let deploymentStatus = MLTrainingModelDeploymentStatus(
            hasDocumentsCompiledModel: false,
            hasDocumentsSourceModel: false,
            compiledModelPathDescription: "",
            sourceModelPathDescription: ""
        )
        let partialPrior = MLTrainingTypeReadiness(
            clothingType: .shorts,
            totalSamples: 3,
            modelTrainingSamples: 3,
            userCorrectedSamples: 3,
            learnedKeypointCount: 2,
            expectedKeypointCount: 6,
            missingKeypointTypes: [.leftHem, .rightHem],
            minimumModelTrainingSamples: 20,
            minimumUserCorrectedSamples: 3,
            modelDeploymentStatus: deploymentStatus
        )
        let trainable = MLTrainingTypeReadiness(
            clothingType: .shorts,
            totalSamples: 20,
            modelTrainingSamples: 20,
            userCorrectedSamples: 12,
            learnedKeypointCount: 6,
            expectedKeypointCount: 6,
            missingKeypointTypes: [],
            minimumModelTrainingSamples: 20,
            minimumUserCorrectedSamples: 3,
            modelDeploymentStatus: deploymentStatus
        )
        let needsCorrections = MLTrainingTypeReadiness(
            clothingType: .shorts,
            totalSamples: 20,
            modelTrainingSamples: 20,
            userCorrectedSamples: 1,
            learnedKeypointCount: 6,
            expectedKeypointCount: 6,
            missingKeypointTypes: [],
            minimumModelTrainingSamples: 20,
            minimumUserCorrectedSamples: 3,
            modelDeploymentStatus: deploymentStatus
        )

        #expect(partialPrior.hasUsableLearnedPrior)
        #expect(!partialPrior.hasCompleteLearnedPrior)
        #expect(!partialPrior.isReadyForModelTraining)
        #expect(partialPrior.missingKeypointSummary == "왼쪽 밑단, 오른쪽 밑단")
        #expect(partialPrior.statusMessage == "타입별 prior 일부 적용")
        #expect(!needsCorrections.isReadyForModelTraining)
        #expect(needsCorrections.neededUserCorrectedSamples == 2)
        #expect(needsCorrections.statusMessage == "보정 샘플 필요")
        #expect(trainable.hasCompleteLearnedPrior)
        #expect(trainable.isReadyForModelTraining)
        #expect(trainable.statusMessage == "모델 학습 가능")
    }

    @MainActor
    @Test func modelTrainingReadinessRequiresDecodableImageData() async throws {
        let deploymentStatus = MLTrainingModelDeploymentStatus(
            hasDocumentsCompiledModel: false,
            hasDocumentsSourceModel: false,
            compiledModelPathDescription: "",
            sourceModelPathDescription: ""
        )
        let rawOnly = MLTrainingTypeReadiness(
            clothingType: .shorts,
            totalSamples: 20,
            modelTrainingSamples: 19,
            userCorrectedSamples: 20,
            learnedKeypointCount: 6,
            expectedKeypointCount: 6,
            missingKeypointTypes: [],
            minimumModelTrainingSamples: 20,
            minimumUserCorrectedSamples: 3,
            modelDeploymentStatus: deploymentStatus
        )
        let validImageData = solidImage(size: CGSize(width: 10, height: 10))
            .jpegData(compressionQuality: 0.8)?
            .base64EncodedString() ?? ""
        var validSample = shortsTrainingSample(idSeed: 4, leftHemX: 0.30, rightHemX: 0.62)
        validSample = TrainingSample(
            id: validSample.id,
            imageData: validImageData,
            clothingType: validSample.clothingType,
            keypoints: validSample.keypoints,
            timestamp: validSample.timestamp,
            isUserCorrected: validSample.isUserCorrected,
            confidence: validSample.confidence
        )
        var augmentedSample = validSample
        augmentedSample.isAugmented = true

        #expect(!rawOnly.isReadyForModelTraining)
        #expect(!MLTrainingDataCollector.isUsableForModelTraining(shortsTrainingSample(idSeed: 5, leftHemX: 0.30, rightHemX: 0.62)))
        #expect(MLTrainingDataCollector.isUsableForModelTraining(validSample))
        #expect(!MLTrainingDataCollector.isUsableForModelTraining(augmentedSample))
    }

    @MainActor
    @Test func modelTrainingReadinessCountsUniqueCapturedImages() async throws {
        let imageA = solidImage(size: CGSize(width: 10, height: 10))
            .jpegData(compressionQuality: 0.8)?
            .base64EncodedString() ?? ""
        let imageB = solidImage(size: CGSize(width: 12, height: 10))
            .jpegData(compressionQuality: 0.8)?
            .base64EncodedString() ?? ""

        let duplicateA = trainingSample(
            from: shortsTrainingSample(idSeed: 6, leftHemX: 0.30, rightHemX: 0.62),
            imageData: imageA,
            isUserCorrected: true
        )
        let duplicateB = trainingSample(
            from: shortsTrainingSample(idSeed: 7, leftHemX: 0.31, rightHemX: 0.63),
            imageData: imageA,
            isUserCorrected: false
        )
        let secondImage = trainingSample(
            from: shortsTrainingSample(idSeed: 8, leftHemX: 0.32, rightHemX: 0.64),
            imageData: imageB,
            isUserCorrected: false
        )

        let samples = [duplicateA, duplicateB, secondImage]

        #expect(MLTrainingDataCollector.uniqueUsableModelTrainingImageCount(in: samples) == 2)
        #expect(MLTrainingDataCollector.uniqueUserCorrectedModelTrainingImageCount(in: samples) == 1)
    }

    @MainActor
    @Test func collectionGapSummaryPrioritizesCaptureDeficits() async throws {
        let missingModel = MLTrainingModelDeploymentStatus(
            hasDocumentsCompiledModel: false,
            hasDocumentsSourceModel: false,
            compiledModelPathDescription: "",
            sourceModelPathDescription: ""
        )
        let deployedModel = MLTrainingModelDeploymentStatus(
            hasDocumentsCompiledModel: true,
            hasDocumentsSourceModel: false,
            compiledModelPathDescription: "",
            sourceModelPathDescription: ""
        )
        let shorts = MLTrainingTypeReadiness(
            clothingType: .shorts,
            totalSamples: 10,
            modelTrainingSamples: 10,
            userCorrectedSamples: 0,
            learnedKeypointCount: 6,
            expectedKeypointCount: 6,
            missingKeypointTypes: [],
            minimumModelTrainingSamples: 20,
            minimumUserCorrectedSamples: 3,
            modelDeploymentStatus: missingModel
        )
        let pants = MLTrainingTypeReadiness(
            clothingType: .pants,
            totalSamples: 20,
            modelTrainingSamples: 20,
            userCorrectedSamples: 3,
            learnedKeypointCount: 8,
            expectedKeypointCount: 8,
            missingKeypointTypes: [],
            minimumModelTrainingSamples: 20,
            minimumUserCorrectedSamples: 3,
            modelDeploymentStatus: missingModel
        )
        let shirt = MLTrainingTypeReadiness(
            clothingType: .shirt,
            totalSamples: 20,
            modelTrainingSamples: 20,
            userCorrectedSamples: 3,
            learnedKeypointCount: 7,
            expectedKeypointCount: 7,
            missingKeypointTypes: [],
            minimumModelTrainingSamples: 20,
            minimumUserCorrectedSamples: 3,
            modelDeploymentStatus: deployedModel
        )

        let summary = MLTrainingCollectionGapSummary(readiness: [pants, shirt, shorts], targetLimit: 2)

        #expect(summary.totalRequiredModelTrainingSamples == 60)
        #expect(summary.totalSatisfiedModelTrainingSamples == 50)
        #expect(summary.totalNeededModelTrainingSamples == 10)
        #expect(summary.totalRequiredUserCorrectedSamples == 9)
        #expect(summary.totalSatisfiedUserCorrectedSamples == 6)
        #expect(summary.totalNeededUserCorrectedSamples == 3)
        #expect(summary.missingCompiledModelCount == 2)
        #expect(summary.trainableTypeCount == 2)
        #expect(summary.completedTypeCount == 1)
        #expect(!summary.isComplete)
        #expect(abs(summary.collectionProgress - (56.0 / 69.0)) < 0.001)
        #expect(summary.nextTargets.map(\.clothingType) == [.shorts, .pants])
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

    private func representativeGarmentKeypoints() -> [MeasurementKeypoint] {
        [
            MeasurementKeypoint(type: .leftShoulder, position: CGPoint(x: 0.24, y: 0.86), confidence: 0.95),
            MeasurementKeypoint(type: .rightShoulder, position: CGPoint(x: 0.76, y: 0.86), confidence: 0.95),
            MeasurementKeypoint(type: .leftArmpit, position: CGPoint(x: 0.30, y: 0.70), confidence: 0.90),
            MeasurementKeypoint(type: .rightArmpit, position: CGPoint(x: 0.70, y: 0.70), confidence: 0.90),
            MeasurementKeypoint(type: .leftSleeveEnd, position: CGPoint(x: 0.10, y: 0.52), confidence: 0.88),
            MeasurementKeypoint(type: .rightSleeveEnd, position: CGPoint(x: 0.90, y: 0.52), confidence: 0.88),
            MeasurementKeypoint(type: .neckline, position: CGPoint(x: 0.50, y: 0.92), confidence: 0.95),
            MeasurementKeypoint(type: .hemCenter, position: CGPoint(x: 0.50, y: 0.10), confidence: 0.95),
            MeasurementKeypoint(type: .chestLeft, position: CGPoint(x: 0.22, y: 0.66), confidence: 0.90),
            MeasurementKeypoint(type: .chestRight, position: CGPoint(x: 0.78, y: 0.66), confidence: 0.90),
            MeasurementKeypoint(type: .waistLeft, position: CGPoint(x: 0.24, y: 0.78), confidence: 0.90),
            MeasurementKeypoint(type: .waistRight, position: CGPoint(x: 0.76, y: 0.78), confidence: 0.90),
            MeasurementKeypoint(type: .hipLeft, position: CGPoint(x: 0.18, y: 0.56), confidence: 0.86),
            MeasurementKeypoint(type: .hipRight, position: CGPoint(x: 0.82, y: 0.56), confidence: 0.86),
            MeasurementKeypoint(type: .crotch, position: CGPoint(x: 0.50, y: 0.40), confidence: 0.86),
            MeasurementKeypoint(type: .leftHem, position: CGPoint(x: 0.18, y: 0.12), confidence: 0.84),
            MeasurementKeypoint(type: .rightHem, position: CGPoint(x: 0.40, y: 0.12), confidence: 0.84)
        ]
    }

    private func representativeFeaturePoints(for clothingType: ClothingType) -> ClothingFeaturePoints {
        let points = [
            CGPoint(x: 0.18, y: 0.92),
            CGPoint(x: 0.82, y: 0.92),
            CGPoint(x: 0.10, y: 0.72),
            CGPoint(x: 0.90, y: 0.72),
            CGPoint(x: 0.14, y: 0.48),
            CGPoint(x: 0.86, y: 0.48),
            CGPoint(x: 0.22, y: 0.12),
            CGPoint(x: 0.78, y: 0.12)
        ]
        return ClothingFeaturePoints.withTemplate(
            topPoint: CGPoint(x: 0.50, y: 0.92),
            bottomPoint: CGPoint(x: 0.50, y: 0.12),
            leftmostPoint: CGPoint(x: 0.10, y: 0.72),
            rightmostPoint: CGPoint(x: 0.90, y: 0.72),
            allPoints: points,
            clothingType: clothingType
        )
    }

    private func shortsTrainingSample(
        idSeed: UInt8,
        leftHemX: Float,
        rightHemX: Float
    ) -> TrainingSample {
        TrainingSample(
            id: UUID(uuid: (
                idSeed, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
            )),
            imageData: "",
            clothingType: ClothingType.shorts.rawValue,
            keypoints: [
                KeypointLabel(identifier: "waist_left", x: 0.20, y: 0.90, visibility: 1.0),
                KeypointLabel(identifier: "waist_right", x: 0.80, y: 0.90, visibility: 1.0),
                KeypointLabel(identifier: "crotch", x: 0.50, y: 0.52, visibility: 1.0),
                KeypointLabel(identifier: "hem_left", x: leftHemX, y: 0.20, visibility: 1.0),
                KeypointLabel(identifier: "hem_right", x: rightHemX, y: 0.20, visibility: 1.0),
                KeypointLabel(identifier: "hem_center", x: (leftHemX + rightHemX) / 2, y: 0.20, visibility: 1.0)
            ],
            timestamp: Date(timeIntervalSince1970: TimeInterval(idSeed)),
            isUserCorrected: true,
            confidence: 0.92
        )
    }

    private func trainingSample(
        from sample: TrainingSample,
        imageData: String,
        isUserCorrected: Bool
    ) -> TrainingSample {
        TrainingSample(
            id: sample.id,
            imageData: imageData,
            clothingType: sample.clothingType,
            keypoints: sample.keypoints,
            timestamp: sample.timestamp,
            isUserCorrected: isUserCorrected,
            confidence: sample.confidence,
            isAugmented: sample.isAugmented,
            sourceSampleID: sample.sourceSampleID
        )
    }
}

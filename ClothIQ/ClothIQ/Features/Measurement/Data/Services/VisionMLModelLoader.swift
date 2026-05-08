//
//  VisionMLModelLoader.swift
//  ClothIQ
//
//  Core ML 키포인트 모델의 로드 상태, 경로 탐색, 출력 파싱을 담당합니다.
//

import Foundation
@preconcurrency import Vision
import CoreML
import CoreGraphics

struct VisionMLModelStatus {
    let isLoaded: Bool
    let sourceDescription: String
    let message: String
}

final class VisionMLModelLoader {
    static let shared = VisionMLModelLoader()
    static let genericModelResourceName = "ClothingKeypointDetector"

    private let documentsModelsRelativePath = "MLTrainingData/Models"
    private var cachedModels: [String: VNCoreMLModel] = [:]
    private var attemptedModelLoads = Set<String>()
    private var modelStatus = VisionMLModelStatus(
        isLoaded: false,
        sourceDescription: "확인 전",
        message: "Core ML 모델 로드 상태를 아직 확인하지 않았습니다."
    )

    private init() {}

    static func modelResourceName(for clothingType: ClothingType?) -> String {
        guard let clothingType else {
            return genericModelResourceName
        }
        return "\(genericModelResourceName)_\(clothingType.rawValue)"
    }

    func currentModelStatus(for clothingType: ClothingType? = nil) -> VisionMLModelStatus {
        if cachedModels[Self.modelResourceName(for: clothingType)] == nil {
            _ = loadCustomModel(for: clothingType)
        }
        return modelStatus
    }

    func reloadCustomModel(for clothingType: ClothingType? = nil) -> VisionMLModelStatus {
        for resourceName in resourceNames(for: clothingType) {
            cachedModels[resourceName] = nil
            attemptedModelLoads.remove(resourceName)
        }
        _ = loadCustomModel(for: clothingType)
        return modelStatus
    }

    func loadCustomModel(for clothingType: ClothingType? = nil) -> VNCoreMLModel? {
        var finalError: Error?
        var foundSourceModel: (url: URL, sourceDescription: String)?

        for resourceName in resourceNames(for: clothingType) {
            if let cachedModel = cachedModels[resourceName] {
                modelStatus = VisionMLModelStatus(
                    isLoaded: true,
                    sourceDescription: resourceName,
                    message: "\(resourceName).mlmodelc 로드 완료"
                )
                return cachedModel
            }

            guard !attemptedModelLoads.contains(resourceName) else {
                continue
            }

            attemptedModelLoads.insert(resourceName)

            if let loadedModel = loadCompiledModel(named: resourceName, lastLoadError: &finalError) {
                return loadedModel
            }

            if foundSourceModel == nil {
                foundSourceModel = sourceModelCandidates(resourceName: resourceName)
                    .first(where: { FileManager.default.fileExists(atPath: $0.url.path) })
            }
        }

        if let foundSourceModel {
            modelStatus = VisionMLModelStatus(
                isLoaded: false,
                sourceDescription: foundSourceModel.sourceDescription,
                message: "원본 .mlmodel만 발견했습니다. iOS 앱은 컴파일된 .mlmodelc를 로드하므로 Mac에서 컴파일 후 배포해야 합니다."
            )
            print("⚠️ [VisionML] .mlmodel 원본만 발견: \(foundSourceModel.sourceDescription). .mlmodelc 컴파일 필요")
            return nil
        }

        if let finalError {
            modelStatus = VisionMLModelStatus(
                isLoaded: false,
                sourceDescription: "로드 실패",
                message: "컴파일된 모델 후보를 찾았지만 로드하지 못했습니다: \(finalError.localizedDescription)"
            )
        } else {
            let requestedName = Self.modelResourceName(for: clothingType)
            modelStatus = VisionMLModelStatus(
                isLoaded: false,
                sourceDescription: "미탑재",
                message: "컴파일된 \(requestedName).mlmodelc가 없어 Vision/휴리스틱/타입별 사전 프로파일로 동작합니다."
            )
        }

        return nil
    }

    private func loadCompiledModel(
        named resourceName: String,
        lastLoadError: inout Error?
    ) -> VNCoreMLModel? {
        for candidate in compiledModelCandidates(resourceName: resourceName) where isCompiledModelDirectory(candidate.url) {
            do {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                let mlModel = try MLModel(contentsOf: candidate.url, configuration: configuration)
                let visionModel = try VNCoreMLModel(for: mlModel)

                cachedModels[resourceName] = visionModel
                modelStatus = VisionMLModelStatus(
                    isLoaded: true,
                    sourceDescription: candidate.sourceDescription,
                    message: "\(resourceName).mlmodelc 로드 완료 (\(candidate.sourceDescription))"
                )
                print("✅ [VisionML] 커스텀 Core ML 모델 로드: \(candidate.sourceDescription)")
                return visionModel
            } catch {
                lastLoadError = error
                print("⚠️ [VisionML] 모델 로드 실패 (\(candidate.sourceDescription)): \(error.localizedDescription)")
            }
        }
        return nil
    }

    private func resourceNames(for clothingType: ClothingType?) -> [String] {
        let generic = Self.genericModelResourceName
        guard let clothingType else {
            return [generic]
        }

        let typeSpecific = Self.modelResourceName(for: clothingType)
        if typeSpecific == generic {
            return [generic]
        }
        return [typeSpecific, generic]
    }

    private func compiledModelCandidates(resourceName: String) -> [(url: URL, sourceDescription: String)] {
        var candidates: [(url: URL, sourceDescription: String)] = []
        appendBundleCandidate(to: &candidates, resourceName: resourceName, subdirectory: nil, sourceDescription: "앱 번들/\(resourceName).mlmodelc")
        appendBundleCandidate(to: &candidates, resourceName: resourceName, subdirectory: "CoreML", sourceDescription: "앱 번들/CoreML/\(resourceName).mlmodelc")
        appendBundleCandidate(to: &candidates, resourceName: resourceName, subdirectory: "Resources/CoreML", sourceDescription: "앱 번들/Resources/CoreML/\(resourceName).mlmodelc")

        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            candidates.append((
                url: documentsDirectory
                    .appendingPathComponent(documentsModelsRelativePath)
                    .appendingPathComponent("\(resourceName).mlmodelc"),
                sourceDescription: "Documents/\(documentsModelsRelativePath)/\(resourceName).mlmodelc"
            ))
        }
        return uniqueCandidates(candidates)
    }

    private func sourceModelCandidates(resourceName: String) -> [(url: URL, sourceDescription: String)] {
        var candidates: [(url: URL, sourceDescription: String)] = []
        appendBundleCandidate(to: &candidates, resourceName: resourceName, extensionName: "mlmodel", subdirectory: nil, sourceDescription: "앱 번들/\(resourceName).mlmodel")
        appendBundleCandidate(to: &candidates, resourceName: resourceName, extensionName: "mlmodel", subdirectory: "CoreML", sourceDescription: "앱 번들/CoreML/\(resourceName).mlmodel")
        appendBundleCandidate(to: &candidates, resourceName: resourceName, extensionName: "mlmodel", subdirectory: "Resources/CoreML", sourceDescription: "앱 번들/Resources/CoreML/\(resourceName).mlmodel")

        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            candidates.append((
                url: documentsDirectory
                    .appendingPathComponent(documentsModelsRelativePath)
                    .appendingPathComponent("\(resourceName).mlmodel"),
                sourceDescription: "Documents/\(documentsModelsRelativePath)/\(resourceName).mlmodel"
            ))
        }
        return uniqueCandidates(candidates)
    }

    private func appendBundleCandidate(
        to candidates: inout [(url: URL, sourceDescription: String)],
        resourceName: String,
        extensionName: String = "mlmodelc",
        subdirectory: String?,
        sourceDescription: String
    ) {
        guard let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: extensionName,
            subdirectory: subdirectory
        ) else { return }
        candidates.append((url: url, sourceDescription: sourceDescription))
    }

    private func uniqueCandidates(_ candidates: [(url: URL, sourceDescription: String)]) -> [(url: URL, sourceDescription: String)] {
        var seenPaths = Set<String>()
        return candidates.filter { seenPaths.insert($0.url.path).inserted }
    }

    private func isCompiledModelDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

enum VisionMLModelOutputParser {
    private static let keypointIdentifiers = [
        "left_shoulder", "right_shoulder", "left_armpit", "right_armpit",
        "left_sleeve", "right_sleeve", "neckline", "hem_center",
        "chest_left", "chest_right", "waist_left", "waist_right",
        "hip_left", "hip_right", "crotch", "hem_left", "hem_right"
    ]

    static func parse(
        _ results: [VNCoreMLFeatureValueObservation],
        minConfidence: Float,
        keypointMapping: [String: KeypointType]
    ) -> [MLKeypoint] {
        var keypoints: [MLKeypoint] = []

        for observation in results {
            guard let multiArray = observation.featureValue.multiArrayValue else { continue }
            let count = min(keypointIdentifiers.count, multiArray.count / 3)

            for index in 0..<count {
                let baseIndex = index * 3
                let identifier = keypointIdentifiers[index]
                let confidence = clamp01(multiArray[baseIndex + 2].floatValue)
                guard confidence >= minConfidence else { continue }

                keypoints.append(MLKeypoint(
                    identifier: identifier,
                    position: CGPoint(
                        x: CGFloat(clamp01(multiArray[baseIndex].floatValue)),
                        y: CGFloat(clamp01(multiArray[baseIndex + 1].floatValue))
                    ),
                    confidence: confidence,
                    type: keypointMapping[identifier],
                    depth: nil
                ))
            }
        }

        return keypoints
    }

    private static func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}

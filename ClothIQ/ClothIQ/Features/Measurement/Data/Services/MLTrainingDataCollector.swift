//
//  MLTrainingDataCollector.swift
//  ClothIQ
//
//  Created on 2025-11-10
//
//  Description:
//  ML 모델 학습을 위한 데이터 수집 및 관리 서비스입니다.
//  사용자의 수정사항을 학습 데이터로 수집하여 모델을 개선합니다.
//
//  Key Features:
//  - 사용자 피드백 수집
//  - 학습 데이터 저장
//  - 데이터 레이블링
//  - CreateML 형식 내보내기
//

import Foundation
import UIKit
import ImageIO
import CoreML
import Combine
#if os(macOS)
import CreateML
#endif

/// 학습 데이터 샘플
struct TrainingSample: Codable {
    /// 샘플 ID
    let id: UUID

    /// 이미지 데이터 (Base64 인코딩)
    let imageData: String

    /// 의류 타입
    let clothingType: String

    /// 키포인트 레이블 (정규화된 좌표)
    let keypoints: [KeypointLabel]

    /// 수집 날짜
    let timestamp: Date

    /// 사용자 수정 여부
    let isUserCorrected: Bool

    /// 신뢰도 점수
    let confidence: Float

    /// 증강 데이터 여부. 실제 촬영 원본 완료 기준에는 포함하지 않습니다.
    var isAugmented: Bool? = nil

    /// 증강 데이터의 원본 샘플 ID
    var sourceSampleID: String? = nil
}

/// 키포인트 레이블
struct KeypointLabel: Codable {
    /// 키포인트 식별자
    let identifier: String

    /// 정규화된 X 좌표 (0.0 ~ 1.0)
    let x: Float

    /// 정규화된 Y 좌표 (0.0 ~ 1.0)
    let y: Float

    /// 가시성 (0: 보이지 않음, 1: 보임)
    let visibility: Float
}

/// ML 학습 데이터 수집기
final class MLTrainingDataCollector: ObservableObject {

    // MARK: - Properties

    /// 싱글톤 인스턴스
    static let shared = MLTrainingDataCollector()

    /// 저장 경로
    private let documentsDirectory: URL

    /// 학습 데이터 디렉토리
    private let trainingDataDirectory: URL

    /// 이미지 디렉토리
    private let imagesDirectory: URL

    /// 외부 학습 후 컴파일된 모델 배포 디렉토리
    private let modelsDirectory: URL

    /// 레이블 파일
    private let labelsFile: URL

    /// CreateML 내보내기 파일
    private let createMLExportFile: URL

    /// 최대 샘플 수
    private let maxSamples = 10000

    /// 최소 샘플 수 (모델 학습용)
    private let minSamplesForTraining = 100

    /// 타입별 모델 학습 최소 샘플 수
    let minimumSamplesPerTypeForModelTraining = 20

    /// 타입별 모델 학습 최소 사용자 보정 샘플 수
    let minimumUserCorrectedSamplesPerTypeForModelTraining = 3

    // MARK: - Published Properties

    /// 데이터 수집 활성화 상태
    @Published var isEnabled: Bool = true

    /// 사용자 수정 데이터만 수집
    @Published var collectOnlyUserCorrected: Bool = false

    /// 총 샘플 수
    @Published var totalSamples: Int = 0

    /// 사용자 수정 샘플 수
    @Published var userCorrectedSamples: Int = 0

    /// 모델 학습에 사용할 수 있는 고유 원본 촬영 수
    @Published var usableModelTrainingSamples: Int = 0

    /// 모델 학습에 사용할 수 있는 고유 사용자 보정 원본 촬영 수
    @Published var uniqueUserCorrectedModelTrainingSamples: Int = 0

    /// 평균 신뢰도
    @Published var averageConfidence: Float = 0.0

    // MARK: - Initialization

    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        trainingDataDirectory = documentsDirectory.appendingPathComponent("MLTrainingData")
        imagesDirectory = trainingDataDirectory.appendingPathComponent("images")
        modelsDirectory = trainingDataDirectory.appendingPathComponent("Models")
        labelsFile = trainingDataDirectory.appendingPathComponent("labels.json")
        createMLExportFile = trainingDataDirectory.appendingPathComponent("createml_data.json")

        setupDirectories()
        updateStatistics()
    }

    // MARK: - Public Methods

    /// 학습 데이터 수집
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - keypoints: 감지된 키포인트
    ///   - clothingType: 의류 타입
    ///   - isUserCorrected: 사용자 수정 여부
    func collectTrainingData(
        image: UIImage,
        keypoints: [MeasurementKeypoint],
        clothingType: ClothingType,
        isUserCorrected: Bool
    ) {
        // 데이터 수집이 비활성화되어 있으면 종료
        guard isEnabled else {
            print("⏸ [MLTraining] 데이터 수집 비활성화 상태")
            return
        }

        // 사용자 수정 데이터만 수집 설정 확인
        if collectOnlyUserCorrected && !isUserCorrected {
            print("⏸ [MLTraining] 사용자 수정 데이터만 수집 모드 - 건너뜀")
            return
        }

        print("📊 [MLTraining] 학습 데이터 수집 시작")

        // 이미지를 Base64로 인코딩
        guard let imageData = image.jpegData(compressionQuality: 0.8)?.base64EncodedString() else {
            print("❌ [MLTraining] 이미지 인코딩 실패")
            return
        }

        // 키포인트를 레이블 형식으로 변환
        let labels = keypoints.map { keypoint in
            KeypointLabel(
                identifier: keypoint.type.trainingIdentifier,
                x: Float(keypoint.position.x),
                y: Float(keypoint.position.y),
                visibility: keypoint.confidence > 0.5 ? 1.0 : 0.0
            )
        }

        // 샘플 생성
        let sample = TrainingSample(
            id: UUID(),
            imageData: imageData,
            clothingType: clothingType.rawValue,
            keypoints: labels,
            timestamp: Date(),
            isUserCorrected: isUserCorrected,
            confidence: calculateAverageConfidence(keypoints),
            isAugmented: nil,
            sourceSampleID: nil
        )

        // 샘플 저장
        saveSample(sample)

        print("✅ [MLTraining] 학습 데이터 수집 완료")
        print("  - 키포인트 수: \(labels.count)")
        print("  - 사용자 수정: \(isUserCorrected)")
    }

    /// 학습 데이터 통계
    func getTrainingDataStatistics() -> TrainingDataStatistics {
        let samples = loadAllSamples()

        let totalSamples = samples.count
        let usableModelTrainingSamples = Self.uniqueUsableModelTrainingImageCount(in: samples)
        let uniqueUserCorrectedModelTrainingSamples = Self.uniqueUserCorrectedModelTrainingImageCount(in: samples)
        let userCorrectedSamples = samples.filter { $0.isUserCorrected }.count

        // 의류 타입별 통계
        var clothingTypeStats: [String: Int] = [:]
        for sample in samples {
            clothingTypeStats[sample.clothingType, default: 0] += 1
        }

        return TrainingDataStatistics(
            totalSamples: totalSamples,
            usableModelTrainingSamples: usableModelTrainingSamples,
            uniqueUserCorrectedModelTrainingSamples: uniqueUserCorrectedModelTrainingSamples,
            userCorrectedSamples: userCorrectedSamples,
            clothingTypeDistribution: clothingTypeStats,
            averageConfidence: calculateAverageConfidence(from: samples),
            isReadyForTraining: usableModelTrainingSamples >= minSamplesForTraining
        )
    }

    /// 외부 모델 학습에 실제로 사용할 수 있는 샘플인지 확인
    nonisolated static func isUsableForModelTraining(_ sample: TrainingSample) -> Bool {
        guard !sample.isAugmentedSample,
              !sample.clothingType.isEmpty,
              !sample.keypoints.isEmpty,
              let imageData = Data(base64Encoded: sample.imageData),
              !imageData.isEmpty,
              let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0 else {
            return false
        }

        return true
    }

    /// 모델 학습 완료 기준에 사용할 고유 촬영 원본 수입니다.
    ///
    /// 같은 촬영 이미지가 여러 측정 라벨로 저장될 수 있으므로 레코드 수가 아닌
    /// 이미지 데이터 기준 고유 개수를 사용합니다.
    nonisolated static func uniqueUsableModelTrainingImageCount(in samples: [TrainingSample]) -> Int {
        Set(samples.filter(isUsableForModelTraining).map(\.imageData)).count
    }

    /// 모델 학습 완료 기준에 사용할 고유 사용자 보정 촬영 원본 수입니다.
    nonisolated static func uniqueUserCorrectedModelTrainingImageCount(in samples: [TrainingSample]) -> Int {
        Set(samples.filter { isUsableForModelTraining($0) && $0.isUserCorrected }.map(\.imageData)).count
    }

    /// 앱 내부 학습 대신 사용하는 외부 학습 워크플로우 안내
    var trainingNotSupportedMessage: String {
        "iOS 앱 내부에서는 TensorFlow/CreateML 학습을 실행하지 않습니다. 앱에서 데이터를 수집한 뒤 \(createMLExportPathDescription)로 내보내고, Mac에서 scripts/ml_training_workflow.sh --per-type를 실행해 의류 타입별 \(VisionMLModelLoader.genericModelResourceName)_<type>.mlmodelc 또는 공통 \(VisionMLModelLoader.genericModelResourceName).mlmodelc를 배포하세요."
    }

    /// 학습 데이터 루트 경로 설명
    var trainingDataDirectoryDescription: String {
        "Documents/MLTrainingData"
    }

    /// 원본 레이블 JSON 경로 설명
    var labelsFileDescription: String {
        "Documents/MLTrainingData/labels.json"
    }

    /// CreateML/Python 학습 입력 JSON 경로 설명
    var createMLExportPathDescription: String {
        "Documents/MLTrainingData/createml_data.json"
    }

    /// 앱 Documents에 배포할 컴파일된 모델 경로 설명
    var documentsModelDeploymentPathDescription: String {
        "Documents/MLTrainingData/Models/ClothingKeypointDetector.mlmodelc"
    }

    /// 앱 번들에 포함할 컴파일된 모델 경로 설명
    var bundledModelDeploymentPathDescription: String {
        "앱 번들/CoreML/ClothingKeypointDetector.mlmodelc"
    }

    /// Documents 모델 배포 상태
    func getModelDeploymentStatus() -> MLTrainingModelDeploymentStatus {
        getModelDeploymentStatus(for: nil)
    }

    /// Documents 모델 배포 상태
    func getModelDeploymentStatus(for clothingType: ClothingType?) -> MLTrainingModelDeploymentStatus {
        let resourceName = VisionMLModelLoader.modelResourceName(for: clothingType)
        let compiledModelURL = modelsDirectory.appendingPathComponent("\(resourceName).mlmodelc")
        let sourceModelURL = modelsDirectory.appendingPathComponent("\(resourceName).mlmodel")

        return MLTrainingModelDeploymentStatus(
            hasDocumentsCompiledModel: directoryExists(at: compiledModelURL),
            hasDocumentsSourceModel: FileManager.default.fileExists(atPath: sourceModelURL.path),
            compiledModelPathDescription: documentsModelDeploymentPathDescription(for: clothingType),
            sourceModelPathDescription: "Documents/MLTrainingData/Models/\(resourceName).mlmodel"
        )
    }

    func documentsModelDeploymentPathDescription(for clothingType: ClothingType?) -> String {
        let resourceName = VisionMLModelLoader.modelResourceName(for: clothingType)
        return "Documents/MLTrainingData/Models/\(resourceName).mlmodelc"
    }

    /// 의류 타입별 학습/prior 준비 상태
    func getTypeTrainingReadiness() -> [MLTrainingTypeReadiness] {
        let samples = loadAllSamples()
        return ClothingType.allCases.map { clothingType in
            typeTrainingReadiness(
                for: clothingType,
                samples: samples,
                deploymentStatus: getModelDeploymentStatus(for: clothingType)
            )
        }
    }

    /// 전체 타입 기준 수집 부족분 요약
    func getCollectionGapSummary() -> MLTrainingCollectionGapSummary {
        MLTrainingCollectionGapSummary(readiness: getTypeTrainingReadiness())
    }

    /// 특정 의류 타입의 학습/prior 준비 상태
    func getTypeTrainingReadiness(for clothingType: ClothingType) -> MLTrainingTypeReadiness {
        typeTrainingReadiness(
            for: clothingType,
            samples: loadAllSamples(),
            deploymentStatus: getModelDeploymentStatus(for: clothingType)
        )
    }

    /// 수집된 촬영/수정 샘플 기반 의류 타입별 prior 키포인트
    func learnedMeasurementPriorKeypoints(
        for clothingType: ClothingType,
        featurePoints: ClothingFeaturePoints,
        minimumVisibleSamples: Int = ClothingTypeLearnedMeasurementPrior.minimumVisibleSamples
    ) -> [KeypointType: MeasurementKeypoint] {
        ClothingTypeLearnedMeasurementPrior.projectedKeypoints(
            from: loadAllSamples(),
            clothingType: clothingType,
            featurePoints: featurePoints,
            minimumVisibleSamples: minimumVisibleSamples
        )
    }

    private func typeTrainingReadiness(
        for clothingType: ClothingType,
        samples: [TrainingSample],
        deploymentStatus: MLTrainingModelDeploymentStatus
    ) -> MLTrainingTypeReadiness {
        let typeSamples = samples.filter { $0.clothingType == clothingType.rawValue }
        let uniqueModelTrainingSampleCount = Self.uniqueUsableModelTrainingImageCount(in: typeSamples)
        let uniqueUserCorrectedSampleCount = Self.uniqueUserCorrectedModelTrainingImageCount(in: typeSamples)
        let learnedProfile = ClothingTypeLearnedMeasurementPrior.relativeProfile(
            from: samples,
            clothingType: clothingType
        )
        let expectedKeypoints = ClothingTypeMeasurementPrior.expectedKeypointTypes(for: clothingType)
        let missingKeypoints = expectedKeypoints
            .subtracting(Set(learnedProfile.keys))
            .sorted { $0.displayName < $1.displayName }

        return MLTrainingTypeReadiness(
            clothingType: clothingType,
            totalSamples: typeSamples.count,
            modelTrainingSamples: uniqueModelTrainingSampleCount,
            userCorrectedSamples: uniqueUserCorrectedSampleCount,
            learnedKeypointCount: learnedProfile.count,
            expectedKeypointCount: expectedKeypoints.count,
            missingKeypointTypes: missingKeypoints,
            minimumModelTrainingSamples: minimumSamplesPerTypeForModelTraining,
            minimumUserCorrectedSamples: minimumUserCorrectedSamplesPerTypeForModelTraining,
            modelDeploymentStatus: deploymentStatus
        )
    }

    /// CreateML 형식으로 내보내기
    ///
    /// - Returns: 내보낸 파일 URL
    func exportForCreateML() throws -> URL {
        print("🚀 [MLTraining] CreateML 형식으로 내보내기 시작")
        print("  - 원본 레이블: \(labelsFileDescription)")
        print("  - 내보내기 경로: \(createMLExportPathDescription)")
        print("  - 모델 배포 경로: \(documentsModelDeploymentPathDescription)")

        let samples = loadAllSamples()

        guard samples.count >= minSamplesForTraining else {
            throw MLTrainingError.insufficientData(current: samples.count, required: minSamplesForTraining)
        }

        // CreateML JSON 형식 생성
        var createMLData: [[String: Any]] = []

        for (index, sample) in samples.enumerated() {
            // 이미지 파일로 저장
            let imageFilename = "image_\(index).jpg"
            let imageURL = imagesDirectory.appendingPathComponent(imageFilename)

            if let imageData = Data(base64Encoded: sample.imageData) {
                try imageData.write(to: imageURL)
            }

            // 레이블 데이터 생성
            var annotations: [[String: Any]] = []

            for keypoint in sample.keypoints {
                annotations.append([
                    "label": keypoint.identifier,
                    "coordinates": [
                        "x": keypoint.x,
                        "y": keypoint.y
                    ],
                    "visibility": keypoint.visibility
                ])
            }

            createMLData.append([
                "image": imageFilename,
                "annotations": annotations
            ])
        }

        // JSON 파일로 저장
        let jsonData = try JSONSerialization.data(withJSONObject: createMLData, options: .prettyPrinted)
        try jsonData.write(to: createMLExportFile)

        print("✅ [MLTraining] CreateML 내보내기 완료")
        print("  - 샘플 수: \(samples.count)")
        print("  - 출력 경로: \(createMLExportPathDescription)")

        return createMLExportFile
    }

    /// 모델 학습 (CreateML 사용)
    @available(iOS 15.0, macOS 12.0, *)
    func trainModel() async throws -> MLModel {
        print("🎓 [MLTraining] 모델 학습 시작")
        print("🚫 [MLTraining] \(trainingNotSupportedMessage)")

        // 학습 데이터 준비
        _ = try exportForCreateML()

        // CreateML 모델 학습 (예시)
        // 실제로는 macOS에서 CreateML 앱을 사용하거나
        // CreateMLComponents 프레임워크를 사용해야 함

        throw MLTrainingError.trainingNotSupported
    }

    /// 학습 데이터 초기화
    func clearTrainingData() {
        do {
            if FileManager.default.fileExists(atPath: trainingDataDirectory.path) {
                try FileManager.default.removeItem(at: trainingDataDirectory)
                setupDirectories()
                print("✅ [MLTraining] 학습 데이터 초기화 완료")
                updateStatistics()
            }
        } catch {
            print("❌ [MLTraining] 학습 데이터 초기화 실패: \(error)")
        }
    }

    /// 모든 데이터 삭제
    func clearAllData() {
        clearTrainingData()
    }

    /// 의류 타입별 샘플 수 가져오기
    func getSampleCount(for clothingType: ClothingType) -> Int {
        let samples = loadAllSamples()
        return samples.filter { $0.clothingType == clothingType.rawValue }.count
    }

    /// 측정 타입별 샘플 수 가져오기
    func getSampleCount(forMeasurement measurementType: MeasurementType) -> Int {
        // 측정 타입과 관련된 키포인트 식별자 매핑
        let identifiers = getKeypoints(for: measurementType)
        let samples = loadAllSamples()

        return samples.filter { sample in
            sample.keypoints.contains { keypoint in
                identifiers.contains(keypoint.identifier)
            }
        }.count
    }

    /// 최근 샘플 가져오기
    func getRecentSamples(limit: Int) -> [(clothingType: String, timestamp: Date, isUserCorrected: Bool)]? {
        let samples = loadAllSamples()
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)

        guard !samples.isEmpty else { return nil }

        return samples.map {
            (clothingType: $0.clothingType, timestamp: $0.timestamp, isUserCorrected: $0.isUserCorrected)
        }
    }

    /// CreateML 형식으로 비동기 내보내기
    func exportForCreateMLAsync() async -> Bool {
        do {
            _ = try exportForCreateML()
            return true
        } catch {
            print("❌ [MLTraining] CreateML 내보내기 실패: \(error)")
            return false
        }
    }

    /// 통계 업데이트
    private func updateStatistics() {
        let stats = getTrainingDataStatistics()
        DispatchQueue.main.async {
            self.totalSamples = stats.totalSamples
            self.userCorrectedSamples = stats.userCorrectedSamples
            self.usableModelTrainingSamples = stats.usableModelTrainingSamples
            self.uniqueUserCorrectedModelTrainingSamples = stats.uniqueUserCorrectedModelTrainingSamples
            self.averageConfidence = stats.averageConfidence
        }
    }

    /// 측정 타입에 대한 키포인트 식별자 가져오기
    private func getKeypoints(for measurementType: MeasurementType) -> [String] {
        switch measurementType {
        case .shoulderWidth:
            return ["left_shoulder", "right_shoulder"]
        case .chestCircumference:
            return ["left_armpit", "right_armpit", "chest_left", "chest_right"]
        case .totalLength:
            return ["neckline", "hem_center"]
        case .sleeveLength:
            return ["left_shoulder", "left_sleeve", "right_shoulder", "right_sleeve"]
        case .armCircumference:
            return ["left_sleeve", "right_sleeve", "left_shoulder", "right_shoulder"]
        case .neckCircumference:
            return ["neckline", "left_shoulder", "right_shoulder"]
        case .cuffCircumference:
            return ["left_sleeve", "right_sleeve"]
        case .waistCircumference:
            return ["waist_left", "waist_right"]
        case .hipCircumference:
            return ["hip_left", "hip_right"]
        case .rise:
            return ["waist_left", "waist_right", "crotch"]
        case .hem:
            return ["hem_left", "hem_right"]
        case .thighCircumference:
            return ["crotch", "hip_left", "hip_right"]
        }
    }

    // MARK: - Private Methods

    /// 디렉토리 설정
    private func setupDirectories() {
        do {
            try FileManager.default.createDirectory(at: trainingDataDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        } catch {
            print("❌ [MLTraining] 디렉토리 생성 실패: \(error)")
        }
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// 샘플 저장
    private func saveSample(_ sample: TrainingSample) {
        var samples = loadAllSamples()

        // 최대 샘플 수 제한
        if samples.count >= maxSamples {
            // 가장 오래된 샘플 제거
            samples.sort { $0.timestamp < $1.timestamp }
            samples.removeFirst()
        }

        samples.append(sample)

        // JSON으로 저장
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(samples)
            try data.write(to: labelsFile)

            print("💾 [MLTraining] 샘플 저장 완료 (총 \(samples.count)개)")

            // 통계 업데이트
            updateStatistics()
        } catch {
            print("❌ [MLTraining] 샘플 저장 실패: \(error)")
        }
    }

    /// 모든 샘플 로드
    private func loadAllSamples() -> [TrainingSample] {
        guard FileManager.default.fileExists(atPath: labelsFile.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: labelsFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([TrainingSample].self, from: data)
        } catch {
            print("❌ [MLTraining] 샘플 로드 실패: \(error)")
            return []
        }
    }

    /// 평균 신뢰도 계산
    private func calculateAverageConfidence(_ keypoints: [MeasurementKeypoint]) -> Float {
        guard !keypoints.isEmpty else { return 0 }
        let sum = keypoints.reduce(Float(0)) { $0 + $1.confidence }
        return sum / Float(keypoints.count)
    }

    /// 샘플들의 평균 신뢰도 계산
    private func calculateAverageConfidence(from samples: [TrainingSample]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1.confidence }
        return sum / Float(samples.count)
    }
}

private extension TrainingSample {
    nonisolated var isAugmentedSample: Bool {
        isAugmented == true || !(sourceSampleID?.isEmpty ?? true)
    }
}

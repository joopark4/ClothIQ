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
import SwiftUI
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

    /// 레이블 파일
    private let labelsFile: URL

    /// 최대 샘플 수
    private let maxSamples = 10000

    /// 최소 샘플 수 (모델 학습용)
    private let minSamplesForTraining = 100

    // MARK: - Published Properties

    /// 데이터 수집 활성화 상태
    @Published var isEnabled: Bool = true

    /// 사용자 수정 데이터만 수집
    @Published var collectOnlyUserCorrected: Bool = false

    /// 총 샘플 수
    @Published var totalSamples: Int = 0

    /// 사용자 수정 샘플 수
    @Published var userCorrectedSamples: Int = 0

    /// 평균 신뢰도
    @Published var averageConfidence: Float = 0.0

    // MARK: - Initialization

    private init() {
        documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        trainingDataDirectory = documentsDirectory.appendingPathComponent("MLTrainingData")
        imagesDirectory = trainingDataDirectory.appendingPathComponent("images")
        labelsFile = trainingDataDirectory.appendingPathComponent("labels.json")

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
                identifier: getIdentifier(for: keypoint.type),
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
            confidence: calculateAverageConfidence(keypoints)
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
        let userCorrectedSamples = samples.filter { $0.isUserCorrected }.count

        // 의류 타입별 통계
        var clothingTypeStats: [String: Int] = [:]
        for sample in samples {
            clothingTypeStats[sample.clothingType, default: 0] += 1
        }

        return TrainingDataStatistics(
            totalSamples: totalSamples,
            userCorrectedSamples: userCorrectedSamples,
            clothingTypeDistribution: clothingTypeStats,
            averageConfidence: calculateAverageConfidence(from: samples),
            isReadyForTraining: totalSamples >= minSamplesForTraining
        )
    }

    /// CreateML 형식으로 내보내기
    ///
    /// - Returns: 내보낸 파일 URL
    func exportForCreateML() throws -> URL {
        print("🚀 [MLTraining] CreateML 형식으로 내보내기 시작")

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
        let outputURL = trainingDataDirectory.appendingPathComponent("createml_data.json")
        let jsonData = try JSONSerialization.data(withJSONObject: createMLData, options: .prettyPrinted)
        try jsonData.write(to: outputURL)

        print("✅ [MLTraining] CreateML 내보내기 완료")
        print("  - 샘플 수: \(samples.count)")
        print("  - 출력 경로: \(outputURL.path)")

        return outputURL
    }

    /// 모델 학습 (CreateML 사용)
    @available(iOS 15.0, macOS 12.0, *)
    func trainModel() async throws -> MLModel {
        print("🎓 [MLTraining] 모델 학습 시작")

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
        default:
            return []
        }
    }

    // MARK: - Private Methods

    /// 디렉토리 설정
    private func setupDirectories() {
        do {
            try FileManager.default.createDirectory(at: trainingDataDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        } catch {
            print("❌ [MLTraining] 디렉토리 생성 실패: \(error)")
        }
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

    /// 키포인트 타입을 식별자로 변환
    private func getIdentifier(for type: KeypointType) -> String {
        switch type {
        case .leftShoulder: return "left_shoulder"
        case .rightShoulder: return "right_shoulder"
        case .leftArmpit: return "left_armpit"
        case .rightArmpit: return "right_armpit"
        case .leftSleeveEnd: return "left_sleeve"
        case .rightSleeveEnd: return "right_sleeve"
        case .neckline: return "neckline"
        case .hemCenter: return "hem_center"
        case .chestLeft: return "chest_left"
        case .chestRight: return "chest_right"
        case .waistLeft: return "waist_left"
        case .waistRight: return "waist_right"
        case .hipLeft: return "hip_left"
        case .hipRight: return "hip_right"
        case .crotch: return "crotch"
        case .leftHem: return "hem_left"
        case .rightHem: return "hem_right"
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

// MARK: - Supporting Types

/// 학습 데이터 통계
struct TrainingDataStatistics {
    /// 총 샘플 수
    let totalSamples: Int

    /// 사용자 수정 샘플 수
    let userCorrectedSamples: Int

    /// 의류 타입별 분포
    let clothingTypeDistribution: [String: Int]

    /// 평균 신뢰도
    let averageConfidence: Float

    /// 학습 준비 상태
    let isReadyForTraining: Bool
}

/// ML 학습 에러
enum MLTrainingError: LocalizedError {
    case insufficientData(current: Int, required: Int)
    case trainingNotSupported
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .insufficientData(let current, let required):
            return "학습 데이터 부족 (현재: \(current), 필요: \(required))"
        case .trainingNotSupported:
            return "iOS 기기에서는 모델 학습이 지원되지 않습니다"
        case .exportFailed:
            return "데이터 내보내기 실패"
        }
    }
}

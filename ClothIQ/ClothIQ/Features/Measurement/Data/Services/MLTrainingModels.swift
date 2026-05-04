//
//  MLTrainingModels.swift
//  ClothIQ
//
//  ML 학습 데이터 수집 상태와 배포 상태 모델
//

import Foundation

/// 학습 데이터 통계
struct TrainingDataStatistics {
    /// 총 샘플 수
    let totalSamples: Int

    /// 모델 학습에 사용할 수 있는 유효 샘플 수
    let usableModelTrainingSamples: Int

    /// 모델 학습에 사용할 수 있는 고유 사용자 보정 원본 촬영 수
    let uniqueUserCorrectedModelTrainingSamples: Int

    /// 사용자 수정 샘플 수
    let userCorrectedSamples: Int

    /// 의류 타입별 분포
    let clothingTypeDistribution: [String: Int]

    /// 평균 신뢰도
    let averageConfidence: Float

    /// 학습 준비 상태
    let isReadyForTraining: Bool
}

/// 학습된 모델 배포 상태
struct MLTrainingModelDeploymentStatus {
    let hasDocumentsCompiledModel: Bool
    let hasDocumentsSourceModel: Bool
    let compiledModelPathDescription: String
    let sourceModelPathDescription: String

    var statusMessage: String {
        if hasDocumentsCompiledModel {
            return "Documents에 컴파일된 .mlmodelc 모델이 배포되어 있습니다."
        }

        if hasDocumentsSourceModel {
            return "Documents에 원본 .mlmodel만 있습니다. 앱 로드를 위해 .mlmodelc 컴파일이 필요합니다."
        }

        return "Documents 모델 배포 경로에 학습된 모델이 없습니다."
    }
}

/// 의류 타입별 학습 준비 상태
struct MLTrainingTypeReadiness {
    let clothingType: ClothingType
    let totalSamples: Int
    let modelTrainingSamples: Int
    let userCorrectedSamples: Int
    let learnedKeypointCount: Int
    let expectedKeypointCount: Int
    let missingKeypointTypes: [KeypointType]
    let minimumModelTrainingSamples: Int
    let minimumUserCorrectedSamples: Int
    let modelDeploymentStatus: MLTrainingModelDeploymentStatus

    var neededModelTrainingSamples: Int {
        max(0, minimumModelTrainingSamples - modelTrainingSamples)
    }

    var neededUserCorrectedSamples: Int {
        max(0, minimumUserCorrectedSamples - userCorrectedSamples)
    }

    var hasUsableLearnedPrior: Bool {
        learnedKeypointCount > 0
    }

    var hasCompleteLearnedPrior: Bool {
        expectedKeypointCount > 0 && learnedKeypointCount >= expectedKeypointCount
    }

    var missingKeypointSummary: String {
        guard !missingKeypointTypes.isEmpty else {
            return "부족 키포인트 없음"
        }
        return missingKeypointTypes.map(\.displayName).joined(separator: ", ")
    }

    var isReadyForModelTraining: Bool {
        modelTrainingSamples >= minimumModelTrainingSamples
            && userCorrectedSamples >= minimumUserCorrectedSamples
    }

    var isCompleteForTrainingDeployment: Bool {
        modelDeploymentStatus.hasDocumentsCompiledModel
            && isReadyForModelTraining
            && hasCompleteLearnedPrior
    }

    var statusMessage: String {
        if modelDeploymentStatus.hasDocumentsCompiledModel {
            return "타입별 모델 배포됨"
        }

        if isReadyForModelTraining {
            return "모델 학습 가능"
        }

        if neededModelTrainingSamples == 0 && neededUserCorrectedSamples > 0 {
            return "보정 샘플 필요"
        }

        if hasCompleteLearnedPrior {
            return "타입별 prior 완료"
        }

        if hasUsableLearnedPrior {
            return "타입별 prior 일부 적용"
        }

        return "샘플 수집 필요"
    }
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
            return "iOS 앱 내부에서는 모델 학습이 지원되지 않습니다"
        case .exportFailed:
            return "데이터 내보내기 실패"
        }
    }

    var failureReason: String? {
        switch self {
        case .trainingNotSupported:
            return "CreateML/TensorFlow 학습과 .mlmodelc 컴파일은 Mac의 외부 학습 워크플로우에서 수행해야 합니다."
        default:
            return nil
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .trainingNotSupported:
            return "앱에서 데이터를 수집하고 CreateML 형식으로 내보낸 뒤 scripts/ml_training_workflow.sh --per-type를 실행하세요. 산출물은 앱 번들/CoreML 또는 Documents/MLTrainingData/Models의 ClothingKeypointDetector_<type>.mlmodelc 또는 공통 ClothingKeypointDetector.mlmodelc로 배포해야 합니다."
        default:
            return nil
        }
    }
}

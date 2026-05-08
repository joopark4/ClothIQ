//
//  MLTrainingCollectionGapSummary.swift
//  ClothIQ
//
//  의류 타입별 ML 학습 데이터 수집 부족분 요약
//

import Foundation

/// 전체 타입 기준 학습 데이터 수집 부족분 요약
struct MLTrainingCollectionGapSummary {
    let totalRequiredModelTrainingSamples: Int
    let totalSatisfiedModelTrainingSamples: Int
    let totalNeededModelTrainingSamples: Int
    let totalRequiredUserCorrectedSamples: Int
    let totalSatisfiedUserCorrectedSamples: Int
    let totalNeededUserCorrectedSamples: Int
    let missingCompiledModelCount: Int
    let trainableTypeCount: Int
    let completedTypeCount: Int
    let nextTargets: [MLTrainingTypeReadiness]

    init(readiness: [MLTrainingTypeReadiness], targetLimit: Int = 5) {
        totalRequiredModelTrainingSamples = readiness.reduce(0) { $0 + $1.minimumModelTrainingSamples }
        totalSatisfiedModelTrainingSamples = readiness.reduce(0) {
            $0 + min($1.modelTrainingSamples, $1.minimumModelTrainingSamples)
        }
        totalNeededModelTrainingSamples = readiness.reduce(0) { $0 + $1.neededModelTrainingSamples }
        totalRequiredUserCorrectedSamples = readiness.reduce(0) { $0 + $1.minimumUserCorrectedSamples }
        totalSatisfiedUserCorrectedSamples = readiness.reduce(0) {
            $0 + min($1.userCorrectedSamples, $1.minimumUserCorrectedSamples)
        }
        totalNeededUserCorrectedSamples = readiness.reduce(0) { $0 + $1.neededUserCorrectedSamples }
        missingCompiledModelCount = readiness.filter { !$0.modelDeploymentStatus.hasDocumentsCompiledModel }.count
        trainableTypeCount = readiness.filter(\.isReadyForModelTraining).count
        completedTypeCount = readiness.filter(\.isCompleteForTrainingDeployment).count

        nextTargets = Array(readiness
            .filter { !$0.isCompleteForTrainingDeployment }
            .sorted { lhs, rhs in
                if lhs.neededModelTrainingSamples != rhs.neededModelTrainingSamples {
                    return lhs.neededModelTrainingSamples > rhs.neededModelTrainingSamples
                }
                if lhs.neededUserCorrectedSamples != rhs.neededUserCorrectedSamples {
                    return lhs.neededUserCorrectedSamples > rhs.neededUserCorrectedSamples
                }
                if lhs.missingKeypointTypes.count != rhs.missingKeypointTypes.count {
                    return lhs.missingKeypointTypes.count > rhs.missingKeypointTypes.count
                }
                if lhs.modelDeploymentStatus.hasDocumentsCompiledModel != rhs.modelDeploymentStatus.hasDocumentsCompiledModel {
                    return !lhs.modelDeploymentStatus.hasDocumentsCompiledModel
                }
                return lhs.clothingType.displayName < rhs.clothingType.displayName
            }
            .prefix(targetLimit))
    }

    var isComplete: Bool {
        completedTypeCount == ClothingType.allCases.count
            && totalNeededModelTrainingSamples == 0
            && totalNeededUserCorrectedSamples == 0
            && missingCompiledModelCount == 0
    }

    var collectionProgress: Double {
        let required = totalRequiredModelTrainingSamples + totalRequiredUserCorrectedSamples
        guard required > 0 else {
            return 1
        }

        let satisfied = totalSatisfiedModelTrainingSamples + totalSatisfiedUserCorrectedSamples
        return min(Double(satisfied) / Double(required), 1)
    }
}

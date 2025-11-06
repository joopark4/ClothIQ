//
//  CalibrationViewModel.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  교정 워크플로우를 관리하는 ViewModel입니다.
//  5단계 교정 프로세스를 진행하고 결과를 저장합니다.
//
//  Key Responsibilities:
//  - 5단계 워크플로우 관리
//  - 실측값 vs 측정값 비교
//  - 보정 계수 계산
//  - 교정 데이터 SwiftData 저장
//

import Foundation
import SwiftUI
import SwiftData
import Combine

/// 교정 워크플로우 단계
enum CalibrationStep: Int, CaseIterable {
    case selectSample = 0      // 1단계: 기준 샘플 선택
    case inputActualValue = 1   // 2단계: 실측값 입력
    case performMeasurement = 2 // 3단계: AR 측정 (10회 반복)
    case compareResults = 3     // 4단계: 결과 비교
    case saveCalibration = 4    // 5단계: 교정 저장

    var title: String {
        switch self {
        case .selectSample: return "1. 기준 샘플 선택"
        case .inputActualValue: return "2. 실측값 입력"
        case .performMeasurement: return "3. AR 측정"
        case .compareResults: return "4. 결과 비교"
        case .saveCalibration: return "5. 교정 저장"
        }
    }

    var description: String {
        switch self {
        case .selectSample:
            return "교정할 의류 타입과 측정 항목을 선택합니다."
        case .inputActualValue:
            return "자로 직접 측정한 정확한 값을 입력합니다."
        case .performMeasurement:
            return "AR 측정을 여러 번 반복하여 평균값을 계산합니다. (10회 권장)"
        case .compareResults:
            return "실측값과 측정값을 비교하여 오차율과 보정 계수를 확인합니다."
        case .saveCalibration:
            return "교정 데이터를 프로파일로 저장합니다."
        }
    }
}

/// 교정 워크플로우 ViewModel
@MainActor
final class CalibrationViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 현재 단계
    @Published var currentStep: CalibrationStep = .selectSample

    /// 선택된 의류 타입
    @Published var selectedClothingType: ClothingType?

    /// 선택된 측정 타입
    @Published var selectedMeasurementType: MeasurementType?

    /// 실측값 (cm)
    @Published var actualValue: String = ""

    /// 측정값 목록 (cm)
    @Published var measurements: [Double] = []

    /// 프로파일 이름
    @Published var profileName: String = ""

    /// 로딩 상태
    @Published var isLoading: Bool = false

    /// 에러 메시지
    @Published var errorMessage: String?

    // MARK: - Computed Properties

    /// 평균 측정값
    var averageMeasured: Double {
        guard !measurements.isEmpty else { return 0.0 }
        return measurements.reduce(0, +) / Double(measurements.count)
    }

    /// 표준편차
    var stdDeviation: Double? {
        guard measurements.count > 1 else { return nil }

        let avg = averageMeasured
        let variance = measurements
            .map { pow($0 - avg, 2) }
            .reduce(0, +) / Double(measurements.count - 1)
        return sqrt(variance)
    }

    /// 실측값 (Double)
    var actualValueDouble: Double? {
        Double(actualValue)
    }

    /// 오차값 (cm)
    var errorValue: Double? {
        guard let actual = actualValueDouble else { return nil }
        return abs(actual - averageMeasured)
    }

    /// 오차율 (%)
    var errorPercent: Double? {
        guard let actual = actualValueDouble, actual > 0 else { return nil }
        return (errorValue ?? 0) / actual * 100.0
    }

    /// 보정 계수
    var correctionFactor: Double? {
        guard let actual = actualValueDouble, averageMeasured > 0 else { return nil }
        return actual / averageMeasured
    }

    /// 다음 단계 가능 여부
    var canProceedToNext: Bool {
        switch currentStep {
        case .selectSample:
            return selectedClothingType != nil && selectedMeasurementType != nil
        case .inputActualValue:
            return actualValueDouble != nil && (actualValueDouble ?? 0) > 0
        case .performMeasurement:
            return !measurements.isEmpty
        case .compareResults:
            return true
        case .saveCalibration:
            return !profileName.isEmpty
        }
    }

    // MARK: - Dependencies

    private let modelContext: ModelContext

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Actions

    /// 다음 단계로 이동
    func proceedToNext() {
        guard canProceedToNext else { return }

        if let nextStep = CalibrationStep(rawValue: currentStep.rawValue + 1) {
            withAnimation {
                currentStep = nextStep
            }

            // 자동 프로파일 이름 생성 (5단계 진입 시)
            if currentStep == .saveCalibration, profileName.isEmpty {
                generateProfileName()
            }
        }
    }

    /// 이전 단계로 이동
    func goBack() {
        if let previousStep = CalibrationStep(rawValue: currentStep.rawValue - 1) {
            withAnimation {
                currentStep = previousStep
            }
        }
    }

    /// 측정값 추가
    func addMeasurement(_ value: Double) {
        measurements.append(value)
    }

    /// 측정값 삭제
    func removeMeasurement(at index: Int) {
        guard measurements.indices.contains(index) else { return }
        measurements.remove(at: index)
    }

    /// 측정값 초기화
    func clearMeasurements() {
        measurements.removeAll()
    }

    /// 마지막 측정값 삭제
    func removeLastMeasurement() {
        if !measurements.isEmpty {
            measurements.removeLast()
        }
    }

    /// 교정 저장
    func saveCalibration() async throws {
        guard let clothingType = selectedClothingType,
              let measurementType = selectedMeasurementType,
              let actual = actualValueDouble,
              correctionFactor != nil else {
            throw NSError(domain: "CalibrationError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "필수 데이터가 누락되었습니다."
            ])
        }

        isLoading = true
        defer { isLoading = false }

        // CalibrationProfile 생성 또는 기존 프로파일 업데이트
        let profile: CalibrationProfile

        // 같은 이름의 프로파일 검색
        let descriptor = FetchDescriptor<CalibrationProfile>(
            predicate: #Predicate { $0.name == profileName }
        )

        if let existingProfile = try? modelContext.fetch(descriptor).first {
            profile = existingProfile
            profile.updatedAt = Date()
        } else {
            // 새 프로파일 생성
            profile = CalibrationProfile(name: profileName)
            modelContext.insert(profile)
        }

        // CalibrationFactor 생성
        let calibrationFactor = CalibrationFactor(
            clothingType: clothingType.rawValue,
            measurementType: measurementType.rawValue,
            actualValue: actual,
            measuredValue: averageMeasured,
            sampleCount: measurements.count,
            averageMeasured: averageMeasured,
            stdDeviation: stdDeviation
        )

        // 측정값 통계 업데이트
        calibrationFactor.updateStatistics(with: measurements)

        // 프로파일에 추가
        profile.upsertCalibrationFactor(calibrationFactor)

        // 저장
        try modelContext.save()

        // MeasurementSettings에 적용
        MeasurementSettings.shared.applyProfile(profile)
        MeasurementSettings.shared.useCalibration = true
    }

    /// 워크플로우 초기화
    func reset() {
        currentStep = .selectSample
        selectedClothingType = nil
        selectedMeasurementType = nil
        actualValue = ""
        measurements.removeAll()
        profileName = ""
        errorMessage = nil
    }

    // MARK: - Private Helpers

    /// 프로파일 이름 자동 생성
    private func generateProfileName() {
        guard let clothingType = selectedClothingType,
              let measurementType = selectedMeasurementType else {
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        profileName = "\(clothingType.displayName) \(measurementType.displayName) - \(dateString)"
    }
}

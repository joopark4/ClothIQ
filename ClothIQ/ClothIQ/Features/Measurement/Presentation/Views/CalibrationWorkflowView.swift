//
//  CalibrationWorkflowView.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  교정 워크플로우 UI입니다.
//  5단계 교정 프로세스를 안내하고 결과를 저장합니다.
//
//  Key Responsibilities:
//  - 5단계 워크플로우 UI 제공
//  - 실측값 입력 폼
//  - AR 측정 통합
//  - 결과 비교 화면
//  - 교정 데이터 저장
//

import SwiftUI
import SwiftData

/// 교정 워크플로우 뷰
struct CalibrationWorkflowView: View {

    // MARK: - Properties

    @StateObject private var viewModel: CalibrationViewModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: CalibrationViewModel(modelContext: modelContext))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // 배경
                Color(.systemGroupedBackground)
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    // 진행 상태 표시
                    progressIndicator

                    // 단계별 콘텐츠
                    ScrollView {
                        VStack(spacing: 20) {
                            stepContent
                        }
                        .padding()
                    }

                    // 하단 버튼
                    bottomButtons
                }
            }
            .navigationTitle("측정 시스템 교정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
            .alert("오류", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("확인") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Progress Indicator

    @ViewBuilder
    private var progressIndicator: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(CalibrationStep.allCases, id: \.self) { step in
                    Rectangle()
                        .fill(step.rawValue <= viewModel.currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal)

            Text(viewModel.currentStep.title)
                .font(.headline)
                .padding(.horizontal)

            Text(viewModel.currentStep.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.currentStep {
        case .selectSample:
            selectSampleStep
        case .inputActualValue:
            inputActualValueStep
        case .performMeasurement:
            performMeasurementStep
        case .compareResults:
            compareResultsStep
        case .saveCalibration:
            saveCalibrationStep
        }
    }

    // MARK: - Step 1: Select Sample

    private var selectSampleStep: some View {
        VStack(spacing: 16) {
            // 의류 타입 선택
            VStack(alignment: .leading, spacing: 8) {
                Text("의류 타입")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ClothingType.allCases, id: \.self) { type in
                            Button(action: {
                                viewModel.selectedClothingType = type
                                viewModel.selectedMeasurementType = nil
                            }) {
                                Text(type.displayName)
                                    .font(.subheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        viewModel.selectedClothingType == type ?
                                        Color.blue : Color(.systemGray5)
                                    )
                                    .foregroundColor(
                                        viewModel.selectedClothingType == type ?
                                        .white : .primary
                                    )
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // 측정 항목 선택
            if let clothingType = viewModel.selectedClothingType {
                VStack(alignment: .leading, spacing: 8) {
                    Text("측정 항목")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(spacing: 8) {
                        ForEach(clothingType.requiredMeasurements, id: \.self) { measurement in
                            Button(action: {
                                viewModel.selectedMeasurementType = measurement
                            }) {
                                HStack {
                                    Text(measurement.displayName)
                                    Spacer()
                                    if viewModel.selectedMeasurementType == measurement {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Step 2: Input Actual Value

    private var inputActualValueStep: some View {
        VStack(spacing: 16) {
            if let measurementType = viewModel.selectedMeasurementType {
                VStack(alignment: .leading, spacing: 8) {
                    Text("측정 가이드")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(measurementType.measurementGuide)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("실측값 입력")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack {
                    TextField("예: 45.5", text: $viewModel.actualValue)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)

                    Text("cm")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                Text("자나 줄자로 직접 측정한 정확한 값을 입력하세요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Step 3: Perform Measurement

    private var performMeasurementStep: some View {
        VStack(spacing: 16) {
            // 측정 횟수 표시
            VStack(spacing: 8) {
                Text("측정 횟수: \(viewModel.measurements.count)회")
                    .font(.title2)
                    .fontWeight(.bold)

                if let avg = viewModel.measurements.isEmpty ? nil : viewModel.averageMeasured {
                    Text(String(format: "평균: %.1f cm", avg))
                        .font(.headline)
                        .foregroundColor(.blue)
                }

                if let std = viewModel.stdDeviation {
                    Text(String(format: "표준편차: %.2f cm", std))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // 측정 목록
            if !viewModel.measurements.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("측정값 목록")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ForEach(Array(viewModel.measurements.enumerated()), id: \.offset) { index, value in
                        HStack {
                            Text("\(index + 1).")
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f cm", value))
                                .fontWeight(.medium)
                            Spacer()
                            Button(action: {
                                viewModel.removeMeasurement(at: index)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }

            // 측정 버튼 (실제 구현 시 AR 측정 연동 필요)
            Text("실제 구현 시 AR 측정 화면과 연동됩니다")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
        }
    }

    // MARK: - Step 4: Compare Results

    private var compareResultsStep: some View {
        VStack(spacing: 16) {
            // 결과 비교
            if let actual = viewModel.actualValueDouble {
                VStack(spacing: 12) {
                    resultRow(
                        label: "실측값",
                        value: String(format: "%.1f cm", actual),
                        color: .green
                    )

                    resultRow(
                        label: "평균 측정값",
                        value: String(format: "%.1f cm", viewModel.averageMeasured),
                        color: .blue
                    )

                    if let error = viewModel.errorValue {
                        resultRow(
                            label: "오차",
                            value: String(format: "%.1f cm", error),
                            color: .orange
                        )
                    }

                    if let errorPercent = viewModel.errorPercent {
                        resultRow(
                            label: "오차율",
                            value: String(format: "%.2f%%", errorPercent),
                            color: errorColor(errorPercent)
                        )
                    }

                    if let factor = viewModel.correctionFactor {
                        resultRow(
                            label: "보정 계수",
                            value: String(format: "%.4f", factor),
                            color: .purple
                        )
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }

            // 측정 통계
            if let std = viewModel.stdDeviation {
                VStack(alignment: .leading, spacing: 8) {
                    Text("측정 통계")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack {
                        Text("샘플 수:")
                        Spacer()
                        Text("\(viewModel.measurements.count)회")
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("표준편차:")
                        Spacer()
                        Text(String(format: "%.2f cm", std))
                            .fontWeight(.medium)
                    }

                    if let cv = (std / viewModel.averageMeasured * 100) as Double? {
                        HStack {
                            Text("변동 계수:")
                            Spacer()
                            Text(String(format: "%.2f%%", cv))
                                .fontWeight(.medium)
                                .foregroundColor(cv < 5 ? .green : .orange)
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Step 5: Save Calibration

    private var saveCalibrationStep: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("프로파일 이름")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                TextField("예: 반바지 기준", text: $viewModel.profileName)
                    .textFieldStyle(.roundedBorder)

                Text("이 교정 데이터를 식별할 수 있는 이름을 입력하세요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)

            // 요약
            VStack(alignment: .leading, spacing: 8) {
                Text("교정 요약")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let clothingType = viewModel.selectedClothingType,
                   let measurementType = viewModel.selectedMeasurementType {
                    summaryRow(label: "의류 타입", value: clothingType.displayName)
                    summaryRow(label: "측정 항목", value: measurementType.displayName)
                }

                if let actual = viewModel.actualValueDouble {
                    summaryRow(label: "실측값", value: String(format: "%.1f cm", actual))
                }

                summaryRow(label: "평균 측정값", value: String(format: "%.1f cm", viewModel.averageMeasured))
                summaryRow(label: "측정 횟수", value: "\(viewModel.measurements.count)회")

                if let factor = viewModel.correctionFactor {
                    summaryRow(label: "보정 계수", value: String(format: "%.4f", factor))
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Bottom Buttons

    @ViewBuilder
    private var bottomButtons: some View {
        VStack(spacing: 12) {
            // 다음/저장 버튼
            Button(action: {
                if viewModel.currentStep == .saveCalibration {
                    Task {
                        do {
                            try await viewModel.saveCalibration()
                            dismiss()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                } else {
                    viewModel.proceedToNext()
                }
            }) {
                Text(viewModel.currentStep == .saveCalibration ? "저장" : "다음")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.canProceedToNext ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!viewModel.canProceedToNext)

            // 이전 버튼
            if viewModel.currentStep.rawValue > 0 {
                Button(action: {
                    viewModel.goBack()
                }) {
                    Text("이전")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Helper Views

    private func resultRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.headline)
                .foregroundColor(color)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private func errorColor(_ percent: Double) -> Color {
        switch percent {
        case 0..<5: return .green
        case 5..<10: return .yellow
        default: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    let container = try! ModelContainer(for: CalibrationProfile.self, CalibrationFactor.self)
    return CalibrationWorkflowView(modelContext: container.mainContext)
}

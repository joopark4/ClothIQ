//
//  BatchAutoMeasurementView.swift
//  ClothIQ
//
//  Created on 2026-02-19
//
//  Description:
//  상세화면에서 일괄 자동 측정을 수행하는 시트 뷰입니다.
//  Phase별로 진행 상태, 타입 확인, 결과 리스트를 표시합니다.
//
//  Key Responsibilities:
//  - 진행 상태 표시 (윤곽선 감지, 타입 확인, 측정)
//  - 타입 불일치 시 사용자 확인 UI
//  - 측정 결과 리스트 (체크박스 + 측정값 + 신뢰도 + 기존값 비교)
//  - 저장 기능 (전체/선택)
//

import SwiftUI
import SwiftData

/// 일괄 자동 측정 시트 뷰
struct BatchAutoMeasurementView: View {
    @StateObject private var viewModel: BatchAutoMeasurementViewModel
    @Environment(\.dismiss) private var dismiss

    init(item: ClothingItemModel, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: BatchAutoMeasurementViewModel(
            item: item,
            modelContext: modelContext
        ))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .idle, .detectingContour, .classifyingType, .measuring:
                    progressView
                case .typeConfirmation:
                    typeConfirmationView
                case .results:
                    resultsView
                case .error(let message):
                    errorView(message: message)
                }
            }
            .navigationTitle("자동 측정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await viewModel.startBatchMeasurement()
        }
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text(viewModel.progressMessage)
                .font(.headline)
                .foregroundColor(.secondary)

            // 단계 표시
            HStack(spacing: 16) {
                stepIndicator(step: 1, label: "윤곽선", isActive: viewModel.phase == .detectingContour, isDone: viewModel.phase != .idle && viewModel.phase != .detectingContour)
                stepConnector(isDone: viewModel.phase != .idle && viewModel.phase != .detectingContour)
                stepIndicator(step: 2, label: "타입 확인", isActive: viewModel.phase == .classifyingType, isDone: viewModel.phase == .measuring || viewModel.phase == .results)
                stepConnector(isDone: viewModel.phase == .measuring || viewModel.phase == .results)
                stepIndicator(step: 3, label: "측정", isActive: viewModel.phase == .measuring, isDone: viewModel.phase == .results)
            }
            .padding(.top, 16)

            Spacer()
        }
        .padding()
    }

    private func stepIndicator(step: Int, label: String, isActive: Bool, isDone: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.green : isActive ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)

                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                } else {
                    Text("\(step)")
                        .font(.caption.bold())
                        .foregroundColor(isActive ? .white : .secondary)
                }
            }

            Text(label)
                .font(.caption2)
                .foregroundColor(isActive ? .primary : .secondary)
        }
    }

    private func stepConnector(isDone: Bool) -> some View {
        Rectangle()
            .fill(isDone ? Color.green : Color.gray.opacity(0.3))
            .frame(width: 30, height: 2)
    }

    // MARK: - Type Confirmation View

    private var typeConfirmationView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("의류 타입이 다릅니다")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 16) {
                typeComparisonRow(
                    label: "현재 타입",
                    type: viewModel.item.clothingType,
                    isHighlighted: false
                )

                Image(systemName: "arrow.down")
                    .foregroundColor(.secondary)

                typeComparisonRow(
                    label: "감지된 타입",
                    type: viewModel.detectedType,
                    confidence: viewModel.detectedTypeConfidence,
                    isHighlighted: true
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )

            Text("어떤 타입으로 측정할까요?")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                if let detectedType = viewModel.detectedType {
                    Button {
                        Task { await viewModel.confirmType(detectedType) }
                    } label: {
                        Label("감지된 타입으로 측정 (\(detectedType.displayName))", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }

                Button {
                    Task { await viewModel.keepCurrentType() }
                } label: {
                    Label("현재 타입 유지 (\(viewModel.item.clothingType?.displayName ?? "알 수 없음"))", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }

            Spacer()
        }
        .padding()
    }

    private func typeComparisonRow(label: String, type: ClothingType?, confidence: Float? = nil, isHighlighted: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(type?.displayName ?? "알 수 없음")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(isHighlighted ? .orange : .primary)
            }

            Spacer()

            if let confidence = confidence {
                Text("\(String(format: "%.0f", confidence * 100))%")
                    .font(.headline)
                    .foregroundColor(confidence > 0.7 ? .green : .orange)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Results View

    private var resultsView: some View {
        VStack(spacing: 0) {
            // 헤더
            resultsHeader
                .padding()

            Divider()

            // 결과 리스트
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(sortedResults, id: \.key) { type, result in
                        resultRow(type: type, result: result)
                    }
                }
                .padding()
            }

            Divider()

            // 저장 버튼
            saveButtons
                .padding()
        }
    }

    private var resultsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("측정 결과")
                    .font(.headline)

                Text("\(viewModel.measurementResults.count)개 항목 측정 완료")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 전체 선택/해제
            Button {
                if viewModel.selectedResults.count == viewModel.measurementResults.count {
                    viewModel.selectedResults.removeAll()
                } else {
                    viewModel.selectedResults = Set(viewModel.measurementResults.keys)
                }
            } label: {
                Text(viewModel.selectedResults.count == viewModel.measurementResults.count ? "전체 해제" : "전체 선택")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
    }

    private var sortedResults: [(key: MeasurementType, value: AutoMeasurementResult)] {
        viewModel.measurementResults
            .sorted { $0.key.displayName < $1.key.displayName }
    }

    private func resultRow(type: MeasurementType, result: AutoMeasurementResult) -> some View {
        let isSelected = viewModel.selectedResults.contains(type)
        let existingValue = viewModel.existingValue(for: type)

        return Button {
            if isSelected {
                viewModel.selectedResults.remove(type)
            } else {
                viewModel.selectedResults.insert(type)
            }
        } label: {
            HStack(spacing: 12) {
                // 체크박스
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .gray)

                // 측정 정보
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        // 측정값
                        Text(String(format: "%.1f cm", result.distance))
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.blue)

                        // 신뢰도
                        confidenceBadge(confidence: result.confidence)
                    }

                    // 기존값 비교
                    if let existing = existingValue {
                        let diff = result.distance - existing
                        HStack(spacing: 4) {
                            Text("기존: \(String(format: "%.1f", existing))cm")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("(\(diff >= 0 ? "+" : "")\(String(format: "%.1f", diff)))")
                                .font(.caption)
                                .foregroundColor(abs(diff) < 2 ? .green : .orange)
                        }
                    }
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.05) : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
    }

    private func confidenceBadge(confidence: Double) -> some View {
        let color: Color = confidence >= 0.9 ? .green :
                           confidence >= 0.7 ? .blue :
                           confidence >= 0.5 ? .orange : .red

        return HStack(spacing: 2) {
            Image(systemName: "checkmark.shield.fill")
                .font(.caption2)
            Text("\(Int(confidence * 100))%")
                .font(.caption2)
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }

    private var saveButtons: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.saveAllMeasurements()
                dismiss()
            } label: {
                Label("모두 저장 (\(viewModel.measurementResults.count)개)", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            if viewModel.selectedResults.count != viewModel.measurementResults.count {
                Button {
                    viewModel.saveSelectedMeasurements()
                    dismiss()
                } label: {
                    Label("선택 저장 (\(viewModel.selectedResults.count)개)", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("측정 실패")
                .font(.title2)
                .fontWeight(.semibold)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                Task { await viewModel.startBatchMeasurement() }
            } label: {
                Label("다시 시도", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}

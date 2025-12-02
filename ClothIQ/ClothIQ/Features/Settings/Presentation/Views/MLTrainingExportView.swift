//
//  MLTrainingExportView.swift
//  ClothIQ
//
//  ML 학습 데이터를 내보내기 위한 뷰
//

import SwiftUI
import UniformTypeIdentifiers

struct MLTrainingExportView: View {
    @StateObject private var collector = MLTrainingDataCollector.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: ExportFormat = .tensorflow
    @State private var includeImages: Bool = true
    @State private var compressOutput: Bool = true
    @State private var onlyUserCorrected: Bool = false
    @State private var minConfidence: Float = 0.5

    @State private var isExporting: Bool = false
    @State private var exportProgress: Double = 0.0
    @State private var exportResult: ExportResult?
    @State private var showingShareSheet: Bool = false
    @State private var exportedFileURL: URL?

    enum ExportFormat: String, CaseIterable {
        case tensorflow = "TensorFlow/Keras"
        case createml = "CreateML"
        case coreml = "Core ML JSON"
        case csv = "CSV (메타데이터만)"

        var fileExtension: String {
            switch self {
            case .tensorflow, .createml, .coreml: return "json"
            case .csv: return "csv"
            }
        }

        var icon: String {
            switch self {
            case .tensorflow: return "brain"
            case .createml: return "cube.box.fill"
            case .coreml: return "square.stack.3d.up.fill"
            case .csv: return "tablecells"
            }
        }
    }

    struct ExportResult {
        let success: Bool
        let message: String
        let fileSize: String
        let sampleCount: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - 내보내기 형식
                    formatSection

                    // MARK: - 내보내기 옵션
                    optionsSection

                    // MARK: - 데이터 필터
                    filterSection

                    // MARK: - 미리보기
                    previewSection

                    // MARK: - 내보내기 버튼
                    exportButton

                    // MARK: - 결과
                    if let result = exportResult {
                        resultSection(result)
                    }
                }
                .padding()
            }
            .navigationTitle("데이터 내보내기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    // MARK: - Sections

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("내보내기 형식")
                .font(.headline)

            ForEach(ExportFormat.allCases, id: \.self) { format in
                HStack {
                    Image(systemName: format.icon)
                        .foregroundColor(.blue)
                        .frame(width: 30)

                    Text(format.rawValue)
                        .font(.subheadline)

                    Spacer()

                    if selectedFormat == format {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.gray.opacity(0.5))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedFormat = format
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("내보내기 옵션")
                .font(.headline)

            Toggle(isOn: $includeImages) {
                HStack {
                    Image(systemName: "photo.fill")
                        .foregroundColor(.green)
                    Text("이미지 포함")
                        .font(.subheadline)
                }
            }
            .disabled(selectedFormat == .csv)

            Toggle(isOn: $compressOutput) {
                HStack {
                    Image(systemName: "doc.zipper")
                        .foregroundColor(.purple)
                    Text("압축 파일로 내보내기")
                        .font(.subheadline)
                }
            }

            Toggle(isOn: $onlyUserCorrected) {
                HStack {
                    Image(systemName: "hand.draw.fill")
                        .foregroundColor(.orange)
                    Text("사용자 수정 데이터만")
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("데이터 필터")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("최소 신뢰도")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.0f%%", minConfidence * 100))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.blue)
                }

                Slider(value: $minConfidence, in: 0...1, step: 0.1)
                    .accentColor(.blue)
            }

            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text("신뢰도가 \(Int(minConfidence * 100))% 이상인 데이터만 내보냅니다")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("내보내기 미리보기")
                .font(.headline)

            let filteredCount = getFilteredSampleCount()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("포함될 샘플")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(filteredCount)개")
                        .font(.title2.bold())
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("예상 크기")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(estimateFileSize())
                        .font(.title2.bold())
                }
            }

            if filteredCount == 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("필터 조건에 맞는 데이터가 없습니다")
                        .font(.caption)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var exportButton: some View {
        Button(action: performExport) {
            if isExporting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("내보내는 중...")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            } else {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("내보내기")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(getFilteredSampleCount() > 0 ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
        }
        .disabled(isExporting || getFilteredSampleCount() == 0)
    }

    private func resultSection(_ result: ExportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.success ? .green : .red)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(result.success ? "내보내기 성공" : "내보내기 실패")
                        .font(.headline)
                    Text(result.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            if result.success {
                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text("파일 크기")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(result.fileSize)
                            .font(.subheadline.bold())
                    }

                    VStack(alignment: .leading) {
                        Text("샘플 수")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(result.sampleCount)개")
                            .font(.subheadline.bold())
                    }

                    Spacer()

                    Button(action: {
                        showingShareSheet = true
                    }) {
                        Label("공유", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Helper Methods

    private func getFilteredSampleCount() -> Int {
        var count = collector.totalSamples

        if onlyUserCorrected {
            count = collector.userCorrectedSamples
        }

        // 신뢰도 필터 적용 (실제 구현에서는 collector에서 필터링된 수를 가져와야 함)
        count = Int(Double(count) * (1.0 - Double(minConfidence)))

        return max(0, count)
    }

    private func estimateFileSize() -> String {
        let sampleCount = getFilteredSampleCount()
        var sizeInBytes = sampleCount * 1024 // 각 샘플당 약 1KB 메타데이터

        if includeImages {
            sizeInBytes += sampleCount * 512 * 1024 // 각 이미지당 약 512KB
        }

        if compressOutput {
            sizeInBytes = sizeInBytes / 3 // 압축 시 약 1/3로 감소
        }

        return ByteCountFormatter.string(fromByteCount: Int64(sizeInBytes), countStyle: .file)
    }

    private func performExport() {
        isExporting = true
        exportProgress = 0.0

        Task {
            do {
                // 실제 내보내기 로직
                let url = try await exportData()

                await MainActor.run {
                    exportedFileURL = url
                    exportResult = ExportResult(
                        success: true,
                        message: "데이터가 성공적으로 내보내졌습니다",
                        fileSize: getFileSize(at: url),
                        sampleCount: getFilteredSampleCount()
                    )
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportResult = ExportResult(
                        success: false,
                        message: error.localizedDescription,
                        fileSize: "0 KB",
                        sampleCount: 0
                    )
                    isExporting = false
                }
            }
        }
    }

    private func exportData() async throws -> URL {
        // 임시 구현 - 실제로는 선택된 형식에 따라 다른 내보내기 수행
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "ClothIQ_TrainingData_\(Date().timeIntervalSince1970).\(selectedFormat.fileExtension)"
        let fileURL = documentsPath.appendingPathComponent(fileName)

        // 데이터 내보내기 시뮬레이션
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2초 대기

        // 더미 데이터 생성
        let dummyData = "Training data export".data(using: .utf8)!
        try dummyData.write(to: fileURL)

        return fileURL
    }

    private func getFileSize(at url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    MLTrainingExportView()
}
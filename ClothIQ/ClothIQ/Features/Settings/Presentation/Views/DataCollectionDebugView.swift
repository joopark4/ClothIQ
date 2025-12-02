//
//  DataCollectionDebugView.swift
//  ClothIQ
//
//  ML 학습 데이터 수집 디버그 뷰
//  실제 수집된 데이터를 확인하고 테스트할 수 있습니다.
//

import SwiftUI
import SwiftData
import Combine

struct DataCollectionDebugView: View {
    @StateObject private var collector = MLTrainingDataCollector.shared
    @State private var showingRawData = false
    @State private var selectedSampleIndex: Int?
    @State private var lastCollectedSample: String = "아직 수집된 데이터 없음"
    @State private var isMonitoring = false

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - 실시간 모니터링
                    monitoringCard

                    // MARK: - 수집 상태
                    statusCard

                    // MARK: - 최근 수집 데이터
                    recentDataCard

                    // MARK: - 데이터 경로
                    pathInfoCard

                    // MARK: - 테스트 액션
                    testActionsCard
                }
                .padding()
            }
            .navigationTitle("데이터 수집 디버그")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(timer) { _ in
                if isMonitoring {
                    refreshData()
                }
            }
        }
    }

    // MARK: - Components

    private var monitoringCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("실시간 모니터링", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $isMonitoring)
                    .labelsHidden()
            }

            if isMonitoring {
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.green, lineWidth: 1)
                                .scaleEffect(2)
                                .opacity(0)
                                .animation(
                                    Animation.easeOut(duration: 1)
                                        .repeatForever(autoreverses: false),
                                    value: isMonitoring
                                )
                        )
                    Text("모니터링 중...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("수집 상태", systemImage: "chart.bar.fill")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    Text("수집 활성화:")
                        .foregroundColor(.secondary)
                    HStack {
                        Image(systemName: collector.isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(collector.isEnabled ? .green : .red)
                        Text(collector.isEnabled ? "활성" : "비활성")
                    }
                }

                GridRow {
                    Text("총 샘플:")
                        .foregroundColor(.secondary)
                    Text("\(collector.totalSamples)개")
                        .fontWeight(.semibold)
                }

                GridRow {
                    Text("사용자 수정:")
                        .foregroundColor(.secondary)
                    Text("\(collector.userCorrectedSamples)개")
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }

                GridRow {
                    Text("평균 신뢰도:")
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f%%", collector.averageConfidence * 100))
                        .fontWeight(.semibold)
                        .foregroundColor(confidenceColor(collector.averageConfidence))
                }

                GridRow {
                    Text("사용자 수정만:")
                        .foregroundColor(.secondary)
                    HStack {
                        Image(systemName: collector.collectOnlyUserCorrected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(collector.collectOnlyUserCorrected ? .orange : .gray)
                        Text(collector.collectOnlyUserCorrected ? "예" : "아니오")
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var recentDataCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("최근 수집 데이터", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Button("새로고침") {
                    refreshData()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }

            if let recentSamples = collector.getRecentSamples(limit: 3) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(recentSamples.enumerated()), id: \.offset) { index, sample in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("#\(index + 1)")
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)

                                Text(sample.clothingType)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Spacer()

                                if sample.isUserCorrected {
                                    Label("수정됨", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }

                            Text(sample.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            } else {
                Text("수집된 데이터 없음")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var pathInfoCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("데이터 저장 경로", systemImage: "folder.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Documents/MLTrainingData/")
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(6)

                HStack(spacing: 12) {
                    Label("labels.json", systemImage: "doc.text")
                        .font(.caption)

                    Label("images/", systemImage: "folder")
                        .font(.caption)

                    Label("createml_data.json", systemImage: "doc.badge.gearshape")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Button(action: checkFileSystem) {
                Label("파일 시스템 확인", systemImage: "magnifyingglass")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var testActionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("테스트 액션", systemImage: "wrench.and.screwdriver")
                .font(.headline)

            VStack(spacing: 12) {
                Button(action: generateTestData) {
                    Label("테스트 데이터 생성", systemImage: "plus.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(action: validateDataIntegrity) {
                    Label("데이터 무결성 확인", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: exportDebugReport) {
                    Label("디버그 리포트 내보내기", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: clearAllTestData) {
                    Label("테스트 데이터 삭제", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    // MARK: - Helper Methods

    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence >= 0.8 {
            return .green
        } else if confidence >= 0.6 {
            return .orange
        } else {
            return .red
        }
    }

    private func refreshData() {
        // 데이터 새로고침
        // collector의 @Published 속성들이 자동으로 UI를 업데이트합니다
    }

    private func checkFileSystem() {
        // 파일 시스템 확인 로직
        print("📁 [Debug] 파일 시스템 확인 중...")
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let trainingDataPath = documentsPath.appendingPathComponent("MLTrainingData")

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: trainingDataPath, includingPropertiesForKeys: nil)
            print("📁 [Debug] MLTrainingData 디렉토리 내용:")
            for item in contents {
                let attributes = try FileManager.default.attributesOfItem(atPath: item.path)
                let size = attributes[.size] as? Int64 ?? 0
                print("  - \(item.lastPathComponent): \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
            }
        } catch {
            print("❌ [Debug] 파일 시스템 확인 실패: \(error)")
        }
    }

    private func generateTestData() {
        print("🧪 [Debug] 테스트 데이터 생성 중...")
        // 테스트 데이터 생성 로직
    }

    private func validateDataIntegrity() {
        print("🔍 [Debug] 데이터 무결성 확인 중...")
        // 데이터 무결성 확인 로직
    }

    private func exportDebugReport() {
        print("📤 [Debug] 디버그 리포트 생성 중...")
        // 디버그 리포트 생성 로직
    }

    private func clearAllTestData() {
        print("🗑 [Debug] 테스트 데이터 삭제 중...")
        collector.clearAllData()
    }
}

#Preview {
    DataCollectionDebugView()
}
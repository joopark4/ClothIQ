//
//  MLTrainingSettingsView.swift
//  ClothIQ
//
//  ML 학습 데이터 수집 설정을 관리하는 뷰
//

import SwiftUI
import SwiftData

struct MLTrainingSettingsView: View {
    @StateObject private var collector = MLTrainingDataCollector.shared
    @State private var showingExportView = false
    @State private var showingStatisticsView = false
    @State private var showingClearConfirmation = false
    @State private var exportProgress: Double = 0.0
    @State private var isExporting = false
    @State private var exportMessage: String = ""
    @State private var modelStatus = VisionMLModelLoader.shared.currentModelStatus()
    @State private var deploymentStatus = MLTrainingDataCollector.shared.getModelDeploymentStatus()

    var body: some View {
        List {
            // MARK: - 데이터 수집 설정
            Section {
                Toggle(isOn: $collector.isEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("학습 데이터 수집")
                        Text("측정 시 키포인트 데이터를 자동으로 수집합니다")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $collector.collectOnlyUserCorrected) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("사용자 수정 데이터만 수집")
                        Text("사용자가 직접 수정한 고품질 데이터만 수집합니다")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(!collector.isEnabled)
            } header: {
                Text("데이터 수집 설정")
            }

            // MARK: - 데이터 통계
            Section {
                HStack {
                    Label("수집된 샘플", systemImage: "chart.bar.fill")
                    Spacer()
                    Text("\(collector.totalSamples)개")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("사용자 수정 샘플", systemImage: "checkmark.circle.fill")
                    Spacer()
                    Text("\(collector.userCorrectedSamples)개")
                        .foregroundColor(.green)
                }

                HStack {
                    Label("저장 위치", systemImage: "folder.fill")
                    Spacer()
                    Text(collector.trainingDataDirectoryDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    showingStatisticsView = true
                }) {
                    HStack {
                        Label("상세 통계 보기", systemImage: "chart.line.uptrend.xyaxis")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("데이터 통계")
            }

            // MARK: - 수집 기준
            Section {
                HStack {
                    Label("타입별 원본", systemImage: "camera.fill")
                    Spacer()
                    Text("\(collector.minimumSamplesPerTypeForModelTraining)장")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("타입별 보정", systemImage: "hand.draw.fill")
                    Spacer()
                    Text("\(collector.minimumUserCorrectedSamplesPerTypeForModelTraining)장")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("학습 라벨", systemImage: "doc.text.fill")
                    Spacer()
                    Text(collector.labelsFileDescription)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("촬영 원본", systemImage: "photo.fill")
                    Spacer()
                    Text("Documents/clothing_images/*.jpg")
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("학습 수집 기준")
            }

            // MARK: - 데이터 관리
            Section {
                Button(action: {
                    showingExportView = true
                }) {
                    HStack {
                        Label("학습 데이터 내보내기", systemImage: "square.and.arrow.up")
                            .foregroundColor(.blue)
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(collector.totalSamples == 0 || isExporting)

                Button(action: {
                    exportCreateMLFormat()
                }) {
                    HStack {
                        Label("CreateML 형식으로 내보내기", systemImage: "doc.badge.gearshape")
                            .foregroundColor(.purple)
                        Spacer()
                    }
                }
                .disabled(collector.totalSamples == 0 || isExporting)

                Button(role: .destructive, action: {
                    showingClearConfirmation = true
                }) {
                    Label("모든 데이터 삭제", systemImage: "trash")
                        .foregroundColor(.red)
                }
                .disabled(collector.totalSamples == 0)
            } header: {
                Text("데이터 관리")
            } footer: {
                if !exportMessage.isEmpty {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundColor(exportMessage.contains("성공") ? .green : .orange)
                }
            }

            // MARK: - 모델 정보
            Section {
                HStack {
                    Label("모델 로드 상태", systemImage: "cube.box.fill")
                    Spacer()
                    Text(modelStatus.isLoaded ? "로드됨" : "미탑재")
                        .foregroundColor(modelStatus.isLoaded ? .green : .orange)
                }

                HStack {
                    Label("로드 경로", systemImage: "location.fill")
                    Spacer()
                    Text(modelStatus.sourceDescription)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Documents 배포", systemImage: "externaldrive.fill")
                    Spacer()
                    Text(deploymentStatus.hasDocumentsCompiledModel ? "있음" : "없음")
                        .foregroundColor(deploymentStatus.hasDocumentsCompiledModel ? .green : .secondary)
                }

                HStack {
                    Label("배포 경로", systemImage: "folder.badge.gearshape")
                    Spacer()
                    Text(collector.documentsModelDeploymentPathDescription)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.secondary)
                }

                Button(action: refreshModelStatus) {
                    HStack {
                        Label("모델 로드 상태 새로고침", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundColor(.blue)
                        Spacer()
                    }
                }

                #if DEBUG
                NavigationLink(destination: DataCollectionDebugView()) {
                    HStack {
                        Label("디버그 모드", systemImage: "ladybug")
                            .foregroundColor(.purple)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
                #endif
            } header: {
                Text("모델 정보")
            } footer: {
                Text(collector.trainingNotSupportedMessage)
                    .font(.caption)
            }
        }
        .navigationTitle("ML 학습 설정")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            refreshModelStatus()
        }
        .sheet(isPresented: $showingStatisticsView) {
            MLTrainingStatisticsView()
        }
        .sheet(isPresented: $showingExportView) {
            MLTrainingExportView()
        }
        .alert("데이터 삭제", isPresented: $showingClearConfirmation) {
            Button("취소", role: .cancel) { }
            Button("삭제", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("모든 학습 데이터를 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.")
        }
    }

    // MARK: - Helper Methods

    private func exportCreateMLFormat() {
        Task {
            isExporting = true
            exportMessage = "CreateML 형식으로 변환 중..."

            let success = await collector.exportForCreateMLAsync()
            await MainActor.run {
                if success {
                    exportMessage = "✅ CreateML 형식으로 내보내기 성공"
                } else {
                    exportMessage = "⚠️ 내보내기 실패"
                }
                isExporting = false
            }

            // 3초 후 메시지 삭제
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                exportMessage = ""
            }
        }
    }

    private func clearAllData() {
        collector.clearAllData()
        exportMessage = "모든 데이터가 삭제되었습니다"

        // 3초 후 메시지 삭제
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                exportMessage = ""
            }
        }
    }

    private func refreshModelStatus() {
        modelStatus = VisionMLModelLoader.shared.reloadCustomModel()
        deploymentStatus = collector.getModelDeploymentStatus()
        exportMessage = modelStatus.message

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                exportMessage = ""
            }
        }
    }
}

#Preview {
    NavigationStack {
        MLTrainingSettingsView()
    }
}

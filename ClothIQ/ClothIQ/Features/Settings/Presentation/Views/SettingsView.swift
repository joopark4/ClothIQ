//
//  SettingsView.swift
//  ClothIQ
//
//  앱 설정 메인 뷰
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingMLTrainingSettings = false
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - ML 학습 섹션
                Section {
                    NavigationLink(destination: MLTrainingSettingsView()) {
                        HStack {
                            Image(systemName: "brain")
                                .foregroundColor(.purple)
                                .frame(width: 30)
                            VStack(alignment: .leading) {
                                Text("ML 학습 설정")
                                Text("학습 데이터 수집 및 관리")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("기계 학습")
                }

                // MARK: - 측정 설정
                Section {
                    NavigationLink {
                        MeasurementSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "ruler")
                                .foregroundColor(.blue)
                                .frame(width: 30)
                            VStack(alignment: .leading) {
                                Text("측정 설정")
                                Text("측정 단위 및 정확도 설정")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    NavigationLink {
                        CalibrationSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "tuningfork")
                                .foregroundColor(.orange)
                                .frame(width: 30)
                            VStack(alignment: .leading) {
                                Text("교정 설정")
                                Text("측정 보정 계수 관리")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("측정")
                }

                // MARK: - 데이터 관리
                Section {
                    Button(action: exportData) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.green)
                                .frame(width: 30)
                            Text("데이터 내보내기")
                        }
                    }

                    Button(action: importData) {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.indigo)
                                .frame(width: 30)
                            Text("데이터 가져오기")
                        }
                    }

                    Button(role: .destructive, action: clearAllData) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .frame(width: 30)
                            Text("모든 데이터 삭제")
                        }
                    }
                } header: {
                    Text("데이터 관리")
                }

                // MARK: - 앱 정보
                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.gray)
                            .frame(width: 30)
                        Text("버전")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Button(action: { showingAbout = true }) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.gray)
                                .frame(width: 30)
                            Text("도움말")
                        }
                    }
                } header: {
                    Text("정보")
                }
            }
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
    }

    // MARK: - Actions

    private func exportData() {
        // TODO: 데이터 내보내기 구현
    }

    private func importData() {
        // TODO: 데이터 가져오기 구현
    }

    private func clearAllData() {
        // TODO: 데이터 삭제 구현
    }
}

// MARK: - Supporting Views

struct MeasurementSettingsView: View {
    @AppStorage("measurementUnit") private var measurementUnit = "cm"
    @AppStorage("showConfidenceScore") private var showConfidenceScore = true
    @AppStorage("autoSaveMeasurements") private var autoSaveMeasurements = true

    var body: some View {
        List {
            Section {
                Picker("측정 단위", selection: $measurementUnit) {
                    Text("센티미터 (cm)").tag("cm")
                    Text("인치 (inch)").tag("inch")
                }

                Toggle("신뢰도 점수 표시", isOn: $showConfidenceScore)
                Toggle("자동 저장", isOn: $autoSaveMeasurements)
            } header: {
                Text("기본 설정")
            }
        }
        .navigationTitle("측정 설정")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CalibrationSettingsView: View {
    @State private var calibrationProfiles: [String] = ["기본", "반바지 기준"]
    @State private var selectedProfile = "기본"

    var body: some View {
        List {
            Section {
                Picker("교정 프로파일", selection: $selectedProfile) {
                    ForEach(calibrationProfiles, id: \.self) { profile in
                        Text(profile)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("교정 프로파일")
            }

            Section {
                HStack {
                    Text("허리둘레 보정")
                    Spacer()
                    Text("×1.02")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("어깨너비 보정")
                    Spacer()
                    Text("×0.98")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("현재 보정 계수")
            }
        }
        .navigationTitle("교정 설정")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "ruler.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text("ClothIQ")
                        .font(.largeTitle.bold())

                    Text("의류 측정 전문 앱")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("LiDAR 센서를 활용한 정확한 의류 측정")
                        .multilineTextAlignment(.center)
                        .padding()

                    VStack(alignment: .leading, spacing: 10) {
                        Label("버전 1.0.0", systemImage: "info.circle")
                        Label("© 2025 ClothIQ", systemImage: "c.circle")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("앱 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
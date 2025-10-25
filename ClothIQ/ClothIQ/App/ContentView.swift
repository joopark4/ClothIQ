//
//  ContentView.swift
//  ClothIQ
//
//  Created by EUN YEON on 10/22/25.
//
//  Description:
//  임시 메인 뷰입니다.
//  추후 Features 모듈의 뷰들로 교체될 예정입니다.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var clothingItems: [ClothingItemModel]
    @State private var navigateToMeasurement = false
    @State private var showTestView = false

    var body: some View {
        NavigationStack {
            List {
                // 개발 테스트 섹션
                #if DEBUG
                Section("개발 테스트") {
                    Button {
                        showTestView = true
                    } label: {
                        Label("배경 제거 테스트", systemImage: "wand.and.stars")
                    }
                }
                #endif

                ForEach(clothingItems) { item in
                    NavigationLink {
                        ClothingItemDetailView(item: item)
                    } label: {
                        ClothingItemRowView(item: item)
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("ClothIQ")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: { navigateToMeasurement = true }) {
                        Label("의류 측정", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToMeasurement) {
                MeasurementView()
            }
            .sheet(isPresented: $showTestView) {
                BackgroundRemovalTestView()
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(clothingItems[index])
            }
        }
    }
}

// MARK: - Row View

struct ClothingItemRowView: View {
    let item: ClothingItemModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.clothingType?.displayName ?? "알 수 없음")
                    .font(.headline)

                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }

            Text("측정 항목: \(item.measurements.count)개")
                .font(.caption)
                .foregroundColor(.secondary)

            if item.isComplete {
                Text("측정 완료")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Text("진행률: \(Int(item.completionProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail View

struct ClothingItemDetailView: View {
    let item: ClothingItemModel

    var body: some View {
        List {
            Section("기본 정보") {
                LabeledContent("타입", value: item.clothingType?.displayName ?? "알 수 없음")
                LabeledContent("생성일", value: item.createdAt.formatted(date: .long, time: .shortened))
                LabeledContent("즐겨찾기", value: item.isFavorite ? "예" : "아니오")
            }

            Section("측정값") {
                if item.measurements.isEmpty {
                    Text("측정값이 없습니다")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(item.measurements) { measurement in
                        if let measurementType = measurement.measurementType {
                            LabeledContent {
                                VStack(alignment: .trailing) {
                                    Text(measurement.formattedValue())
                                        .font(.body)
                                    Text("신뢰도: \(Int(measurement.confidence * 100))%")
                                        .font(.caption)
                                        .foregroundColor(confidenceColor(measurement.confidence))
                                }
                            } label: {
                                Text(measurementType.displayName)
                            }
                        }
                    }
                }
            }

            if let notes = item.notes {
                Section("메모") {
                    Text(notes)
                }
            }
        }
        .navigationTitle("의류 상세")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.9...1.0: return .green
        case 0.7..<0.9: return .blue
        case 0.5..<0.7: return .orange
        default: return .red
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ClothingItemModel.self, inMemory: true)
}

//
//  ClothingListView.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  의류 아이템 목록을 표시하는 화면입니다.
//  SwiftData로 저장된 의류 아이템들을 리스트로 보여줍니다.
//
//  Key Responsibilities:
//  - 의류 아이템 목록 표시
//  - 썸네일 이미지 표시
//  - 측정 진행률 시각화
//  - 아이템 삭제 기능
//

import SwiftUI
import SwiftData

/// 의류 아이템 목록 화면
struct ClothingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItemModel.createdAt, order: .reverse) private var items: [ClothingItemModel]
    @State private var showingAddNew = false
    @State private var selectedItem: ClothingItemModel?

    var body: some View {
        NavigationStack {
            ZStack {
                if items.isEmpty {
                    emptyStateView
                } else {
                    itemsListView
                }

                // 플로팅 추가 버튼
                floatingAddButton
            }
            .navigationTitle("내 옷장")
            .navigationDestination(for: ClothingItemModel.self) { item in
                ClothingDetailView(item: item)
            }
            .sheet(isPresented: $showingAddNew) {
                NavigationStack {
                    ClothingTypeSelectionView { clothingType in
                        showingAddNew = false
                        navigateToMeasurement(clothingType: clothingType)
                    }
                }
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "tshirt")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.3))

            VStack(spacing: 8) {
                Text("아직 저장된 의류가 없습니다")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("첫 번째 의류를 추가해보세요")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button(action: {
                showingAddNew = true
            }) {
                HStack {
                    Image(systemName: "plus")
                    Text("의류 추가하기")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(25)
            }
        }
    }

    // MARK: - Items List View

    private var itemsListView: some View {
        List {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    ClothingItemCard(item: item)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button {
                        toggleFavorite(item)
                    } label: {
                        Label(
                            item.isFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                            systemImage: item.isFavorite ? "star.slash" : "star"
                        )
                    }

                    Button(role: .destructive) {
                        deleteItem(item)
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Floating Add Button

    private var floatingAddButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: {
                    showingAddNew = true
                }) {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .fill(LinearGradient(
                                    colors: [.blue, .blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .padding()
            }
        }
    }

    // MARK: - Actions

    private func deleteItem(_ item: ClothingItemModel) {
        withAnimation {
            // 이미지 파일 삭제
            if let imagePath = item.imagePath {
                _ = try? ImageFileManager.shared.deleteImage(at: imagePath)
            }

            // SwiftData에서 삭제
            modelContext.delete(item)
        }
    }

    private func toggleFavorite(_ item: ClothingItemModel) {
        withAnimation {
            item.isFavorite.toggle()
            item.updatedAt = Date()
        }
    }

    private func navigateToMeasurement(clothingType: ClothingType) {
        // TODO: MeasurementView로 네비게이션
    }
}


// MARK: - Clothing Type Selection View

/// 의류 타입 선택 화면
struct ClothingTypeSelectionView: View {
    let onSelect: (ClothingType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Button("취소") {
                    dismiss()
                }
                .foregroundColor(.blue)

                Spacer()

                Text("의류 타입 선택")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 44, height: 44)
            }
            .padding()

            Divider()

            // 의류 타입 목록
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(ClothingType.allCases, id: \.self) { type in
                        Button(action: {
                            onSelect(type)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(type.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text("필수 측정 항목: \(type.requiredMeasurements.count)개")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ClothingListView()
        .modelContainer(for: [ClothingItemModel.self])
}
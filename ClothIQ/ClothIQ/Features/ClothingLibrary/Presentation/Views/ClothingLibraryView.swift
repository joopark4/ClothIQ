//
//  ClothingLibraryView.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  의류 라이브러리 메인 화면입니다.
//  iPhone과 iPad에 각각 최적화된 UI를 제공합니다.
//
//  Key Responsibilities:
//  - iPhone: NavigationStack 사용
//  - iPad: NavigationSplitView 사용
//  - Size Class 기반 적응형 레이아웃
//

import SwiftUI
import SwiftData

/// 의류 라이브러리 메인 화면 (iPhone/iPad 적응형)
struct ClothingLibraryView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItemModel.createdAt, order: .reverse) private var items: [ClothingItemModel]

    @State private var selectedItem: ClothingItemModel?
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var searchText = ""
    @State private var showingMeasurement = false
    @State private var showingDeleteAllAlert = false
    @State private var isDeleting = false
    @State private var showingSettings = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad - Split View 레이아웃
                iPadLayout
            } else {
                // iPhone - Stack 레이아웃
                iPhoneLayout
            }
        }
        .fullScreenCover(isPresented: $showingMeasurement) {
            NavigationStack {
                // 테스트용 기본 타입: 반바지
                MeasurementView(clothingType: .shorts)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        NavigationStack {
            ZStack {
                if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    itemsListView
                }

                // 플로팅 추가 버튼 (iPhone)
                floatingAddButton
            }
            .navigationTitle("내 옷장")
            .searchable(text: $searchText, prompt: "의류 검색")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // 전체 삭제 버튼
                        if !filteredItems.isEmpty {
                            Button(action: {
                                showingDeleteAllAlert = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .disabled(isDeleting)
                        }

                        sortMenu
                    }
                }
            }
            .navigationDestination(for: ClothingItemModel.self) { item in
                ClothingDetailView(item: item)
            }
            .alert("전체 삭제", isPresented: $showingDeleteAllAlert) {
                Button("취소", role: .cancel) { }
                Button("전체 삭제", role: .destructive) {
                    deleteAllItems()
                }
            } message: {
                Text("모든 의류 아이템을 삭제하시겠습니까?\n이 작업은 취소할 수 없습니다.")
            }
            .disabled(isDeleting)
        }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - 의류 리스트
            sidebarContent
                .navigationTitle("내 옷장")
                .navigationSplitViewColumnWidth(min: 320, ideal: 400, max: 500)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gearshape")
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showingMeasurement = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }

                    // 전체 삭제 버튼 (iPad)
                    if !filteredItems.isEmpty {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                showingDeleteAllAlert = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .disabled(isDeleting)
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        sortMenu
                    }
                }
                .alert("전체 삭제", isPresented: $showingDeleteAllAlert) {
                    Button("취소", role: .cancel) { }
                    Button("전체 삭제", role: .destructive) {
                        deleteAllItems()
                    }
                } message: {
                    Text("모든 의류 아이템을 삭제하시겠습니까?\n이 작업은 취소할 수 없습니다.")
                }
                .disabled(isDeleting)
        } detail: {
            // Detail - 선택된 아이템 상세보기
            if let selectedItem = selectedItem {
                NavigationStack {
                    ClothingDetailView(item: selectedItem)
                }
            } else {
                ContentUnavailableView(
                    "의류 선택",
                    systemImage: "tshirt",
                    description: Text("왼쪽 목록에서 의류를 선택하세요")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .sidebar, prompt: "의류 검색")
    }

    // MARK: - Shared Components

    private var sidebarContent: some View {
        Group {
            if filteredItems.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "의류가 없습니다",
                        systemImage: "tshirt",
                        description: Text("+ 버튼을 눌러 첫 번째 의류를 추가하세요")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                List(filteredItems, selection: $selectedItem) { item in
                    ClothingItemRow(item: item, isCompact: horizontalSizeClass == .regular)
                        .contextMenu {
                            itemContextMenu(for: item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toggleFavorite(item)
                            } label: {
                                Label(
                                    item.isFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                                    systemImage: item.isFavorite ? "star.slash" : "star"
                                )
                            }
                            .tint(.yellow)
                        }
                        .tag(item)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var itemsListView: some View {
        List {
            ForEach(filteredItems) { item in
                NavigationLink(value: item) {
                    ClothingItemCard(item: item)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .contextMenu {
                    itemContextMenu(for: item)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

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

            Button(action: { showingMeasurement = true }) {
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

    private var floatingAddButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: { showingMeasurement = true }) {
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

    private var sortMenu: some View {
        Menu {
            Button {
                // TODO: 정렬 구현
            } label: {
                Label("최신순", systemImage: "arrow.down")
            }

            Button {
                // TODO: 정렬 구현
            } label: {
                Label("이름순", systemImage: "textformat")
            }

            Button {
                // TODO: 정렬 구현
            } label: {
                Label("진행률순", systemImage: "chart.bar")
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
    }

    @ViewBuilder
    private func itemContextMenu(for item: ClothingItemModel) -> some View {
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

    // MARK: - Computed Properties

    private var filteredItems: [ClothingItemModel] {
        if searchText.isEmpty {
            return items
        } else {
            return items.filter { item in
                (item.clothingType?.displayName ?? "").localizedCaseInsensitiveContains(searchText) ||
                (item.notes ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - Actions

    private func deleteItem(_ item: ClothingItemModel) {
        withAnimation {
            if let imagePath = item.imagePath {
                _ = try? ImageFileManager.shared.deleteImage(at: imagePath)
            }

            // Depth map이 있다면 삭제
            if let depthMapPath = item.depthMapPath {
                _ = try? ImageFileManager.shared.deleteImage(at: depthMapPath)
            }

            if selectedItem?.id == item.id {
                selectedItem = nil
            }

            modelContext.delete(item)
        }
    }

    private func deleteAllItems() {
        isDeleting = true

        Task {
            await MainActor.run {
                withAnimation {
                    // 모든 아이템의 이미지 파일 삭제
                    for item in items {
                        // 이미지 파일 삭제
                        if let imagePath = item.imagePath {
                            _ = try? ImageFileManager.shared.deleteImage(at: imagePath)
                        }

                        // Depth map 파일 삭제
                        if let depthMapPath = item.depthMapPath {
                            _ = try? ImageFileManager.shared.deleteImage(at: depthMapPath)
                        }

                        // SwiftData에서 삭제
                        modelContext.delete(item)
                    }

                    // 선택된 아이템 초기화
                    selectedItem = nil

                    // 변경사항 저장
                    do {
                        try modelContext.save()
                    } catch {
                        // Handle error silently
                    }
                }

                isDeleting = false
            }
        }
    }

    private func toggleFavorite(_ item: ClothingItemModel) {
        withAnimation {
            item.isFavorite.toggle()
            item.updatedAt = Date()
        }
    }

}

// MARK: - Clothing Item Row (iPad Sidebar)

/// 의류 아이템 행 (iPad 사이드바용)
struct ClothingItemRow: View {
    @Bindable var item: ClothingItemModel
    let isCompact: Bool

    init(item: ClothingItemModel, isCompact: Bool) {
        self._item = Bindable(item)
        self.isCompact = isCompact
    }

    var body: some View {
        HStack(spacing: 12) {
            // 썸네일
            if let image = item.loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: isCompact ? 50 : 60, height: isCompact ? 50 : 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: isCompact ? 50 : 60, height: isCompact ? 50 : 60)

                    Image(systemName: "tshirt")
                        .foregroundColor(.gray.opacity(0.3))
                }
            }

            // 정보
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.displayTitle)
                        .font(isCompact ? .subheadline : .headline)
                        .lineLimit(1)

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }

                HStack {
                    Label(
                        "\(item.completedMeasurements)/\(item.totalRequiredMeasurements)",
                        systemImage: "ruler"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Spacer()

                    Text("\(Int(item.completionProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(progressColor)
                        .fontWeight(.medium)
                }

                if !isCompact {
                    Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, isCompact ? 4 : 8)
    }

    private var progressColor: Color {
        switch item.completionProgress {
        case 1.0:
            return .green
        case 0.5..<1.0:
            return .blue
        default:
            return .orange
        }
    }
}

// MARK: - Preview

#Preview("iPhone") {
    ClothingLibraryView()
        .modelContainer(for: [ClothingItemModel.self])
        .environment(\.horizontalSizeClass, .compact)
}

#Preview("iPad") {
    ClothingLibraryView()
        .modelContainer(for: [ClothingItemModel.self])
        .environment(\.horizontalSizeClass, .regular)
}

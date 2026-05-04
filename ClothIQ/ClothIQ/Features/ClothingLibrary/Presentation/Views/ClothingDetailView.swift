//
//  ClothingDetailView.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  의류 아이템 상세 정보를 표시하는 화면입니다.
//  배경 제거된 이미지와 측정값들을 시각적으로 보여줍니다.
//
//  Key Responsibilities:
//  - 의류 이미지 크게 표시
//  - 측정값 시각화
//  - 측정값 편집
//  - 메모 추가/편집
//  - 공유 및 삭제 기능
//

import SwiftUI
import SwiftData

/// 의류 아이템 상세보기 화면
struct ClothingDetailView: View {
    @Bindable var item: ClothingItemModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State var showingEditNote = false
    @State var showingDeleteAlert = false
    @State var showingMeasurement = false
    @State var editingNote: String = ""

    // 새로운 기능 State 변수
    @State var showingPhotoMeasurement = false
    @State var showingTypeEditor = false
    @State var showingBatchAutoMeasurement = false
    @State var sharePayload: SharePayload?

    // 측정 라인 표시 관련
    @State var showMeasurementLines = true  // 기본값을 true로 변경 (측정값 자동 표시)
    @State var selectedMeasurement: MeasurementModel?
    @State var hasAttemptedBottomAnchorRepair = false

    // 디버그 도구
    @State var imageTapCount = 0
    @State var showingDebugDiagnostics = false

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad - 2열 레이아웃
                iPadLayout
            } else {
                // iPhone - 단일 컬럼
                iPhoneLayout
            }
        }
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        item.isFavorite.toggle()
                        item.updatedAt = Date()
                    } label: {
                        Label(
                            item.isFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                            systemImage: item.isFavorite ? "star.slash" : "star"
                        )
                    }

                    Button {
                        shareItem()
                    } label: {
                        Label("공유", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("의류 삭제", isPresented: $showingDeleteAlert) {
            Button("취소", role: .cancel) { }
            Button("삭제", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("이 의류 아이템을 삭제하시겠습니까? 이 작업은 취소할 수 없습니다.")
        }
        .modifier(AdaptiveSheet(isPresented: $showingEditNote) {
            NoteEditView(note: $editingNote) { newNote in
                item.notes = newNote.isEmpty ? nil : newNote
                item.updatedAt = Date()
            }
        })
        .sheet(isPresented: $showingMeasurement) {
            NavigationStack {
                MeasurementView(clothingType: item.clothingType)
            }
        }
        .fullScreenCover(isPresented: $showingPhotoMeasurement) {
            PhotoMeasurementView(item: item, modelContext: modelContext)
        }
        .sheet(isPresented: $showingTypeEditor) {
            ClothingTypeEditorView(item: item)
        }
        .sheet(isPresented: $showingBatchAutoMeasurement) {
            BatchAutoMeasurementView(item: item, modelContext: modelContext)
        }
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(items: [payload.text])
        }
        .task(id: item.id) {
            await repairBottomMeasurementAnchorsIfNeeded()
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: 24) {
                imageSection
                basicInfoSection
                measurementsSection
                notesSection
                actionButtons
            }
            .padding()
        }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        GeometryReader { geometry in
            ScrollView {
                HStack(alignment: .top, spacing: 32) {
                    // 왼쪽: 이미지와 기본 정보
                    VStack(spacing: 24) {
                        imageSection
                            .frame(maxWidth: geometry.size.width * 0.45)

                        basicInfoSection

                        if geometry.size.width > 1000 {
                            actionButtons
                        }
                    }
                    .frame(width: geometry.size.width * 0.45)

                    // 오른쪽: 측정값과 메모
                    VStack(spacing: 24) {
                        measurementsSection
                        notesSection

                        if geometry.size.width <= 1000 {
                            actionButtons
                        }
                    }
                    .frame(width: geometry.size.width * 0.45)
                }
                .padding(32)
                .frame(minHeight: geometry.size.height)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ClothingDetailView(
            item: ClothingItemModel(
                type: ClothingType.shortSleeve.rawValue,
                imagePath: nil,
                notes: "테스트 메모입니다."
            )
        )
    }
    .modelContainer(for: [ClothingItemModel.self])
}

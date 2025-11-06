//
//  PhotoMeasurementView.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  사진 기반 측정 화면입니다.
//  저장된 Depth map을 활용하여 의류 사진에서 직접 측정할 수 있습니다.
//

import SwiftUI
import SwiftData

/// 사진 기반 측정 화면
struct PhotoMeasurementView: View {

    // MARK: - Properties

    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel: PhotoMeasurementViewModel
    @State private var showingSaveConfirmation = false
    @State private var showingDepthMapWarning = false
    @State private var refreshID = UUID()  // 뷰 강제 업데이트용

    // MARK: - Initialization

    init(item: ClothingItemModel, modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: PhotoMeasurementViewModel(
            item: item,
            modelContext: modelContext
        ))
    }

    // MARK: - Body

    var body: some View {
        mainContent
            .onAppear {
                // Depth map이 없으면 경고 표시
                if !viewModel.hasDepthMap {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showingDepthMapWarning = true
                    }
                }
            }
            .navigationBarHidden(true)
            .alert("이미지 회전 저장", isPresented: $showingSaveConfirmation) {
                Button("저장") {
                    viewModel.saveRotatedImage()
                    dismiss()
                }
                Button("저장 안 함") {
                    dismiss()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("이미지를 회전했습니다.\n회전된 이미지를 저장하시겠습니까?")
            }
            .alert("Depth Map 없음", isPresented: $showingDepthMapWarning) {
                Button("확인") {
                    dismiss()
                }
                Button("계속", role: .cancel) {}
            } message: {
                Text("""
                이 사진은 Depth map이 저장되지 않아 측정할 수 없습니다.

                Depth map은 AR 촬영 시 자동으로 저장됩니다.

                ✓ 촬영 버튼이 흰색으로 바뀔 때까지 기다린 후 촬영하세요
                ✓ AR 추적 상태가 "Normal"일 때 촬영하세요

                다시 촬영하시겠습니까?
                """)
            }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            // 배경
            Color.black.ignoresSafeArea()

            // 이미지 뷰 (터치 수신)
            ZoomableImageView(
                image: viewModel.image,
                rotation: viewModel.rotationDegrees,
                measurementAnchors: Binding(
                    get: { viewModel.measurementAnchors },
                    set: { viewModel.measurementAnchors = $0 }
                ),
                isEditingAnchors: Binding(
                    get: { viewModel.isEditingAnchors },
                    set: { viewModel.isEditingAnchors = $0 }
                ),
                activeAnchorID: viewModel.activeAnchorID,
                onTap: { point in
                    viewModel.addMeasurementPoint(point)
                },
                onAnchorDragBegan: { id in
                    viewModel.isEditingAnchors = true
                    viewModel.activeAnchorID = id
                },
                onAnchorDragChanged: { id, position in
                    viewModel.updateAnchorPosition(id: id, to: position, shouldRecalculate: true)
                },
                onAnchorDragEnded: { id, position in
                    viewModel.updateAnchorPosition(id: id, to: position, shouldRecalculate: true)
                    viewModel.isEditingAnchors = false
                },
                onAnchorSelected: { id in
                    viewModel.activeAnchorID = id
                }
            )
            .id("\(refreshID)-\(viewModel.anchorsVersion)")
            .onChange(of: viewModel.measurementAnchors.count) { oldValue, newValue in
                print("🔄 [PhotoMeasurementView] measurementAnchors.count 변경됨: \(oldValue) → \(newValue)")
                // 뷰 강제 새로고침
                DispatchQueue.main.async {
                    refreshID = UUID()
                    print("🔄 [PhotoMeasurementView] refreshID 업데이트됨: \(refreshID)")
                }
            }
            .overlay(alignment: .top) {
                // 상단 툴바 (오버레이)
                topToolbar
            }
            .overlay(alignment: .bottom) {
                // 하단 컨트롤 (오버레이)
                bottomControls
            }

            // 에러 메시지
            if let errorMessage = viewModel.errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                    Spacer()
                }
                .allowsHitTesting(false)  // 터치 통과
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // 성공 메시지
            if let successMessage = viewModel.successMessage {
                VStack {
                    Spacer()
                    Text(successMessage)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding()
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                    Spacer()
                }
                .allowsHitTesting(false)  // 터치 통과
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Depth map 없음 경고
            if !viewModel.hasDepthMap {
                VStack {
                    Spacer()

                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.orange)

                        Text("Depth Map 없음")
                            .font(.headline)

                        Text("이 의류는 Depth 데이터가 없어\n사진 측정을 사용할 수 없습니다.\n\nAR 카메라로 다시 촬영해주세요.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("닫기") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(32)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(radius: 20)
                    .padding(40)

                    Spacer()
                }
                .background(Color.black.opacity(0.5))
            }
        }
    }

    // MARK: - Subviews

    /// 상단 툴바
    @ViewBuilder
    private var topToolbar: some View {
        HStack {
            // 닫기 버튼
            Button {
                closeView()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                    Text("닫기")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
            }

            Spacer()

            // 측정 항목 선택 또는 선택된 항목 표시
            if viewModel.hasDepthMap {
                if let selectedType = viewModel.selectedMeasurementType {
                    // 선택된 측정 항목 표시
                    HStack(spacing: 8) {
                        Text(selectedType.displayName)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Button {
                            viewModel.selectedMeasurementType = nil
                            viewModel.resetPoints()
                            refreshID = UUID()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .clipShape(Capsule())
                } else {
                    // 측정 항목 선택
                    MeasurementTypePickerView(
                        clothingType: viewModel.item.clothingType ?? .shortSleeve,
                        existingMeasurements: viewModel.existingMeasurementTypes,
                        selectedType: Binding(
                            get: {
                                self.viewModel.selectedMeasurementType
                            },
                            set: { newValue in
                                self.viewModel.selectedMeasurementType = newValue
                                self.viewModel.activeAnchorID = nil
                                if let type = newValue {
                                    self.viewModel.loadAnchors(for: type)
                                    // 뷰 강제 업데이트
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        self.refreshID = UUID()
                                    }
                                } else {
                                    self.viewModel.resetPoints()
                                    self.refreshID = UUID()
                                }
                            }
                        )
                    )
                }
            } else {
                Text("Depth Map 없음")
                    .foregroundStyle(.red)
            }

            Spacer()

            // 회전 버튼
            Button {
                viewModel.rotateImage()
            } label: {
                Image(systemName: "rotate.right")
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
        }
        .padding()
    }

    /// 하단 컨트롤
    @ViewBuilder
    private var bottomControls: some View {
        if viewModel.selectedMeasurementType != nil {
            HStack(spacing: 16) {
                // 측정값 표시
                if let result = viewModel.currentMeasurementResult {
                    Text("\(String(format: "%.1f", result.distance)) cm")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                } else if let storedValue = viewModel.selectedMeasurementType.flatMap({ viewModel.existingMeasurementValue(for: $0) }) {
                    Text("\(String(format: "%.1f", storedValue)) cm")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 초기화 버튼
                if !viewModel.measurementAnchors.isEmpty {
                    Button {
                        viewModel.resetPoints()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                }

                // 저장 버튼
                if viewModel.currentMeasurementResult != nil {
                    Button {
                        viewModel.saveMeasurement()
                    } label: {
                        Label("저장", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Actions

    private func closeView() {
        if viewModel.confirmSaveRotatedImage() {
            showingSaveConfirmation = true
        } else {
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var container: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: ClothingItemModel.self, configurations: config)

        let item = ClothingItemModel(
            type: ClothingType.shortSleeve.rawValue,
            imagePath: nil,
            notes: nil
        )

        container.mainContext.insert(item)
        return container
    }()

    let item = try! container.mainContext.fetch(FetchDescriptor<ClothingItemModel>()).first!

    NavigationStack {
        PhotoMeasurementView(item: item, modelContext: container.mainContext)
            .modelContainer(container)
    }
}

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

    let item: ClothingItemModel

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: PhotoMeasurementViewModel?
    @State private var showingSaveConfirmation = false
    @State private var refreshID = UUID()  // 뷰 강제 업데이트용

    // MARK: - Initialization

    init(item: ClothingItemModel) {
        self.item = item
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let viewModel = viewModel {
                mainContent(viewModel: viewModel)
                    .onAppear {
                        print("🟢 [PhotoMeasurementView] View appeared")
                        print("🟢   - ViewModel 있음")
                        print("🟢   - hasDepthMap: \(viewModel.hasDepthMap)")
                        print("🟢   - measurementAnchors: \(viewModel.measurementAnchors.count)개")
                        print("🟢   - selectedMeasurementType: \(viewModel.selectedMeasurementType?.displayName ?? "nil")")
                    }
            } else {
                ProgressView("로딩 중...")
                    .onAppear {
                        print("🟡 [PhotoMeasurementView] ViewModel 초기화 시작...")
                        // Environment modelContext를 사용하여 ViewModel 초기화
                        self.viewModel = PhotoMeasurementViewModel(
                            item: item,
                            modelContext: modelContext
                        )
                        print("🟡 [PhotoMeasurementView] ViewModel 초기화 완료")
                    }
            }
        }
        .navigationBarHidden(true)
        .alert("이미지 회전 저장", isPresented: $showingSaveConfirmation) {
            Button("저장") {
                viewModel?.saveRotatedImage()
                dismiss()
            }
            Button("저장 안 함") {
                dismiss()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이미지를 회전했습니다.\n회전된 이미지를 저장하시겠습니까?")
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private func mainContent(viewModel: PhotoMeasurementViewModel) -> some View {
        ZStack {
            // 메인 콘텐츠
            VStack(spacing: 0) {
                // 상단 툴바
                topToolbar

                // 이미지 뷰
                ZoomableImageView(
                    image: viewModel.image,
                    rotation: viewModel.rotationDegrees,
                    measurementAnchors: Binding(
                        get: { viewModel.measurementAnchors },
                        set: { newValue in
                            viewModel.measurementAnchors = newValue
                            print("🟢 [PhotoMeasurementView] measurementAnchors 업데이트: \(newValue.count)개")
                        }
                    ),
                    isEditingAnchors: Binding(
                        get: { viewModel.isEditingAnchors },
                        set: { newValue in
                            viewModel.isEditingAnchors = newValue
                        }
                    ),
                    activeAnchorID: viewModel.activeAnchorID,
                    onTap: { point in
                        print("🟨 [PhotoMeasurementView] onTap - point: \(point)")
                        viewModel.addMeasurementPoint(point)
                    },
                    onAnchorDragBegan: { id in
                        print("🟨 [PhotoMeasurementView] onAnchorDragBegan - id: \(id)")
                        viewModel.isEditingAnchors = true
                        viewModel.activeAnchorID = id
                        print("🟨   - viewModel.isEditingAnchors 설정됨: \(viewModel.isEditingAnchors)")
                    },
                    onAnchorDragChanged: { id, position in
                        print("🟨 [PhotoMeasurementView] onAnchorDragChanged")
                        print("🟨   - id: \(id)")
                        print("🟨   - position: \(position)")
                        viewModel.updateAnchorPosition(id: id, to: position, shouldRecalculate: true)
                    },
                    onAnchorDragEnded: { id, position in
                        print("🟨 [PhotoMeasurementView] onAnchorDragEnded")
                        print("🟨   - id: \(id)")
                        print("🟨   - position: \(position)")
                        viewModel.updateAnchorPosition(id: id, to: position, shouldRecalculate: true)
                        viewModel.isEditingAnchors = false
                        print("🟨   - viewModel.isEditingAnchors 해제: \(viewModel.isEditingAnchors)")
                    },
                    onAnchorSelected: { id in
                        print("🟨 [PhotoMeasurementView] onAnchorSelected - id: \(id)")
                        viewModel.activeAnchorID = id
                    }
                )
                .id(refreshID)

                // 하단 컨트롤
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
            if viewModel!.hasDepthMap {
                if let selectedType = viewModel!.selectedMeasurementType {
                    // 선택된 측정 항목 표시
                    HStack(spacing: 8) {
                        Text(selectedType.displayName)
                            .font(.headline)
                            .foregroundStyle(.white)

                        Button {
                            print("🔷 [PhotoMeasurementView] 측정 항목 선택 해제")
                            viewModel!.selectedMeasurementType = nil
                            viewModel!.resetPoints()
                            refreshID = UUID()
                            print("🔷   - refreshID 업데이트됨: \(refreshID)")
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
                        clothingType: item.clothingType ?? .shortSleeve,
                        existingMeasurements: viewModel!.existingMeasurementTypes,
                        selectedType: Binding(
                            get: {
                                self.viewModel!.selectedMeasurementType
                            },
                            set: { newValue in
                                print("🔷 [PhotoMeasurementView] 측정 항목 선택: \(newValue?.displayName ?? "nil")")
                                self.viewModel!.selectedMeasurementType = newValue
                                self.viewModel!.activeAnchorID = nil
                                if let type = newValue {
                                    self.viewModel!.loadAnchors(for: type)
                                    // 뷰 강제 업데이트
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        self.refreshID = UUID()
                                        print("🔷   - refreshID 업데이트됨: \(self.refreshID)")
                                    }
                                } else {
                                    self.viewModel!.resetPoints()
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
                viewModel!.rotateImage()
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
        if let selectedType = viewModel!.selectedMeasurementType {
            HStack(spacing: 16) {
                // 측정값 표시
                if let result = viewModel!.currentMeasurementResult {
                    Text("\(String(format: "%.1f", result.distance)) cm")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                } else if let storedValue = viewModel!.selectedMeasurementType.flatMap({ viewModel!.existingMeasurementValue(for: $0) }) {
                    Text("\(String(format: "%.1f", storedValue)) cm")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 초기화 버튼
                if !viewModel!.measurementAnchors.isEmpty {
                    Button {
                        viewModel!.resetPoints()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Color.red)
                            .clipShape(Circle())
                    }
                }

                // 저장 버튼
                if viewModel!.currentMeasurementResult != nil {
                    Button {
                        viewModel!.saveMeasurement()
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
        if let viewModel = viewModel, viewModel.confirmSaveRotatedImage() {
            showingSaveConfirmation = true
        } else {
            dismiss()
        }
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ClothingItemModel.self, configurations: config)

    let item = ClothingItemModel(
        type: ClothingType.shortSleeve.rawValue,
        imagePath: nil,
        notes: nil
    )

    container.mainContext.insert(item)

    return NavigationStack {
        PhotoMeasurementView(item: item)
            .modelContainer(container)
    }
}

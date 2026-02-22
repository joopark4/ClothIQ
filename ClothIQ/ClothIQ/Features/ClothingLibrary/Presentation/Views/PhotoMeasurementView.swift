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
    @State private var showingTrainingStats = false  // 학습 데이터 통계 표시
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
                } else {
                    // Depth map이 있으면 첫 번째 측정 항목 자동 선택
                    print("📱 [PhotoMeasurementView] onAppear - Depth map 있음, 자동 선택 시작")
                    print("  - item.measurements.count: \(viewModel.item.measurements.count)")
                    print("  - selectedMeasurementType: \(viewModel.selectedMeasurementType?.displayName ?? "nil")")

                    if viewModel.selectedMeasurementType == nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            // 기존 측정값이 있으면 첫 번째 측정값 선택
                            if let firstMeasurement = viewModel.item.measurements.first,
                               let measurementType = MeasurementType(rawValue: firstMeasurement.type) {
                                print("✅ [PhotoMeasurementView] 기존 측정값 자동 선택: \(measurementType.displayName)")
                                print("  - startPoint: \(firstMeasurement.startPoint?.debugDescription ?? "nil")")
                                print("  - endPoint: \(firstMeasurement.endPoint?.debugDescription ?? "nil")")

                                viewModel.selectedMeasurementType = measurementType
                                viewModel.loadAnchors(for: measurementType)

                                // 앵커 로드 후 확인
                                print("  - measurementAnchors.count after loadAnchors: \(viewModel.measurementAnchors.count)")
                                refreshID = UUID()
                            }
                            // 측정값이 없으면 첫 번째 필수 측정 항목 선택
                            else if let clothingType = viewModel.item.clothingType,
                                    let firstRequiredType = clothingType.requiredMeasurements.first {
                                print("✅ [PhotoMeasurementView] 새 측정 항목 자동 선택: \(firstRequiredType.displayName)")
                                viewModel.selectedMeasurementType = firstRequiredType
                                // 새로운 측정이므로 앵커는 빈 상태
                                viewModel.resetPoints()
                                refreshID = UUID()
                            } else {
                                print("⚠️ [PhotoMeasurementView] 자동 선택 실패 - 측정값도 없고 의류 타입도 없음")
                            }
                        }
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
                imageSize: viewModel.effectiveImageSize,  // 정확한 이미지 크기 전달
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
                    viewModel.onUserModifiedAnchors()
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
            .overlay {
                // 키포인트 오버레이 (키포인트 표시가 켜져있을 때만)
                if viewModel.showKeypoints && !viewModel.detectedKeypoints.isEmpty {
                    GeometryReader { geometry in
                        KeypointOverlayView(
                            keypoints: viewModel.detectedKeypoints,
                            imageSize: viewModel.effectiveImageSize,
                            displaySize: geometry.size
                        )
                        .allowsHitTesting(false)  // 터치 통과
                    }
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

            // 키포인트 감지 버튼 그룹
            if viewModel.hasDepthMap {
                HStack(spacing: 8) {
                    // 키포인트 표시 토글
                    Button {
                        viewModel.toggleKeypointDisplay()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.showKeypoints ? "eye.fill" : "eye.slash.fill")
                            Text("키포인트")
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(viewModel.showKeypoints ? Color.green.opacity(0.8) : Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }

                    // 자동 측정 모드 토글
                    Button {
                        viewModel.toggleAutoMeasurementMode()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.isAutoMeasurementMode ? "wand.and.stars" : "wand.and.stars.inverse")
                            Text("자동")
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(viewModel.isAutoMeasurementMode ? Color.purple.opacity(0.8) : Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }

                    // ML 모드 토글
                    Button {
                        viewModel.toggleMLMode()
                    } label: {
                        HStack(spacing: 4) {
                            if viewModel.isMLProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: viewModel.isMLModeEnabled ? "brain" : "brain.head.profile")
                            }
                            Text("ML")
                            if viewModel.mlConfidence > 0 {
                                Text("\(Int(viewModel.mlConfidence * 100))%")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(viewModel.isMLModeEnabled ? Color.orange.opacity(0.8) : Color.black.opacity(0.6))
                        .clipShape(Capsule())
                    }
                    .disabled(viewModel.isMLProcessing)
                }
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

                // ML 학습 데이터 통계 버튼 (ML 모드일 때만)
                if viewModel.isMLModeEnabled {
                    Button {
                        showingTrainingStats = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar.fill")
                            Text("학습 데이터")
                        }
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.indigo.opacity(0.8))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .sheet(isPresented: $showingTrainingStats) {
                TrainingStatsView(statistics: viewModel.getTrainingStatistics())
            }
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

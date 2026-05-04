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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var viewModel: PhotoMeasurementViewModel
    @State private var showingSaveConfirmation = false
    @State private var showingDepthMapWarning = false
    @State private var refreshID = UUID()  // 뷰 강제 업데이트용

    private var isCompactWidth: Bool {
        horizontalSizeClass == .compact
    }

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
                    print("  - item.displayMeasurements.count: \(viewModel.item.displayMeasurements.count)")
                    print("  - selectedMeasurementType: \(viewModel.selectedMeasurementType?.displayName ?? "nil")")

                    let removedDuplicates = viewModel.item.deduplicateMeasurements(modelContext: viewModel.modelContext)
                    if removedDuplicates > 0 {
                        viewModel.item.updatedAt = Date()
                        do {
                            try viewModel.modelContext.save()
                            print("✅ [PhotoMeasurementView] 중복 측정값 \(removedDuplicates)개 정리 완료")
                        } catch {
                            print("❌ [PhotoMeasurementView] 중복 측정값 정리 저장 실패: \(error)")
                        }
                    }

                    if viewModel.selectedMeasurementType == nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            // 기존 측정값이 있으면 첫 번째 측정값 선택
                            if let firstMeasurement = viewModel.preferredInitialMeasurement,
                               let measurementType = MeasurementType(rawValue: firstMeasurement.type) {
                                print("✅ [PhotoMeasurementView] 기존 측정값 자동 선택: \(measurementType.displayName)")
                                print("  - startPoint: \(firstMeasurement.startPoint?.debugDescription ?? "nil")")
                                print("  - endPoint: \(firstMeasurement.endPoint?.debugDescription ?? "nil")")

                                viewModel.selectedMeasurementType = measurementType
                                viewModel.loadAnchors(for: measurementType)
                                viewModel.refreshDetectedAnchorsForCurrentSelectionIfNeeded()

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

                            if viewModel.detectedKeypoints.isEmpty {
                                viewModel.showKeypoints = true
                                viewModel.detectKeypoints()
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
                },
                clothingType: viewModel.item.clothingType,
                keypoints: viewModel.detectedKeypoints,
                showKeypoints: viewModel.showKeypoints
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
        HStack(spacing: 8) {
            closeButton

            Spacer()

            // 측정 항목 선택 또는 선택된 항목 표시
            measurementSelectionControl
                .layoutPriority(1)

            Spacer()

            if isCompactWidth {
                compactToolsMenu
            } else {
                HStack(spacing: 8) {
                    if viewModel.hasDepthMap {
                        expandedMeasurementTools
                    }
                    rotateButton
                }
            }
        }
        .padding()
    }

    private var closeButton: some View {
        Button {
            closeView()
        } label: {
            if isCompactWidth {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            } else {
                Label("닫기", systemImage: "xmark")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Capsule())
            }
        }
        .accessibilityLabel("닫기")
    }

    @ViewBuilder
    private var measurementSelectionControl: some View {
        if viewModel.hasDepthMap {
            if let selectedType = viewModel.selectedMeasurementType {
                HStack(spacing: 8) {
                    Text(selectedType.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.white)

                    Button {
                        viewModel.selectedMeasurementType = nil
                        viewModel.resetPoints()
                        refreshID = UUID()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityLabel("측정 항목 선택 해제")
                }
                .padding(.horizontal, isCompactWidth ? 12 : 16)
                .padding(.vertical, 8)
                .background(Color.blue)
                .clipShape(Capsule())
            } else {
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
                                self.viewModel.refreshDetectedAnchorsForCurrentSelectionIfNeeded()
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var expandedMeasurementTools: some View {
        if viewModel.isMLProcessing {
            ProgressView()
                .tint(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }

        keypointButton
        autoMeasurementButton
        mlModeButton
    }

    private var compactToolsMenu: some View {
        Menu {
            if viewModel.hasDepthMap {
                Button {
                    viewModel.toggleKeypointDisplay()
                } label: {
                    Label(
                        viewModel.showKeypoints ? "키포인트 숨기기" : "키포인트 보기",
                        systemImage: viewModel.showKeypoints ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted"
                    )
                }

                Button {
                    viewModel.toggleAutoMeasurementMode()
                } label: {
                    Label(
                        viewModel.isAutoMeasurementMode ? "자동 측정 끄기" : "자동 측정 켜기",
                        systemImage: viewModel.isAutoMeasurementMode ? "wand.and.stars.inverse" : "wand.and.stars"
                    )
                }

                Button {
                    viewModel.toggleMLMode()
                } label: {
                    Label(
                        viewModel.isMLModeEnabled ? "ML 끄기" : "ML 켜기",
                        systemImage: "cpu"
                    )
                }
            }

            Button {
                viewModel.rotateImage()
            } label: {
                Label("회전", systemImage: "rotate.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }
        .accessibilityLabel("측정 도구")
    }

    private var keypointButton: some View {
        Button {
            viewModel.toggleKeypointDisplay()
        } label: {
            Image(systemName: viewModel.showKeypoints ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted")
                .foregroundStyle(viewModel.showKeypoints ? .yellow : .white)
                .padding(12)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }
        .accessibilityLabel(viewModel.showKeypoints ? "키포인트 숨기기" : "키포인트 보기")
    }

    private var autoMeasurementButton: some View {
        Button {
            viewModel.toggleAutoMeasurementMode()
        } label: {
            Image(systemName: viewModel.isAutoMeasurementMode ? "wand.and.stars.inverse" : "wand.and.stars")
                .foregroundStyle(viewModel.isAutoMeasurementMode ? .yellow : .white)
                .padding(12)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }
        .accessibilityLabel(viewModel.isAutoMeasurementMode ? "자동 측정 끄기" : "자동 측정 켜기")
    }

    private var mlModeButton: some View {
        Button {
            viewModel.toggleMLMode()
        } label: {
            Text("ML")
                .font(.caption.bold())
                .foregroundStyle(viewModel.isMLModeEnabled ? .black : .white)
                .frame(width: 36, height: 36)
                .background(viewModel.isMLModeEnabled ? Color.yellow : Color.black.opacity(0.6))
                .clipShape(Circle())
        }
        .accessibilityLabel(viewModel.isMLModeEnabled ? "ML 끄기" : "ML 켜기")
    }

    private var rotateButton: some View {
        Button {
            viewModel.rotateImage()
        } label: {
            Image(systemName: "rotate.right")
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.black.opacity(0.6))
                .clipShape(Circle())
        }
        .accessibilityLabel("회전")
    }

    /// 하단 컨트롤
    @ViewBuilder
    private var bottomControls: some View {
        if viewModel.selectedMeasurementType != nil {
            HStack(spacing: 16) {
                measurementSummary

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

    @ViewBuilder
    private var measurementSummary: some View {
        if let result = viewModel.currentMeasurementResult {
            measurementValue(
                result.distance,
                confidence: result.confidence,
                isCurrentResult: true
            )
        } else if let storedMeasurement = viewModel.selectedMeasurementType.flatMap({ viewModel.existingMeasurement(for: $0) }) {
            measurementValue(
                storedMeasurement.value,
                confidence: storedMeasurement.confidence,
                isCurrentResult: false
            )
        }
    }

    private func measurementValue(
        _ value: Double,
        confidence: Double,
        isCurrentResult: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(String(format: "%.1f", value)) cm")
                .font(.title2)
                .fontWeight(isCurrentResult ? .bold : .semibold)
                .foregroundStyle(isCurrentResult ? .blue : .secondary)

            ConfidenceIndicator(confidence: confidence)
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

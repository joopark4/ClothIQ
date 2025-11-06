//
//  MeasurementView.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  AR 측정 화면의 메인 뷰입니다.
//  ARViewContainer와 측정 UI를 통합하여 표시합니다.
//
//  Key Responsibilities:
//  - AR 카메라 화면 표시
//  - 측정 포인트 오버레이
//  - 측정 컨트롤 UI
//  - 측정 진행 상태 표시
//

import ARKit
import SwiftUI

/// 측정 메인 뷰
///
/// AR 카메라와 측정 인터페이스를 통합한 화면입니다.
///
struct MeasurementView: View {
    @StateObject private var viewModel: MeasurementViewModelRefactored
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var currentDepthData: CVPixelBuffer?
    @State private var currentForegroundMask: CVPixelBuffer?
    @State private var isUpdatingMask = false
    @State private var lastMaskUpdateTime: Date = .distantPast
    @State private var lastEnvironmentUpdateTime: Date = .distantPast
    @State private var showingDetailView = false

    // AutoSize02.md: ARFrame은 자동 측정에만 짧게 사용하고 즉시 해제
    // 타입 선택 시점에만 일시적으로 보관
    @State private var capturedFrameForMeasurement: ARFrame?

    private let maskUpdateInterval: TimeInterval = 1.0
    private let environmentUpdateInterval: TimeInterval = 0.5

    // 전경 분리 서비스
    private let segmentationService = ForegroundSegmentationService()
    private let segmentationQueue = DispatchQueue(label: "com.clothiq.segmentation", qos: .userInitiated)

    init(clothingType: ClothingType? = .shortSleeve) {
        // ModelContext를 나중에 설정하기 위해 일단 nil로 초기화
        _viewModel = StateObject(wrappedValue: MeasurementViewModelRefactored(
            clothingType: clothingType,
            modelContext: nil
        ))
        // AutoSize.md: 의류 분류는 비활성화 (성능 우선)
        segmentationService.enableObjectClassification = false
        segmentationService.strictClothingDetection = false  // 엄격한 검증 비활성화
    }

    /// 촬영 가능 여부
    /// AR이 완전히 초기화되고 tracking이 정상일 때만 촬영 가능
    private var canCapture: Bool {
        viewModel.isARInitialized &&
        viewModel.trackingState == .normal &&
        !viewModel.isLoading
    }

    var body: some View {
        ZStack {
            // AR 카메라 뷰
            ARViewContainer(
                onSessionStarted: {
                    viewModel.startARSession()
                },
                // 탭 시 카메라 포커스 설정 (ARViewContainer 내부에서 처리)
                onTap: nil,
                onFrameUpdate: { frame in
                    // ARFrame 메모리 누수 방지: autoreleasepool 사용
                    let _ = autoreleasepool {
                        Task { @MainActor in
                            // AutoSize02.md: ARFrame은 자동 측정용으로만 일시 보관
                            // 매 프레임마다 최신 프레임으로 교체 (이전 프레임은 자동 해제)
                            self.capturedFrameForMeasurement = frame

                            let now = Date()

                            if now.timeIntervalSince(lastEnvironmentUpdateTime) >= environmentUpdateInterval {
                                lastEnvironmentUpdateTime = now
                                viewModel.updateEnvironment(from: frame)
                            }

                            guard !isUpdatingMask,
                                  now.timeIntervalSince(lastMaskUpdateTime) >= maskUpdateInterval else {
                                return
                            }

                            guard case .normal = viewModel.trackingState else {
                                currentForegroundMask = nil
                                return
                            }

                            isUpdatingMask = true
                            let capturedImage = frame.capturedImage
                            // AutoSize.md에 따라 sceneDepth 사용 (smoothedSceneDepth는 부정확할 수 있음)
                            let depthMap = frame.sceneDepth?.depthMap

                            segmentationQueue.async {
                                let mask: CVPixelBuffer? = {
                                    autoreleasepool {
                                        segmentationService.generateForegroundMask(
                                            from: capturedImage,
                                            depthMap: depthMap
                                        )
                                    }
                                }()

                                Task { @MainActor in
                                    self.currentForegroundMask = mask
                                    self.lastMaskUpdateTime = Date()
                                    self.isUpdatingMask = false
                                }
                            }
                        }
                    }
                },
                onDepthUpdate: { depthData in
                    currentDepthData = depthData
                },
                onTrackingStateChanged: { state in
                    viewModel.updateTrackingState(state)
                },
                onCameraAngleUpdate: { angle in
                    viewModel.cameraPitchAngle = angle
                },
                onAnchorsUpdate: nil,  // 평면 정렬 가이드 제거 - 평면 추정은 백그라운드에서 자동 처리
                captureRequested: $viewModel.captureRequested,
                onImageCaptured: { image, depthMap, camera in
                    viewModel.handleCapturedImage(image, depthMap: depthMap, camera: camera)
                }
            )
            .edgesIgnoringSafeArea(.all)

            // 측정 포인트 오버레이
            MeasurementOverlayView(
                points: viewModel.measurementPoints,
                selectedIndex: viewModel.selectedPointIndex
            )

            // 객체 포커싱 가이드 (실시간 피드백)
            // 평면 추정은 자동으로 시도되며, 실패 시 각도 보정으로 fallback됩니다.
            ObjectFocusGuide(
                foregroundMask: currentForegroundMask,
                depthData: currentDepthData,
                trackingState: viewModel.trackingState,
                cameraPitchAngle: viewModel.cameraPitchAngle
            )

            // AR 초기화 가이드 (최우선 표시)
            ARInitializationGuide(
                trackingState: viewModel.trackingState,
                isInitialized: viewModel.isARInitialized,
                message: viewModel.trackingStateMessage(viewModel.trackingState)
            )

            // UI 컨트롤
            VStack {
                // 상단 헤더
                headerView
                    .padding(.horizontal)
                    .padding(.top, 20)

                Spacer()

                // 하단 컨트롤
                captureControlView
                    .padding(.bottom, 40)
            }

            // 에러/성공 메시지
            if let errorMessage = viewModel.errorMessage {
                errorBanner(errorMessage)
            }

            if let successMessage = viewModel.successMessage {
                successBanner(successMessage)
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $viewModel.showingTypeSelection) {
            NavigationStack {
                ClothingTypeSelectionView { selectedType in
                    // AutoSize02.md: ARFrame을 메서드로 전달하되 즉시 해제되도록
                    // handleTypeSelection 메서드 내에서만 사용됨
                    viewModel.handleTypeSelection(selectedType, frame: capturedFrameForMeasurement)

                    // 타입 선택 후 프레임 참조 즉시 해제
                    capturedFrameForMeasurement = nil
                }
            }
        }
        .onAppear {
            // ModelContext 설정
            viewModel.modelContext = modelContext
        }
        .onChange(of: viewModel.savedClothingItem) { _, newValue in
            if newValue != nil {
                // 약간의 지연 후 상세보기로 이동
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingDetailView = true
                }
            }
        }
        .navigationDestination(isPresented: $showingDetailView) {
            if let savedItem = viewModel.savedClothingItem {
                ClothingDetailView(item: savedItem)
                    .navigationBarBackButtonHidden(false)
            }
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }

            Spacer()
        }
    }

    // MARK: - Capture Controls

    private var captureControlView: some View {
        VStack(spacing: 20) {
            // 촬영 버튼
            Button(action: viewModel.captureImage) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(canCapture ? 0.2 : 0.1))
                        .frame(width: 88, height: 88)

                    Circle()
                        .fill(canCapture ? Color.white : Color.gray.opacity(0.5))
                        .frame(width: 68, height: 68)

                    Circle()
                        .stroke(Color.white.opacity(canCapture ? 0.4 : 0.2), lineWidth: 2)
                        .frame(width: 88, height: 88)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canCapture)

            // 로딩 인디케이터
            if viewModel.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)

                    Text("처리 중...")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Message Banners

    private func errorBanner(_ message: String) -> some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding()
            .background(Color.red)
            .cornerRadius(12)
            .padding()

            Spacer()
        }
        .transition(.move(edge: .top))
        .animation(.spring(), value: viewModel.errorMessage)
    }

    private func successBanner(_ message: String) -> some View {
        VStack {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding()
            .background(Color.green)
            .cornerRadius(12)
            .padding()

            Spacer()
        }
        .transition(.move(edge: .top))
        .animation(.spring(), value: viewModel.successMessage)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MeasurementView()
    }
}

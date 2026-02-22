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

private final class PixelBufferBox: @unchecked Sendable {
    let value: CVPixelBuffer
    init(_ value: CVPixelBuffer) {
        self.value = value
    }
}

private final class OptionalPixelBufferBox: @unchecked Sendable {
    let value: CVPixelBuffer?
    init(_ value: CVPixelBuffer?) {
        self.value = value
    }
}

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

    /// 캡처 시점의 ARFrame (저장 메타데이터용)
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
                // 탭 시 다중 샘플링 시작
                onTap: { location, frame in
                    viewModel.handleTap(at: location, frame: frame)
                },
                onFrameUpdate: { frame in
                    let _ = autoreleasepool {
                        Task { @MainActor in
                            self.capturedFrameForMeasurement = frame
                            viewModel.currentARFrame = frame

                            let now = Date()

                            if now.timeIntervalSince(lastEnvironmentUpdateTime) >= environmentUpdateInterval {
                                lastEnvironmentUpdateTime = now
                                viewModel.updateEnvironment(from: frame)
                            }

                            // 다중 샘플링 워크플로우: AR 프레임 업데이트 전달
                            viewModel.handleARFrameUpdate(frame)

                            guard !isUpdatingMask,
                                  now.timeIntervalSince(lastMaskUpdateTime) >= maskUpdateInterval else {
                                return
                            }

                            guard case .normal = viewModel.trackingState else {
                                currentForegroundMask = nil
                                return
                            }

                            isUpdatingMask = true
                            let capturedImageBox = PixelBufferBox(frame.capturedImage)
                            // 센서 융합: smoothed depth 우선, 없으면 raw scene depth 사용
                            let depthMapBox = OptionalPixelBufferBox(
                                frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
                            )

                            segmentationQueue.async {
                                let maskBox = OptionalPixelBufferBox(
                                    autoreleasepool {
                                        segmentationService.generateForegroundMask(
                                            from: capturedImageBox.value,
                                            depthMap: depthMapBox.value
                                        )
                                    }
                                )

                                Task { @MainActor in
                                    self.currentForegroundMask = maskBox.value
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
                onImageCaptured: { image, depthMap, camera, _ in
                    viewModel.currentARFrame = capturedFrameForMeasurement
                    viewModel.handleCapturedImage(image, depthMap: depthMap, camera: camera)
                }
            )
            .edgesIgnoringSafeArea(.all)

            // 측정 포인트 오버레이
            MeasurementOverlayView(
                points: viewModel.measurementPoints,
                completedMeasurements: viewModel.completedMeasurements,
                selectedIndex: viewModel.selectedPointIndex,
                imageResolution: capturedFrameForMeasurement?.camera.imageResolution
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

            // 다중 샘플링 진행 표시
            if viewModel.isSampling {
                samplingProgressOverlay
            }

            // UI 컨트롤
            VStack {
                // 상단 헤더
                headerView
                    .padding(.horizontal)
                    .padding(.top, 20)

                InCameraMeasurementPicker(
                    clothingType: viewModel.session.clothingType ?? .shortSleeve,
                    onClothingTypeChanged: { type in
                        viewModel.setClothingType(type)
                    },
                    onMeasurementTypeSelected: { type in
                        viewModel.startMeasurement(for: type)
                    },
                    activeMeasurementType: $viewModel.currentMeasurementType,
                    completedTypes: viewModel.completedMeasurements.map { $0.type }
                )
                .padding(.top, 8)

                Spacer()

                // 측정 포인트 관리 버튼 (적용/취소)
                if viewModel.measurementPoints.count > 0 || viewModel.canApplyCurrentMeasurement {
                    measurementControlButtons
                        .padding(.bottom, 16)
                }

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
        .fullScreenCover(isPresented: $viewModel.showingMeasurementPreview) {
            if let previewImage = viewModel.previewImage,
               let clothingType = viewModel.session.clothingType {
                MeasurementPreviewView(
                    image: previewImage,
                    clothingType: clothingType,
                    measurements: viewModel.draftMeasurements,
                    originalImageSize: viewModel.capturedOriginalImageSize,
                    cropRect: viewModel.capturedCropRect,
                    processedImageSize: viewModel.capturedProcessedImageSize ?? previewImage.size,
                    cameraResolution: viewModel.capturedCameraResolution,
                    canSave: !viewModel.draftMeasurements.isEmpty,
                    onSave: {
                        viewModel.confirmPreviewAndSave()
                    },
                    onCancel: {
                        viewModel.cancelPreviewAndDiscardSession()
                    }
                )
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("촬영 이미지를 준비하는 중...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                    }
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

    // MARK: - Measurement Control Buttons

    /// 측정 포인트 관리 버튼 (취소/적용)
    private var measurementControlButtons: some View {
        HStack(spacing: 16) {
            // 다시 찍기(취소) 버튼
            Button(action: {
                viewModel.clearAllPoints()
                viewModel.showSuccess("측정 포인트가 초기화되었습니다")
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 18))
                    Text("다시 찍기")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(Color.orange.opacity(0.8))
                )
                .shadow(color: Color.orange.opacity(0.3), radius: 8, y: 4)
            }
            
            // 적용 버튼 (포인트 2개 또는 계산 완료 캐시가 있을 때)
            if viewModel.canApplyCurrentMeasurement {
                Button(action: {
                    viewModel.applyCurrentMeasurement()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                        Text("적용")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(
                                LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: Color.green.opacity(0.3), radius: 8, y: 4)
                }
            }
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3), value: viewModel.measurementPoints.count)
        .animation(.spring(response: 0.3), value: viewModel.canApplyCurrentMeasurement)
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

    // MARK: - Sampling Progress Overlay

    /// 다중 샘플링 진행 상태 표시 오버레이
    private var samplingProgressOverlay: some View {
        VStack {
            Spacer()
                .frame(height: 100)  // 상단 여백

            VStack(spacing: 16) {
                // 진행률 원형 표시
                ZStack {
                    // 배경 원
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 100, height: 100)

                    // 진행률 원
                    Circle()
                        .trim(from: 0, to: CGFloat(viewModel.samplingProgress))
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.3), value: viewModel.samplingProgress)

                    // 중앙 샘플 카운트
                    VStack(spacing: 4) {
                        Text("\(viewModel.currentSampleCount)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text("/\(viewModel.targetSampleCount)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }

                // 상태 메시지
                Text("측정 포인트 샘플링 중...")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.5))
                    )

                // 진행률 바 (작은 점들)
                HStack(spacing: 4) {
                    ForEach(0..<viewModel.targetSampleCount, id: \.self) { index in
                        Circle()
                            .fill(index < viewModel.currentSampleCount ? Color.cyan : Color.white.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .scaleEffect(index == viewModel.currentSampleCount - 1 ? 1.3 : 1.0)
                            .animation(.spring(response: 0.3), value: viewModel.currentSampleCount)
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.7))
                    .shadow(color: Color.cyan.opacity(0.3), radius: 20, y: 10)
            )
            .transition(.scale.combined(with: .opacity))

            Spacer()
        }
        .animation(.spring(response: 0.5), value: viewModel.isSampling)
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

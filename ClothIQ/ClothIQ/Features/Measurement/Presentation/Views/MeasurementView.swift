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
    @State private var currentDepthData: CVPixelBuffer?
    @State private var currentForegroundMask: CVPixelBuffer?
    @State private var isUpdatingMask = false
    @State private var lastMaskUpdateTime: Date = .distantPast
    @State private var lastEnvironmentUpdateTime: Date = .distantPast

    private let maskUpdateInterval: TimeInterval = 1.0
    private let environmentUpdateInterval: TimeInterval = 0.5

    // 전경 분리 서비스
    private let segmentationService = ForegroundSegmentationService()
    private let segmentationQueue = DispatchQueue(label: "com.clothiq.segmentation", qos: .userInitiated)

    init(clothingType: ClothingType? = .shortSleeve) {
        _viewModel = StateObject(wrappedValue: MeasurementViewModelRefactored(clothingType: clothingType))
        segmentationService.enableObjectClassification = false
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
                    Task { @MainActor in
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
                        let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap

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
                },
                onDepthUpdate: { depthData in
                    currentDepthData = depthData
                },
                onTrackingStateChanged: { state in
                    viewModel.updateTrackingState(state)
                },
                captureRequested: $viewModel.captureRequested,
                onImageCaptured: { image, depthMap in
                    viewModel.handleCapturedImage(image, depthMap: depthMap)
                }
            )
            .edgesIgnoringSafeArea(.all)

            // 측정 포인트 오버레이
            MeasurementOverlayView(
                points: viewModel.measurementPoints,
                selectedIndex: viewModel.selectedPointIndex
            )

            // 객체 포커싱 가이드 (실시간 피드백)
            ObjectFocusGuide(
                foregroundMask: currentForegroundMask,
                depthData: currentDepthData,
                trackingState: viewModel.trackingState
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
        Button(action: viewModel.captureImage) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 88, height: 88)

                Circle()
                    .fill(Color.white)
                    .frame(width: 68, height: 68)

                Circle()
                    .stroke(Color.white.opacity(0.4), lineWidth: 2)
                    .frame(width: 88, height: 88)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(viewModel.isLoading)
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

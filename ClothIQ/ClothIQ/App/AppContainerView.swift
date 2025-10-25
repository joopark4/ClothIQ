//
//  AppContainerView.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  앱의 컨테이너 뷰입니다.
//  기기 지원 여부와 권한 상태를 확인하고 적절한 화면을 표시합니다.
//
//  Key Responsibilities:
//  - 기기 요구사항 확인 (LiDAR, iOS 버전)
//  - 카메라 권한 상태 확인 및 요청
//  - 적절한 뷰 라우팅
//

import SwiftUI
import SwiftData
import AVFoundation

/// 앱 컨테이너 뷰
///
/// 앱 실행 시 최초로 표시되는 래퍼 뷰입니다.
/// 기기 지원 여부와 권한을 확인하여 메인 앱 또는 안내 화면을 표시합니다.
///
struct AppContainerView: View {
    @State private var deviceSupported: Bool = false
    @State private var supportCheckMessage: String? = nil
    @State private var cameraPermissionGranted: Bool = false
    @State private var isCheckingDevice: Bool = true

    var body: some View {
        Group {
            if isCheckingDevice {
                // 기기 확인 중
                LoadingView(message: "기기 확인 중...")
            } else if !deviceSupported, let message = supportCheckMessage {
                // 기기 미지원
                UnsupportedDeviceView(
                    errorMessage: message,
                    deviceModel: DeviceCapability.deviceModel,
                    iOSVersion: DeviceCapability.iOSVersion
                )
            } else if !cameraPermissionGranted {
                // 카메라 권한 미허용
                CameraPermissionView {
                    checkCameraPermission()
                }
            } else {
                // 모든 요구사항 충족 - 메인 앱 표시
                ContentView()
            }
        }
        .onAppear {
            checkDeviceSupport()
        }
    }

    // MARK: - Device Support Check

    /// 기기 지원 여부 확인
    private func checkDeviceSupport() {
        isCheckingDevice = true

        // 비동기로 확인 (시뮬레이션을 위해 약간의 지연 추가)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let result = DeviceCapability.checkMinimumRequirements()

            deviceSupported = result.supported
            supportCheckMessage = result.reason

            isCheckingDevice = false

            // 기기가 지원되면 카메라 권한 확인
            if deviceSupported {
                checkCameraPermission()
            }
        }
    }

    /// 카메라 권한 확인
    private func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            cameraPermissionGranted = true

        case .notDetermined:
            // 권한 요청 뷰에서 처리
            cameraPermissionGranted = false

        case .denied, .restricted:
            // 권한 거부됨 - 권한 뷰 표시
            cameraPermissionGranted = false

        @unknown default:
            cameraPermissionGranted = false
        }
    }
}

// MARK: - Loading View

/// 로딩 화면
struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Supported Device") {
    AppContainerView()
        .modelContainer(for: ClothingItemModel.self, inMemory: true)
}

#Preview("Loading") {
    LoadingView(message: "기기 확인 중...")
}

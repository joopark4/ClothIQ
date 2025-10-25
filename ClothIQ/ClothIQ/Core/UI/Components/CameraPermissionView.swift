//
//  CameraPermissionView.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  카메라 권한 요청 화면입니다.
//  사용자에게 권한의 필요성을 설명하고 권한을 요청합니다.
//

import SwiftUI
import AVFoundation

/// 카메라 권한 요청 뷰
///
/// 카메라 접근 권한이 없는 경우 표시되며,
/// 사용자에게 권한 허용을 안내합니다.
///
struct CameraPermissionView: View {
    @State private var isRequestingPermission = false
    let onPermissionGranted: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // 카메라 아이콘
            Image(systemName: "camera.fill")
                .font(.system(size: 72))
                .foregroundColor(.blue)
                .padding(.top, 60)

            // 제목
            Text("카메라 접근 권한 필요")
                .font(.title)
                .fontWeight(.bold)

            // 설명
            VStack(spacing: 16) {
                Text("ClothIQ는 의류를 측정하기 위해\n카메라와 LiDAR 센서를 사용합니다.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                // 기능 설명
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(
                        icon: "ruler",
                        title: "정밀 측정",
                        description: "LiDAR로 정확한 사이즈 측정"
                    )

                    FeatureRow(
                        icon: "camera.viewfinder",
                        title: "실시간 프리뷰",
                        description: "측정 과정을 실시간으로 확인"
                    )

                    FeatureRow(
                        icon: "photo",
                        title: "이미지 저장",
                        description: "측정한 의류 사진 보관"
                    )
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }

            Spacer()

            // 권한 요청 버튼
            Button(action: requestPermission) {
                HStack {
                    if isRequestingPermission {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "camera.fill")
                        Text("카메라 권한 허용")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal, 32)
            }
            .disabled(isRequestingPermission)

            // 설정으로 이동 버튼 (권한이 이미 거부된 경우)
            if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                Button(action: openSettings) {
                    HStack {
                        Image(systemName: "gear")
                        Text("설정에서 권한 허용")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                    .padding(.horizontal, 32)
                }
            }

            // 안내 메시지
            Text("카메라 접근 권한은 측정 기능에만 사용되며,\n다른 목적으로 사용되지 않습니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
        }
    }

    // MARK: - Actions

    private func requestPermission() {
        isRequestingPermission = true

        DeviceCapability.requestCameraPermission { granted in
            isRequestingPermission = false

            if granted {
                onPermissionGranted()
            }
        }
    }

    private func openSettings() {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    CameraPermissionView {
        print("Permission granted")
    }
}

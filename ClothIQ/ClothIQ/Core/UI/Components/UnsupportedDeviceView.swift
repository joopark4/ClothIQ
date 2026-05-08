//
//  UnsupportedDeviceView.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  LiDAR를 지원하지 않는 기기에 표시되는 안내 화면입니다.
//  지원되는 기기 목록과 앱 사용 불가 이유를 설명합니다.
//

import SwiftUI

/// LiDAR 미지원 기기 안내 뷰
///
/// 앱 실행에 필요한 최소 요구사항을 충족하지 못하는 경우 표시됩니다.
///
struct UnsupportedDeviceView: View {
    let errorMessage: String
    let deviceModel: String
    let iOSVersion: String

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 아이콘
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.orange)
                    .padding(.top, 32)

                // 제목
                Text("기기가 지원되지 않습니다")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("unsupported-device-title")

                // 에러 메시지
                Text(errorMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Divider()
                    .padding(.horizontal, 24)

                // 현재 기기 정보
                VStack(spacing: 12) {
                    Text("현재 기기 정보")
                        .font(.headline)

                    HStack {
                        Text("기기 모델:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(deviceModel)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("iOS 버전:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(iOSVersion)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal, 24)

                Divider()
                    .padding(.horizontal, 24)

                // 지원 기기 목록
                VStack(spacing: 16) {
                    Text("지원되는 기기")
                        .font(.headline)

                    supportedDeviceGroup(
                        title: "iPhone",
                        models: DeviceCapability.lidarSupportedIPhones
                    )

                    supportedDeviceGroup(
                        title: "iPad",
                        models: DeviceCapability.lidarSupportediPads
                    )
                }

                // 안내 메시지
                Text("ClothIQ는 LiDAR 센서가 탑재된 기기에서만 사용할 수 있습니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("unsupported-device-scroll-view")
    }

    private func supportedDeviceGroup(title: String, models: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            ForEach(models, id: \.self) { model in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(model)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}

// MARK: - Preview

#Preview("LiDAR Not Supported") {
    UnsupportedDeviceView(
        errorMessage: "이 기기는 LiDAR 센서를 지원하지 않습니다.\n\nLiDAR가 탑재된 기기:\n• iPhone 12 Pro 이후 Pro 모델\n• iPad Pro (2020년 이후 모델)",
        deviceModel: "iPhone 11",
        iOSVersion: "17.0"
    )
}

#Preview("iOS Version Too Low") {
    UnsupportedDeviceView(
        errorMessage: "iOS 17.0 이상이 필요합니다. 현재 버전: 16.5",
        deviceModel: "iPhone 14 Pro",
        iOSVersion: "16.5"
    )
}

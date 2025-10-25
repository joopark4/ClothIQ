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
        VStack(spacing: 24) {
            // 아이콘
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 72))
                .foregroundColor(.orange)
                .padding(.top, 40)

            // 제목
            Text("기기가 지원되지 않습니다")
                .font(.title)
                .fontWeight(.bold)

            // 에러 메시지
            Text(errorMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Divider()
                .padding(.horizontal, 32)

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
                }
                .padding(.horizontal, 32)

                HStack {
                    Text("iOS 버전:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(iOSVersion)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 32)
            }

            Divider()
                .padding(.horizontal, 32)

            // 지원 기기 목록
            VStack(spacing: 16) {
                Text("지원되는 기기")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("iPhone")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ForEach(DeviceCapability.lidarSupportedIPhones, id: \.self) { model in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text(model)
                                .font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)

                VStack(alignment: .leading, spacing: 8) {
                    Text("iPad")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ForEach(DeviceCapability.lidarSupportediPads, id: \.self) { model in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text(model)
                                .font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
            }

            Spacer()

            // 안내 메시지
            Text("ClothIQ는 LiDAR 센서가 탑재된 기기에서만 사용할 수 있습니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
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

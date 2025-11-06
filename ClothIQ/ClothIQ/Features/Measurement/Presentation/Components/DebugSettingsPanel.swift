//
//  DebugSettingsPanel.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  측정 임계값을 실시간으로 조정하는 디버그 설정 패널입니다.
//  슬라이더를 통해 런타임에 파라미터를 변경할 수 있습니다.
//
//  Key Responsibilities:
//  - 임계값 실시간 조정 (슬라이더)
//  - 설정 값 실시간 표시
//  - 교정 활성화/비활성화 토글
//  - 프로파일 선택
//

import SwiftUI

/// 디버그 설정 패널
///
/// 측정 시스템의 임계값 파라미터를 실시간으로 조정할 수 있는 UI를 제공합니다.
///
struct DebugSettingsPanel: View {

    // MARK: - Properties

    @ObservedObject var settings: MeasurementSettings

    @State private var showAdvanced: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            // 헤더
            HStack {
                Text("실시간 임계값 조정")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: {
                    withAnimation {
                        showAdvanced.toggle()
                    }
                }) {
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white)
                }
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // 기본 설정
            Group {
                // 최소 신뢰도
                sliderControl(
                    label: "최소 신뢰도",
                    value: $settings.minConfidence,
                    range: 0.3...0.9,
                    step: 0.05,
                    format: "%.2f"
                )

                // 최소 깊이 커버리지
                sliderControl(
                    label: "최소 깊이 커버리지",
                    value: $settings.minDepthCoverage,
                    range: 0.05...0.5,
                    step: 0.05,
                    format: "%.2f"
                )

                // 최적 거리 (최소)
                sliderControl(
                    label: "최적 거리 (최소)",
                    value: $settings.optimalMinDistance,
                    range: 0.4...1.0,
                    step: 0.05,
                    format: "%.2fm",
                    color: distanceColor(settings.optimalMinDistance)
                )

                // 최적 거리 (최대)
                sliderControl(
                    label: "최적 거리 (최대)",
                    value: $settings.optimalMaxDistance,
                    range: 0.8...2.0,
                    step: 0.1,
                    format: "%.2fm",
                    color: distanceColor(settings.optimalMaxDistance)
                )
            }

            // 고급 설정
            if showAdvanced {
                Divider()
                    .background(Color.white.opacity(0.3))

                Text("고급 설정")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    // 낮은 신뢰도 경고
                    sliderControl(
                        label: "낮은 신뢰도 경고",
                        value: $settings.lowConfidenceWarning,
                        range: 0.5...0.9,
                        step: 0.05,
                        format: "%.2f",
                        color: .yellow
                    )

                    // 매우 낮은 신뢰도
                    sliderControl(
                        label: "매우 낮은 신뢰도",
                        value: $settings.veryLowConfidence,
                        range: 0.2...0.6,
                        step: 0.05,
                        format: "%.2f",
                        color: .red
                    )

                    // 중간 깊이 커버리지
                    sliderControl(
                        label: "중간 깊이 커버리지",
                        value: $settings.midDepthCoverage,
                        range: 0.05...0.3,
                        step: 0.05,
                        format: "%.2f"
                    )

                    // 평면 샘플 개수
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("평면 샘플 개수:")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            Spacer()
                            Text("\(settings.planeSampleCount)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.planeSampleCount) },
                                set: { settings.planeSampleCount = Int($0) }
                            ),
                            in: 50...200,
                            step: 10
                        )
                        .tint(.blue)
                    }

                    // 평면 오차 허용
                    sliderControl(
                        label: "평면 오차 허용",
                        value: $settings.planeErrorTolerance,
                        range: 0.1...1.0,
                        step: 0.1,
                        format: "%.1f"
                    )
                }
            }

            Divider()
                .background(Color.white.opacity(0.3))

            // 교정 활성화
            Toggle("교정 활성화", isOn: $settings.useCalibration)
                .foregroundColor(.white)
                .tint(.green)

            // 기본값 복원 버튼
            Button(action: {
                withAnimation {
                    settings.resetToDefaults()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("기본값 복원")
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.6))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .padding()
    }

    // MARK: - Helper Views

    /// 슬라이더 컨트롤
    private func sliderControl(
        label: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float,
        format: String,
        color: Color = .white
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label + ":")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }
            Slider(
                value: value,
                in: range,
                step: step
            )
            .tint(color)
        }
    }

    // MARK: - Helper Functions

    /// 거리에 따른 색상
    private func distanceColor(_ distance: Float) -> Color {
        if distance >= 0.7 && distance <= 1.0 {
            return .green
        } else if distance >= 0.5 && distance <= 1.5 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.edgesIgnoringSafeArea(.all)

        DebugSettingsPanel(settings: MeasurementSettings.shared)
    }
}

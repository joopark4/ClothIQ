//
//  DebugMetricsPanel.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  실시간 측정 메트릭을 표시하는 디버그 패널입니다.
//  AR 측정 환경의 상태를 실시간으로 모니터링합니다.
//
//  Key Responsibilities:
//  - 환경 점수 실시간 표시
//  - 깊이 품질 모니터링
//  - 카메라 거리 표시
//  - 감지된 포인트 수 표시
//  - 현재 측정값 표시
//

import SwiftUI

/// 실시간 메트릭 패널
///
/// AR 측정 환경의 상태를 실시간으로 표시합니다.
/// 환경 점수, 깊이 품질, 카메라 거리 등의 메트릭을 색상 코딩하여 시각화합니다.
///
struct DebugMetricsPanel: View {

    // MARK: - Properties

    /// 환경 점수 (0.0 ~ 1.0)
    let environmentScore: Float

    /// 깊이 품질 (0.0 ~ 1.0)
    let depthQuality: Float

    /// 카메라 거리 (미터)
    let cameraDistance: Float?

    /// 감지된 포인트 수
    let detectedPointsCount: Int

    /// 현재 측정값 (옵셔널)
    let currentMeasurement: (type: String, value: Double)?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("실시간 메트릭")
                .font(.headline)
                .foregroundColor(.white)

            Divider()
                .background(Color.white.opacity(0.3))

            // 환경 점수
            metricRow(
                label: "환경 점수",
                value: String(format: "%.2f", environmentScore),
                color: scoreColor(environmentScore)
            )

            // 깊이 품질
            metricRow(
                label: "깊이 품질",
                value: String(format: "%.2f", depthQuality),
                color: scoreColor(depthQuality)
            )

            // 카메라 거리
            if let distance = cameraDistance {
                metricRow(
                    label: "카메라 거리",
                    value: String(format: "%.2fm", distance),
                    color: distanceColor(distance)
                )
            }

            // 감지된 포인트 수
            metricRow(
                label: "감지된 포인트",
                value: "\(detectedPointsCount)개",
                color: .white
            )

            // 현재 측정값
            if let measurement = currentMeasurement {
                Divider()
                    .background(Color.white.opacity(0.3))

                HStack {
                    Text("\(measurement.type):")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    Text(String(format: "%.1fcm", measurement.value))
                        .font(.headline)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(12)
        .padding()
    }

    // MARK: - Helper Views

    /// 메트릭 행
    private func metricRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label + ":")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }

    // MARK: - Helper Functions

    /// 점수에 따른 색상 반환
    private func scoreColor(_ score: Float) -> Color {
        switch score {
        case 0.8...1.0:
            return .green
        case 0.6..<0.8:
            return .yellow
        default:
            return .red
        }
    }

    /// 거리에 따른 색상 반환
    private func distanceColor(_ distance: Float) -> Color {
        let settings = MeasurementSettings.shared
        let optimalMin = settings.optimalMinDistance
        let optimalMax = settings.optimalMaxDistance

        if distance >= optimalMin && distance <= optimalMax {
            return .green
        } else if distance >= (optimalMin * 0.7) && distance <= (optimalMax * 1.3) {
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

        VStack(spacing: 20) {
            // 좋은 상태
            DebugMetricsPanel(
                environmentScore: 0.85,
                depthQuality: 0.90,
                cameraDistance: 0.8,
                detectedPointsCount: 4,
                currentMeasurement: ("어깨너비", 45.2)
            )

            // 경고 상태
            DebugMetricsPanel(
                environmentScore: 0.65,
                depthQuality: 0.70,
                cameraDistance: 1.2,
                detectedPointsCount: 2,
                currentMeasurement: nil
            )

            // 나쁜 상태
            DebugMetricsPanel(
                environmentScore: 0.45,
                depthQuality: 0.50,
                cameraDistance: 0.3,
                detectedPointsCount: 0,
                currentMeasurement: nil
            )
        }
    }
}

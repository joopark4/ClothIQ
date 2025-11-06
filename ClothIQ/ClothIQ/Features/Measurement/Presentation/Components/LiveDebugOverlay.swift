//
//  LiveDebugOverlay.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  AR 카메라 뷰 위에 표시되는 라이브 디버깅 오버레이입니다.
//  실시간 메트릭과 설정 조정 UI를 제공합니다.
//
//  Key Responsibilities:
//  - 디버그 메트릭 표시
//  - 설정 조정 패널 토글
//  - 디버그 모드 on/off
//

import SwiftUI

/// 라이브 디버깅 오버레이
///
/// AR 측정 화면 위에 표시되는 디버그 정보 오버레이입니다.
/// 실시간 메트릭과 설정 조정 UI를 제공합니다.
///
struct LiveDebugOverlay: View {

    // MARK: - Properties

    @ObservedObject var settings = MeasurementSettings.shared

    /// 환경 점수
    let environmentScore: Float

    /// 깊이 품질
    let depthQuality: Float

    /// 카메라 거리
    let cameraDistance: Float?

    /// 감지된 포인트 수
    let detectedPointsCount: Int

    /// 현재 측정값
    let currentMeasurement: (type: String, value: Double)?

    /// 설정 패널 표시 여부
    @State private var showSettings: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // 디버그 모드가 활성화된 경우에만 표시
            if settings.isDebugMode {
                VStack {
                    // 상단: 실시간 메트릭
                    DebugMetricsPanel(
                        environmentScore: environmentScore,
                        depthQuality: depthQuality,
                        cameraDistance: cameraDistance,
                        detectedPointsCount: detectedPointsCount,
                        currentMeasurement: currentMeasurement
                    )

                    Spacer()

                    // 하단: 설정 패널 (토글 가능)
                    if showSettings {
                        DebugSettingsPanel(settings: settings)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // 설정 토글 버튼
                    HStack {
                        Spacer()

                        Button(action: {
                            withAnimation(.spring()) {
                                showSettings.toggle()
                            }
                        }) {
                            Image(systemName: showSettings ? "slider.horizontal.3" : "slider.horizontal.3")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 50, height: 50)
                                .background(Color.blue.opacity(0.8))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 5, x: 0, y: 2)
                        }
                        .padding()
                    }
                }
            }
        }
        .allowsHitTesting(settings.isDebugMode)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        // 배경 (AR 카메라 뷰를 시뮬레이션)
        Color.gray.edgesIgnoringSafeArea(.all)

        // 디버그 오버레이
        LiveDebugOverlay(
            environmentScore: 0.85,
            depthQuality: 0.90,
            cameraDistance: 0.8,
            detectedPointsCount: 4,
            currentMeasurement: ("어깨너비", 45.2)
        )
    }
    .onAppear {
        MeasurementSettings.shared.isDebugMode = true
    }
}

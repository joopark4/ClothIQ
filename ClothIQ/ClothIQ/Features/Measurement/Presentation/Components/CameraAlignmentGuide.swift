//
//  CameraAlignmentGuide.swift
//  ClothIQ
//
//  Created on 2025-11-03
//
//  Description:
//  촬영 시 카메라 각도와 거리를 가이드하는 오버레이 컴포넌트입니다.
//  수평계처럼 카메라가 의류 평면에 수직인지 체크하고 시각적/햅틱 피드백을 제공합니다.
//
//  Key Features:
//  - 카메라 틸트 각도 시각화 (원형 레벨 인디케이터)
//  - 의류까지의 거리 표시
//  - 최적 조건 도달 시 햅틱 피드백
//  - 상태별 색상 변경 (빨강 → 노랑 → 녹색)
//

import SwiftUI

/// 카메라 정렬 상태
enum CameraAlignmentState {
    case poor       // 각도나 거리가 많이 벗어남 (빨강)
    case fair       // 개선 필요 (노랑)
    case good       // 최적 상태 (녹색)

    var color: Color {
        switch self {
        case .poor: return .red
        case .fair: return .yellow
        case .good: return .green
        }
    }

    var message: String {
        switch self {
        case .poor: return "카메라 위치 조정 필요"
        case .fair: return "조금만 더 조정해주세요"
        case .good: return "완벽한 각도입니다!"
        }
    }
}

/// 카메라 정렬 데이터
struct CameraAlignmentData {
    /// 평면과 카메라의 각도 (0° = 완벽한 수직, 90° = 완벽한 수평)
    let tiltAngle: Double

    /// 의류까지의 거리 (미터)
    let distance: Double

    /// 평면이 감지되었는지
    let hasPlaneDetected: Bool

    /// 전체 정렬 상태
    var alignmentState: CameraAlignmentState {
        guard hasPlaneDetected else { return .poor }

        let isAngleGood = abs(tiltAngle) < 10.0  // 10도 이내
        let isAngleFair = abs(tiltAngle) < 20.0  // 20도 이내

        let isDistanceGood = (0.4...0.6).contains(distance)  // 40-60cm
        let isDistanceFair = (0.3...0.8).contains(distance)  // 30-80cm

        if isAngleGood && isDistanceGood {
            return .good
        } else if isAngleFair && isDistanceFair {
            return .fair
        } else {
            return .poor
        }
    }

    /// 각도가 적절한지
    var isAngleGood: Bool {
        hasPlaneDetected && abs(tiltAngle) < 10.0
    }

    /// 거리가 적절한지
    var isDistanceGood: Bool {
        (0.4...0.6).contains(distance)
    }
}

/// 카메라 정렬 가이드 오버레이
struct CameraAlignmentGuide: View {

    let alignmentData: CameraAlignmentData?
    let onOptimalAlignment: (() -> Void)?  // 최적 상태 도달 시 콜백

    @State private var previousState: CameraAlignmentState = .poor
    @State private var lastHapticTime: Date = .distantPast

    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            if let data = alignmentData {
                VStack {
                    // 상단 상태 메시지
                    statusMessage(for: data)
                        .padding(.top, 60)

                    Spacer()

                    // 중앙 레벨 인디케이터
                    levelIndicator(for: data)

                    Spacer()

                    // 하단 정보
                    bottomInfo(for: data)
                        .padding(.bottom, 120)
                }
                .onChange(of: data.alignmentState) { oldValue, newValue in
                    handleStateChange(from: oldValue, to: newValue)
                }
            } else {
                // 평면 탐지 중
                VStack {
                    Spacer()

                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .scaleEffect(1.5)

                        Text("의류 평면 탐지 중...")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Text("카메라를 의류 위에 천천히 움직여주세요")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Spacer()
                }
            }
        }
    }

    // MARK: - Subviews

    /// 상태 메시지
    @ViewBuilder
    private func statusMessage(for data: CameraAlignmentData) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(data.alignmentState.color)
                    .frame(width: 12, height: 12)

                Text(data.alignmentState.message)
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.6))
            .clipShape(Capsule())
        }
    }

    /// 중앙 원형 레벨 인디케이터
    @ViewBuilder
    private func levelIndicator(for data: CameraAlignmentData) -> some View {
        ZStack {
            // 배경 원
            Circle()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 3)
                .frame(width: 200, height: 200)

            // 십자선 (수평/수직 기준선)
            Path { path in
                // 수평선
                path.move(to: CGPoint(x: 50, y: 100))
                path.addLine(to: CGPoint(x: 150, y: 100))
                // 수직선
                path.move(to: CGPoint(x: 100, y: 50))
                path.addLine(to: CGPoint(x: 100, y: 150))
            }
            .stroke(Color.white.opacity(0.5), lineWidth: 1)
            .frame(width: 200, height: 200)

            // 틸트 인디케이터 (각도에 따라 움직이는 원)
            Circle()
                .fill(data.alignmentState.color)
                .frame(width: 30, height: 30)
                .shadow(color: data.alignmentState.color.opacity(0.6), radius: 10)
                .offset(
                    x: CGFloat(data.tiltAngle) * 3.0,  // 각도에 따라 X축 이동
                    y: 0
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: data.tiltAngle)

            // 중앙 타겟
            Circle()
                .strokeBorder(Color.white, lineWidth: 2)
                .frame(width: 40, height: 40)

            // 최적 상태일 때 체크 표시
            if data.alignmentState == .good {
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 200, height: 200)
    }

    /// 하단 정보 (각도, 거리)
    @ViewBuilder
    private func bottomInfo(for data: CameraAlignmentData) -> some View {
        VStack(spacing: 16) {
            // 각도 정보
            HStack(spacing: 12) {
                Image(systemName: "angle")
                    .font(.title3)
                    .foregroundStyle(data.isAngleGood ? .green : .red)

                VStack(alignment: .leading, spacing: 4) {
                    Text("카메라 각도")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))

                    Text("\(String(format: "%.1f", abs(data.tiltAngle)))°")
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                Spacer()

                Text(data.isAngleGood ? "✓" : "✗")
                    .font(.title2)
                    .foregroundStyle(data.isAngleGood ? .green : .red)
            }
            .padding()
            .background(Color.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 거리 정보
            HStack(spacing: 12) {
                Image(systemName: "ruler")
                    .font(.title3)
                    .foregroundStyle(data.isDistanceGood ? .green : .red)

                VStack(alignment: .leading, spacing: 4) {
                    Text("촬영 거리")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))

                    Text("\(String(format: "%.0f", data.distance * 100)) cm")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text("권장: 40-60 cm")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Text(data.isDistanceGood ? "✓" : "✗")
                    .font(.title2)
                    .foregroundStyle(data.isDistanceGood ? .green : .red)
            }
            .padding()
            .background(Color.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Helpers

    /// 상태 변경 처리 (햅틱 피드백)
    private func handleStateChange(from oldState: CameraAlignmentState, to newState: CameraAlignmentState) {
        // Good 상태에 진입했을 때만 햅틱 발생
        if newState == .good && oldState != .good {
            let now = Date()
            // 최소 1초 간격으로만 햅틱 발생 (과도한 진동 방지)
            if now.timeIntervalSince(lastHapticTime) > 1.0 {
                hapticFeedback.impactOccurred()
                lastHapticTime = now
                onOptimalAlignment?()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        CameraAlignmentGuide(
            alignmentData: CameraAlignmentData(
                tiltAngle: 5.0,
                distance: 0.5,
                hasPlaneDetected: true
            ),
            onOptimalAlignment: {
                print("최적 정렬 상태!")
            }
        )
    }
}

#Preview("Poor Alignment") {
    ZStack {
        Color.black.ignoresSafeArea()

        CameraAlignmentGuide(
            alignmentData: CameraAlignmentData(
                tiltAngle: 35.0,
                distance: 0.9,
                hasPlaneDetected: true
            ),
            onOptimalAlignment: nil
        )
    }
}

#Preview("No Plane") {
    ZStack {
        Color.black.ignoresSafeArea()

        CameraAlignmentGuide(
            alignmentData: nil,
            onOptimalAlignment: nil
        )
    }
}

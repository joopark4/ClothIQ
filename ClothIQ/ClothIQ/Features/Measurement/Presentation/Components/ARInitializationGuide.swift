//
//  ARInitializationGuide.swift
//  ClothIQ
//
//  Created on 2025-10-23
//
//  Description:
//  AR 세션 초기화 가이드를 표시하는 뷰입니다.
//  LiDAR 센서 초기화 중 사용자에게 안내 메시지를 제공합니다.
//
//  Key Responsibilities:
//  - AR TrackingState 기반 안내 메시지 표시
//  - "아이폰을 움직여주세요" 같은 인터랙티브 가이드 제공
//  - 초기화 완료 시 자동으로 사라짐
//

import SwiftUI
import ARKit

/// AR 초기화 가이드
///
/// AR 세션 초기화 중 사용자에게 안내를 제공합니다.
///
struct ARInitializationGuide: View {
    let trackingState: ARCamera.TrackingState
    let isInitialized: Bool
    let message: String?

    @State private var isAnimating = false

    var body: some View {
        // AR이 초기화되면 가이드 숨김
        if !isInitialized, let guideMessage = message {
            VStack(spacing: 24) {
                // 애니메이션 아이콘
                animationIcon

                // 메시지
                VStack(spacing: 12) {
                    Text(guideMessage)
                        .font(.headline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    // 상세 설명
                    if let subtitle = subtitleForState {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)

                // 진행 표시
                if case .limited(.initializing) = trackingState {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
            )
            .padding(.horizontal, 40)
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Animation Icon

    /// TrackingState에 따른 애니메이션 아이콘
    private var animationIcon: some View {
        Group {
            switch trackingState {
            case .limited(.initializing):
                scanningAnimation

            case .limited(.insufficientFeatures):
                phoneMovementAnimation

            case .limited(.excessiveMotion):
                slowDownAnimation

            case .limited(.relocalizing):
                relocalizingAnimation

            default:
                EmptyView()
            }
        }
    }

    /// 스캐닝 애니메이션
    private var scanningAnimation: some View {
        ZStack {
            // 외곽 원
            Circle()
                .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                .frame(width: 100, height: 100)

            // 펄스 애니메이션
            Circle()
                .stroke(Color.blue, lineWidth: 2)
                .frame(width: 100, height: 100)
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .opacity(isAnimating ? 0.0 : 1.0)
                .animation(
                    Animation.easeOut(duration: 1.5)
                        .repeatForever(autoreverses: false),
                    value: isAnimating
                )

            // 중앙 아이콘
            Image(systemName: "sensor")
                .font(.system(size: 40))
                .foregroundColor(.blue)
        }
        .onAppear {
            isAnimating = true
        }
    }

    /// 폰 움직임 애니메이션
    private var phoneMovementAnimation: some View {
        HStack(spacing: 16) {
            // 왼쪽 화살표
            Image(systemName: "arrow.left")
                .font(.title)
                .foregroundColor(.green)
                .offset(x: isAnimating ? -10 : 0)
                .animation(
                    Animation.easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )

            // 중앙 폰 아이콘
            Image(systemName: "iphone")
                .font(.system(size: 50))
                .foregroundColor(.white)

            // 오른쪽 화살표
            Image(systemName: "arrow.right")
                .font(.title)
                .foregroundColor(.green)
                .offset(x: isAnimating ? 10 : 0)
                .animation(
                    Animation.easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )
        }
        .onAppear {
            isAnimating = true
        }
    }

    /// 느리게 움직이라는 애니메이션
    private var slowDownAnimation: some View {
        VStack(spacing: 12) {
            Image(systemName: "tortoise.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
                .scaleEffect(isAnimating ? 1.2 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )

            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundColor(.orange)
        }
        .onAppear {
            isAnimating = true
        }
    }

    /// 재인식 애니메이션
    private var relocalizingAnimation: some View {
        Image(systemName: "arrow.clockwise.circle.fill")
            .font(.system(size: 50))
            .foregroundColor(.yellow)
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .animation(
                Animation.linear(duration: 2.0)
                    .repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }

    // MARK: - Subtitle

    /// TrackingState에 따른 상세 설명
    private var subtitleForState: String? {
        switch trackingState {
        case .limited(.initializing):
            return "잠시만 기다려주세요"

        case .limited(.insufficientFeatures):
            return "좌우로 천천히 움직이며\n주변을 스캔해주세요"

        case .limited(.excessiveMotion):
            return "폰을 천천히 움직여주세요"

        case .limited(.relocalizing):
            return "이전 위치를 찾는 중입니다"

        default:
            return nil
        }
    }
}

// MARK: - Preview

#Preview("Initializing") {
    ZStack {
        Color.black.ignoresSafeArea()

        ARInitializationGuide(
            trackingState: .limited(.initializing),
            isInitialized: false,
            message: "LiDAR 센서 초기화 중..."
        )
    }
}

#Preview("Insufficient Features") {
    ZStack {
        Color.black.ignoresSafeArea()

        ARInitializationGuide(
            trackingState: .limited(.insufficientFeatures),
            isInitialized: false,
            message: "아이폰을 천천히 움직여주세요"
        )
    }
}

#Preview("Excessive Motion") {
    ZStack {
        Color.black.ignoresSafeArea()

        ARInitializationGuide(
            trackingState: .limited(.excessiveMotion),
            isInitialized: false,
            message: "카메라가 너무 빠릅니다"
        )
    }
}

#Preview("Initialized") {
    ZStack {
        Color.black.ignoresSafeArea()

        ARInitializationGuide(
            trackingState: .normal,
            isInitialized: true,
            message: nil
        )
    }
}

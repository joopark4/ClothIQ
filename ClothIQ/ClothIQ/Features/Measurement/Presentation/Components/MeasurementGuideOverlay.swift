//
//  MeasurementGuideOverlay.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  측정 가이드를 AR 화면에 오버레이로 표시하는 뷰입니다.
//  사용자에게 정확한 측정을 위한 안내를 제공합니다.
//

import SwiftUI

/// 측정 가이드 오버레이
///
/// AR 카메라 화면에 표시되는 측정 가이드 UI
///
struct MeasurementGuideOverlay: View {
    let isClothingDetected: Bool
    let detectionMessage: String?
    let environmentScore: Float
    let currentMeasurementType: MeasurementType?

    var body: some View {
        ZStack {
            // 1. 중앙 타겟 가이드
            centerTargetGuide

            // 2. 상단 상태 표시
            VStack {
                statusIndicator
                    .padding(.top, 100)

                Spacer()

                // 3. 하단 측정 가이드
                if let measurementType = currentMeasurementType {
                    measurementInstructions(for: measurementType)
                        .padding(.bottom, 150)
                }
            }

            // 4. 측면 거리 가이드
            distanceGuides
        }
    }

    // MARK: - Center Target Guide

    /// 중앙 타겟 가이드 (십자선 + 원)
    private var centerTargetGuide: some View {
        ZStack {
            // 외곽 원
            Circle()
                .stroke(
                    isClothingDetected ? Color.green : Color.orange,
                    lineWidth: 3
                )
                .frame(width: 120, height: 120)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        .frame(width: 100, height: 100)
                )

            // 십자선
            Path { path in
                // 가로선
                path.move(to: CGPoint(x: -80, y: 0))
                path.addLine(to: CGPoint(x: -30, y: 0))
                path.move(to: CGPoint(x: 30, y: 0))
                path.addLine(to: CGPoint(x: 80, y: 0))

                // 세로선
                path.move(to: CGPoint(x: 0, y: -80))
                path.addLine(to: CGPoint(x: 0, y: -30))
                path.move(to: CGPoint(x: 0, y: 30))
                path.addLine(to: CGPoint(x: 0, y: 80))
            }
            .stroke(
                isClothingDetected ? Color.green : Color.white,
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )

            // 중앙 점
            Circle()
                .fill(isClothingDetected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Status Indicator

    /// 상단 상태 표시
    private var statusIndicator: some View {
        VStack(spacing: 12) {
            // 의류 감지 상태
            HStack(spacing: 8) {
                Image(systemName: isClothingDetected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(isClothingDetected ? .green : .orange)

                Text(detectionMessage ?? "의류를 화면에 맞춰주세요")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(20)

            // 환경 점수 표시
            if environmentScore < 0.5 {
                HStack(spacing: 8) {
                    Image(systemName: "light.max")
                        .foregroundColor(.yellow)

                    Text(environmentQualityMessage)
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.8))
                .cornerRadius(15)
            }
        }
    }

    /// 환경 품질 메시지
    private var environmentQualityMessage: String {
        switch environmentScore {
        case 0..<0.3:
            return "조명이 부족합니다"
        case 0.3..<0.5:
            return "측정 환경 개선 필요"
        default:
            return "양호"
        }
    }

    // MARK: - Measurement Instructions

    /// 측정 가이드 설명
    private func measurementInstructions(for type: MeasurementType) -> some View {
        VStack(spacing: 12) {
            // 측정 타입
            Text(type.displayName)
                .font(.headline)
                .foregroundColor(.white)

            // 측정 방법
            VStack(alignment: .leading, spacing: 8) {
                instructionRow(icon: "1.circle.fill", text: type.measurementGuide)

                instructionRow(
                    icon: "hand.tap.fill",
                    text: "측정할 시작점과 끝점을 터치하세요"
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(.horizontal, 24)
        }
    }

    /// 가이드 행
    private func instructionRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .font(.body)

            Text(text)
                .font(.caption)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Distance Guides

    /// 거리 가이드 (측면)
    private var distanceGuides: some View {
        GeometryReader { geometry in
            ZStack {
                // 좌측 거리 가이드
                VStack {
                    Spacer()
                    distanceIndicator(
                        text: "30cm~2m",
                        subtitle: "권장 거리",
                        color: .blue
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    Spacer()
                }

                // 우측 각도 가이드
                VStack {
                    Spacer()
                    angleIndicator
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 16)
                    Spacer()
                }
            }
        }
    }

    /// 거리 표시기
    private func distanceIndicator(text: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.7))
        .cornerRadius(12)
    }

    /// 각도 표시기
    private var angleIndicator: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.down")
                .font(.title3)
                .foregroundColor(.white)

            Text("수직으로")
                .font(.caption2)
                .foregroundColor(.white)

            Image(systemName: "camera.fill")
                .font(.body)
                .foregroundColor(.white)
        }
        .padding(12)
        .background(Color.purple.opacity(0.7))
        .cornerRadius(12)
    }
}

// MARK: - Checklist Guide

/// 측정 전 체크리스트 가이드
struct MeasurementChecklistGuide: View {
    @Binding var isVisible: Bool

    var body: some View {
        if isVisible {
            VStack(spacing: 20) {
                // 헤더
                HStack {
                    Text("측정 준비 체크리스트")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: { isVisible = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                // 체크리스트
                VStack(alignment: .leading, spacing: 12) {
                    checklistItem(
                        icon: "checkmark.circle.fill",
                        text: "의류를 평평한 곳에 펼쳐주세요",
                        color: .green
                    )

                    checklistItem(
                        icon: "light.max",
                        text: "밝은 조명 아래에서 촬영하세요",
                        color: .yellow
                    )

                    checklistItem(
                        icon: "ruler",
                        text: "카메라와 30cm~2m 거리 유지",
                        color: .blue
                    )

                    checklistItem(
                        icon: "arrow.down",
                        text: "카메라를 수직으로 위에서 촬영",
                        color: .purple
                    )

                    checklistItem(
                        icon: "hand.raised.fill",
                        text: "의류만 화면에 나오도록 조정",
                        color: .orange
                    )
                }

                // 시작 버튼
                Button(action: { isVisible = false }) {
                    Text("측정 시작하기")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                }
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(radius: 20)
            .padding(.horizontal, 32)
            .transition(.scale.combined(with: .opacity))
        }
    }

    private func checklistItem(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
                .frame(width: 30)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Preview

#Preview("Guide Overlay") {
    ZStack {
        Color.black.ignoresSafeArea()

        MeasurementGuideOverlay(
            isClothingDetected: true,
            detectionMessage: "✅ T-shirt 감지됨",
            environmentScore: 0.8,
            currentMeasurementType: .shoulderWidth
        )
    }
}

#Preview("Checklist") {
    ZStack {
        Color.black.ignoresSafeArea()

        MeasurementChecklistGuide(isVisible: .constant(true))
    }
}

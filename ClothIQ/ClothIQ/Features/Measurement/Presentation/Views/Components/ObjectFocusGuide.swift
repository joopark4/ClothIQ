//
//  ObjectFocusGuide.swift
//  ClothIQ
//
//  Created on 2025-10-23
//
//  Description:
//  실시간 객체 포커싱 가이드 컴포넌트입니다.
//  사용자가 의류를 제대로 포커싱하고 있는지 시각적 피드백을 제공합니다.
//

import SwiftUI
import ARKit

/// 포커싱 상태
enum FocusState {
    case notDetected          // 객체 미감지
    case tooFar              // 너무 멀음
    case tooClose            // 너무 가까움
    case tooSmall            // 객체가 너무 작음
    case tooLarge            // 객체가 너무 큼
    case poorLighting        // 조명 불량
    case ready               // 촬영 준비 완료

    var icon: String {
        switch self {
        case .notDetected: return "viewfinder.circle"
        case .tooFar: return "arrow.down.circle"
        case .tooClose: return "arrow.up.circle"
        case .tooSmall: return "arrow.up.left.and.arrow.down.right.circle"
        case .tooLarge: return "arrow.down.right.and.arrow.up.left.circle"
        case .poorLighting: return "light.max"
        case .ready: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready: return .green
        case .notDetected, .poorLighting: return .red
        default: return .orange
        }
    }

    var message: String {
        switch self {
        case .notDetected:
            return "의류를 화면 중앙에 배치하세요"
        case .tooFar:
            return "카메라를 더 가까이 하세요"
        case .tooClose:
            return "카메라를 더 멀리 하세요"
        case .tooSmall:
            return "의류가 화면에 너무 작습니다\n더 가까이 촬영하세요"
        case .tooLarge:
            return "의류가 화면을 벗어납니다\n더 멀리 촬영하세요"
        case .poorLighting:
            return "조명이 부족합니다\n밝은 곳에서 촬영하세요"
        case .ready:
            return "촬영 준비 완료!"
        }
    }

    var canCapture: Bool {
        return self == .ready
    }
}

/// 포커싱 분석 결과
struct FocusAnalysis {
    let state: FocusState
    let coverage: Float           // 객체가 화면을 차지하는 비율 (0.0 ~ 1.0)
    let averageDepth: Float       // 평균 거리 (미터)
    let confidence: Float         // 감지 신뢰도

    static let `default` = FocusAnalysis(
        state: .notDetected,
        coverage: 0,
        averageDepth: 0,
        confidence: 0
    )
}

/// 객체 포커싱 가이드 뷰
struct ObjectFocusGuide: View {
    let foregroundMask: CVPixelBuffer?
    let depthData: CVPixelBuffer?
    let trackingState: ARCamera.TrackingState
    var cameraPitchAngle: Float = 0  // 카메라 기울기 각도

    private static let analysisQueue = DispatchQueue(label: "com.clothiq.focus-analysis", qos: .userInitiated)
    private static let maskSampleStride = 4

    @State private var focusAnalysis: FocusAnalysis = .default
    @State private var pulseAnimation: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // 포커싱 가이드 카드
            VStack(spacing: 16) {
                // 상태 아이콘 및 메시지
                HStack(spacing: 16) {
                    // 아이콘 (펄스 애니메이션)
                    ZStack {
                        if focusAnalysis.state == .ready {
                            Circle()
                                .fill(focusAnalysis.state.color.opacity(0.3))
                                .frame(width: 60, height: 60)
                                .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                                .opacity(pulseAnimation ? 0 : 1)
                                .animation(
                                    Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                                    value: pulseAnimation
                                )
                        }

                        Image(systemName: focusAnalysis.state.icon)
                            .font(.system(size: 32))
                            .foregroundColor(focusAnalysis.state.color)
                    }
                    .frame(width: 60, height: 60)

                    // 메시지
                    VStack(alignment: .leading, spacing: 4) {
                        Text(focusAnalysis.state.message)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        // 상세 정보 (Ready 상태가 아닐 때만)
                        if focusAnalysis.state != .ready && focusAnalysis.state != .notDetected {
                            HStack(spacing: 12) {
                                if focusAnalysis.coverage > 0 {
                                    Label(
                                        "\(Int(focusAnalysis.coverage * 100))%",
                                        systemImage: "viewfinder"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                }

                                if focusAnalysis.averageDepth > 0 {
                                    Label(
                                        String(format: "%.1fm", focusAnalysis.averageDepth),
                                        systemImage: "ruler"
                                    )
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                                }
                            }
                        }
                    }

                    Spacer()
                }

                // 진행 바 (Ready 상태가 아닐 때)
                if focusAnalysis.state != .ready && focusAnalysis.state != .notDetected {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // 배경
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.2))
                                .frame(height: 6)

                            // 진행도
                            RoundedRectangle(cornerRadius: 4)
                                .fill(progressColor)
                                .frame(
                                    width: geometry.size.width * CGFloat(progressValue),
                                    height: 6
                                )
                        }
                    }
                    .frame(height: 6)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(focusAnalysis.state.color, lineWidth: 2)
                    )
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 120)
        }
        .onChange(of: foregroundMask) { oldValue, newValue in
            analyzeFocus()
        }
        .onChange(of: depthData) { oldValue, newValue in
            analyzeFocus()
        }
        .onAppear {
            pulseAnimation = true
        }
    }

    // MARK: - Helpers

    /// 진행도 값 (0.0 ~ 1.0)
    private var progressValue: Float {
        switch focusAnalysis.state {
        case .tooSmall, .tooFar:
            // 너무 작거나 멀면: coverage가 클수록 좋음
            return min(focusAnalysis.coverage * 2, 1.0)
        case .tooLarge, .tooClose:
            // 너무 크거나 가까우면: coverage가 작을수록 좋음
            return max(1.0 - focusAnalysis.coverage, 0.0)
        default:
            return focusAnalysis.confidence
        }
    }

    /// 진행도 색상
    private var progressColor: Color {
        if progressValue > 0.7 {
            return .green
        } else if progressValue > 0.4 {
            return .orange
        } else {
            return .red
        }
    }

    /// 포커싱 상태 분석
    private func analyzeFocus() {
        guard case .normal = trackingState else {
            focusAnalysis = .default
            return
        }

        guard let mask = foregroundMask else {
            focusAnalysis = .default
            return
        }

        let depth = depthData
        Self.analysisQueue.async {
            let coverage = Self.calculateMaskCoverage(mask, sampleStride: Self.maskSampleStride)
            let avgDepth = Self.calculateAverageDepth(mask: mask, depthMap: depth, sampleStride: Self.maskSampleStride)
            let state = Self.determineFocusState(coverage: coverage, depth: avgDepth)
            let confidence = Self.calculateConfidence(coverage: coverage, depth: avgDepth, state: state)

            DispatchQueue.main.async {
                self.focusAnalysis = FocusAnalysis(
                    state: state,
                    coverage: coverage,
                    averageDepth: avgDepth,
                    confidence: confidence
                )
            }
        }
    }

    /// 마스크 커버리지 계산
    private static func calculateMaskCoverage(_ mask: CVPixelBuffer, sampleStride: Int = 1) -> Float {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let step = max(sampleStride, 1)

        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else {
            return 0.0
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var sampledPixels = 0
        var foregroundPixels = 0

        for y in stride(from: 0, to: height, by: step) {
            let rowPointer = buffer + y * bytesPerRow
            for x in stride(from: 0, to: width, by: step) {
                if rowPointer[x] > 128 {
                    foregroundPixels += 1
                }
                sampledPixels += 1
            }
        }

        guard sampledPixels > 0 else {
            return 0.0
        }

        return Float(foregroundPixels) / Float(sampledPixels)
    }

    /// 평균 깊이 계산
    private static func calculateAverageDepth(mask: CVPixelBuffer, depthMap: CVPixelBuffer?, sampleStride: Int = 1) -> Float {
        guard let depthMap = depthMap else { return 0 }

        CVPixelBufferLockBaseAddress(mask, .readOnly)
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(mask, .readOnly)
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)

        guard let maskAddress = CVPixelBufferGetBaseAddress(mask),
              let depthAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return 0
        }

        let maskBytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let depthBytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let maskBuffer = maskAddress.assumingMemoryBound(to: UInt8.self)
        let depthBuffer = depthAddress.assumingMemoryBound(to: Float32.self)
        let step = max(sampleStride, 1)

        let depthRowStride = depthBytesPerRow / MemoryLayout<Float32>.stride

        var totalDepth: Float = 0
        var count = 0

        for y in stride(from: 0, to: maskHeight, by: step) {
            let maskRow = maskBuffer + y * maskBytesPerRow
            let depthY = min(depthHeight - 1, y * depthHeight / max(maskHeight, 1))
            let depthRow = depthBuffer + depthY * depthRowStride

            for x in stride(from: 0, to: maskWidth, by: step) {
                if maskRow[x] > 128 {
                    let depthX = min(depthWidth - 1, x * depthWidth / max(maskWidth, 1))
                    let depth = depthRow[depthX]

                    if depth > 0 && depth.isFinite {
                        totalDepth += depth
                        count += 1
                    }
                }
            }
        }

        return count > 0 ? totalDepth / Float(count) : 0
    }

    /// 포커싱 상태 결정
    private static func determineFocusState(coverage: Float, depth: Float) -> FocusState {
        // 커버리지 기준 (반바지 등 작은 의류를 위해 매우 완화)
        let idealCoverageMin: Float = 0.05  // 최소 5% (매우 작은 의류 대응)
        let idealCoverageMax: Float = 0.80  // 최대 80%
        let goodCoverageMin: Float = 0.08   // 좋은 범위 최소 8%
        let goodCoverageMax: Float = 0.70   // 좋은 범위 최대 70%

        // 거리 기준 (미터) - 거리 우선 판단
        let idealDepthMin: Float = 0.3      // 최소 30cm
        let idealDepthMax: Float = 2.0      // 최대 2.0m
        let goodDepthMin: Float = 0.4       // 좋은 범위 최소 40cm
        let goodDepthMax: Float = 1.5       // 좋은 범위 최대 1.5m

        // 1. 깊이 우선 체크 (깊이 데이터가 있을 때)
        if depth > 0 {
            // 너무 가까우면 커버리지 무시하고 경고
            if depth < idealDepthMin {
                return .tooClose
            }
            // 너무 멀면 커버리지 무시하고 경고
            if depth > idealDepthMax {
                return .tooFar
            }

            // 최적 거리 범위 내면 커버리지 관대하게 판단
            if depth >= goodDepthMin && depth <= goodDepthMax {
                // 커버리지가 극단적이지 않으면 OK
                if coverage >= idealCoverageMin && coverage <= idealCoverageMax {
                    return .ready
                }
            }

            // 거리는 괜찮은데 커버리지가 문제
            if coverage > idealCoverageMax {
                return .tooLarge
            }
            if coverage < idealCoverageMin {
                return .tooSmall
            }
        } else {
            // 깊이 데이터 없으면 커버리지만으로 판단
            if coverage >= goodCoverageMin && coverage <= goodCoverageMax {
                return .ready
            }
            if coverage > idealCoverageMax {
                return .tooLarge
            }
            if coverage < idealCoverageMin {
                return .tooSmall
            }
        }

        // 기본값: 거리 기준 판단
        if depth > 0 {
            if depth < goodDepthMin {
                return .tooClose
            }
            if depth > goodDepthMax {
                return .tooFar
            }
        }

        return .ready  // 모든 조건이 애매하면 촬영 허용
    }

    /// 신뢰도 계산
    private static func calculateConfidence(coverage: Float, depth: Float, state: FocusState) -> Float {
        if state == .ready {
            return 1.0
        }

        // 커버리지 점수 (0.0 ~ 1.0) - 매우 완화된 임계값
        let coverageScore: Float
        if coverage < 0.05 {
            coverageScore = coverage / 0.05
        } else if coverage > 0.80 {
            coverageScore = max(0, 1.0 - (coverage - 0.80) / 0.20)
        } else {
            coverageScore = 1.0
        }

        // 깊이 점수 (0.0 ~ 1.0) - 거리 우선
        let depthScore: Float
        if depth > 0 {
            if depth < 0.3 {
                depthScore = depth / 0.3
            } else if depth > 2.0 {
                depthScore = max(0, 1.0 - (depth - 2.0) / 2.0)
            } else {
                depthScore = 1.0
            }
        } else {
            depthScore = 0.7  // 깊이 데이터 없으면 높은 값 (더 관대)
        }

        // 깊이를 더 중요하게 (60% vs 40%)
        return (depthScore * 0.6) + (coverageScore * 0.4)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.edgesIgnoringSafeArea(.all)

        ObjectFocusGuide(
            foregroundMask: nil,
            depthData: nil,
            trackingState: .normal
        )
    }
}

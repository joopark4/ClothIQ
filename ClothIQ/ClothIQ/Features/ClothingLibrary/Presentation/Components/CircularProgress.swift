//
//  CircularProgress.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  원형 진행률을 시각적으로 표시하는 재사용 가능한 컴포넌트입니다.
//  진행률에 따라 색상이 변경됩니다.
//

import SwiftUI

/// 원형 진행률 표시 컴포넌트
struct CircularProgress: View {
    let progress: Double
    let lineWidth: CGFloat
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
                .frame(width: size, height: size)

            Text("\(Int(progress * 100))%")
                .font(.system(size: size * 0.25))
                .fontWeight(.semibold)
                .foregroundColor(progressColor)
        }
    }

    private var progressColor: Color {
        switch progress {
        case 1.0:
            return .green
        case 0.5..<1.0:
            return .blue
        default:
            return .orange
        }
    }
}

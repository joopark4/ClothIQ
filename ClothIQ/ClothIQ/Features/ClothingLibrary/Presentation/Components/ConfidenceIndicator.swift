//
//  ConfidenceIndicator.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  측정 신뢰도를 시각적으로 표시하는 재사용 가능한 컴포넌트입니다.
//  신뢰도 수준에 따라 색상이 변경됩니다.
//

import SwiftUI

/// 신뢰도 표시 컴포넌트
struct ConfidenceIndicator: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark.shield.fill")
                .font(.caption)

            Text("\(Int(confidence * 100))%")
                .font(.caption)
        }
        .foregroundColor(confidenceColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(confidenceColor.opacity(0.1))
        )
    }

    private var confidenceColor: Color {
        switch confidence {
        case 0.9...1.0:
            return .green
        case 0.7..<0.9:
            return .blue
        case 0.5..<0.7:
            return .orange
        default:
            return .red
        }
    }
}

//
//  MeasurementTypeSelectionView.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  측정 항목 선택 UI 컴포넌트입니다.
//  의류 타입에 따른 필수 측정 항목을 표시하고 선택할 수 있습니다.
//
//  Key Responsibilities:
//  - 측정 항목 목록 표시
//  - 완료/미완료 상태 표시
//  - 현재 선택된 항목 하이라이트
//  - 측정 가이드 표시
//

import SwiftUI

/// 측정 항목 선택 뷰
///
/// 의류 타입에 따른 측정 항목을 표시하고 선택할 수 있는 UI입니다.
///
struct MeasurementTypeSelectionView: View {
    /// 의류 타입
    let clothingType: ClothingType

    /// 현재 측정값 딕셔너리
    let measurements: [MeasurementType: Double]

    /// 현재 선택된 측정 타입
    let selectedType: MeasurementType?

    /// 측정 항목 선택 콜백
    var onSelect: (MeasurementType) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            headerView
                .padding()
                .background(.ultraThinMaterial)

            Divider()

            // 측정 항목 목록
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(clothingType.requiredMeasurements, id: \.self) { type in
                        MeasurementTypeRow(
                            type: type,
                            value: measurements[type],
                            isSelected: selectedType == type,
                            onTap: { onSelect(type) }
                        )
                    }
                }
                .padding()
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(20)
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("측정 항목")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("\(completedCount)/\(totalCount) 완료")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 진행률 원형 표시
            CircularProgressView(
                progress: progress,
                lineWidth: 4
            )
            .frame(width: 40, height: 40)
        }
    }

    // MARK: - Computed Properties

    private var totalCount: Int {
        clothingType.requiredMeasurements.count
    }

    private var completedCount: Int {
        measurements.count
    }

    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }
}

// MARK: - Measurement Type Row

/// 측정 항목 행
private struct MeasurementTypeRow: View {
    let type: MeasurementType
    let value: Double?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 상태 아이콘
                statusIcon
                    .frame(width: 24, height: 24)

                // 측정 항목 정보
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(.primary)

                    if let value = value {
                        Text(String(format: "%.1f cm", value))
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text(type.measurementGuide)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 화살표
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Computed Properties

    private var statusIcon: some View {
        Group {
            if let _ = value {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.gray)
            }
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.blue.opacity(0.1)
        } else if value != nil {
            return Color.green.opacity(0.05)
        } else {
            return Color.gray.opacity(0.05)
        }
    }

    private var borderColor: Color {
        if isSelected {
            return .blue
        } else if value != nil {
            return .green.opacity(0.3)
        } else {
            return .gray.opacity(0.2)
        }
    }
}

// MARK: - Circular Progress View

/// 원형 진행률 표시
private struct CircularProgressView: View {
    let progress: Double
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            // 배경 원
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)

            // 진행률 원
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

            // 퍼센트 텍스트
            Text("\(Int(progress * 100))%")
                .font(.caption2)
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

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.edgesIgnoringSafeArea(.all)

        MeasurementTypeSelectionView(
            clothingType: .shortSleeve,
            measurements: [
                .shoulderWidth: 45.0,
                .chestCircumference: 95.0
            ],
            selectedType: .sleeveLength,
            onSelect: { type in
            }
        )
        .frame(height: 400)
        .padding()
    }
}

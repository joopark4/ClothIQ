//
//  MeasurementRow.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  측정값 행을 표시하는 재사용 가능한 컴포넌트입니다.
//  측정 타입, 값, 신뢰도, 날짜 정보를 시각적으로 표시합니다.
//

import SwiftUI

/// 측정값 행 컴포넌트
struct MeasurementRow: View {
    let measurement: MeasurementModel
    var isSelected: Bool = false

    var body: some View {
        HStack {
            // 측정 아이콘 및 선택 표시
            ZStack {
                Circle()
                    .fill(isSelected ? measurementColor.opacity(0.2) : Color.clear)
                    .frame(width: 36, height: 36)

                Image(systemName: measurementIcon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? measurementColor : .secondary)
            }
            .animation(.spring(response: 0.3), value: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                Text(measurementType?.displayName ?? measurement.type)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? measurementColor : .primary)

                HStack(spacing: 4) {
                    Text(measurement.formattedCalibratedValue())
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? measurementColor : .blue)

                    // 신뢰도 표시
                    ConfidenceIndicator(confidence: measurement.confidence)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(measurement.measuredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if measurement.hasCoordinates {
                    Image(systemName: "location.circle.fill")
                        .font(.caption)
                        .foregroundColor(isSelected ? measurementColor : .gray)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? measurementColor.opacity(0.1) : Color.clear)
        )
        .animation(.spring(response: 0.3), value: isSelected)
    }

    private var measurementType: MeasurementType? {
        MeasurementType(rawValue: measurement.type)
    }

    private var measurementIcon: String {
        switch measurement.type {
        case "shoulder_width":
            return "arrow.left.and.right"
        case "chest_circumference", "waist_circumference", "hip_circumference":
            return "circle.dashed"
        case "total_length", "sleeve_length", "inseam", "outseam":
            return "arrow.up.and.down"
        case "arm_circumference", "thigh_circumference", "knee_circumference":
            return "circle"
        case "rise":
            return "arrow.up.to.line"
        case "hem", "hem_width":
            return "arrow.down.to.line"
        case "neck_circumference":
            return "person.crop.circle"
        default:
            return "ruler"
        }
    }

    private var measurementColor: Color {
        // 측정 타입별 색상 (MeasurementLinesOverlay와 동일)
        switch measurement.type {
        // 상의 측정 항목
        case "shoulder_width":
            return .blue
        case "chest_circumference":
            return .green
        case "total_length":
            return .orange
        case "sleeve_length":
            return .purple
        case "arm_circumference":
            return .cyan
        case "neck_circumference":
            return .indigo

        // 하의 측정 항목
        case "waist_circumference":
            return .red
        case "hip_circumference":
            return .green
        case "rise":
            return .purple
        case "hem":
            return .brown
        case "thigh_circumference":
            return .cyan
        case "inseam":
            return .indigo
        case "outseam":
            return .mint
        case "knee_circumference":
            return .pink

        // 기본값
        default:
            return .gray
        }
    }
}

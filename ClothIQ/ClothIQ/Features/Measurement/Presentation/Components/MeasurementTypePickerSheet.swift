//
//  MeasurementTypePickerSheet.swift
//  ClothIQ
//
//  Created on 2025-11-12
//
//  Description:
//  AR 실시간 측정에서 측정 타입을 선택하기 위한 시트입니다.
//  의류 타입에 따른 필수/선택 측정 항목을 표시합니다.
//

import SwiftUI

/// 측정 타입 선택 시트
struct MeasurementTypePickerSheet: View {

    // MARK: - Properties

    let clothingType: ClothingType
    let onSelect: (MeasurementType) -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // 필수 항목
                Section {
                    ForEach(clothingType.requiredMeasurements, id: \.self) { type in
                        measurementTypeRow(type: type, isRequired: true)
                    }
                } header: {
                    Text("필수 측정 항목")
                        .font(.headline)
                }

                // 선택 항목
                if !clothingType.optionalMeasurements.isEmpty {
                    Section {
                        ForEach(clothingType.optionalMeasurements, id: \.self) { type in
                            measurementTypeRow(type: type, isRequired: false)
                        }
                    } header: {
                        Text("선택 측정 항목")
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("측정 항목 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - View Components

    @ViewBuilder
    private func measurementTypeRow(type: MeasurementType, isRequired: Bool) -> some View {
        Button {
            onSelect(type)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                // 아이콘
                Image(systemName: iconName(for: type))
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 32)

                // 측정 항목 정보
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(type.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        if isRequired {
                            Text("필수")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .cornerRadius(4)
                        }
                    }

                    Text(type.measurementGuide)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                // 화살표
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Helper Methods

    /// 측정 타입에 따른 아이콘 이름
    private func iconName(for type: MeasurementType) -> String {
        switch type {
        case .shoulderWidth:
            return "arrow.left.and.right"
        case .chestCircumference:
            return "circle"
        case .waistCircumference:
            return "circle.dotted"
        case .hipCircumference:
            return "circle.dashed"
        case .totalLength:
            return "arrow.up.and.down"
        case .sleeveLength:
            return "arrow.right"
        case .armCircumference:
            return "circle.hexagonpath"
        case .neckCircumference:
            return "circle.grid.2x2"
        case .cuffCircumference:
            return "circle.bottomhalf.filled"
        case .rise:
            return "arrow.up.to.line"
        case .hem:
            return "arrow.down.to.line"
        case .thighCircumference:
            return "circle.hexagongrid"
        }
    }
}

// MARK: - Preview

#Preview {
    MeasurementTypePickerSheet(
        clothingType: .shortSleeve,
        onSelect: { type in
            print("선택됨: \(type.displayName)")
        }
    )
}

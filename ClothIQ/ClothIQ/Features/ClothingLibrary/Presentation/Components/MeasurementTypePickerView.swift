//
//  MeasurementTypePickerView.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  측정 항목 선택 UI입니다.
//  현재 의류 타입의 필수/선택 측정 항목을 표시합니다.
//

import SwiftUI

/// 측정 항목 선택 뷰
struct MeasurementTypePickerView: View {

    // MARK: - Properties

    let clothingType: ClothingType
    let existingMeasurements: [String]  // 이미 측정된 항목들
    @Binding var selectedType: MeasurementType?

    // MARK: - Body

    var body: some View {
        Menu {
            // 필수 항목
            Section("필수 측정 항목") {
                ForEach(clothingType.requiredMeasurements, id: \.self) { type in
                    Button {
                        selectedType = type
                    } label: {
                        HStack {
                            // 현재 선택된 항목 표시
                            if selectedType == type {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                            Text(type.displayName)
                            Spacer()
                            // 이미 측정된 항목 표시
                            if existingMeasurements.contains(type.rawValue) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            // 선택 항목
            if !clothingType.optionalMeasurements.isEmpty {
                Section("선택 측정 항목") {
                    ForEach(clothingType.optionalMeasurements, id: \.self) { type in
                        Button {
                            selectedType = type
                        } label: {
                            HStack {
                                // 현재 선택된 항목 표시
                                if selectedType == type {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                                Text(type.displayName)
                                Spacer()
                                // 이미 측정된 항목 표시
                                if existingMeasurements.contains(type.rawValue) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "ruler")
                    .font(.body)

                if let selectedType = selectedType {
                    Text(selectedType.displayName)
                        .fontWeight(.medium)
                } else {
                    Text("측정 항목 선택")
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selectedType: MeasurementType? = nil

    VStack {
        MeasurementTypePickerView(
            clothingType: .shortSleeve,
            existingMeasurements: [
                MeasurementType.shoulderWidth.rawValue,
                MeasurementType.chestCircumference.rawValue
            ],
            selectedType: $selectedType
        )

        if let selectedType = selectedType {
            Text("선택됨: \(selectedType.displayName)")
                .padding()
        }
    }
}

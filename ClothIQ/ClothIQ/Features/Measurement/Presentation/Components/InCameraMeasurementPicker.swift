//
//  InCameraMeasurementPicker.swift
//  ClothIQ
//
//  Created on 2026-02-22
//
//  Description:
//  카메라 뷰 내에서 의류 타입 및 측정 항목을 선택할 수 있는 오버레이 컴포넌트입니다.
//  칩(Chip) 기반 UI를 통해 측정할 항목을 시각적으로 명확하게 파악할 수 있습니다.
//

import SwiftUI

struct InCameraMeasurementPicker: View {
    let clothingType: ClothingType
    let onClothingTypeChanged: (ClothingType) -> Void
    let onMeasurementTypeSelected: (MeasurementType) -> Void
    @Binding var activeMeasurementType: MeasurementType?
    let completedTypes: [MeasurementType]
    
    var body: some View {
        VStack(spacing: 12) {
            // 의류 타입 메뉴
            Menu {
                ForEach(ClothingType.allCases, id: \.self) { type in
                    Button(action: {
                        onClothingTypeChanged(type)
                    }) {
                        Text(type.displayName)
                    }
                }
            } label: {
                HStack {
                    Text(clothingType.displayName)
                        .font(.headline)
                        .foregroundColor(.white)
                    Image(systemName: "chevron.down")
                        .foregroundColor(.white)
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
            }

            // 측정 항목 칩 스크롤 뷰
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(clothingType.requiredMeasurements, id: \.self) { type in
                        Button(action: {
                            onMeasurementTypeSelected(type)
                        }) {
                            HStack(spacing: 4) {
                                if completedTypes.contains(type) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(activeMeasurementType == type ? .black : .green)
                                        .font(.system(size: 12))
                                }
                                Text(type.displayName)
                            }
                            .font(.system(size: 14, weight: activeMeasurementType == type ? .bold : .medium))
                            .foregroundColor(activeMeasurementType == type ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(activeMeasurementType == type ? Color.green : Color.black.opacity(0.5))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(activeMeasurementType == type ? Color.green : Color.white.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.5), Color.clear], startPoint: .top, endPoint: .bottom)
        )
    }
}

#Preview {
    InCameraMeasurementPicker(
        clothingType: .shortSleeve,
        onClothingTypeChanged: { _ in },
        onMeasurementTypeSelected: { _ in },
        activeMeasurementType: .constant(.chestCircumference),
        completedTypes: [.shoulderWidth]
    )
}

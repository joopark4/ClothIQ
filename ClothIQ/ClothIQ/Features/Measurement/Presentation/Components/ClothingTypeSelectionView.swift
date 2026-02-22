//
//  ClothingTypeSelectionView.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  의류 타입 선택 화면입니다.
//  AR 촬영 시 의류 타입을 선택하는 데 사용됩니다.
//
//  Key Responsibilities:
//  - 의류 타입 목록 표시
//  - 타입 선택 및 콜백 호출
//

import SwiftUI

// MARK: - Clothing Type Selection View

/// 의류 타입 선택 화면
struct ClothingTypeSelectionView: View {
    let onSelect: (ClothingType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack {
                Button("취소") {
                    dismiss()
                }
                .foregroundColor(.blue)

                Spacer()

                Text("의류 타입 선택")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 44, height: 44)
            }
            .padding()

            Divider()

            // 의류 타입 목록
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(ClothingType.allCases, id: \.self) { type in
                        Button(action: {
                            onSelect(type)
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(type.displayName)
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text("필수 측정 항목: \(type.requiredMeasurements.count)개")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray6))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ClothingTypeSelectionView { type in
        print("Selected: \(type.displayName)")
    }
}

//
//  ClothingTypeEditorView.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  의류 타입 변경 화면입니다.
//  Sheet 형태로 표시되며, 5가지 의류 타입 중 하나를 선택할 수 있습니다.
//
//  Key Features:
//  - 5가지 의류 타입 선택
//  - 현재 타입 하이라이트
//  - 측정값 변경 경고
//  - 호환되는 측정값만 유지
//

import SwiftUI
import SwiftData

/// 의류 타입 변경 화면
struct ClothingTypeEditorView: View {

    // MARK: - Properties

    /// 의류 아이템
    let item: ClothingItemModel

    /// Model context
    @Environment(\.modelContext) private var modelContext

    /// Dismiss action
    @Environment(\.dismiss) private var dismiss

    /// 선택된 타입
    @State private var selectedType: ClothingType

    /// 확인 Alert 표시 여부
    @State private var showingConfirmation: Bool = false

    // MARK: - Initialization

    init(item: ClothingItemModel) {
        self.item = item
        self._selectedType = State(initialValue: item.clothingType ?? .shortSleeve)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 현재 타입 정보
                    currentTypeInfoSection

                    // 경고 메시지
                    if !item.measurements.isEmpty {
                        warningBanner
                    }

                    // 타입 선택 그리드
                    typeSelectionGrid
                }
                .padding()
            }
            .navigationTitle("의류 타입 변경")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("변경") {
                        if selectedType != item.clothingType {
                            showingConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(selectedType == item.clothingType)
                }
            }
            .alert("의류 타입 변경", isPresented: $showingConfirmation) {
                Button("변경", role: .destructive) {
                    changeClothingType()
                }
                Button("취소", role: .cancel) {}
            } message: {
                if item.measurements.isEmpty {
                    Text("의류 타입을 '\(selectedType.displayName)'(으)로 변경하시겠습니까?")
                } else {
                    Text("타입을 변경하면 호환되지 않는 측정값이 제거될 수 있습니다.\n\n변경하시겠습니까?")
                }
            }
        }
    }

    // MARK: - Subviews

    /// 현재 타입 정보 섹션
    private var currentTypeInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("현재 타입")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: item.clothingType?.iconName ?? "tshirt")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.clothingType?.displayName ?? "알 수 없음")
                        .font(.headline)

                    Text("필수 측정 항목: \(item.clothingType?.requiredMeasurements.count ?? 0)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 경고 배너
    private var warningBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("측정값 변경 경고")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("현재 \(item.measurements.count)개의 측정값이 있습니다.\n새 타입과 호환되지 않는 측정값은 제거됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 타입 선택 그리드
    private var typeSelectionGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("새 타입 선택")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(ClothingType.allCases, id: \.self) { type in
                    ClothingTypeCard(
                        type: type,
                        isSelected: selectedType == type,
                        isCurrent: item.clothingType == type
                    ) {
                        selectedType = type
                    }
                }
            }
        }
    }

    // MARK: - Actions

    /// 의류 타입 변경
    private func changeClothingType() {
        // 타입 업데이트
        item.type = selectedType.rawValue

        // 호환되지 않는 측정값 제거 (필수 + 선택 측정값 모두 고려)
        let newAllowedTypes = selectedType.requiredMeasurements + selectedType.optionalMeasurements
        let newAllowedTypeRawValues = newAllowedTypes.map { $0.rawValue }
        item.measurements.removeAll { measurement in
            !newAllowedTypeRawValues.contains(measurement.type)
        }

        // 업데이트 시간 갱신
        item.updatedAt = Date()

        // 저장
        do {
            try modelContext.save()
            dismiss()
        } catch {
        }
    }
}

// MARK: - Clothing Type Card

/// 의류 타입 선택 카드
struct ClothingTypeCard: View {
    let type: ClothingType
    let isSelected: Bool
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 12) {
                // 아이콘
                Image(systemName: type.iconName)
                    .font(.largeTitle)
                    .foregroundStyle(foregroundColor)

                // 타입 이름
                Text(type.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(foregroundColor)

                // 측정 항목 개수
                Text("\(type.requiredMeasurements.count)개 항목")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // 현재 타입 배지
                if isCurrent {
                    Text("현재")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor, lineWidth: isSelected ? 3 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        isSelected ? .white : .primary
    }

    private var backgroundColor: Color {
        if isSelected {
            return .blue
        } else if isCurrent {
            return Color(.systemGray6)
        } else {
            return Color(.systemGray5)
        }
    }

    private var borderColor: Color {
        isSelected ? .blue : Color(.systemGray4)
    }
}

// MARK: - ClothingType Extension

extension ClothingType {
    /// SF Symbol 아이콘 이름
    var iconName: String {
        switch self {
        case .shortSleeve:
            return "tshirt"
        case .longSleeve:
            return "tshirt.fill"
        case .shorts:
            return "figure.walk"
        case .pants:
            return "figure.stand"
        case .skirt:
            return "figure.dress.line.vertical.figure"
        }
    }
}

// MARK: - Previews

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: ClothingItemModel.self, configurations: config)

    let item = ClothingItemModel(
        type: ClothingType.shortSleeve.rawValue,
        imagePath: nil,
        notes: nil
    )

    // 측정값 추가
    let measurement1 = MeasurementModel(
        type: MeasurementType.shoulderWidth.rawValue,
        value: 45.0
    )
    let measurement2 = MeasurementModel(
        type: MeasurementType.chestCircumference.rawValue,
        value: 100.0
    )
    item.measurements.append(measurement1)
    item.measurements.append(measurement2)

    container.mainContext.insert(item)

    return ClothingTypeEditorView(item: item)
        .modelContainer(container)
}

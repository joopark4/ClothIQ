//
//  ClothingItemCard.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  의류 아이템 카드 컴포넌트입니다.
//  리스트에서 각 의류 아이템을 표시하는 재사용 가능한 뷰입니다.
//

import SwiftUI
import SwiftData

/// 의류 아이템 카드 컴포넌트
struct ClothingItemCard: View {
    let item: ClothingItemModel

    var body: some View {
        HStack(spacing: 16) {
            // 썸네일 이미지
            thumbnailView

            // 아이템 정보
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.clothingType?.displayName ?? "알 수 없음")
                        .font(.headline)
                        .foregroundColor(.primary)

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }

                HStack {
                    Label(
                        "\(item.completedMeasurements)/\(item.totalRequiredMeasurements)",
                        systemImage: "ruler"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Spacer()

                    // 진행률 표시
                    ProgressView(value: item.completionProgress) {
                        Text("\(Int(item.completionProgress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .progressViewStyle(LinearProgressViewStyle(tint: progressColor))
                    .frame(width: 80)
                }

                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
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
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Thumbnail View

    private var thumbnailView: some View {
        Group {
            if let image = item.loadImage() {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: "tshirt")
                        .font(.title)
                        .foregroundColor(.gray.opacity(0.3))
                }
            }
        }
    }

    private var progressColor: Color {
        switch item.completionProgress {
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
    ClothingItemCard(item: ClothingItemModel(
        type: ClothingType.shortSleeve.rawValue,
        imagePath: nil,
        measurements: [],
        tags: [],
        notes: "테스트 아이템"
    ))
    .padding()
}
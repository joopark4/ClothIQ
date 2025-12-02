//
//  MLTrainingStatisticsView.swift
//  ClothIQ
//
//  ML 학습 데이터 통계를 보여주는 뷰
//

import SwiftUI
import Charts

struct MLTrainingStatisticsView: View {
    @StateObject private var collector = MLTrainingDataCollector.shared
    @State private var selectedClothingType: ClothingType?
    @State private var selectedMeasurementType: MeasurementType?
    @Environment(\.dismiss) private var dismiss

    private var clothingTypeData: [(ClothingType, Int)] {
        let types = ClothingType.allCases
        return types.compactMap { type in
            let count = collector.getSampleCount(for: type)
            return count > 0 ? (type, count) : nil
        }
    }

    private var measurementTypeData: [(MeasurementType, Int)] {
        // 모든 측정 타입별 샘플 수 계산
        let measurements = [
            MeasurementType.shoulderWidth,
            .chestCircumference,
            .totalLength,
            .sleeveLength,
            .waistCircumference,
            .hipCircumference,
            .rise,
            .hem,
            .thighCircumference
        ]

        return measurements.compactMap { type in
            let count = collector.getSampleCount(forMeasurement: type)
            return count > 0 ? (type, count) : nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - 개요 카드
                    overviewCard

                    // MARK: - 의류 타입별 차트
                    if !clothingTypeData.isEmpty {
                        clothingTypeChart
                    }

                    // MARK: - 측정 타입별 차트
                    if !measurementTypeData.isEmpty {
                        measurementTypeChart
                    }

                    // MARK: - 품질 지표
                    qualityMetricsCard

                    // MARK: - 최근 수집 기록
                    recentCollectionsCard
                }
                .padding()
            }
            .navigationTitle("학습 데이터 통계")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Components

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("전체 개요")
                .font(.headline)

            HStack(spacing: 20) {
                StatisticItem(
                    title: "총 샘플",
                    value: "\(collector.totalSamples)",
                    icon: "doc.text.fill",
                    color: .blue
                )

                StatisticItem(
                    title: "사용자 수정",
                    value: "\(collector.userCorrectedSamples)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )

                StatisticItem(
                    title: "정확도",
                    value: String(format: "%.1f%%", collector.averageConfidence * 100),
                    icon: "target",
                    color: .orange
                )
            }

            // 진행 바
            VStack(alignment: .leading, spacing: 8) {
                Text("목표 달성도")
                    .font(.caption)
                    .foregroundColor(.secondary)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geometry.size.width * min(Double(collector.totalSamples) / 1000.0, 1.0), height: 8)
                    }
                }
                .frame(height: 8)

                Text("\(collector.totalSamples) / 1000 샘플 (권장)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var clothingTypeChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("의류 타입별 분포")
                .font(.headline)

            Chart(clothingTypeData, id: \.0) { item in
                BarMark(
                    x: .value("수량", item.1),
                    y: .value("타입", item.0.displayName)
                )
                .foregroundStyle(Color.blue.gradient)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(item.1)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: CGFloat(clothingTypeData.count) * 40)
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var measurementTypeChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("측정 항목별 분포")
                .font(.headline)

            Chart(measurementTypeData, id: \.0) { item in
                SectorMark(
                    angle: .value("수량", item.1),
                    innerRadius: .ratio(0.5),
                    angularInset: 1.5
                )
                .foregroundStyle(by: .value("타입", item.0.displayName))
                .opacity(0.8)
            }
            .frame(height: 240)
            .chartLegend(position: .bottom, spacing: 10)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var qualityMetricsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("데이터 품질 지표")
                .font(.headline)

            VStack(spacing: 12) {
                QualityMetricRow(
                    title: "평균 신뢰도",
                    value: Double(collector.averageConfidence),
                    threshold: 0.7,
                    format: "%.1f%%"
                )

                QualityMetricRow(
                    title: "사용자 수정 비율",
                    value: Double(collector.userCorrectedSamples) / max(Double(collector.totalSamples), 1.0),
                    threshold: 0.3,
                    format: "%.1f%%"
                )

                QualityMetricRow(
                    title: "데이터 다양성",
                    value: Double(clothingTypeData.count) / Double(ClothingType.allCases.count),
                    threshold: 0.5,
                    format: "%.1f%%"
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var recentCollectionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("최근 수집 기록")
                .font(.headline)

            if let recentSamples = collector.getRecentSamples(limit: 5), !recentSamples.isEmpty {
                ForEach(recentSamples.indices, id: \.self) { index in
                    let sample = recentSamples[index]
                    HStack {
                        Image(systemName: sample.isUserCorrected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(sample.isUserCorrected ? .green : .gray)
                            .font(.caption)

                        Text(sample.clothingType)
                            .font(.caption)
                            .lineLimit(1)

                        Spacer()

                        Text(sample.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    if index < recentSamples.count - 1 {
                        Divider()
                    }
                }
            } else {
                Text("아직 수집된 데이터가 없습니다")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// MARK: - Supporting Views

struct StatisticItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title3.bold())

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct QualityMetricRow: View {
    let title: String
    let value: Double
    let threshold: Double
    let format: String

    private var color: Color {
        if value >= threshold {
            return .green
        } else if value >= threshold * 0.7 {
            return .orange
        } else {
            return .red
        }
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)

            Spacer()

            HStack(spacing: 8) {
                Text(String(format: format, value * 100))
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(color)

                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

#Preview {
    MLTrainingStatisticsView()
}
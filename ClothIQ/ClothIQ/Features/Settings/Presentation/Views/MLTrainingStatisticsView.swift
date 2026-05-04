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

    private var typeReadinessData: [MLTrainingTypeReadiness] {
        collector.getTypeTrainingReadiness()
    }

    private var collectionGapSummary: MLTrainingCollectionGapSummary {
        collector.getCollectionGapSummary()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - 개요 카드
                    overviewCard

                    collectionPriorityCard

                    // MARK: - 의류 타입별 차트
                    if !clothingTypeData.isEmpty {
                        clothingTypeChart
                    }

                    typeReadinessCard

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
        let summary = collectionGapSummary

        return VStack(alignment: .leading, spacing: 16) {
            Text("전체 개요")
                .font(.headline)

            HStack(spacing: 20) {
                StatisticItem(
                    title: "고유 촬영",
                    value: "\(collector.usableModelTrainingSamples)",
                    icon: "camera.fill",
                    color: .blue
                )

                StatisticItem(
                    title: "고유 보정",
                    value: "\(collector.uniqueUserCorrectedModelTrainingSamples)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )

                StatisticItem(
                    title: "완료 타입",
                    value: "\(summary.completedTypeCount)/\(ClothingType.allCases.count)",
                    icon: "shippingbox.fill",
                    color: .orange
                )
            }

            // 진행 바
            VStack(alignment: .leading, spacing: 8) {
                Text("학습 수집 진행도")
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
                            .frame(width: geometry.size.width * summary.collectionProgress, height: 8)
                    }
                }
                .frame(height: 8)

                Text(
                    "\(summary.totalSatisfiedModelTrainingSamples)/\(summary.totalRequiredModelTrainingSamples) 고유 촬영"
                    + " · \(summary.totalSatisfiedUserCorrectedSamples)/\(summary.totalRequiredUserCorrectedSamples) 고유 보정"
                )
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }

    private var collectionPriorityCard: some View {
        let summary = collectionGapSummary

        return VStack(alignment: .leading, spacing: 16) {
            Text("다음 수집 우선순위")
                .font(.headline)

            HStack(spacing: 20) {
                StatisticItem(
                    title: "추가 촬영",
                    value: "\(summary.totalNeededModelTrainingSamples)",
                    icon: "camera.fill",
                    color: .blue
                )

                StatisticItem(
                    title: "추가 보정",
                    value: "\(summary.totalNeededUserCorrectedSamples)",
                    icon: "hand.draw.fill",
                    color: .orange
                )

                StatisticItem(
                    title: "모델 없음",
                    value: "\(summary.missingCompiledModelCount)",
                    icon: "shippingbox.fill",
                    color: .purple
                )
            }

            if summary.nextTargets.isEmpty {
                Text("모든 의류 타입의 학습 준비가 완료되었습니다")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(summary.nextTargets, id: \.clothingType) { readiness in
                        CollectionTargetRow(readiness: readiness)

                        if readiness.clothingType != summary.nextTargets.last?.clothingType {
                            Divider()
                        }
                    }
                }
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

    private var typeReadinessCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("의류 타입별 학습 준비 상태")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(typeReadinessData, id: \.clothingType) { readiness in
                    TypeReadinessRow(readiness: readiness)

                    if readiness.clothingType != typeReadinessData.last?.clothingType {
                        Divider()
                    }
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
                    title: "고유 보정 비율",
                    value: Double(collector.uniqueUserCorrectedModelTrainingSamples)
                        / max(Double(collector.usableModelTrainingSamples), 1.0),
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

struct TypeReadinessRow: View {
    let readiness: MLTrainingTypeReadiness

    private var statusColor: Color {
        if readiness.modelDeploymentStatus.hasDocumentsCompiledModel || readiness.isReadyForModelTraining {
            return .green
        }

        if readiness.hasUsableLearnedPrior {
            return .orange
        }

        return .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(readiness.clothingType.displayName)
                    .font(.subheadline)

                Text(
                    "\(readiness.modelTrainingSamples)/\(readiness.minimumModelTrainingSamples) 고유 촬영"
                    + " · 보정 \(readiness.userCorrectedSamples)/\(readiness.minimumUserCorrectedSamples)"
                    + " · 부족 \(readiness.neededModelTrainingSamples)/\(readiness.neededUserCorrectedSamples)"
                    + " · prior \(readiness.learnedKeypointCount)/\(readiness.expectedKeypointCount)"
                )
                    .font(.caption)
                    .foregroundColor(.secondary)

                if !readiness.missingKeypointTypes.isEmpty {
                    Text("부족 키포인트: \(readiness.missingKeypointSummary)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(readiness.statusMessage)
                .font(.caption.weight(.semibold))
                .foregroundColor(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
    }
}

struct CollectionTargetRow: View {
    let readiness: MLTrainingTypeReadiness

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(readiness.clothingType.displayName)
                    .font(.subheadline)

                Spacer()

                Text(targetText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(.orange)
            }

            if !readiness.missingKeypointTypes.isEmpty {
                Text("부족 키포인트: \(readiness.missingKeypointSummary)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var targetText: String {
        var parts: [String] = []
        if readiness.neededModelTrainingSamples > 0 {
            parts.append("촬영 +\(readiness.neededModelTrainingSamples)")
        }
        if readiness.neededUserCorrectedSamples > 0 {
            parts.append("보정 +\(readiness.neededUserCorrectedSamples)")
        }
        if !readiness.modelDeploymentStatus.hasDocumentsCompiledModel,
           readiness.neededModelTrainingSamples == 0,
           readiness.neededUserCorrectedSamples == 0 {
            parts.append("모델 배포")
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    MLTrainingStatisticsView()
}

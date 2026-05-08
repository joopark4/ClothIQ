//
//  TrainingStatsView.swift
//  ClothIQ
//
//  Created on 2025-11-10
//
//  Description:
//  ML 학습 데이터 통계를 표시하는 뷰입니다.
//

import SwiftUI
import Charts

/// 학습 데이터 통계 뷰
struct TrainingStatsView: View {

    let statistics: TrainingDataStatistics

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 전체 통계 카드
                    overallStatsCard

                    // 학습 준비 상태
                    readinessCard

                    // 의류 타입별 분포
                    clothingDistributionCard

                    // 데이터 관리
                    dataManagementCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("학습 데이터 통계")
            .navigationBarTitleDisplayMode(.inline)
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

    /// 전체 통계 카드
    private var overallStatsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("전체 통계")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 30) {
                // 총 샘플 수
                VStack {
                    Text("\(statistics.totalSamples)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("총 샘플")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 50)

                // 사용자 수정 샘플
                VStack {
                    Text("\(statistics.usableModelTrainingSamples)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.green)
                    Text("학습 유효")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 50)

                // 평균 신뢰도
                VStack {
                    Text("\(Int(statistics.averageConfidence * 100))%")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.orange)
                    Text("평균 신뢰도")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 학습 준비 상태 카드
    private var readinessCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: statistics.isReadyForTraining ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(statistics.isReadyForTraining ? .green : .orange)
                Text("학습 준비 상태")
                    .font(.headline)
                Spacer()
            }

            if statistics.isReadyForTraining {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("충분한 데이터가 수집되었습니다")
                        .font(.subheadline)
                    Spacer()
                }

                Text("Mac의 외부 학습 워크플로우로 모델을 학습할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                    Text("더 많은 데이터가 필요합니다")
                        .font(.subheadline)
                    Spacer()
                }

                Text("최소 100개의 학습 유효 샘플이 필요합니다. 현재: \(statistics.usableModelTrainingSamples)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 의류 타입별 분포 카드
    private var clothingDistributionCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
                Text("의류 타입별 분포")
                    .font(.headline)
                Spacer()
            }

            ForEach(statistics.clothingTypeDistribution.sorted(by: { $0.value > $1.value }), id: \.key) { type, count in
                HStack {
                    Text(ClothingType(rawValue: type)?.displayName ?? type)
                        .font(.subheadline)
                    Spacer()

                    // 프로그레스 바
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 20)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.purple.opacity(0.7))
                                .frame(
                                    width: geometry.size.width * (CGFloat(count) / CGFloat(statistics.totalSamples)),
                                    height: 20
                                )
                        }
                    }
                    .frame(width: 100, height: 20)

                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
            }

            if statistics.clothingTypeDistribution.isEmpty {
                Text("아직 수집된 데이터가 없습니다")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 데이터 관리 카드
    private var dataManagementCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                Text("데이터 관리")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 8) {
                Button {
                    exportTrainingData()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("CreateML 형식으로 내보내기")
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!statistics.isReadyForTraining)

                Button(role: .destructive) {
                    clearTrainingData()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("학습 데이터 초기화")
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func exportTrainingData() {
        do {
            let url = try MLTrainingDataCollector.shared.exportForCreateML()
            print("✅ 학습 데이터 내보내기 성공: \(url)")
            // 실제로는 Share Sheet 등으로 파일 공유
        } catch {
            print("❌ 학습 데이터 내보내기 실패: \(error)")
        }
    }

    private func clearTrainingData() {
        MLTrainingDataCollector.shared.clearTrainingData()
        dismiss()
    }
}

// MARK: - Preview

struct TrainingStatsView_Previews: PreviewProvider {
    static var previews: some View {
        TrainingStatsView(
            statistics: TrainingDataStatistics(
                totalSamples: 156,
                usableModelTrainingSamples: 156,
                uniqueUserCorrectedModelTrainingSamples: 42,
                userCorrectedSamples: 42,
                clothingTypeDistribution: [
                    "short_sleeve": 45,
                    "long_sleeve": 38,
                    "pants": 35,
                    "shorts": 23,
                    "skirt": 15
                ],
                averageConfidence: 0.78,
                isReadyForTraining: true
            )
        )
    }
}

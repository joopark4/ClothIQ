//
//  ClothingDetailView+Sections.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  ClothingDetailView의 콘텐츠 섹션 빌더들입니다.
//  이미지, 기본 정보, 측정값, 메모, 액션 버튼 섹션을 포함합니다.
//

import SwiftUI
import SwiftData

extension ClothingDetailView {

    // MARK: - Image Section

    var imageSection: some View {
        Group {
            if let image = item.loadImage() {
                Button {
                    showingPhotoMeasurement = true
                } label: {
                    let normalizedImage = image.normalizedOrientation()
                    Image(uiImage: normalizedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 400)
                        .overlay {
                            // 측정 라인 오버레이
                            MeasurementLinesOverlay(
                                measurements: item.displayMeasurements,
                                imageSize: normalizedImage.size,
                                selectedMeasurement: $selectedMeasurement,
                                showLines: showMeasurementLines
                            )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        .overlay(alignment: .topLeading) {
                            // 진단 버튼 (이미지 3번 탭)
                            Button {
                                imageTapCount += 1
                                if imageTapCount >= 3 {
                                    printDiagnostics()
                                    imageTapCount = 0
                                    showingDebugDiagnostics = true
                                }
                            } label: {
                                Image(systemName: imageTapCount >= 1 ? "stethoscope.circle.fill" : "stethoscope.circle")
                                    .foregroundStyle(imageTapCount >= 1 ? .orange : .secondary)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .padding(12)
                            .opacity(imageTapCount >= 1 ? 1 : 0.5)
                        }
                        .overlay(alignment: .topTrailing) {
                            // 측정 라인 토글 버튼
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    showMeasurementLines.toggle()
                                }
                            } label: {
                                Image(systemName: showMeasurementLines ? "ruler.fill" : "ruler")
                                    .foregroundStyle(showMeasurementLines ? .blue : .primary)
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .padding(12)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            // 측정 모드 힌트
                            HStack(spacing: 6) {
                                Image(systemName: "hand.tap")
                                Text("탭하여 측정")
                            }
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(12)
                        }
                }
                .buttonStyle(.plain)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 300)

                    VStack(spacing: 16) {
                        Image(systemName: "tshirt")
                            .font(.system(size: 60))
                            .foregroundColor(.gray.opacity(0.3))

                        Text("이미지 없음")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }

    // MARK: - Basic Info Section

    var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 타이틀 편집 영역
            VStack(alignment: .leading, spacing: 8) {
                Text("이름")
                    .font(.caption)
                    .foregroundColor(.secondary)

                EditableTitleView(
                    title: $item.title,
                    placeholder: item.clothingType?.displayName ?? "의류 아이템"
                ) { _ in
                    item.updatedAt = Date()
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("의류 타입")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        showingTypeEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(item.clothingType?.displayName ?? "알 수 없음")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if item.isFavorite {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("진행률")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    CircularProgress(
                        progress: item.completionProgress,
                        lineWidth: 8,
                        size: 60
                    )
                }
            }

            Divider()

            HStack {
                Label(
                    item.createdAt.formatted(date: .abbreviated, time: .omitted),
                    systemImage: "calendar"
                )
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                if item.createdAt != item.updatedAt {
                    Label(
                        "수정: \(item.updatedAt.formatted(date: .abbreviated, time: .omitted))",
                        systemImage: "pencil"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Measurements Section

    var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("측정값")
                    .font(.headline)

                Spacer()

                // 측정값이 있을 때만 표시 상태 및 토글 버튼 표시
                if !item.displayMeasurements.isEmpty {
                    // 측정값 표시 상태 표시
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            showMeasurementLines.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showMeasurementLines ? "eye.fill" : "eye.slash.fill")
                                .font(.caption)
                            Text(showMeasurementLines ? "표시됨" : "숨김")
                                .font(.caption)
                        }
                        .foregroundColor(showMeasurementLines ? .blue : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(showMeasurementLines ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Text("\(item.completedMeasurements)/\(item.totalRequiredMeasurements)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if item.displayMeasurements.isEmpty {
                emptyMeasurementsView
            } else {
                measurementsList
            }
        }
    }

    var emptyMeasurementsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "ruler")
                .font(.title)
                .foregroundColor(.gray.opacity(0.3))

            Text("아직 측정값이 없습니다")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    var measurementsList: some View {
        VStack(spacing: 8) {
            ForEach(item.displayMeasurements) { measurement in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        // 이미 선택된 경우 해제, 아니면 선택
                        if selectedMeasurement?.id == measurement.id {
                            selectedMeasurement = nil
                        } else {
                            selectedMeasurement = measurement
                            // 측정 라인이 표시되지 않은 경우 자동으로 표시
                            if !showMeasurementLines {
                                showMeasurementLines = true
                            }
                        }
                    }
                } label: {
                    MeasurementRow(
                        measurement: measurement,
                        isSelected: selectedMeasurement?.id == measurement.id
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }

    // MARK: - Notes Section

    var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("메모")
                    .font(.headline)

                Spacer()

                Button(action: {
                    editingNote = item.notes ?? ""
                    showingEditNote = true
                }) {
                    Image(systemName: item.notes == nil ? "plus.circle" : "pencil")
                        .foregroundColor(.blue)
                }
            }

            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
            } else {
                Text("메모가 없습니다")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .italic()
            }
        }
    }

    // MARK: - Action Buttons

    var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(action: {
                    showingMeasurement = true
                }) {
                    Label("측정 추가", systemImage: "ruler")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: {
                    showingBatchAutoMeasurement = true
                }) {
                    Label("자동 측정", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(item.depthMapPath == nil ? Color.gray : Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(item.depthMapPath == nil)
            }

            HStack(spacing: 16) {
                Button(action: {
                    showingPhotoMeasurement = true
                }) {
                    Label("사진 측정", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(item.depthMapPath == nil ? Color.gray : Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(item.depthMapPath == nil)

                Button(action: shareItem) {
                    Label("공유", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        .padding(.top)
    }
}

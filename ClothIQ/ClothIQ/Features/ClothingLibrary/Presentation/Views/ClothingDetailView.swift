//
//  ClothingDetailView.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  의류 아이템 상세 정보를 표시하는 화면입니다.
//  배경 제거된 이미지와 측정값들을 시각적으로 보여줍니다.
//
//  Key Responsibilities:
//  - 의류 이미지 크게 표시
//  - 측정값 시각화
//  - 측정값 편집
//  - 메모 추가/편집
//  - 공유 및 삭제 기능
//

import SwiftUI
import SwiftData

/// 의류 아이템 상세보기 화면
struct ClothingDetailView: View {
    @Bindable var item: ClothingItemModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showingEditNote = false
    @State private var showingDeleteAlert = false
    @State private var showingMeasurement = false
    @State private var editingNote: String = ""

    // 새로운 기능 State 변수
    @State private var showingPhotoMeasurement = false
    @State private var showingTypeEditor = false

    // 측정 라인 표시 관련
    @State private var showMeasurementLines = false
    @State private var selectedMeasurement: MeasurementModel?

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad - 2열 레이아웃
                iPadLayout
            } else {
                // iPhone - 단일 컬럼
                iPhoneLayout
            }
        }
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        item.isFavorite.toggle()
                        item.updatedAt = Date()
                    } label: {
                        Label(
                            item.isFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                            systemImage: item.isFavorite ? "star.slash" : "star"
                        )
                    }

                    Button {
                        shareItem()
                    } label: {
                        Label("공유", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("의류 삭제", isPresented: $showingDeleteAlert) {
            Button("취소", role: .cancel) { }
            Button("삭제", role: .destructive) {
                deleteItem()
            }
        } message: {
            Text("이 의류 아이템을 삭제하시겠습니까? 이 작업은 취소할 수 없습니다.")
        }
        .modifier(AdaptiveSheet(isPresented: $showingEditNote) {
            NoteEditView(note: $editingNote) { newNote in
                item.notes = newNote.isEmpty ? nil : newNote
                item.updatedAt = Date()
            }
        })
        .sheet(isPresented: $showingMeasurement) {
            NavigationStack {
                MeasurementView(clothingType: item.clothingType)
            }
        }
        .fullScreenCover(isPresented: $showingPhotoMeasurement) {
            PhotoMeasurementView(item: item)
        }
        .sheet(isPresented: $showingTypeEditor) {
            ClothingTypeEditorView(item: item)
        }
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        ScrollView {
            VStack(spacing: 24) {
                imageSection
                basicInfoSection
                measurementsSection
                notesSection
                actionButtons
            }
            .padding()
        }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        GeometryReader { geometry in
            ScrollView {
                HStack(alignment: .top, spacing: 32) {
                    // 왼쪽: 이미지와 기본 정보
                    VStack(spacing: 24) {
                        imageSection
                            .frame(maxWidth: geometry.size.width * 0.45)

                        basicInfoSection

                        if geometry.size.width > 1000 {
                            actionButtons
                        }
                    }
                    .frame(width: geometry.size.width * 0.45)

                    // 오른쪽: 측정값과 메모
                    VStack(spacing: 24) {
                        measurementsSection
                        notesSection

                        if geometry.size.width <= 1000 {
                            actionButtons
                        }
                    }
                    .frame(width: geometry.size.width * 0.45)
                }
                .padding(32)
                .frame(minHeight: geometry.size.height)
            }
        }
    }

    // MARK: - Image Section

    private var imageSection: some View {
        Group {
            if let image = item.loadImage() {
                Button {
                    showingPhotoMeasurement = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 400)
                        .overlay {
                            // 측정 라인 오버레이
                            MeasurementLinesOverlay(
                                measurements: item.measurements,
                                imageSize: image.size,
                                selectedMeasurement: $selectedMeasurement,
                                showLines: showMeasurementLines
                            )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
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

    private var basicInfoSection: some View {
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

    private var measurementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("측정값")
                    .font(.headline)

                Spacer()

                Text("\(item.completedMeasurements)/\(item.totalRequiredMeasurements)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if item.measurements.isEmpty {
                emptyMeasurementsView
            } else {
                measurementsList
            }
        }
    }

    private var emptyMeasurementsView: some View {
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

    private var measurementsList: some View {
        VStack(spacing: 8) {
            ForEach(item.measurements.sorted(by: { $0.measuredAt < $1.measuredAt })) { measurement in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        // 디버그 로그
                        print("📍 [ClothingDetailView] Measurement tapped: \(measurement.measurementType?.displayName ?? measurement.type)")
                        print("   Has coordinates: \(measurement.hasCoordinates)")
                        if let start = measurement.startPoint, let end = measurement.endPoint {
                            print("   Start: \(start), End: \(end)")
                        }

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
        .onAppear {
            // 디버그: 측정값 좌표 확인
            print("📊 [ClothingDetailView] Total measurements: \(item.measurements.count)")
            for measurement in item.measurements {
                print("   - \(measurement.measurementType?.displayName ?? measurement.type): hasCoordinates=\(measurement.hasCoordinates)")
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
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

    private var actionButtons: some View {
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

            Button(action: shareItem) {
                Label("공유", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding(.top)
    }

    // MARK: - Actions

    private func deleteItem() {
        // 이미지 파일 삭제
        if let imagePath = item.imagePath {
            _ = try? ImageFileManager.shared.deleteImage(at: imagePath)
        }

        // SwiftData에서 삭제
        modelContext.delete(item)

        // 화면 닫기
        dismiss()
    }

    private func shareItem() {
        // TODO: 공유 기능 구현
        var shareText = """
        의류 정보
        타입: \(item.clothingType?.displayName ?? "알 수 없음")
        측정값: \(item.completedMeasurements)/\(item.totalRequiredMeasurements) 완료
        """

        if !item.measurements.isEmpty {
            shareText += "\n\n측정값:\n"
            for measurement in item.measurements {
                if let type = MeasurementType(rawValue: measurement.type) {
                    shareText += "\(type.displayName): \(measurement.formattedValue())\n"
                }
            }
        }

        // UIActivityViewController 표시
        // TODO: 실제 공유 구현
    }
}

// MARK: - Measurement Row

/// 측정값 행 컴포넌트
struct MeasurementRow: View {
    let measurement: MeasurementModel
    var isSelected: Bool = false

    var body: some View {
        HStack {
            // 측정 아이콘 및 선택 표시
            ZStack {
                Circle()
                    .fill(isSelected ? measurementColor.opacity(0.2) : Color.clear)
                    .frame(width: 36, height: 36)

                Image(systemName: measurementIcon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? measurementColor : .secondary)
            }
            .animation(.spring(response: 0.3), value: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                Text(measurementType?.displayName ?? measurement.type)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? measurementColor : .primary)

                HStack(spacing: 4) {
                    Text(measurement.formattedValue())
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? measurementColor : .blue)

                    // 신뢰도 표시
                    ConfidenceIndicator(confidence: measurement.confidence)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(measurement.measuredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)

                if measurement.hasCoordinates {
                    Image(systemName: "location.circle.fill")
                        .font(.caption)
                        .foregroundColor(isSelected ? measurementColor : .gray)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? measurementColor.opacity(0.1) : Color.clear)
        )
        .animation(.spring(response: 0.3), value: isSelected)
    }

    private var measurementType: MeasurementType? {
        MeasurementType(rawValue: measurement.type)
    }

    private var measurementIcon: String {
        switch measurement.type {
        case "shoulder_width":
            return "arrow.left.and.right"
        case "chest_circumference", "waist_circumference", "hip_circumference":
            return "circle.dashed"
        case "total_length", "sleeve_length", "inseam", "outseam":
            return "arrow.up.and.down"
        case "arm_circumference", "thigh_circumference", "knee_circumference":
            return "circle"
        case "rise":
            return "arrow.up.to.line"
        case "hem", "hem_width":
            return "arrow.down.to.line"
        case "neck_circumference":
            return "person.crop.circle"
        default:
            return "ruler"
        }
    }

    private var measurementColor: Color {
        // 측정 타입별 색상 (MeasurementLinesOverlay와 동일)
        switch measurement.type {
        // 상의 측정 항목
        case "shoulder_width":
            return .blue
        case "chest_circumference":
            return .green
        case "total_length":
            return .orange
        case "sleeve_length":
            return .purple
        case "arm_circumference":
            return .cyan
        case "neck_circumference":
            return .indigo

        // 하의 측정 항목
        case "waist_circumference":
            return .red
        case "hip_circumference":
            return .green
        case "rise":
            return .purple
        case "hem":
            return .brown
        case "thigh_circumference":
            return .cyan
        case "inseam":
            return .indigo
        case "outseam":
            return .mint
        case "knee_circumference":
            return .pink

        // 기본값
        default:
            return .gray
        }
    }
}

// MARK: - Confidence Indicator

/// 신뢰도 표시 컴포넌트
struct ConfidenceIndicator: View {
    let confidence: Double

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "checkmark.shield.fill")
                .font(.caption)

            Text("\(Int(confidence * 100))%")
                .font(.caption)
        }
        .foregroundColor(confidenceColor)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(confidenceColor.opacity(0.1))
        )
    }

    private var confidenceColor: Color {
        switch confidence {
        case 0.9...1.0:
            return .green
        case 0.7..<0.9:
            return .blue
        case 0.5..<0.7:
            return .orange
        default:
            return .red
        }
    }
}

// MARK: - Circular Progress

/// 원형 진행률 표시 컴포넌트
struct CircularProgress: View {
    let progress: Double
    let lineWidth: CGFloat
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progressColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)
                .frame(width: size, height: size)

            Text("\(Int(progress * 100))%")
                .font(.system(size: size * 0.25))
                .fontWeight(.semibold)
                .foregroundColor(progressColor)
        }
    }

    private var progressColor: Color {
        switch progress {
        case 1.0:
            return .green
        case 0.5..<1.0:
            return .blue
        default:
            return .orange
        }
    }
}

// MARK: - Note Edit View

/// 메모 편집 화면
struct NoteEditView: View {
    @Binding var note: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $note)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .padding()

                Spacer()
            }
            .navigationTitle("메모 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("저장") {
                        onSave(note)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ClothingDetailView(
            item: ClothingItemModel(
                type: ClothingType.shortSleeve.rawValue,
                imagePath: nil,
                notes: "테스트 메모입니다."
            )
        )
    }
    .modelContainer(for: [ClothingItemModel.self])
}
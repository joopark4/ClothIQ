//
//  BackgroundRemovalTestView.swift
//  ClothIQ
//
//  Created on 2025-10-23
//
//  Description:
//  배경 제거 기능을 테스트하기 위한 개발용 뷰입니다.
//  정적 이미지를 로드하여 배경 제거 결과를 확인할 수 있습니다.
//

import SwiftUI
import PhotosUI
import Combine

/// 배경 제거 테스트 뷰
///
/// ObjectCaptureService의 배경 제거 기능을 테스트합니다.
///
struct BackgroundRemovalTestView: View {

    @StateObject private var viewModel = BackgroundRemovalTestViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // 상태 표시
                    statusSection

                    // 원본 이미지
                    if let originalImage = viewModel.originalImage {
                        imageSection(
                            title: "원본 이미지",
                            image: originalImage
                        )
                    }

                    // 처리된 이미지
                    if let processedImage = viewModel.processedImage {
                        imageSection(
                            title: "배경 제거 결과",
                            image: processedImage
                        )
                    }

                    // 버튼들
                    buttonSection

                    // 로그
                    if !viewModel.logs.isEmpty {
                        logSection
                    }
                }
                .padding()
            }
            .navigationTitle("배경 제거 테스트")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: viewModel.selectedPhoto) { oldValue, newValue in
                if newValue != nil {
                    Task {
                        await viewModel.loadSelectedPhoto()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        VStack(spacing: 12) {
            if viewModel.isProcessing {
                ProgressView("처리 중...")
                    .padding()
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            if let processingTime = viewModel.processingTime {
                Text("처리 시간: \(String(format: "%.2f", processingTime))초")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func imageSection(title: String, image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            Text("크기: \(Int(image.size.width)) × \(Int(image.size.height))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var buttonSection: some View {
        VStack(spacing: 12) {
            // 테스트 이미지 로드
            Button {
                viewModel.loadTestImage()
            } label: {
                Label("테스트 이미지 로드 (IMG_2338.JPG)", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isProcessing)

            // 포토 라이브러리에서 선택
            PhotosPicker(
                selection: $viewModel.selectedPhoto,
                matching: .images
            ) {
                Label("사진 라이브러리에서 선택", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isProcessing)

            // 배경 제거 실행
            if viewModel.originalImage != nil {
                Button {
                    viewModel.removeBackground()
                } label: {
                    Label("배경 제거 실행", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(viewModel.isProcessing)
            }

            // 초기화
            if viewModel.originalImage != nil || viewModel.processedImage != nil {
                Button(role: .destructive) {
                    viewModel.reset()
                } label: {
                    Label("초기화", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isProcessing)
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("처리 로그")
                    .font(.headline)

                Spacer()

                Button {
                    viewModel.clearLogs()
                } label: {
                    Text("지우기")
                        .font(.caption)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.logs.indices, id: \.self) { index in
                        Text(viewModel.logs[index])
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
            .padding(8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

// MARK: - ViewModel

@MainActor
final class BackgroundRemovalTestViewModel: ObservableObject {

    @Published var originalImage: UIImage?
    @Published var processedImage: UIImage?
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var processingTime: TimeInterval?
    @Published var logs: [String] = []
    @Published var selectedPhoto: PhotosPickerItem?

    private let objectCaptureService = ObjectCaptureService()

    /// 테스트 이미지 로드 (Reference/IMG_2338.JPG)
    func loadTestImage() {
        addLog("📂 테스트 이미지 로드 시작...")

        // Reference 폴더에서 이미지 로드 (IMG_2338.JPG - 배경 제거 문제 이미지)
        let testImagePath = "/Users/cauca/Projects/ClothIQ-ClaudeCode/Reference/IMG_2338.JPG"

        if let image = UIImage(contentsOfFile: testImagePath) {
            originalImage = image
            processedImage = nil
            errorMessage = nil
            processingTime = nil
            addLog("✅ 테스트 이미지 로드 성공: \(Int(image.size.width))×\(Int(image.size.height))")
        } else {
            errorMessage = "테스트 이미지를 찾을 수 없습니다: \(testImagePath)"
            addLog("❌ 테스트 이미지 로드 실패")
        }
    }

    /// 배경 제거 실행
    func removeBackground() {
        guard let image = originalImage else {
            errorMessage = "원본 이미지가 없습니다"
            return
        }

        isProcessing = true
        errorMessage = nil
        processedImage = nil
        processingTime = nil

        addLog("🎨 배경 제거 시작...")
        addLog("   이미지 크기: \(Int(image.size.width))×\(Int(image.size.height))")

        let startTime = Date()

        // 배경 제거 실행 (depth map 없이)
        objectCaptureService.processImage(image, depthMap: nil) { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isProcessing = false
                self.processingTime = Date().timeIntervalSince(startTime)

                switch result {
                case .success(let processedImage):
                    self.processedImage = processedImage
                    self.addLog("✅ 배경 제거 성공!")
                    self.addLog("   처리 시간: \(String(format: "%.2f", self.processingTime!))초")
                    self.addLog("   결과 크기: \(Int(processedImage.size.width))×\(Int(processedImage.size.height))")

                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                    self.addLog("❌ 배경 제거 실패: \(error.localizedDescription)")
                }
            }
        }
    }

    /// 포토 선택 처리
    func loadSelectedPhoto() async {
        guard let selectedPhoto = selectedPhoto else { return }

        addLog("📂 사진 라이브러리에서 이미지 로드 중...")

        do {
            if let data = try await selectedPhoto.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                originalImage = image
                processedImage = nil
                errorMessage = nil
                processingTime = nil
                addLog("✅ 이미지 로드 성공: \(Int(image.size.width))×\(Int(image.size.height))")
            } else {
                errorMessage = "이미지를 로드할 수 없습니다"
                addLog("❌ 이미지 로드 실패")
            }
        } catch {
            errorMessage = "이미지 로드 오류: \(error.localizedDescription)"
            addLog("❌ 이미지 로드 오류: \(error.localizedDescription)")
        }
    }

    /// 초기화
    func reset() {
        originalImage = nil
        processedImage = nil
        errorMessage = nil
        processingTime = nil
        selectedPhoto = nil
        addLog("🔄 초기화 완료")
    }

    /// 로그 추가
    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
    }

    /// 로그 지우기
    func clearLogs() {
        logs.removeAll()
    }
}

// MARK: - Preview

#Preview {
    BackgroundRemovalTestView()
}

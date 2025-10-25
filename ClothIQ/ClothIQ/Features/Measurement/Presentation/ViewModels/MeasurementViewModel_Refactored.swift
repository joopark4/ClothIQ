//
//  MeasurementViewModel.swift (Refactored)
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  측정 화면의 ViewModel입니다 (리팩토링 버전).
//  ARMeasurementService를 사용하여 측정 로직을 분리했습니다.
//
//  Key Responsibilities:
//  - AR 세션 상태 관리
//  - 측정 포인트 추가 및 삭제 (Service 위임)
//  - 거리 계산 및 측정값 저장
//  - 측정 세션 관리
//  - UI 상태 관리
//

import Foundation
import Combine
import ARKit
import SwiftUI
import UIKit

/// 측정 화면 ViewModel (리팩토링 버전)
///
/// AR 측정 화면의 상태와 로직을 관리합니다.
/// ARMeasurementService를 통해 측정 로직을 처리합니다.
///
@MainActor
final class MeasurementViewModelRefactored: ObservableObject {

    // MARK: - Published Properties

    /// 현재 측정 세션
    @Published var session: MeasurementSession

    /// AR 세션 실행 중 여부
    @Published var isARSessionRunning: Bool = false

    /// 측정 포인트 목록
    @Published var measurementPoints: [MeasurementPoint] = []

    /// 선택된 포인트 인덱스
    @Published var selectedPointIndex: Int?

    /// 에러 메시지
    @Published var errorMessage: String?

    /// 성공 메시지
    @Published var successMessage: String?

    /// 현재 측정 중인 항목
    @Published var currentMeasurementType: MeasurementType?

    /// 로딩 상태
    @Published var isLoading: Bool = false

    /// 환경 점수
    @Published var environmentScore: Float = 0.0

    /// AR 추적 상태
    @Published var trackingState: ARCamera.TrackingState = .notAvailable

    /// AR 초기화 완료 여부
    @Published var isARInitialized: Bool = false

    /// 이미지 캡처 요청 플래그
    @Published var captureRequested: Bool = false

    /// 캡처된 이미지
    @Published var capturedImage: UIImage?

    // MARK: - Private Properties

    private let measurementService: ARMeasurementServiceProtocol
    private let imageFileManager: ImageFileManager
    private let objectCaptureService: ObjectCaptureService
    private let photoLibraryService: PhotoLibraryService
    private var cancellables = Set<AnyCancellable>()
    private var hasShownOrientationWarning = false
    private var lastTemporaryCaptureURL: URL?

    // MARK: - Initialization

    init(
        clothingType: ClothingType? = nil,
        measurementService: ARMeasurementServiceProtocol = ARMeasurementService(),
        imageFileManager: ImageFileManager = .shared,
        objectCaptureService: ObjectCaptureService = ObjectCaptureService(),
        photoLibraryService: PhotoLibraryService = .shared
    ) {
        self.session = MeasurementSession(clothingType: clothingType)
        self.measurementService = measurementService
        self.imageFileManager = imageFileManager
        self.objectCaptureService = objectCaptureService
        self.photoLibraryService = photoLibraryService

        setupOrientationMonitoring()
    }

    deinit {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    // MARK: - AR Session Management

    /// AR 세션 시작
    func startARSession() {
        isARSessionRunning = true
        session.state = .measuring
        let isOrientationValid = validateCurrentOrientation()
        if isOrientationValid {
            showSuccess("AR 세션이 시작되었습니다")
        }
    }

    /// AR 세션 일시정지
    func pauseARSession() {
        isARSessionRunning = false
    }

    /// AR 세션 재개
    func resumeARSession() {
        isARSessionRunning = true
    }

    // MARK: - Measurement Point Management

    /// 화면 탭 처리 - 측정 포인트 추가
    ///
    /// - Parameters:
    ///   - location: 화면 좌표
    ///   - frame: AR 프레임
    func handleTap(at location: CGPoint, frame: ARFrame) {
        do {
            // Service를 통해 측정 포인트 추출
            guard let point = try measurementService.extractMeasurementPoint(
                at: location,
                from: frame
            ) else {
                showError("측정 포인트를 추가할 수 없습니다.")
                return
            }

            addMeasurementPoint(point)

        } catch let error as ARError {
            handleARError(error)
        } catch {
            showError("측정 중 오류가 발생했습니다: \(error.localizedDescription)")
        }
    }

    /// 측정 포인트 추가
    func addMeasurementPoint(_ point: MeasurementPoint) {
        measurementPoints.append(point)
        session.addPoint(point)
        selectedPointIndex = measurementPoints.count - 1

        // 2개 이상의 포인트가 있으면 거리 계산
        if measurementPoints.count >= 2 {
            calculateDistance()
        }
    }

    /// 마지막 측정 포인트 제거
    func removeLastPoint() {
        guard !measurementPoints.isEmpty else { return }
        _ = measurementPoints.popLast()
        session.removeLastPoint()

        if measurementPoints.isEmpty {
            selectedPointIndex = nil
        } else {
            selectedPointIndex = measurementPoints.count - 1
        }
    }

    /// 모든 측정 포인트 제거
    func clearAllPoints() {
        measurementPoints.removeAll()
        session.clearPoints()
        selectedPointIndex = nil
    }

    /// 의류 타입 설정
    ///
    /// 선택된 의류 타입을 변경하고 관련 상태를 초기화합니다.
    /// - Parameter type: 새로 선택된 의류 타입
    func setClothingType(_ type: ClothingType) {
        let isSameType = session.clothingType == type

        if isSameType {
            session.state = .measuring
            return
        }

        session = MeasurementSession(
            clothingType: type,
            state: .measuring
        )
        measurementPoints.removeAll()
        selectedPointIndex = nil
        currentMeasurementType = nil
        captureRequested = false
        capturedImage = nil
        showSuccess("\(type.displayName) 측정을 시작하세요")
    }

    // MARK: - Distance Calculation

    /// 거리 계산 (가장 최근 2개 포인트 기준)
    private func calculateDistance() {
        guard measurementPoints.count >= 2 else { return }

        let lastIndex = measurementPoints.count - 1
        let startPoint = measurementPoints[lastIndex - 1]
        let endPoint = measurementPoints[lastIndex]

        // MeasurementCalculator를 사용한 거리 계산
        let distanceInCm = MeasurementCalculator.calculateDistance(
            from: startPoint,
            to: endPoint
        )

        // 측정 타입이 지정되어 있으면 저장
        if let measurementType = currentMeasurementType {
            // 측정값 검증
            let validation = MeasurementCalculator.validateMeasurement(
                value: distanceInCm,
                type: measurementType
            )

            if !validation.isValid {
                showError(validation.warning ?? "측정값이 유효하지 않습니다")
                return
            }

            // 경고가 있으면 표시
            if let warning = validation.warning {
                showSuccess("⚠️ \(warning)")
            }

            session.setMeasurement(distanceInCm, for: measurementType)
            showSuccess("측정 완료: \(measurementType.displayName) = \(String(format: "%.1f", distanceInCm)) cm")
        }
    }

    /// 특정 측정 타입 시작
    func startMeasurement(for type: MeasurementType) {
        currentMeasurementType = type
        clearAllPoints()
        showSuccess("\(type.displayName) 측정을 시작합니다\n\n\(type.measurementGuide)")
    }

    /// 측정 완료
    func completeMeasurement() {
        guard session.isComplete else {
            showError("필수 측정 항목이 모두 완료되지 않았습니다")
            return
        }

        // 세션 검증
        let validation = session.validate()
        guard validation.isValid else {
            showError(validation.error ?? "측정 세션이 유효하지 않습니다")
            return
        }

        session.complete()
        session.state = .reviewing
        showSuccess("측정이 완료되었습니다!")
    }

    // MARK: - Environment Assessment

    // 마지막 경고 시간 추적
    private var lastWarningTime: Date?
    private let warningCooldown: TimeInterval = 5.0  // 5초에 한 번만 경고

    /// AR 프레임 업데이트 처리
    func updateEnvironment(from frame: ARFrame) {
        // Service를 통해 환경 평가
        environmentScore = measurementService.assessEnvironment(from: frame)

        // 환경 점수가 매우 낮을 때만 경고 (기준을 0.3으로 낮춤)
        if environmentScore < 0.3 && isARSessionRunning {
            let now = Date()
            // 쿨다운 체크
            if let lastWarning = lastWarningTime,
               now.timeIntervalSince(lastWarning) < warningCooldown {
                return
            }

            lastWarningTime = now
            showError("측정 환경이 좋지 않습니다. 밝은 곳에서 의류를 수평으로 펼쳐 촬영해주세요.")
        }
    }

    /// AR 추적 상태 업데이트 처리
    func updateTrackingState(_ state: ARCamera.TrackingState) {
        trackingState = state

        // TrackingState가 Normal이면 초기화 완료
        if case .normal = state {
            if !isARInitialized {
                print("✅ AR 세션 초기화 완료 - Tracking State: Normal")
                isARInitialized = true
            }
        } else {
            // Normal이 아니면 초기화 미완료
            if isARInitialized {
                print("⚠️ AR 추적 상태 변경: \(trackingStateDescription(state))")
                isARInitialized = false
            }
        }
    }

    /// TrackingState를 사용자 친화적 메시지로 변환
    func trackingStateMessage(_ state: ARCamera.TrackingState) -> String? {
        switch state {
        case .notAvailable:
            return "AR을 사용할 수 없습니다"

        case .limited(let reason):
            switch reason {
            case .initializing:
                return "LiDAR 센서 초기화 중..."
            case .insufficientFeatures:
                return "아이폰을 천천히 움직여주세요"
            case .excessiveMotion:
                return "카메라가 너무 빠릅니다. 천천히 움직여주세요"
            case .relocalizing:
                return "공간을 다시 인식하는 중..."
            @unknown default:
                return "AR 추적 제한됨"
            }

        case .normal:
            return nil  // 정상 상태일 때는 메시지 없음
        }
    }

    /// TrackingState 설명 (디버깅용)
    private func trackingStateDescription(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .notAvailable:
            return "Not Available"
        case .limited(let reason):
            return "Limited (\(reason))"
        case .normal:
            return "Normal"
        }
    }

    // MARK: - Orientation Monitoring

    private func setupOrientationMonitoring() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.validateCurrentOrientation()
            }
            .store(in: &cancellables)

        validateCurrentOrientation()
    }

    @discardableResult
    private func validateCurrentOrientation() -> Bool {
        let orientation = UIDevice.current.orientation

        var isLandscape = orientation.isLandscape
        var isPortrait = orientation.isPortrait

        if orientation == .unknown || orientation == .faceUp || orientation == .faceDown {
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first {
                switch windowScene.interfaceOrientation {
                case .landscapeLeft, .landscapeRight:
                    isLandscape = true
                    isPortrait = false
                case .portrait, .portraitUpsideDown:
                    isPortrait = true
                    isLandscape = false
                default:
                    break
                }
            }
        }

        if isLandscape {
            if !hasShownOrientationWarning {
                showError("기기가 가로 모드입니다. 측정 정확도를 위해 세로 방향으로 전환해주세요.")
                hasShownOrientationWarning = true
            }
            return false
        } else if isPortrait {
            if hasShownOrientationWarning {
                showSuccess("세로 방향이 감지되었습니다. 측정을 계속 진행할 수 있어요.")
                hasShownOrientationWarning = false
            }
            return true
        }

        return true
    }

    // MARK: - Error Handling

    private func handleARError(_ error: ARError) {
        switch error {
        case .lidarNotSupported:
            showError("LiDAR 센서가 지원되지 않습니다")

        case .insufficientDepthData:
            // 더 구체적이고 실용적인 안내
            showError("측정 포인트를 찾을 수 없습니다.\n\n✓ 의류를 평평한 곳에 펼쳐주세요\n✓ 30cm~2m 거리를 유지해주세요\n✓ 측정하려는 부위를 명확히 터치해주세요")

        case .tooClose(let minDistance):
            showError("너무 가깝습니다. 최소 \(Int(minDistance * 100))cm 이상 떨어져주세요")

        case .tooFar(let maxDistance):
            showError("너무 멉니다. \(Int(maxDistance * 100))cm 이내로 가까이 다가가주세요")

        case .confidenceTooLow(let score):
            showError("측정 신뢰도: \(Int(score * 100))%\n\n밝은 조명 아래에서 다시 시도해주세요")

        case .surfaceTrackingLost:
            showError("추적이 중단되었습니다. 카메라를 천천히 움직여주세요")

        case .excessiveMotion:
            showError("카메라가 너무 빠릅니다. 천천히 움직여주세요")

        case .insufficientLighting:
            showError("조명이 부족합니다. 밝은 곳에서 측정해주세요")

        default:
            showError(error.localizedDescription)
        }
    }

    // MARK: - Image Capture

    /// 이미지 캡처 요청
    ///
    /// 카메라 포커스의 객체를 캡처하고, 다음 처리를 수행합니다:
    /// 1. 객체 감지 및 정사각형 크롭
    /// 2. 배경 제거
    /// 3. Photos 앱에 저장
    func captureImage() {
        print("🔵 [ViewModel] 캡처 버튼 클릭 - captureRequested = true")
        captureRequested = true
    }

    /// 캡처된 이미지를 처리하여 배경을 제거하고 저장합니다.
    ///
    /// ## Post-Capture Workflow
    /// 1. 객체 촬영 (AR 카메라에서 캡처된 이미지)
    /// 2. 1:1 정사각형 크로핑 (객체 중심)
    /// 3. JPG로 임시 저장 (디스크에 임시 파일 생성)
    /// 4. 임시 저장된 JPG에 대해 배경 제거 실행
    /// 5. 최종 이미지를 Photos 앨범 및 로컬에 저장
    ///
    /// - Parameters:
    ///   - image: AR 카메라에서 캡처된 원본 이미지
    ///   - depthMap: LiDAR depth map (배경 제거 품질 향상용, 선택)
    ///
    func handleCapturedImage(_ image: UIImage, depthMap: CVPixelBuffer?) {
        print("📸 이미지 캡처됨 - 크기: \(image.size)")
        print("📊 Depth map: \(depthMap != nil ? "있음" : "없음")")
        isLoading = true

        // 이전 임시 파일 정리
        cleanupTemporaryCaptureFile()

        objectCaptureService.runPostCaptureWorkflow(from: image, depthMap: depthMap) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case .success(let workflowResult):
                    let processedImage = workflowResult.backgroundRemovedImage
                    print("✅ 배경 제거 완료 - 크기: \(processedImage.size)")
                    print("⏱️ 전체 처리 시간: \(String(format: "%.2f", workflowResult.processingTime))초")

                    // 임시 JPEG 경로 저장 (다음 캡처 전까지 유지)
                    self.lastTemporaryCaptureURL = workflowResult.temporaryJPEGURL
                    print("📂 임시 JPEG 경로: \(workflowResult.temporaryJPEGURL.lastPathComponent)")

                    // 처리된 이미지 상태 업데이트
                    self.capturedImage = processedImage

                    // Photos 앱에 최종 이미지 저장
                    print("💾 Photos 앱 저장 시작...")
                    self.saveToPhotosApp(processedImage)

                    // 로컬 파일 시스템 백업 (백그라운드 처리)
                    Task.detached(priority: .utility) { [weak self] in
                        guard let data = ImageCaptureUtility.optimizeImage(processedImage, quality: .high) else {
                            print("❌ 처리된 이미지 최적화 실패")
                            return
                        }

                        await MainActor.run {
                            guard let self else { return }
                            self.session.capturedImageData = data
                            print("✅ 로컬 파일 시스템 백업 완료")
                        }
                    }

                case .failure(let error):
                    print("❌ 이미지 처리 실패: \(error.localizedDescription)")
                    self.handleCaptureError(error)
                }

                // 캡처 플래그 리셋
                self.captureRequested = false
            }
        }
    }

    /// Photos 앱에 이미지 저장
    ///
    /// - Parameter image: 저장할 이미지
    ///
    /// ## Behavior
    /// - 권한이 없으면 자동으로 요청합니다.
    /// - ClothIQ 전용 앨범에 저장됩니다.
    /// - 저장 성공/실패 메시지를 표시합니다.
    private func saveToPhotosApp(_ image: UIImage) {
        print("🔐 사진 라이브러리 권한 확인 중...")
        photoLibraryService.requestPermissionAndSave(image) { [weak self] success, error in
            guard let self = self else { return }

            Task { @MainActor in
                if success {
                    print("✅ Photos 앱 저장 성공!")
                    self.showSuccess("이미지가 Photos 앱에 저장되었습니다")
                } else {
                    let errorMsg = error?.localizedDescription ?? "알 수 없는 오류"
                    print("❌ Photos 앱 저장 실패: \(errorMsg)")
                    self.showError("Photos 저장 실패: \(errorMsg)")
                }
            }
        }
    }

    /// 캡처 에러 처리
    ///
    /// - Parameter error: 발생한 에러
    private func handleCaptureError(_ error: Error) {
        if let captureError = error as? ObjectCaptureError {
            switch captureError {
            case .objectNotDetected:
                showError("객체를 감지할 수 없습니다. 의류를 카메라 중앙에 배치해주세요.")
            case .invalidImage:
                showError("유효하지 않은 이미지입니다.")
            case .cropFailed:
                showError("이미지 크롭에 실패했습니다.")
            case .backgroundRemovalFailed:
                showError("배경 제거에 실패했습니다.")
            case .maskGenerationFailed:
                showError("마스크 생성에 실패했습니다. 다시 시도해주세요.")
            case .processingFailed:
                showError("이미지 처리에 실패했습니다.")
            }
        } else {
            showError("이미지 캡처 중 오류가 발생했습니다: \(error.localizedDescription)")
        }
    }

    /// 이미지를 파일로 저장
    func saveImageToFile() async throws -> String {
        guard let image = capturedImage else {
            throw ImageFileError.saveFailed
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let relativePath = try imageFileManager.saveImage(image, quality: .high)
            showSuccess("이미지가 저장되었습니다")
            return relativePath
        } catch {
            showError("이미지 저장에 실패했습니다")
            throw error
        }
    }

    /// 캡처된 이미지 삭제
    func clearCapturedImage() {
        capturedImage = nil
        session.capturedImageData = nil
    }

    // MARK: - UI Helpers

    private func showError(_ message: String) {
        errorMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.errorMessage == message {
                self?.errorMessage = nil
            }
        }
    }

    private func showSuccess(_ message: String) {
        successMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.successMessage == message {
                self?.successMessage = nil
            }
        }
    }

    /// 임시로 저장된 캡처 이미지를 정리합니다.
    private func cleanupTemporaryCaptureFile() {
        guard let url = lastTemporaryCaptureURL else { return }

        do {
            try FileManager.default.removeItem(at: url)
            print("🧹 임시 JPEG 정리 완료 - \(url.lastPathComponent)")
        } catch {
            print("⚠️ 임시 JPEG 정리에 실패했습니다: \(error.localizedDescription)")
        }

        lastTemporaryCaptureURL = nil
    }
}

// MARK: - Computed Properties

extension MeasurementViewModelRefactored {
    /// 전체 신뢰도 점수
    var overallConfidence: Float {
        return measurementService.assessOverallConfidence(
            points: measurementPoints,
            environmentScore: environmentScore
        )
    }

    /// 신뢰도 표시 텍스트
    var confidenceText: String {
        let confidence = overallConfidence
        let percentage = Int(confidence * 100)

        switch confidence {
        case 0.9...1.0:
            return "신뢰도: 매우 높음 (\(percentage)%)"
        case 0.7..<0.9:
            return "신뢰도: 높음 (\(percentage)%)"
        case 0.5..<0.7:
            return "신뢰도: 보통 (\(percentage)%)"
        default:
            return "신뢰도: 낮음 (\(percentage)%) - 재측정 권장"
        }
    }
}

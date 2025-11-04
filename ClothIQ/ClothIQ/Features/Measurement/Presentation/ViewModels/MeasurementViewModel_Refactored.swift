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
import SwiftData
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

    /// 카메라 pitch 각도 (도)
    @Published var cameraPitchAngle: Float = 0

    /// 이미지 캡처 요청 플래그
    @Published var captureRequested: Bool = false

    /// 캡처된 이미지
    @Published var capturedImage: UIImage?

    /// 임시 저장할 처리된 이미지
    @Published var processedImageToSave: UIImage?

    // MARK: - Private Properties

    private let measurementService: ARMeasurementServiceProtocol
    private let imageFileManager: ImageFileManager
    private let objectCaptureService: ObjectCaptureService
    private let photoLibraryService: PhotoLibraryService
    private let measurementFilter = MeasurementFilter()
    var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var hasShownOrientationWarning = false
    private var lastTemporaryCaptureURL: URL?

    // MARK: - Initialization

    @MainActor
    init(
        clothingType: ClothingType? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.session = MeasurementSession(clothingType: clothingType)
        self.modelContext = modelContext
        self.measurementService = ARMeasurementService()
        self.imageFileManager = .shared
        self.objectCaptureService = ObjectCaptureService()
        self.photoLibraryService = .shared

        setupOrientationMonitoring()
    }

    deinit {
        Task { @MainActor in
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
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

        // 타입이 변경되면 Kalman 필터 리셋
        if !isSameType {
            measurementFilter.resetAll()
        }

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

        // 각도 보정이 적용된 거리 계산
        let rawDistanceInCm = MeasurementCalculator.calculateCorrectedDistance(
            from: startPoint,
            to: endPoint,
            useAngleCorrection: true
        )

        // 측정 타입이 지정되어 있으면 저장
        if let measurementType = currentMeasurementType {
            // 신뢰도 계산 (양쪽 포인트의 평균 신뢰도)
            let avgConfidence = (startPoint.confidence + endPoint.confidence) / 2.0

            // 각도 기반 신뢰도 조정
            let avgAngle = (startPoint.cameraPitchAngle + endPoint.cameraPitchAngle) / 2.0
            let angleConfidence = AngleCorrectionService.assessConfidence(for: avgAngle)
            let totalConfidence = avgConfidence * angleConfidence

            // Kalman 필터 적용
            let filteredDistance = measurementFilter.update(
                id: measurementType.rawValue,
                value: rawDistanceInCm,
                confidence: totalConfidence
            )

            // 측정값 검증
            let validation = MeasurementCalculator.validateMeasurement(
                value: filteredDistance,
                type: measurementType
            )

            if !validation.isValid {
                showError(validation.warning ?? "측정값이 유효하지 않습니다")
                return
            }

            // 각도 경고
            if avgAngle > 45 {
                showSuccess("⚠️ 카메라를 더 정면으로 향해주세요 (현재 각도: \(Int(avgAngle))°)")
            } else if let warning = validation.warning {
                showSuccess("⚠️ \(warning)")
            }

            session.setMeasurement(filteredDistance, for: measurementType)

            // 측정 품질 표시
            let qualityDesc = AngleCorrectionService.qualityDescription(for: avgAngle)
            showSuccess("측정 완료: \(measurementType.displayName) = \(String(format: "%.1f", filteredDistance)) cm (품질: \(qualityDesc))")
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

        // SwiftData에 저장
        saveToSwiftData()
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
                let orientation = windowScene.effectiveGeometry.interfaceOrientation
                switch orientation {
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

        // 모든 방향 허용 - 가로/세로 모두 정상 촬영 가능
        if isLandscape {
            if !hasShownOrientationWarning {
                // 가로 모드도 지원한다는 안내 메시지
                showSuccess("가로 모드로 촬영이 가능합니다.")
                hasShownOrientationWarning = true
            }
            return true  // 가로 모드 허용
        } else if isPortrait {
            if hasShownOrientationWarning {
                showSuccess("세로 모드로 촬영이 가능합니다.")
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

        // processImage 사용으로 변경 (테스트 뷰와 동일한 고품질 처리)
        let startTime = Date()
        objectCaptureService.processImage(image, depthMap: depthMap) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                self.isLoading = false
                let processingTime = Date().timeIntervalSince(startTime)

                switch result {
                case .success(let processedImage):
                    print("✅ 배경 제거 완료 - 크기: \(processedImage.size)")
                    print("⏱️ 전체 처리 시간: \(String(format: "%.2f", processingTime))초")

                    // 임시 JPEG 저장 (Photos 앱 저장용)
                    if let jpegData = processedImage.jpegData(compressionQuality: 0.95),
                       let tempURL = try? self.createTemporaryJPEGURL() {
                        do {
                            try jpegData.write(to: tempURL)
                            self.lastTemporaryCaptureURL = tempURL
                            print("📂 임시 JPEG 저장: \(tempURL.lastPathComponent)")
                        } catch {
                            print("❌ 임시 JPEG 저장 실패: \(error)")
                        }
                    }

                    // 처리된 이미지 상태 업데이트
                    self.capturedImage = processedImage
                    self.processedImageToSave = processedImage

                    // LiDAR 측정 자동 시도 (선택 사항, 실패해도 진행)
                    // TODO: 자동 측정 로직 추가 가능

                    // Photos 앱에 최종 이미지 저장
                    print("💾 Photos 앱 저장 시작...")
                    self.saveToPhotosApp(processedImage)

                    // 의류 타입 자동 감지 및 SwiftData 저장
                    print("🔍 의류 타입 자동 감지 시작...")
                    let classifier = VisionClothingClassifier()
                    let result = classifier.classify(image: processedImage)

                    print(classifier.debugDescription(for: result))

                    // 자동 감지된 타입으로 저장
                    self.saveWithClothingType(result.type)

                    // 성공 메시지 표시 (감지된 타입 포함)
                    self.successMessage = "이미지가 캡처되었습니다\n의류 타입: \(result.type.displayName)"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        self.successMessage = nil
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

    /// 임시 JPEG URL 생성
    private func createTemporaryJPEGURL() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "capture_\(UUID().uuidString).jpg"
        return tempDirectory.appendingPathComponent(fileName)
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

    // MARK: - SwiftData Save

    /// 의류 타입 선택 후 즉시 저장
    func saveWithClothingType(_ clothingType: ClothingType) {
        guard let modelContext = modelContext else {
            showError("데이터 저장 환경이 준비되지 않았습니다")
            return
        }

        guard let processedImage = processedImageToSave else {
            showError("저장할 이미지가 없습니다")
            return
        }

        // 의류 타입 설정
        session.clothingType = clothingType

        // ClothingItemModel 생성
        let clothingItem = ClothingItemModel(
            type: clothingType.rawValue,
            imagePath: nil,
            notes: nil
        )

        // 이미지 저장
        do {
            print("📸 이미지 저장 시작 - 크기: \(processedImage.size)")
            let relativePath = try imageFileManager.saveImage(processedImage, quality: .high)
            clothingItem.imagePath = relativePath
            print("✅ 이미지 파일 저장됨: \(relativePath)")

            // 저장 확인
            if let testImage = try? imageFileManager.loadImage(at: relativePath) {
                print("✅ 저장된 이미지 검증 성공 - 크기: \(testImage.size)")
            } else {
                print("❌ 저장된 이미지 검증 실패")
            }
        } catch {
            print("❌ 이미지 파일 저장 실패: \(error)")
            // 이미지 저장 실패해도 계속 진행
        }

        // 측정값이 있다면 추가 (자동 측정이 성공한 경우)
        for (type, value) in session.measurements {
            let measurement = MeasurementModel(
                type: type.rawValue,
                value: value,
                unit: "cm",
                confidence: Double(overallConfidence)
            )
            clothingItem.measurements.append(measurement)
            measurement.clothingItem = clothingItem
        }

        // SwiftData에 저장
        modelContext.insert(clothingItem)

        do {
            try modelContext.save()
            print("✅ SwiftData 저장 완료")
            successMessage = "저장되었습니다"

            // 저장 후 정리
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.successMessage = nil
                self.processedImageToSave = nil
            }
        } catch {
            print("❌ SwiftData 저장 실패: \(error)")
            showError("저장에 실패했습니다: \(error.localizedDescription)")
        }
    }

    /// 측정 데이터를 SwiftData에 저장 (기존 메서드, 측정 완료 시 사용)
    private func saveToSwiftData() {
        guard let modelContext = modelContext else {
            showError("데이터 저장 환경이 준비되지 않았습니다")
            return
        }

        guard let clothingType = session.clothingType else {
            showError("의류 타입이 선택되지 않았습니다")
            return
        }

        // ClothingItemModel 생성
        let clothingItem = ClothingItemModel(
            type: clothingType.rawValue,
            imagePath: nil,
            notes: nil
        )

        // 이미지 저장
        if let capturedImage = capturedImage {
            do {
                let relativePath = try imageFileManager.saveImage(capturedImage, quality: .high)
                clothingItem.imagePath = relativePath
            } catch {
                print("이미지 저장 실패: \(error.localizedDescription)")
                // 이미지 저장 실패해도 측정값은 저장 계속
            }
        }

        // 측정값들을 MeasurementModel로 변환
        for (type, value) in session.measurements {
            let measurement = MeasurementModel(
                type: type.rawValue,
                value: value,
                unit: "cm",
                confidence: Double(overallConfidence)
            )
            clothingItem.measurements.append(measurement)
        }

        // SwiftData에 저장
        modelContext.insert(clothingItem)

        do {
            try modelContext.save()
            showSuccess("의류 아이템이 저장되었습니다!")

            // 저장 후 세션 초기화
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.resetSession()
            }
        } catch {
            showError("데이터 저장에 실패했습니다: \(error.localizedDescription)")
        }
    }

    /// 세션 초기화
    private func resetSession() {
        session = MeasurementSession(clothingType: session.clothingType)
        measurementPoints.removeAll()
        capturedImage = nil
        currentMeasurementType = nil
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

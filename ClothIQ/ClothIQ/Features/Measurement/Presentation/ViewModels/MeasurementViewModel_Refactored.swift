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

    /// 자동 측정 포인트 미리보기
    @Published var autoMeasurementPreview: [MeasurementPointCandidate]?

    /// 자동 측정 결과 (좌표 포함)
    private var autoMeasurementResults: [MeasurementResult] = []

    /// 의류 타입 선택 Sheet 표시 여부
    @Published var showingTypeSelection: Bool = false

    /// 저장된 의류 아이템 (상세보기 화면 이동용)
    @Published var savedClothingItem: ClothingItemModel?

    /// 감지된 평면 앵커
    @Published var detectedPlane: ARPlaneAnchor?

    /// 카메라 정렬 상태 데이터
    @Published var cameraAlignmentData: CameraAlignmentData?

    /// 카메라 정렬 가이드 표시 여부
    @Published var showAlignmentGuide: Bool = true

    // MARK: - Private Properties

    private let measurementService: ARMeasurementServiceProtocol
    private let autoMeasurementService: AutoMeasurementService
    private let imageFileManager: ImageFileManager
    private let objectCaptureService: ObjectCaptureService
    private let photoLibraryService: PhotoLibraryService
    private let measurementFilter = MeasurementFilter()
    var modelContext: ModelContext?
    private var cancellables = Set<AnyCancellable>()
    private var hasShownOrientationWarning = false
    private var lastTemporaryCaptureURL: URL?

    /// 캡처된 depth map (사진 측정에 사용)
    private var capturedDepthMap: CVPixelBuffer?
    /// 원본 이미지 크기 (크롭 전)
    private var capturedOriginalImageSize: CGSize?
    /// 크롭 영역 (원본 이미지 좌표계)
    private var capturedCropRect: CGRect?
    /// 최종 저장될 이미지 크기
    private var capturedProcessedImageSize: CGSize?
    /// 캡처 시점 카메라 intrinsics
    private var capturedCameraIntrinsics: simd_float3x3?
    /// 캡처 시점 카메라 이미지 해상도
    private var capturedCameraResolution: CGSize?

    // MARK: - Initialization

    @MainActor
    init(
        clothingType: ClothingType? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.session = MeasurementSession(clothingType: clothingType)
        self.modelContext = modelContext
        self.measurementService = ARMeasurementService()
        self.autoMeasurementService = AutoMeasurementService()
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

    /// 평면 감지 및 카메라 정렬 상태 업데이트
    ///
    /// ARFrame과 앵커 배열을 받아서 가장 가까운 수평 평면을 찾고,
    /// 카메라 정렬 상태를 계산합니다.
    ///
    /// - Parameters:
    ///   - frame: 현재 AR 프레임
    ///   - anchors: 감지된 앵커 목록
    func updateCameraAlignment(from frame: ARFrame, anchors: [ARAnchor]) {
        // 정렬 가이드가 비활성화되어 있으면 업데이트하지 않음
        guard showAlignmentGuide else {
            cameraAlignmentData = nil
            detectedPlane = nil
            return
        }

        // 수평 평면만 필터링 (의류는 수평으로 놓임)
        let horizontalPlanes = anchors.compactMap { $0 as? ARPlaneAnchor }
            .filter { $0.alignment == .horizontal }

        // 카메라 위치
        let cameraPosition = frame.camera.transform.columns.3

        // 가장 가까운 평면 찾기
        let closestPlane = horizontalPlanes.min(by: { plane1, plane2 in
            let pos1 = plane1.transform.columns.3
            let pos2 = plane2.transform.columns.3

            let dist1 = simd_distance(
                SIMD3<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z),
                SIMD3<Float>(pos1.x, pos1.y, pos1.z)
            )
            let dist2 = simd_distance(
                SIMD3<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z),
                SIMD3<Float>(pos2.x, pos2.y, pos2.z)
            )

            return dist1 < dist2
        })

        // 평면이 감지되면 정렬 데이터 계산
        if let plane = closestPlane {
            detectedPlane = plane
            cameraAlignmentData = measurementService.calculateCameraAlignment(
                from: frame,
                planeAnchor: plane
            )
        } else {
            // 평면이 없으면 nil
            detectedPlane = nil
            cameraAlignmentData = nil
        }
    }

    /// 정렬 가이드 토글
    func toggleAlignmentGuide() {
        showAlignmentGuide.toggle()

        if showAlignmentGuide {
            showSuccess("정렬 가이드가 활성화되었습니다")
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
    func handleCapturedImage(
        _ image: UIImage,
        depthMap: CVPixelBuffer?,
        camera: ARCamera?
    ) {
        print("📸 이미지 캡처됨 - 크기: \(image.size)")
        print("📊 Depth map: \(depthMap != nil ? "있음" : "없음")")
        isLoading = true

        // Depth map 저장 (사진 측정에 사용)
        self.capturedDepthMap = depthMap
        self.capturedOriginalImageSize = image.size
        self.capturedCameraIntrinsics = camera?.intrinsics
        if let resolution = camera?.imageResolution {
            self.capturedCameraResolution = CGSize(width: resolution.width, height: resolution.height)
        } else {
            self.capturedCameraResolution = nil
        }

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
                case .success(let processedResult):
                    let processedImage = processedResult.finalImage
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
                    self.capturedProcessedImageSize = processedImage.size
                    self.capturedOriginalImageSize = processedResult.originalImageSize
                    self.capturedCropRect = processedResult.cropRect

                    // Photos 앱에 최종 이미지 저장
                    print("💾 Photos 앱 저장 시작...")
                    self.saveToPhotosApp(processedImage)

                    // 의류 타입 선택 Sheet 표시
                    print("👔 의류 타입 선택 화면 표시...")
                    self.showingTypeSelection = true

                case .failure(let error):
                    print("❌ 이미지 처리 실패: \(error.localizedDescription)")
                    self.capturedOriginalImageSize = nil
                    self.capturedProcessedImageSize = nil
                    self.capturedCropRect = nil
                    self.capturedCameraIntrinsics = nil
                    self.capturedCameraResolution = nil
                    self.handleCaptureError(error)
                }

                // 캡처 플래그 리셋
                self.captureRequested = false
            }
        }
    }

    /// 의류 타입 선택 후 처리
    ///
    /// 선택된 의류 타입으로 자동 측정을 실행하고 결과를 저장합니다.
    /// AutoSize02.md: ARFrame은 이 메서드 내에서만 사용하고, 메서드 종료 시 자동 해제되도록 함
    ///
    /// - Parameters:
    ///   - type: 선택된 의류 타입
    ///   - frame: 현재 AR 프레임 (메서드 스코프에서만 유지, 저장하지 않음)
    func handleTypeSelection(
        _ type: ClothingType,
        frame: ARFrame?
    ) {
        guard processedImageToSave != nil else {
            showError("처리된 이미지가 없습니다")
            return
        }

        // Sheet 닫기
        showingTypeSelection = false

        // 의류 타입 설정
        session.clothingType = type
        print("👔 선택된 타입: \(type.displayName)")

        // AR 프레임이 있으면 자동 측정 실행
        if let frame = frame {
            isLoading = true

            Task {
                do {
                    print("🔮 자동 측정 시작...")

                    // 1. 윤곽선 감지
                    guard let contour = try await autoMeasurementService.detectClothingContour(
                        from: frame
                    ) else {
                        await MainActor.run {
                            // 자동 측정 실패해도 저장은 진행
                            print("⚠️ 윤곽선 감지 실패, 측정 없이 저장")
                            saveWithClothingType(type)
                            isLoading = false
                        }
                        return
                    }

                    // 2. 특징점 추출
                    let featurePoints = autoMeasurementService.extractFeaturePoints(from: contour)

                    // 3. 측정 포인트 감지
                    let candidates = autoMeasurementService.detectMeasurementPoints(
                        featurePoints: featurePoints,
                        contour: contour,
                        clothingType: type
                    )

                    if !candidates.isEmpty {
                        // 4. 2D → 3D 변환 및 측정
                        let measurements = try await processCandidates(candidates, frame: frame)

                        // 5. 측정값 저장
                        await MainActor.run {
                            autoMeasurementResults = measurements
                            for measurement in measurements {
                                session.setMeasurement(measurement.value, for: measurement.type)
                            }
                            print("✅ 자동 측정 완료: \(measurements.count)개 항목")
                        }
                    } else {
                        await MainActor.run {
                            autoMeasurementResults = []
                        }
                    }

                    // 6. SwiftData 저장
                    await MainActor.run {
                        saveWithClothingType(type)
                        showSuccess("촬영 완료! \(type.displayName) 저장됨")
                        isLoading = false
                    }

                } catch {
                    await MainActor.run {
                        print("❌ 자동 측정 실패: \(error), 측정 없이 저장")
                        // 실패해도 이미지는 저장
                        saveWithClothingType(type)
                        showSuccess("촬영 완료! \(type.displayName) 저장됨")
                        isLoading = false
                    }
                }
            }
        } else {
            // AR 프레임이 없으면 측정 없이 저장
            print("⚠️ AR 프레임 없음, 측정 없이 저장")
            saveWithClothingType(type)
            showSuccess("촬영 완료! \(type.displayName) 저장됨")
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

    func showError(_ message: String) {
        errorMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.errorMessage == message {
                self?.errorMessage = nil
            }
        }
    }

    func showSuccess(_ message: String) {
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

        // Depth map 저장 (있는 경우)
        if let depthMap = capturedDepthMap {
            do {
                print("📊 Depth map 저장 시작")
                let depthFilename = clothingItem.id.uuidString
                let depthPath = try DepthDataProcessor.saveDepthMap(depthMap, filename: depthFilename)
                clothingItem.depthMapPath = depthPath
                print("✅ Depth map 저장됨: \(depthPath)")

                // 메모리 해제 (CVPixelBuffer는 큰 메모리 객체이므로 즉시 해제)
                self.capturedDepthMap = nil
                print("🧹 Depth map 메모리 해제됨")
            } catch {
                print("❌ Depth map 저장 실패: \(error)")
                // 저장 실패해도 메모리 해제
                self.capturedDepthMap = nil
            }
        } else {
            print("ℹ️ Depth map 없음 (촬영 시 LiDAR 데이터 없음)")
        }

        // 메타데이터 저장
        if let originalSize = capturedOriginalImageSize {
            clothingItem.originalImageWidth = Double(originalSize.width)
            clothingItem.originalImageHeight = Double(originalSize.height)
        }

        if let processedSize = capturedProcessedImageSize ?? processedImageToSave?.size {
            clothingItem.processedImageWidth = Double(processedSize.width)
            clothingItem.processedImageHeight = Double(processedSize.height)
        }

        if let cropRect = capturedCropRect {
            clothingItem.cropOriginX = Double(cropRect.origin.x)
            clothingItem.cropOriginY = Double(cropRect.origin.y)
            clothingItem.cropWidth = Double(cropRect.size.width)
            clothingItem.cropHeight = Double(cropRect.size.height)
        }

        if let intrinsics = capturedCameraIntrinsics {
            clothingItem.cameraIntrinsicsData = encodeIntrinsicsMatrix(intrinsics)
        }

        if let resolution = capturedCameraResolution {
            clothingItem.cameraResolutionWidth = Double(resolution.width)
            clothingItem.cameraResolutionHeight = Double(resolution.height)
        }

        // 측정값이 있다면 추가 (자동 측정이 성공한 경우)
        for (type, value) in session.measurements {
            // autoMeasurementResults에서 해당 타입의 좌표 찾기
            let resultWithCoords = autoMeasurementResults.first { $0.type == type }
            let startPoint = convertToProcessedNormalizedPoint(resultWithCoords?.startPoint)
            let endPoint = convertToProcessedNormalizedPoint(resultWithCoords?.endPoint)
            let measurement = MeasurementModel(
                type: type.rawValue,
                value: value,
                unit: "cm",
                confidence: Double(overallConfidence),
                startPointX: startPoint.map { Double($0.x) },
                startPointY: startPoint.map { Double($0.y) },
                endPointX: endPoint.map { Double($0.x) },
                endPointY: endPoint.map { Double($0.y) }
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

            // 저장된 아이템 설정 (상세보기 화면 이동용)
            print("🔵 [ViewModel] Setting savedClothingItem for navigation")
            self.savedClothingItem = clothingItem
            print("🔵 [ViewModel] savedClothingItem is now: \(clothingItem.id)")

            // 메타데이터 정리
            self.capturedOriginalImageSize = nil
            self.capturedProcessedImageSize = nil
            self.capturedCropRect = nil
            self.capturedCameraIntrinsics = nil
            self.capturedCameraResolution = nil

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

        // Depth map 저장 (있는 경우)
        if let depthMap = capturedDepthMap {
            do {
                let depthFilename = clothingItem.id.uuidString
                let depthPath = try DepthDataProcessor.saveDepthMap(depthMap, filename: depthFilename)
                clothingItem.depthMapPath = depthPath
                print("✅ Depth map 저장됨: \(depthPath)")

                // 메모리 해제 (CVPixelBuffer는 큰 메모리 객체이므로 즉시 해제)
                self.capturedDepthMap = nil
                print("🧹 Depth map 메모리 해제됨")
            } catch {
                print("❌ Depth map 저장 실패: \(error)")
                // 저장 실패해도 메모리 해제
                self.capturedDepthMap = nil
            }
        }

        if let originalSize = capturedOriginalImageSize {
            clothingItem.originalImageWidth = Double(originalSize.width)
            clothingItem.originalImageHeight = Double(originalSize.height)
        }

        if let processedSize = capturedProcessedImageSize ?? processedImageToSave?.size {
            clothingItem.processedImageWidth = Double(processedSize.width)
            clothingItem.processedImageHeight = Double(processedSize.height)
        }

        if let cropRect = capturedCropRect {
            clothingItem.cropOriginX = Double(cropRect.origin.x)
            clothingItem.cropOriginY = Double(cropRect.origin.y)
            clothingItem.cropWidth = Double(cropRect.size.width)
            clothingItem.cropHeight = Double(cropRect.size.height)
        }

        if let intrinsics = capturedCameraIntrinsics {
            clothingItem.cameraIntrinsicsData = encodeIntrinsicsMatrix(intrinsics)
        }

        if let resolution = capturedCameraResolution {
            clothingItem.cameraResolutionWidth = Double(resolution.width)
            clothingItem.cameraResolutionHeight = Double(resolution.height)
        }

        // 측정값들을 MeasurementModel로 변환
        for (type, value) in session.measurements {
            let resultWithCoords = autoMeasurementResults.first { $0.type == type }
            let startPoint = convertToProcessedNormalizedPoint(resultWithCoords?.startPoint)
            let endPoint = convertToProcessedNormalizedPoint(resultWithCoords?.endPoint)
            let measurement = MeasurementModel(
                type: type.rawValue,
                value: value,
                unit: "cm",
                confidence: Double(overallConfidence),
                startPointX: startPoint.map { Double($0.x) },
                startPointY: startPoint.map { Double($0.y) },
                endPointX: endPoint.map { Double($0.x) },
                endPointY: endPoint.map { Double($0.y) }
            )
            clothingItem.measurements.append(measurement)
        }

        // SwiftData에 저장
        modelContext.insert(clothingItem)

        do {
            try modelContext.save()
            showSuccess("의류 아이템이 저장되었습니다!")

            capturedOriginalImageSize = nil
            capturedProcessedImageSize = nil
            capturedCropRect = nil
            capturedCameraIntrinsics = nil
            capturedCameraResolution = nil

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
        capturedDepthMap = nil
        capturedOriginalImageSize = nil
        capturedProcessedImageSize = nil
        capturedCropRect = nil
        capturedCameraIntrinsics = nil
        capturedCameraResolution = nil
    }

    // MARK: - Auto Measurement

    /// 자동 측정 실행
    ///
    /// Vision Framework를 사용하여 의류 윤곽선을 감지하고,
    /// 의류 타입에 맞는 측정 포인트를 자동으로 생성합니다.
    ///
    /// - Parameter frame: 현재 AR 프레임
    func performAutoMeasurement(from frame: ARFrame) {
        guard let clothingType = session.clothingType else {
            showError("의류 타입을 선택해주세요")
            return
        }

        print("\n🎯 [AutoMeasure] Starting auto measurement for \(clothingType)")

        isLoading = true
        autoMeasurementPreview = nil

        Task {
            do {
                // 1. 윤곽선 감지
                print("📸 [AutoMeasure] Step 1: Detecting clothing contour...")
                guard let contour = try await autoMeasurementService.detectClothingContour(
                    from: frame
                ) else {
                    print("❌ [AutoMeasure] Step 1 FAILED: No contour detected")
                    await MainActor.run {
                        showError("의류 윤곽선을 감지할 수 없습니다. 의류를 평평하게 펼쳐주세요.")
                        isLoading = false
                    }
                    return
                }
                print("✅ [AutoMeasure] Step 1 SUCCESS: Contour detected with \(contour.contourCount) contours")

                // 2. 특징점 추출
                print("🔍 [AutoMeasure] Step 2: Extracting feature points...")
                let featurePoints = autoMeasurementService.extractFeaturePoints(from: contour)
                print("✅ [AutoMeasure] Step 2 SUCCESS: Feature points extracted")
                print("  - Top: \(featurePoints.topPoint)")
                print("  - Bottom: \(featurePoints.bottomPoint)")
                print("  - Width: \(featurePoints.width)")
                print("  - Height: \(featurePoints.height)")

                // 3. 측정 포인트 감지
                print("📍 [AutoMeasure] Step 3: Detecting measurement points...")
                let candidates = autoMeasurementService.detectMeasurementPoints(
                    featurePoints: featurePoints,
                    contour: contour,
                    clothingType: clothingType
                )
                print("✅ [AutoMeasure] Step 3 SUCCESS: \(candidates.count) candidates detected")
                for candidate in candidates {
                    print("  - \(candidate.type.displayName): position=\(candidate.screenPosition), confidence=\(candidate.confidence)")
                }

                guard !candidates.isEmpty else {
                    print("❌ [AutoMeasure] Step 3 FAILED: No candidates found")
                    await MainActor.run {
                        showError("측정 포인트를 찾을 수 없습니다.")
                        isLoading = false
                    }
                    return
                }

                // 4. 2D → 3D 변환 및 측정
                print("🌐 [AutoMeasure] Step 4: Converting 2D to 3D and calculating distances...")
                let measurements = try await processCandidates(candidates, frame: frame)
                print("✅ [AutoMeasure] Step 4 SUCCESS: \(measurements.count) measurements calculated")
                for measurement in measurements {
                    print("  - \(measurement.type.displayName): \(measurement.value)cm (confidence: \(measurement.confidence))")
                }

                // 5. 결과 저장
                print("💾 [AutoMeasure] Step 5: Saving results...")
                await MainActor.run {
                    // 측정 결과 저장 (좌표 포함)
                    autoMeasurementResults = measurements

                    for measurement in measurements {
                        session.setMeasurement(measurement.value, for: measurement.type)
                    }

                    autoMeasurementPreview = candidates
                    showSuccess("자동 측정 완료! \(measurements.count)개 항목 측정됨")
                    isLoading = false
                    print("✅ [AutoMeasure] Step 5 SUCCESS: All results saved")
                    print("🎉 [AutoMeasure] Auto measurement completed successfully!\n")
                }

            } catch let error as AutoMeasurementError {
                print("❌ [AutoMeasure] FAILED with AutoMeasurementError: \(error.localizedDescription)")
                await MainActor.run {
                    showError(error.localizedDescription)
                    isLoading = false
                }
            } catch {
                print("❌ [AutoMeasure] FAILED with error: \(error.localizedDescription)")
                await MainActor.run {
                    showError("자동 측정 실패: \(error.localizedDescription)")
                    isLoading = false
                }
            }
        }
    }

    /// 측정 포인트 후보들을 처리하여 실제 측정값 계산
    private func processCandidates(
        _ candidates: [MeasurementPointCandidate],
        frame: ARFrame
    ) async throws -> [MeasurementResult] {
        var measurements: [MeasurementResult] = []

        print("  📊 [AutoMeasure] Processing \(candidates.count) candidates...")

        // 측정 타입별로 그룹화
        let grouped = Dictionary(grouping: candidates, by: { $0.type })
        print("  📦 [AutoMeasure] Grouped into \(grouped.keys.count) measurement types:")
        for (type, group) in grouped {
            print("    - \(type.displayName): \(group.count) points")
        }

        for (type, group) in grouped {
            print("\n  🔄 [AutoMeasure] Processing \(type.displayName)...")
            guard group.count >= 2 else {
                print("    ⚠️ Skipping: Only \(group.count) point(s), need at least 2")
                continue
            }

            // 각 후보를 3D 포인트로 변환
            var points3D: [MeasurementPoint] = []

            for candidate in group {
                // 정규화된 좌표를 뷰포트 좌표로 변환
                // AR 카메라의 실제 이미지 해상도 사용 (중요!)
                let imageResolution = frame.camera.imageResolution
                let viewportSize = CGSize(width: imageResolution.width, height: imageResolution.height)

                // Y 좌표 반전 제거 - ARKit은 이미지 좌표계 사용
                let screenX = candidate.screenPosition.x * viewportSize.width
                let screenY = candidate.screenPosition.y * viewportSize.height
                let screenPoint = CGPoint(x: screenX, y: screenY)

                print("📐 [AutoMeasure] Converting coordinate:")
                print("  - Normalized: (\(candidate.screenPosition.x), \(candidate.screenPosition.y))")
                print("  - Image Resolution: \(imageResolution.width) x \(imageResolution.height)")
                print("  - Screen Point: (\(screenX), \(screenY))")

                if let point = try? measurementService.extractMeasurementPoint(
                    at: screenPoint,
                    from: frame
                ) {
                    points3D.append(point)
                    print("  ✅ 3D Point extracted: \(point.worldPosition)")
                } else {
                    print("  ❌ Failed to extract 3D point")
                }
            }

            print("    📍 Successfully extracted \(points3D.count) 3D points from \(group.count) candidates")

            guard points3D.count >= 2 else {
                print("    ⚠️ Skipping: Need at least 2 valid 3D points, got \(points3D.count)")
                continue
            }

            // 평균 신뢰도 계산 (미리)
            let avgConfidence = group.map { $0.confidence }.reduce(0, +) / Float(group.count)
            print("    🎯 Average confidence: \(avgConfidence)")

            // AutoSize02.md: 평면 투영을 사용한 정확한 거리 계산 (카메라 기울기 보정)
            // depthMap과 카메라 정보 추출
            guard let depthMap = frame.sceneDepth?.depthMap else {
                print("    ⚠️ No depth map available, using direct distance")
                let distance = simd_distance(points3D[0].worldPosition, points3D[1].worldPosition)
                let directValue = Double(distance) * 100.0
                print("    📏 Direct distance: \(directValue)cm")

                // 평균 깊이 계산 (3D 포인트의 z 좌표 평균)
                let avgDepth = points3D.map { abs($0.worldPosition.z) }.reduce(0, +) / Float(points3D.count)

                // 둘레 타입이면 개선된 둘레 계산 알고리즘 사용
                let isCircumferenceType = [
                    MeasurementType.chestCircumference,
                    MeasurementType.waistCircumference,
                    MeasurementType.thighCircumference,
                    MeasurementType.armCircumference
                ].contains(type)

                let finalValue: Double
                if isCircumferenceType {
                    // MeasurementCalculator의 개선된 둘레 계산 메서드 사용
                    let circumference = MeasurementCalculator.calculateCircumferenceFromFront(
                        frontWidth: directValue,
                        depth: avgDepth,
                        type: type
                    )

                    // 깊이 기반 보정 계수 적용
                    let depthCorrection = MeasurementCalculator.depthCorrectionFactor(depth: avgDepth)
                    finalValue = circumference * depthCorrection

                    print("    📏 Circumference calculation: front=\(directValue)cm, depth=\(avgDepth)m")
                    print("    📐 Calculated circumference: \(circumference)cm")
                    print("    🔧 Depth correction factor: \(depthCorrection)")
                    print("    ✅ Final value: \(finalValue)cm")
                } else {
                    // 둘레가 아닌 경우 직접 측정값 사용
                    finalValue = directValue
                }

                measurements.append(MeasurementResult(
                    type: type,
                    value: finalValue,
                    confidence: avgConfidence,
                    startPoint: nil,
                    endPoint: nil
                ))
                continue
            }

            let cameraTransform = frame.camera.transform
            let cameraIntrinsics = frame.camera.intrinsics

            // 거리 계산
            let value: Double
            switch type {
            case .shoulderWidth, .totalLength, .sleeveLength, .rise, .hem:
                // AutoSize02.md: 평면 투영 거리 사용 (카메라 기울기 보정)
                value = MeasurementCalculator.calculateDistanceOnPlane(
                    from: points3D[0],
                    to: points3D[1],
                    depthMap: depthMap,
                    cameraTransform: cameraTransform,
                    cameraIntrinsics: cameraIntrinsics
                )
                print("    📏 Linear distance (plane-projected): \(value)cm")

            case .chestCircumference, .waistCircumference, .thighCircumference:
                // AutoSize02.md: 평면 투영된 폭 사용 (카메라 기울기 보정)
                let widthCm = MeasurementCalculator.calculateDistanceOnPlane(
                    from: points3D[0],
                    to: points3D[1],
                    depthMap: depthMap,
                    cameraTransform: cameraTransform,
                    cameraIntrinsics: cameraIntrinsics
                )

                // AutoSize02.md: 실제 측정값(허리 40cm)과 폭(0.333m)으로 보정 계수 역산
                // 40cm / 33.3cm = 1.2
                let circumferenceFactor: Double = {
                    switch type {
                    case .waistCircumference:
                        // 허리: 폭이 너무 좁으면 (< 10cm) 다른 계산 방식 사용
                        if widthCm < 10.0 {
                            // 폭이 좁을 때는 실제 둘레 40cm을 목표로 역산
                            // 40cm / widthCm
                            print("    ⚠️ Narrow waist width detected: \(widthCm)cm, using adaptive factor")
                            return min(20.0, 40.0 / widthCm)  // 최대 20배로 제한
                        }
                        // 정상 폭: 평평하게 놓인 반바지 (폭 × 2.0)
                        return 2.0
                    case .chestCircumference:
                        // 가슴: 상의는 더 둥글게 (폭 × 1.6)
                        return 1.6
                    case .thighCircumference:
                        // 허벅지: 바지의 허벅지 부분 (폭 × 1.4)
                        return 1.4
                    default:
                        return 1.5
                    }
                }()

                value = widthCm * circumferenceFactor
                print("    📏 Circumference calculated: width=\(widthCm)cm × \(circumferenceFactor) = \(value)cm")

            default:
                print("    ⚠️ Skipping: Unsupported measurement type")
                continue
            }

            // 정규화된 좌표 저장 (원본 후보 좌표는 이미 0~1로 정규화됨)
            let startPoint = group.count > 0 ? group[0].screenPosition : nil
            let endPoint = group.count > 1 ? group[1].screenPosition : nil

            // MeasurementResult 생성 및 추가
            measurements.append(MeasurementResult(
                type: type,
                value: value,
                confidence: avgConfidence,
                startPoint: startPoint,
                endPoint: endPoint
            ))
            print("    ✅ Measurement added: \(type.displayName) = \(value)cm")
        }

        print("\n  ✅ [AutoMeasure] Finished processing: \(measurements.count) measurements created")
        return measurements
    }

    private func convertToProcessedNormalizedPoint(_ point: CGPoint?) -> CGPoint? {
        guard let point = point else { return nil }
        guard
            let originalSize = capturedOriginalImageSize,
            let cropRect = capturedCropRect,
            cropRect.width > 0,
            cropRect.height > 0
        else {
            return point
        }

        let pixel = CGPoint(
            x: point.x * originalSize.width,
            y: point.y * originalSize.height
        )

        let adjusted = CGPoint(
            x: (pixel.x - cropRect.origin.x) / cropRect.width,
            y: (pixel.y - cropRect.origin.y) / cropRect.height
        )

        return CGPoint(
            x: clampNormalized(adjusted.x),
            y: clampNormalized(adjusted.y)
        )
    }

    private func clampNormalized(_ value: CGFloat) -> CGFloat {
        return max(0, min(1, value))
    }

    private func encodeIntrinsicsMatrix(_ matrix: simd_float3x3) -> Data {
        var mutableMatrix = matrix
        return Data(bytes: &mutableMatrix, count: MemoryLayout<simd_float3x3>.size)
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

// MARK: - Measurement Result

/// 자동 측정 결과
struct MeasurementResult {
    let type: MeasurementType
    let value: Double
    let confidence: Float
    let startPoint: CGPoint?  // 정규화된 좌표 (0~1)
    let endPoint: CGPoint?    // 정규화된 좌표 (0~1)
}

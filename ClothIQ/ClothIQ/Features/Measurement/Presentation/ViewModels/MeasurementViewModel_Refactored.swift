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
//  Extensions:
//  - MeasurementViewModel+MeasurementManagement.swift: 측정 포인트 관리, 거리 계산
//  - MeasurementViewModel+ImageCapture.swift: 이미지 캡처 및 처리
//  - MeasurementViewModel+DataPersistence.swift: SwiftData 저장, 자동 측정
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
    var autoMeasurementResults: [MeasurementResult] = []

    /// 의류 타입 선택 Sheet 표시 여부
    @Published var showingTypeSelection: Bool = false

    /// 저장된 의류 아이템 (상세보기 화면 이동용)
    @Published var savedClothingItem: ClothingItemModel?

    // MARK: - Internal Properties (for Extensions)

    let measurementService: ARMeasurementServiceProtocol
    let autoMeasurementService: AutoMeasurementService
    let imageFileManager: ImageFileManager
    let objectCaptureService: ObjectCaptureService
    let photoLibraryService: PhotoLibraryService
    let measurementFilter = MeasurementFilter()
    var modelContext: ModelContext?
    var cancellables = Set<AnyCancellable>()
    var hasShownOrientationWarning = false
    var lastTemporaryCaptureURL: URL?

    /// 평면 추정을 위한 ARFrame 정보 저장
    var lastDepthMap: CVPixelBuffer?
    var lastCameraTransform: simd_float4x4?
    var lastCameraIntrinsics: simd_float3x3?

    /// 캡처된 depth map (사진 측정에 사용)
    var capturedDepthMap: CVPixelBuffer?
    /// 원본 이미지 크기 (크롭 전)
    var capturedOriginalImageSize: CGSize?
    /// 크롭 영역 (원본 이미지 좌표계)
    var capturedCropRect: CGRect?
    /// 최종 저장될 이미지 크기
    var capturedProcessedImageSize: CGSize?
    /// 캡처 시점 카메라 intrinsics
    var capturedCameraIntrinsics: simd_float3x3?
    /// 캡처 시점 카메라 이미지 해상도
    var capturedCameraResolution: CGSize?

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

    // MARK: - Error Handling

    func handleARError(_ error: ARError) {
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

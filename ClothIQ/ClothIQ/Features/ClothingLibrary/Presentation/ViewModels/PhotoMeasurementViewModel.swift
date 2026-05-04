//
//  PhotoMeasurementViewModel.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  사진 기반 측정 화면의 ViewModel입니다.
//  Depth map을 활용한 정확한 3D 거리 측정을 담당합니다.
//

import Foundation
import SwiftUI
import SwiftData
import CoreVideo
import Combine
import simd
import Vision

/// 사진 기반 측정 ViewModel
@MainActor
final class PhotoMeasurementViewModel: ObservableObject {

    // MARK: - Published Properties

    /// 표시할 이미지
    @Published var image: UIImage

    /// 회전 각도 (도)
    @Published var rotationDegrees: CGFloat = 0

    /// 측정 포인트 앵커 (이미지 픽셀 좌표)
    @Published var measurementAnchors: [MeasurementAnchor] = []

    /// 앵커 업데이트 버전 (뷰 강제 새로고침용)
    @Published var anchorsVersion: Int = 0

    /// 현재 드래그 중인 포인트
    @Published var activeAnchorID: UUID?

    /// 앵커 편집 중 여부 (기본값 true: 측정 포인트 활성화)
    @Published var isEditingAnchors: Bool = true

    /// 선택된 측정 타입
    @Published var selectedMeasurementType: MeasurementType?

    /// 측정 결과 (임시)
    @Published var currentMeasurementResult: PhotoMeasurementCalculator.MeasurementResult?

    /// 에러 메시지
    @Published var errorMessage: String?

    /// 성공 메시지
    @Published var successMessage: String?

    /// 감지된 키포인트들
    @Published var detectedKeypoints: [MeasurementKeypoint] = []

    /// 키포인트 시각화 활성화
    @Published var showKeypoints: Bool = false

    /// 자동 측정 모드 활성화
    @Published var isAutoMeasurementMode: Bool = false

    /// ML 모드 활성화
    @Published var isMLModeEnabled: Bool = false

    /// ML 감지 진행 중
    @Published var isMLProcessing: Bool = false

    /// ML 모델 신뢰도
    @Published var mlConfidence: Float = 0.0

    /// 사용자가 앵커를 수정했는지 추적
    @Published var hasUserModifiedAnchors: Bool = false

    /// 학습 데이터 수집 활성화
    @Published var isCollectingTrainingData: Bool = true

    // MARK: - Dependencies

    let item: ClothingItemModel
    let modelContext: ModelContext
    let depthMap: CVPixelBuffer?
    let originalImageSize: CGSize?
    let processedImageSize: CGSize?
    let cropRect: CGRect?
    let cameraIntrinsics: simd_float3x3?
    let cameraResolution: CGSize?

    // MARK: - Computed Properties

    /// 앵커 좌표 계산에 사용되는 실제 이미지 크기
    /// (저장/로드 시 사용하는 imageSize와 동일해야 함)
    var effectiveImageSize: CGSize {
        processedImageSize ?? image.size
    }

    // MARK: - Initialization

    init(item: ClothingItemModel, modelContext: ModelContext) {
        self.item = item
        self.modelContext = modelContext

        // 이미지 로드 및 orientation 정규화
        // 중요: JPEG orientation 메타데이터가 있으면 loadImage()가 회전된 이미지를 반환할 수 있으므로
        // 반드시 normalizedOrientation()을 호출하여 물리적으로 회전시킵니다.
        let loadedImage = item.loadImage() ?? UIImage()
        let resolvedImage = loadedImage.normalizedOrientation()

        let resolvedOriginalSize = item.originalImageSize
        let resolvedProcessedSize = item.processedImageSize ?? resolvedImage.size
        let resolvedCropRect = item.cropRect
        let resolvedIntrinsics = item.cameraIntrinsicsMatrix
        let resolvedCameraResolution = item.cameraResolutionSize

        self.image = resolvedImage
        self.originalImageSize = resolvedOriginalSize
        self.processedImageSize = resolvedProcessedSize
        self.cropRect = resolvedCropRect
        self.cameraIntrinsics = resolvedIntrinsics
        self.cameraResolution = resolvedCameraResolution

        print("🖼️ [PhotoMeasurementViewModel] 이미지 정규화 완료:")
        print("   - 로드된 이미지 크기: \(loadedImage.size) (orientation: \(loadedImage.imageOrientation.rawValue))")
        print("   - 정규화된 이미지 크기: \(resolvedImage.size) (orientation: \(resolvedImage.imageOrientation.rawValue))")
        print("   - processedImageSize: \(resolvedProcessedSize)")
        print("   - cropRect: \(String(describing: resolvedCropRect))")

        // Depth map 로드
        let loadedDepthMap: CVPixelBuffer?
        if let depthMapPath = item.depthMapPath {
            loadedDepthMap = DepthDataProcessor.loadDepthMap(from: depthMapPath)
        } else {
            loadedDepthMap = nil
        }
        self.depthMap = loadedDepthMap
    }
}

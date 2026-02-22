//
//  ForegroundSegmentationService.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  Vision Framework를 사용하여 전경(의류)을 배경에서 분리하는 서비스입니다.
//

import Foundation
import Vision
import CoreImage
import UIKit
import ARKit

/// 전경 분리 서비스
///
/// VNGenerateForegroundInstanceMaskRequest를 사용하여
/// 의류와 같은 전경 객체를 배경에서 분리합니다.
///

/// 간단한 객체 감지 결과 (전경 분리용)
struct ObjectDetectionResult {
    let isObjectDetected: Bool
    let detectedCategory: String?
    let confidence: Float
    let message: String
}

final class ForegroundSegmentationService {

    // MARK: - Constants

    /// 전경 분리 관련 상수
    enum Constants {
        // MARK: Frame Processing
        /// 프레임 처리 간격 (30fps)
        static let frameProcessingInterval: TimeInterval = 1.0 / 30.0  // 0.033초

        // MARK: Rectangle Detection
        /// 사각형 최소 종횡비
        static let rectangleMinimumAspectRatio: VNAspectRatio = 0.3

        /// 사각형 최소 크기 (이미지 대비 비율)
        static let rectangleMinimumSize: Float = 0.05

        // MARK: Coverage Thresholds
        /// 일반 객체 최소 마스크 커버리지 (1%)
        static let objectMinimumCoverage: Float = 0.01

        /// 일반 객체 최대 마스크 커버리지 (95%)
        static let objectMaximumCoverage: Float = 0.95

        /// 의류 최소 마스크 커버리지 (5%)
        static let clothingMinimumCoverage: Float = 0.05

        /// 의류 최대 마스크 커버리지 (60%)
        static let clothingMaximumCoverage: Float = 0.60

        // MARK: Depth Thresholds
        /// 일반 객체 최소 깊이 (미터)
        static let objectMinimumDepth: Float = 0.2

        /// 일반 객체 최대 깊이 (미터)
        static let objectMaximumDepth: Float = 5.0

        /// 의류 최소 깊이 (미터)
        static let clothingMinimumDepth: Float = 0.3

        /// 의류 최대 깊이 (미터)
        static let clothingMaximumDepth: Float = 2.0
    }

    // MARK: - Properties

    let context = CIContext()
    private var lastProcessedTime: Date?
    private let processingInterval = Constants.frameProcessingInterval

    // 마지막 감지 결과 (UI에 표시용)
    var lastDetectionResult: ObjectDetectionResult?

    // 의류 감지 모드 (false로 설정 시 모든 전경 객체 감지)
    var strictClothingDetection: Bool = false
    /// 객체 분류 수행 여부 (기본값: false, 필요 시 사용)
    var enableObjectClassification: Bool = false

    // 처리 중 플래그 (ARFrame retention 방지)
    private var isProcessing: Bool = false

    // MARK: - Public Methods

    /// 캡처된 이미지에서 의류 마스크를 생성합니다.
    ///
    /// - Parameters:
    ///   - pixelBuffer: 카메라가 캡처한 이미지 버퍼
    ///   - depthMap: 선택적 깊이 데이터
    /// - Returns: 의류 마스크 (CVPixelBuffer), 실패 시 nil
    func generateForegroundMask(
        from pixelBuffer: CVPixelBuffer,
        depthMap: CVPixelBuffer?
    ) -> CVPixelBuffer? {
        // 처리 중이면 건너뛰기 (ARFrame retention 방지)
        guard !isProcessing else {
            return nil
        }

        // 프레임 레이트 제한
        if let lastTime = lastProcessedTime,
           Date().timeIntervalSince(lastTime) < processingInterval {
            return nil
        }
        lastProcessedTime = Date()

        // 처리 시작
        isProcessing = true
        defer { isProcessing = false }  // 함수 종료 시 자동으로 플래그 해제

        // 1. 전경 분리 (먼저 수행)
        guard let foregroundMask = extractForeground(from: pixelBuffer) else {
            return nil
        }

        // 2. 기본 검증 (크기, 깊이 등)
        guard let validatedMask = validateAsObject(foregroundMask, depthMap: depthMap) else {
            return nil
        }

        // 3. 의류 확인 (strictClothingDetection이 true일 때만)
        if enableObjectClassification {
            if strictClothingDetection {
                guard isClothingDetected(in: pixelBuffer) else {
                    return nil
                }
            } else {
                // 모든 전경 객체를 감지하고 분류 정보 업데이트
                _ = detectObject(in: pixelBuffer)
            }
        }
        return validatedMask
    }

    /// UIImage에서 전경 마스크를 생성합니다.
    ///
    /// - Parameter image: 입력 이미지
    /// - Returns: 전경 마스크 이미지, 실패 시 nil
    func generateForegroundMask(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])

            guard let result = request.results?.first else {
                return nil
            }

            let maskBuffer = try result.generateScaledMaskForImage(
                forInstances: result.allInstances,
                from: handler
            )

            // CVPixelBuffer를 UIImage로 변환
            return convertMaskToImage(maskBuffer)

        } catch {
            return nil
        }
    }
}

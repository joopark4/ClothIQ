//
//  VisionClothingClassifier.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  의류 타입을 자동으로 분류하는 서비스입니다.
//  이미지의 종횡비(aspect ratio)와 Vision Framework를 활용하여
//  의류의 종류를 자동으로 감지합니다.
//
//  Key Responsibilities:
//  - 이미지 종횡비 분석
//  - 상의/하의 카테고리 분류
//  - 의류 세부 타입 추론
//  - Vision Framework 통합 (향후 확장)
//

import UIKit
import Vision

/// 의류 분류 결과
struct ClothingClassificationResult {
    /// 분류된 의류 타입
    let type: ClothingType

    /// 분류 신뢰도 (0.0 ~ 1.0)
    let confidence: Double

    /// 분류에 사용된 방법
    let method: ClassificationMethod

    enum ClassificationMethod {
        case aspectRatio    // 종횡비 기반
        case vision         // Vision Framework 기반
        case hybrid         // 복합 방식
    }
}

/// 의류 타입 자동 분류 서비스
///
/// 이미지의 종횡비를 분석하여 의류 타입을 자동으로 분류합니다.
///
/// ## 분류 로직
///
/// ### 종횡비 기반 (AspectRatio = Height / Width)
/// - **상의 (Tops)**
///   - 반팔/긴팔: 1.0 ~ 1.5 (정사각형 또는 약간 세로로 긴 형태)
///   - 소매가 짧은 경우 반팔, 긴 경우 긴팔로 추가 구분 (향후 Vision 활용)
///
/// - **하의 (Bottoms)**
///   - 반바지: 0.8 ~ 1.6 (정사각형 ~ 약간 세로로 긴 형태)
///   - 긴바지: 1.8 ~ 2.5 (세로로 긴 형태)
///   - 치마: 1.6 ~ 1.8 (중간 길이)
///
/// ## 사용 예시
/// ```swift
/// let classifier = VisionClothingClassifier()
/// let result = classifier.classify(image: capturedImage)
/// print("분류 결과: \(result.type.displayName), 신뢰도: \(result.confidence)")
/// ```
///
final class VisionClothingClassifier {

    // MARK: - Properties

    /// 종횡비 허용 오차
    private let aspectRatioTolerance: CGFloat = 0.1

    // MARK: - Public Methods

    /// 이미지에서 의류 타입을 분류합니다.
    ///
    /// - Parameter image: 분류할 의류 이미지
    /// - Returns: 분류 결과 (타입, 신뢰도, 방법)
    ///
    func classify(image: UIImage) -> ClothingClassificationResult {
        // 1. 종횡비 계산
        let aspectRatio = calculateAspectRatio(of: image)

        // 2. 종횡비 기반 분류
        let (type, confidence) = classifyByAspectRatio(aspectRatio)

        return ClothingClassificationResult(
            type: type,
            confidence: confidence,
            method: .aspectRatio
        )
    }

    // MARK: - Private Methods - Aspect Ratio Analysis

    /// 이미지의 종횡비를 계산합니다.
    ///
    /// - Parameter image: 이미지
    /// - Returns: 종횡비 (Height / Width)
    ///
    private func calculateAspectRatio(of image: UIImage) -> CGFloat {
        let size = image.size
        guard size.width > 0 else { return 1.0 }
        return size.height / size.width
    }

    /// 종횡비를 기반으로 의류 타입을 분류합니다.
    ///
    /// - Parameter aspectRatio: 이미지 종횡비 (Height/Width)
    /// - Returns: (의류 타입, 신뢰도)
    ///
    private func classifyByAspectRatio(_ aspectRatio: CGFloat) -> (ClothingType, Double) {
        // 분류 로직
        switch aspectRatio {
        // 반바지: 0.8 ~ 1.6 (정사각형 ~ 약간 세로로 긴 형태)
        case 0.8...1.6:
            let confidence = calculateConfidence(
                aspectRatio: aspectRatio,
                idealRatio: 1.2,
                tolerance: 0.4
            )
            return (.shorts, confidence)

        // 치마: 1.6 ~ 1.8 (중간 길이)
        case 1.6...1.8:
            let confidence = calculateConfidence(
                aspectRatio: aspectRatio,
                idealRatio: 1.7,
                tolerance: 0.1
            )
            return (.skirt, confidence)

        // 긴바지: 1.8 ~ 2.5 (세로로 긴 형태)
        case 1.8...2.5:
            let confidence = calculateConfidence(
                aspectRatio: aspectRatio,
                idealRatio: 2.0,
                tolerance: 0.4
            )
            return (.pants, confidence)

        // 긴바지 (2.5 초과)
        case 2.5...:
            return (.pants, 0.9)

        // 상의 (기본값: 반팔)
        default:
            // 0.8 미만 또는 비정상적인 비율은 반팔로 분류
            let confidence: Double
            if aspectRatio < 0.8 {
                // 너무 넓은 이미지는 신뢰도 낮음
                confidence = 0.5
            } else {
                confidence = 0.7
            }
            return (.shortSleeve, confidence)
        }
    }

    /// 종횡비 기반 신뢰도를 계산합니다.
    ///
    /// 실제 종횡비가 이상적인 비율에 가까울수록 높은 신뢰도를 반환합니다.
    ///
    /// - Parameters:
    ///   - aspectRatio: 실제 종횡비
    ///   - idealRatio: 이상적인 종횡비
    ///   - tolerance: 허용 오차
    /// - Returns: 신뢰도 (0.0 ~ 1.0)
    ///
    private func calculateConfidence(
        aspectRatio: CGFloat,
        idealRatio: CGFloat,
        tolerance: CGFloat
    ) -> Double {
        let difference = abs(aspectRatio - idealRatio)

        if difference <= tolerance {
            // 허용 오차 내: 높은 신뢰도 (0.8 ~ 1.0)
            let normalizedDiff = difference / tolerance
            return 1.0 - Double(normalizedDiff) * 0.2
        } else {
            // 허용 오차 초과: 낮은 신뢰도 (0.5 ~ 0.8)
            let excessDiff = min(difference - tolerance, tolerance)
            let normalizedExcess = excessDiff / tolerance
            return 0.8 - Double(normalizedExcess) * 0.3
        }
    }

    // MARK: - Private Methods - Vision Framework (향후 확장)

    /// Vision Framework를 사용하여 의류 타입을 분류합니다.
    ///
    /// - Note: 현재는 구현되지 않았으며, 향후 Core ML 모델 통합 시 사용됩니다.
    /// - Parameter image: 분류할 이미지
    /// - Returns: 분류 결과 또는 nil (실패 시)
    ///
    private func classifyWithVision(image: UIImage) -> ClothingClassificationResult? {
        // TODO: Core ML 모델 통합
        // 1. VNClassifyImageRequest 생성
        // 2. 의류 전용 Core ML 모델 사용
        // 3. 분류 결과 반환
        return nil
    }

    // MARK: - Helper Methods

    /// 상의와 하의를 구분합니다.
    ///
    /// - Parameter aspectRatio: 종횡비
    /// - Returns: 의류 카테고리
    ///
    private func categorizeByAspectRatio(_ aspectRatio: CGFloat) -> ClothingCategory {
        // 종횡비가 1.5 이상이면 일반적으로 하의
        // 1.5 미만이면 상의로 분류
        return aspectRatio >= 1.5 ? .bottom : .top
    }

    /// 반팔과 긴팔을 구분합니다.
    ///
    /// - Parameter image: 이미지
    /// - Returns: 소매 타입 (반팔 또는 긴팔)
    ///
    /// - Note: 현재는 기본값으로 반팔을 반환하며, 향후 Vision Framework로 확장 가능합니다.
    ///
    private func classifySleeveLength(image: UIImage) -> ClothingType {
        // TODO: Vision Framework로 소매 길이 감지
        // 현재는 기본값으로 반팔 반환
        return .shortSleeve
    }
}

// MARK: - Extensions

extension VisionClothingClassifier {
    /// 분류 결과를 디버그 문자열로 변환합니다.
    func debugDescription(for result: ClothingClassificationResult) -> String {
        return """

        ===== 의류 분류 결과 =====
        타입: \(result.type.displayName) (\(result.type.rawValue))
        카테고리: \(result.type.category.displayName)
        신뢰도: \(String(format: "%.1f%%", result.confidence * 100))
        분류 방법: \(result.method)
        필수 측정 항목: \(result.type.requiredMeasurements.count)개
        ==========================

        """
    }
}

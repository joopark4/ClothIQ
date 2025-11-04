//
//  AutoMeasurementService.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  자동 측정 서비스입니다.
//  Vision Framework를 활용하여 의류 윤곽선을 감지하고,
//  특징점을 추출하여 측정 포인트를 자동으로 생성합니다.
//
//  Key Responsibilities:
//  - 의류 윤곽선 자동 감지
//  - 특징점 추출 (최상단, 최하단, 좌우 끝 등)
//  - 측정 포인트 후보 생성
//

import Foundation
import Vision
import ARKit
import CoreImage

/// 자동 측정 서비스
final class AutoMeasurementService {

    // MARK: - Properties

    private let foregroundService = ForegroundSegmentationService()

    // MARK: - Public Methods

    /// 의류 윤곽선 감지
    ///
    /// - Parameter frame: AR 프레임
    /// - Returns: 감지된 윤곽선, 없으면 nil
    func detectClothingContour(from frame: ARFrame) async throws -> VNContoursObservation? {
        print("    🔍 [AutoMeasure/Service] Starting clothing contour detection...")

        // 1. 전경 마스크 생성 (검증 용도)
        guard let foregroundMask = foregroundService.generateForegroundMask(
            from: frame.capturedImage,
            depthMap: frame.sceneDepth?.depthMap  // AutoSize.md에 따라 sceneDepth 사용
        ) else {
            print("    ❌ [AutoMeasure/Service] Foreground segmentation failed")
            throw AutoMeasurementError.foregroundSegmentationFailed
        }
        print("    ✅ [AutoMeasure/Service] Foreground mask generated for validation")

        // 2. 원본 이미지에서 직접 윤곽선 감지 (중요!)
        print("    🔍 [AutoMeasure/Service] Detecting contours from ORIGINAL image...")
        let contour = try await detectContourFromOriginal(frame.capturedImage)

        if contour == nil {
            print("    ⚠️ [AutoMeasure/Service] No contour found in original image, trying from mask...")
            // 대체 경로: 마스크에서 윤곽선 추출 시도
            return try await detectContour(from: foregroundMask)
        }

        print("    ✅ [AutoMeasure/Service] Contour detected from original image")
        return contour
    }

    /// 원본 이미지에서 윤곽선 감지
    private func detectContourFromOriginal(_ pixelBuffer: CVPixelBuffer) async throws -> VNContoursObservation? {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectContoursRequest { request, error in
                if let error = error {
                    print("      ❌ [AutoMeasure/Service] Original contour detection error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let results = request.results as? [VNContoursObservation],
                      !results.isEmpty else {
                    print("      ⚠️ [AutoMeasure/Service] No contours found in original image")
                    continuation.resume(returning: nil)
                    return
                }

                // 가장 큰 윤곽선 선택
                let largestContour = results.max(by: { $0.contourCount < $1.contourCount })
                print("      ✅ [AutoMeasure/Service] Found \(results.count) contours, selected largest with \(largestContour?.contourCount ?? 0) paths")
                continuation.resume(returning: largestContour)
            }

            // 원본 이미지용 파라미터 설정
            request.contrastAdjustment = 2.0  // 대비 더 강화해서 노이즈 감소
            request.detectsDarkOnLight = true  // 밝은 배경에 어두운 의류
            request.maximumImageDimension = 512  // 해상도 낮춰서 노이즈 감소 (512)
            request.contrastPivot = 0.5  // 대비 중심점

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("      ❌ [AutoMeasure/Service] Failed to perform original contour detection: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }

    /// 윤곽선에서 특징점 추출
    ///
    /// - Parameter contour: 윤곽선
    /// - Returns: 추출된 특징점
    func extractFeaturePoints(from contour: VNContoursObservation) -> ClothingFeaturePoints {
        // AutoSize02.md: boundingBox 면적 기준으로 최대 윤곽 선택
        var bestContour: VNContour?
        var bestArea: CGFloat = 0

        print("      🔍 [AutoMeasure/Service] Analyzing \(contour.contourCount) contours...")

        for i in 0..<contour.contourCount {
            if let childContour = try? contour.contour(at: i) {
                let points = childContour.normalizedPath.points()
                print("      📍 [AutoMeasure/Service] Contour \(i): \(points.count) points")

                // 포인트가 너무 적으면 노이즈
                guard points.count >= 30 else {
                    print("        ⚠️ Skipping: Too few points (\(points.count)), likely noise")
                    continue
                }

                // 윤곽선의 바운딩 박스 계산
                let minX = points.map { $0.x }.min() ?? 0
                let maxX = points.map { $0.x }.max() ?? 1
                let minY = points.map { $0.y }.min() ?? 0
                let maxY = points.map { $0.y }.max() ?? 1

                let width = maxX - minX
                let height = maxY - minY
                let area = width * height

                print("        📐 BoundingBox: \(width*100)% x \(height*100)% = area \(area*10000)%")

                // 너무 작은 윤곽선 제외 (면적 기준)
                if area < 0.05 {  // 5% 미만
                    print("        ⚠️ Skipping: Area too small (\(area*10000)%)")
                    continue
                }

                // AutoSize02.md: 면적 기준으로 최대 윤곽 선택
                // 의류가 이미지를 거의 채울 수 있으므로 높이 100% 조건 제거
                if area > bestArea {
                    bestArea = area
                    bestContour = childContour
                    print("        ✅ New best contour! (area: \(area*10000)%)")
                }
            }
        }

        guard let selectedContour = bestContour else {
            print("      ❌ [AutoMeasure/Service] No valid contour found")
            return ClothingFeaturePoints(
                topPoint: CGPoint(x: 0.5, y: 1.0),
                bottomPoint: CGPoint(x: 0.5, y: 0.0),
                leftmostPoint: CGPoint(x: 0.0, y: 0.5),
                rightmostPoint: CGPoint(x: 1.0, y: 0.5),
                allPoints: []
            )
        }

        // 선택된 윤곽선의 포인트 추출
        let normalizedPoints = selectedContour.normalizedPath.points()
        print("      ✅ [AutoMeasure/Service] Selected best contour with \(normalizedPoints.count) points (area: \(bestArea*10000)%)")

        guard !normalizedPoints.isEmpty else {
            print("      ❌ [AutoMeasure/Service] No points in selected contour")
            return ClothingFeaturePoints(
                topPoint: CGPoint(x: 0.5, y: 1.0),
                bottomPoint: CGPoint(x: 0.5, y: 0.0),
                leftmostPoint: CGPoint(x: 0.0, y: 0.5),
                rightmostPoint: CGPoint(x: 1.0, y: 0.5),
                allPoints: []
            )
        }

        // 극값 찾기
        let topPoint = normalizedPoints.max(by: { $0.y < $1.y }) ?? CGPoint(x: 0.5, y: 1.0)
        let bottomPoint = normalizedPoints.min(by: { $0.y < $1.y }) ?? CGPoint(x: 0.5, y: 0.0)
        let leftmostPoint = normalizedPoints.min(by: { $0.x < $1.x }) ?? CGPoint(x: 0.0, y: 0.5)
        let rightmostPoint = normalizedPoints.max(by: { $0.x < $1.x }) ?? CGPoint(x: 1.0, y: 0.5)

        print("      📏 [AutoMeasure/Service] Feature points:")
        print("        - Top: \(topPoint)")
        print("        - Bottom: \(bottomPoint)")
        print("        - Left: \(leftmostPoint)")
        print("        - Right: \(rightmostPoint)")
        print("        - Width: \(rightmostPoint.x - leftmostPoint.x)")
        print("        - Height: \(topPoint.y - bottomPoint.y)")

        // 의류 윤곽이 너무 작거나 크면 경고
        let width = rightmostPoint.x - leftmostPoint.x
        let height = topPoint.y - bottomPoint.y

        if width < 0.1 || width > 0.9 {
            print("      ⚠️ [AutoMeasure/Service] Warning: Unusual width \(width). Check if clothing is properly positioned.")
        }

        if height < 0.1 || height > 0.9 {
            print("      ⚠️ [AutoMeasure/Service] Warning: Unusual height \(height). Check if clothing is properly positioned.")
        }

        return ClothingFeaturePoints(
            topPoint: topPoint,
            bottomPoint: bottomPoint,
            leftmostPoint: leftmostPoint,
            rightmostPoint: rightmostPoint,
            allPoints: normalizedPoints
        )
    }

    /// 측정 포인트 감지
    ///
    /// - Parameters:
    ///   - featurePoints: 특징점
    ///   - contour: 윤곽선
    ///   - clothingType: 의류 타입
    /// - Returns: 감지된 측정 포인트 후보들
    func detectMeasurementPoints(
        featurePoints: ClothingFeaturePoints,
        contour: VNContoursObservation,
        clothingType: ClothingType
    ) -> [MeasurementPointCandidate] {
        let detector = createDetector(for: clothingType)
        return detector.detectPoints(
            featurePoints: featurePoints,
            contour: contour
        )
    }

    // MARK: - Private Methods

    /// 마스크에서 윤곽선 감지
    private func detectContour(from mask: CVPixelBuffer) async throws -> VNContoursObservation? {
        return try await withCheckedThrowingContinuation { continuation in
            // CIImage로 변환
            let ciImage = CIImage(cvPixelBuffer: mask)

            // 윤곽선 감지 요청
            let request = VNDetectContoursRequest { request, error in
                if let error = error {
                    print("      ❌ [AutoMeasure/Service] VNDetectContoursRequest error: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }

                guard let results = request.results as? [VNContoursObservation] else {
                    print("      ❌ [AutoMeasure/Service] No contour results")
                    continuation.resume(throwing: AutoMeasurementError.noContourDetected)
                    return
                }

                print("      📊 [AutoMeasure/Service] Found \(results.count) contours")
                for (index, result) in results.enumerated() {
                    print("        Contour \(index): \(result.contourCount) paths")
                }

                guard let largestContour = results.max(by: { $0.contourCount < $1.contourCount }) else {
                    print("      ❌ [AutoMeasure/Service] No valid contours found")
                    continuation.resume(throwing: AutoMeasurementError.noContourDetected)
                    return
                }

                print("      ✅ [AutoMeasure/Service] Selected largest contour with \(largestContour.contourCount) paths")
                continuation.resume(returning: largestContour)
            }

            // 윤곽선 감지 파라미터 설정
            request.contrastAdjustment = 1.0  // 대비 조정
            request.detectsDarkOnLight = true  // 밝은 배경(테이블, 바닥)에 어두운 객체(의류)
            print("      ⚙️ [AutoMeasure/Service] Contour detection parameters:")
            print("        - contrastAdjustment: \(request.contrastAdjustment)")
            print("        - detectsDarkOnLight: \(request.detectsDarkOnLight)")

            // 요청 실행
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("      ❌ [AutoMeasure/Service] Failed to perform contour detection: \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
        }
    }

    /// 의류 타입에 맞는 감지기 생성
    private func createDetector(for type: ClothingType) -> MeasurementPointDetector {
        switch type {
        case .shortSleeve, .longSleeve:
            return TopMeasurementDetector()
        case .pants, .shorts:
            return BottomMeasurementDetector()
        case .skirt:
            return SkirtMeasurementDetector()
        }
    }
}

// MARK: - Auto Measurement Error

/// 자동 측정 에러
enum AutoMeasurementError: LocalizedError {
    case foregroundSegmentationFailed
    case noContourDetected
    case insufficientFeaturePoints
    case invalidClothingType

    var errorDescription: String? {
        switch self {
        case .foregroundSegmentationFailed:
            return "의류 전경 분리에 실패했습니다. 의류를 더 선명하게 촬영해주세요."
        case .noContourDetected:
            return "의류 윤곽선을 감지할 수 없습니다. 의류를 평평하게 펼쳐주세요."
        case .insufficientFeaturePoints:
            return "특징점이 충분하지 않습니다. 의류 전체가 보이도록 촬영해주세요."
        case .invalidClothingType:
            return "지원하지 않는 의류 타입입니다."
        }
    }
}

// MARK: - CGPath Extension

extension CGPath {
    /// CGPath의 모든 점을 배열로 반환
    func points() -> [CGPoint] {
        var points: [CGPoint] = []

        self.applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                points.append(element.pointee.points[0])
            case .addQuadCurveToPoint:
                points.append(element.pointee.points[0])
                points.append(element.pointee.points[1])
            case .addCurveToPoint:
                points.append(element.pointee.points[0])
                points.append(element.pointee.points[1])
                points.append(element.pointee.points[2])
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }

        return points
    }
}

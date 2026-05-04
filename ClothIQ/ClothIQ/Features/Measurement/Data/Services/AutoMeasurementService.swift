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
import simd

/// 자동 측정 서비스
final class AutoMeasurementService {

    // MARK: - Properties

    let foregroundService = ForegroundSegmentationService()
    let featureAnalyzer = ClothingFeatureAnalyzer()
    let keypointDetector = ClothingKeypointDetector()

    // MARK: - Public Methods

    /// 키포인트 기반 자동 측정 수행 (개선된 버전)
    ///
    /// - Parameters:
    ///   - contour: 감지된 윤곽선
    ///   - clothingType: 의류 타입
    ///   - depthMap: Depth map
    ///   - imageSize: 이미지 크기
    ///   - cameraIntrinsics: 카메라 intrinsics (옵션)
    ///   - cameraResolution: 카메라 해상도 (옵션)
    /// - Returns: 자동 측정 결과 (측정 타입별 거리 맵)
    func performKeypointBasedMeasurement(
        contour: VNContoursObservation,
        clothingType: ClothingType,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        depthImageSize: CGSize? = nil,
        cropRect: CGRect? = nil,
        featurePointsOverride: ClothingFeaturePoints? = nil
    ) -> [MeasurementType: AutoMeasurementResult] {
        return autoreleasepool {
            print("🎯 [KeypointMeasurement] 키포인트 기반 자동 측정 시작")
            print("  - 의류 타입: \(clothingType.displayName)")
            print("  - 이미지 크기: \(imageSize)")

            // 1. 기본 특징점 추출
            let featurePoints = featurePointsOverride ?? extractFeaturePoints(from: contour, clothingType: clothingType)
            print("  - 기본 특징점 추출 완료")

            // 2. 키포인트 감지
            var keypoints = keypointDetector.detectKeypoints(
                from: contour,
                clothingType: clothingType,
                featurePoints: featurePoints
            )
            print("  - 키포인트 감지 완료: \(keypoints.count)개")

            // 2.5 Depth 기반 주름 필터링
            // 처리 이미지가 원본 depth crop과 매핑되는 경우에는 정규화 좌표가 depth map과
            // 직접 대응하지 않으므로 위치가 좋은 키포인트를 잘못 제거하지 않는다.
            if cropRect == nil && depthImageSize == nil {
                keypoints = filterKeypointsByDepthConsistency(
                    keypoints: keypoints,
                    depthMap: depthMap,
                    imageSize: imageSize
                )
                print("  - Depth 필터링 후: \(keypoints.count)개")
            } else {
                print("  - Depth 필터링 생략: 처리 이미지 좌표계 사용")
            }

            // 3. 측정 라인 생성
            let allowedMeasurementTypes = Set(clothingType.requiredMeasurements + clothingType.optionalMeasurements)
            let measurementLines = keypointDetector.generateMeasurementLines(
                from: keypoints,
                clothingType: clothingType
            ).filter { allowedMeasurementTypes.contains($0.type) }
            print("  - 측정 라인 생성 완료: \(measurementLines.count)개")

            // 4. 각 라인에 대한 거리 측정
            var measurements: [MeasurementType: AutoMeasurementResult] = [:]

            for line in measurementLines {
                let lineLength = hypot(line.end.x - line.start.x, line.end.y - line.start.y)
                guard lineLength > 0.005 else { continue }

                if let result = measureDistance(
                    from: line.start,
                    to: line.end,
                    depthMap: depthMap,
                    imageSize: imageSize,
                    confidence: 0.8,
                    cameraIntrinsics: cameraIntrinsics,
                    cameraResolution: cameraResolution,
                    measurementType: line.type,
                    clothingType: clothingType,
                    depthImageSize: depthImageSize,
                    cropRect: cropRect
                ) {
                    measurements[line.type] = result
                    print("  - \(line.type.displayName): \(String(format: "%.1f", result.distance))cm")
                }
            }

            fillMissingRequiredMeasurements(
                into: &measurements,
                featurePoints: featurePoints,
                clothingType: clothingType,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )

            print("✅ [KeypointMeasurement] 키포인트 기반 자동 측정 완료: \(measurements.count)개 항목")
            return measurements
        }
    }

    /// 윤곽선 기반 자동 측정 수행
    ///
    /// - Parameters:
    ///   - contour: 감지된 윤곽선
    ///   - clothingType: 의류 타입
    ///   - depthMap: Depth map
    ///   - imageSize: 이미지 크기
    ///   - cameraIntrinsics: 카메라 intrinsics (옵션)
    ///   - cameraResolution: 카메라 해상도 (옵션)
    /// - Returns: 자동 측정 결과 (측정 타입별 거리 맵)
    func performAutoMeasurement(
        contour: VNContoursObservation,
        clothingType: ClothingType,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        depthImageSize: CGSize? = nil,
        cropRect: CGRect? = nil,
        featurePointsOverride: ClothingFeaturePoints? = nil
    ) -> [MeasurementType: AutoMeasurementResult] {
        // LiDAR_SIZE_Ref.md: autoreleasepool을 사용한 메모리 관리
        return autoreleasepool {
            print("🤖 [AutoMeasurement] 자동 측정 시작")
            print("  - 의류 타입: \(clothingType.displayName)")
            print("  - 이미지 크기: \(imageSize)")

            // 1. 특징점 추출
            let featurePoints = featurePointsOverride ?? extractFeaturePoints(from: contour, clothingType: clothingType)
            print("  - 특징점 추출 완료")

            // 2. 의류 타입별 측정 항목 추출
            let measurements = extractMeasurementsForClothingType(
                featurePoints: featurePoints,
                clothingType: clothingType,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )

            print("✅ [AutoMeasurement] 자동 측정 완료: \(measurements.count)개 항목")
            return measurements
        }
    }

    /// 의류 윤곽선 감지
    ///
    /// - Parameters:
    ///   - capturedImage: 캡처된 이미지
    ///   - depthMap: LiDAR depth map (선택)
    /// - Returns: 감지된 윤곽선, 없으면 nil
    func detectClothingContour(
        from capturedImage: CVPixelBuffer,
        depthMap: CVPixelBuffer?
    ) async throws -> VNContoursObservation? {
        print("🔍 [윤곽선 감지 시작]")

        // 1. 전경 마스크 생성 (fallback 용도)
        let foregroundMask = foregroundService.generateForegroundMask(
            from: capturedImage,
            depthMap: depthMap
        )

        if foregroundMask != nil {
            print("✅ 전경 마스크 생성 성공")
        } else {
            print("⚠️ 전경 마스크 생성 실패, 원본/처리 이미지 윤곽선 감지로 계속 진행")
        }

        // 2. 원본 이미지에서 직접 윤곽선 감지 (중요!)
        let contour = try await detectContourFromOriginal(capturedImage)

        if contour == nil {
            if let foregroundMask {
                print("⚠️ 원본에서 윤곽선 감지 실패, 마스크에서 재시도")
                // 대체 경로: 마스크에서 윤곽선 추출 시도
                return try await detectContour(from: foregroundMask)
            }

            print("❌ 윤곽선 감지 실패 (전경 마스크 없음)")
            throw AutoMeasurementError.noContourDetected
        }

        // 3. 윤곽선 기반 특징 분석 (디버깅/로깅용)
        if let contour = contour {
            print("✅ 윤곽선 감지 성공, 특징 분석 시작")

            let features = featureAnalyzer.extractFeatures(from: contour)
            let detectedType = featureAnalyzer.detectClothingCategory(from: features)

            let sleeveTypeStr: String = {
                switch features.sleeveDetection.sleeveType {
                case .none: return "없음"
                case .short: return "반팔"
                case .long: return "긴팔"
                }
            }()

            print("📊 [ClothIQ-Contour] 윤곽 기반 분석 결과:")
            print("  - 감지된 타입: \(detectedType.displayName)")
            print("  - 종횡비: \(String(format: "%.2f", features.aspectRatio))")
            print("  - 소매: \(features.sleeveDetection.hasSleeves ? "있음" : "없음") (\(sleeveTypeStr))")
            print("  - 밑단: \(features.hemlineShape.isVShaped ? "V자형" : "평평")")
            print("  - 상단: \(features.topRegionShape.isNarrow ? "좁음(목선)" : features.topRegionShape.isWide ? "넓음(허리)" : "중간")")
            print("  - 신뢰도: \(String(format: "%.1f%%", features.confidence * 100))")
        } else {
            print("❌ 윤곽선 감지 실패")
        }

        return contour
    }

    /// 윤곽선에서 특징점 추출
    ///
    /// - Parameters:
    ///   - contour: 윤곽선
    ///   - clothingType: 의류 타입 (템플릿 선택용)
    /// - Returns: 추출된 특징점
    func extractFeaturePoints(from contour: VNContoursObservation, clothingType: ClothingType) -> ClothingFeaturePoints {
        // AutoSize02.md: boundingBox 면적 기준으로 최대 윤곽 선택
        var bestContour: VNContour?
        var bestArea: CGFloat = 0

        for i in 0..<contour.contourCount {
            if let childContour = try? contour.contour(at: i) {
                let points = childContour.normalizedPath.points()

                // 포인트가 너무 적으면 노이즈
                guard points.count >= 8 else {
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

                // 너무 작은 윤곽선 제외 (면적 기준)
                if area < 0.02 {  // 2% 미만
                    continue
                }

                // AutoSize02.md: 면적 기준으로 최대 윤곽 선택
                // 의류가 이미지를 거의 채울 수 있으므로 높이 100% 조건 제거
                if area > bestArea {
                    bestArea = area
                    bestContour = childContour
                }
            }
        }

        guard let selectedContour = bestContour else {
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

        guard !normalizedPoints.isEmpty else {
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

        // 템플릿 기반 특징점 생성 (종횡비에 따라 자동 템플릿 선택)
        return ClothingFeaturePoints.withTemplate(
            topPoint: topPoint,
            bottomPoint: bottomPoint,
            leftmostPoint: leftmostPoint,
            rightmostPoint: rightmostPoint,
            allPoints: normalizedPoints,
            clothingType: clothingType
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
        var candidates = detector.detectPoints(
            featurePoints: featurePoints,
            contour: contour
        )

        // 카메라 기반 키포인트 라인 후보를 추가로 결합
        let keypointCandidates = generateCandidatesFromKeypoints(
            contour: contour,
            featurePoints: featurePoints,
            clothingType: clothingType
        )
        candidates.append(contentsOf: keypointCandidates)

        return candidates
    }

    // MARK: - Private Methods

    /// 의류 타입에 맞는 감지기 생성
    private func createDetector(for type: ClothingType) -> MeasurementPointDetector {
        switch type {
        case .shortSleeve, .longSleeve, .shirt, .polo, .hoodie, .vest, .cardigan:
            return TopMeasurementDetector()
        case .pants, .shorts, .jeans, .leggings:
            return BottomMeasurementDetector()
        case .skirt:
            return SkirtMeasurementDetector()
        case .jacket, .coat:
            return TopMeasurementDetector()  // 아우터도 상의 감지기 사용
        case .dress, .jumpsuit:
            return TopMeasurementDetector()  // 원피스류는 상의 감지기로 시작
        }
    }
}

// MARK: - Auto Measurement Result

/// 자동 측정 결과
struct AutoMeasurementResult {
    /// 측정 거리 (센티미터)
    let distance: Double

    /// 측정 신뢰도 (0.0 ~ 1.0)
    let confidence: Double

    /// 시작 포인트 (픽셀 좌표)
    let point1: CGPoint

    /// 끝 포인트 (픽셀 좌표)
    let point2: CGPoint
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

//
//  AutoMeasurementService+Measurement.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  AutoMeasurementService의 개별 측정 항목 추출 확장입니다.
//  의류 타입별 측정 항목 디스패치 및
//  어깨너비, 가슴둘레, 허리둘레, 엉덩이둘레, 총길이 등의 개별 측정을 수행합니다.
//

import Foundation
import Vision
import ARKit
import CoreImage
import simd

// MARK: - Individual Measurement Methods

extension AutoMeasurementService {

    /// 의류 타입별 측정 항목 추출
    func extractMeasurementsForClothingType(
        featurePoints: ClothingFeaturePoints,
        clothingType: ClothingType,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        depthImageSize: CGSize? = nil,
        cropRect: CGRect? = nil
    ) -> [MeasurementType: AutoMeasurementResult] {
        var measurements: [MeasurementType: AutoMeasurementResult] = [:]

        switch clothingType {
        case .shortSleeve, .longSleeve, .shirt, .polo, .hoodie, .vest, .cardigan, .jacket, .coat, .dress, .jumpsuit:
            // 상의 측정: 어깨너비, 가슴둘레, 총길이, 소매길이
            if let shoulderWidth = measureShoulderWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            ) {
                measurements[.shoulderWidth] = shoulderWidth
            }

            if let chestWidth = measureChestWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            ) {
                measurements[.chestCircumference] = chestWidth
            }

            if let totalLength = measureTotalLength(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            ) {
                measurements[.totalLength] = totalLength
            }

        case .pants, .shorts, .jeans, .leggings:
            // 하의 측정: 허리둘레, 엉덩이둘레, 총길이
            if let waistWidth = measureWaistWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            ) {
                measurements[.waistCircumference] = waistWidth
            }

            if let hipWidth = measureHipWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            ) {
                measurements[.hipCircumference] = hipWidth
            }

            if let totalLength = measureTotalLength(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            ) {
                measurements[.totalLength] = totalLength
            }

        case .skirt:
            // 치마 측정: 허리둘레, 총길이
            if let waistWidth = measureWaistWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            ) {
                measurements[.waistCircumference] = waistWidth
            }

            if let hipWidth = measureHipWidth(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            ) {
                measurements[.hipCircumference] = hipWidth
            }

            if let totalLength = measureTotalLength(
                featurePoints: featurePoints,
                depthMap: depthMap,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            ) {
                measurements[.totalLength] = totalLength
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

        let allowedMeasurementTypes = Set(clothingType.requiredMeasurements + clothingType.optionalMeasurements)
        measurements = measurements.filter { allowedMeasurementTypes.contains($0.key) }

        return measurements
    }

    // MARK: - Specific Measurements

    /// 어깨너비 측정
    func measureShoulderWidth(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType,
        depthImageSize: CGSize? = nil,
        cropRect: CGRect? = nil
    ) -> AutoMeasurementResult? {
        // 상단 5% 영역에서 최대 너비 찾기
        guard let (left, right, confidence) = featurePoints.robustHorizontalSpan(
            at: featurePoints.topPoint.y - featurePoints.height * 0.02,
            halfSpans: [0.01, 0.02, 0.03]
        ) else {
            return nil
        }

        return measureDistance(
            from: left,
            to: right,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: confidence,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .shoulderWidth,
            clothingType: clothingType,
            depthImageSize: depthImageSize,
            cropRect: cropRect
        )
    }

    /// 가슴둘레 측정 (실제로는 가슴 너비)
    func measureChestWidth(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType,
        depthImageSize: CGSize? = nil,
        cropRect: CGRect? = nil
    ) -> AutoMeasurementResult? {
        // 가슴 위치에서 최대 너비 찾기
        guard let (left, right, confidence) = featurePoints.robustHorizontalSpan(
            at: featurePoints.chestY,
            halfSpans: [0.02, 0.03, 0.04]
        ) else {
            return nil
        }

        return measureDistance(
            from: left,
            to: right,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: confidence,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .chestCircumference,
            clothingType: clothingType,
            depthImageSize: depthImageSize,
            cropRect: cropRect
        )
    }

    /// 허리둘레 측정 (실제로는 허리 너비)
    func measureWaistWidth(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType,
        depthImageSize: CGSize? = nil,
        cropRect: CGRect? = nil
    ) -> AutoMeasurementResult? {
        if clothingType.category == .bottom,
           let waistSpan = featurePoints.robustBottomWaistSpan() {
            return measureDistance(
                from: waistSpan.left,
                to: waistSpan.right,
                depthMap: depthMap,
                imageSize: imageSize,
                confidence: waistSpan.confidence,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                measurementType: .waistCircumference,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        }

        // 허리 위치에서 너비 찾기 (하의는 상단 10% 근처가 허리)
        guard let (left, right, confidence) = featurePoints.robustHorizontalSpan(
            at: featurePoints.waistY,
            halfSpans: [0.02, 0.03, 0.04]
        ) else {
            return nil
        }

        return measureDistance(
            from: left,
            to: right,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: confidence,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .waistCircumference,
            clothingType: clothingType,
            depthImageSize: depthImageSize,
            cropRect: cropRect
        )
    }

    /// 엉덩이둘레 측정 (실제로는 엉덩이 너비)
    func measureHipWidth(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType,
        depthImageSize: CGSize? = nil,
        cropRect: CGRect? = nil
    ) -> AutoMeasurementResult? {
        // 엉덩이 위치에서 최대 너비 찾기
        guard let (left, right, confidence) = featurePoints.robustHorizontalSpan(
            at: featurePoints.hipY,
            halfSpans: [0.02, 0.03, 0.04]
        ) else {
            return nil
        }

        return measureDistance(
            from: left,
            to: right,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: confidence,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .hipCircumference,
            clothingType: clothingType,
            depthImageSize: depthImageSize,
            cropRect: cropRect
        )
    }

    /// 총길이 측정
    func measureTotalLength(
        featurePoints: ClothingFeaturePoints,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        clothingType: ClothingType,
        depthImageSize: CGSize? = nil,
        cropRect: CGRect? = nil
    ) -> AutoMeasurementResult? {
        if clothingType.category == .bottom,
           let lengthLine = featurePoints.bestBottomTotalLengthLine() {
            return measureDistance(
                from: lengthLine.start,
                to: lengthLine.end,
                depthMap: depthMap,
                imageSize: imageSize,
                confidence: lengthLine.confidence,
                cameraIntrinsics: cameraIntrinsics,
                cameraResolution: cameraResolution,
                measurementType: .totalLength,
                clothingType: clothingType,
                depthImageSize: depthImageSize,
                cropRect: cropRect
            )
        }

        return measureDistance(
            from: featurePoints.topPoint,
            to: featurePoints.bottomPoint,
            depthMap: depthMap,
            imageSize: imageSize,
            confidence: 0.9, // 상하 끝점은 신뢰도 높음
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: .totalLength,
            clothingType: clothingType,
            depthImageSize: depthImageSize,
            cropRect: cropRect
        )
    }

    // MARK: - Distance Measurement Helper

    /// 두 정규화 좌표 간 거리 측정
    func measureDistance(
        from normalizedPoint1: CGPoint,
        to normalizedPoint2: CGPoint,
        depthMap: CVPixelBuffer,
        imageSize: CGSize,
        confidence: Float,
        cameraIntrinsics: simd_float3x3?,
        cameraResolution: CGSize?,
        measurementType: MeasurementType,
        clothingType: ClothingType,
        depthImageSize: CGSize? = nil,
        cropRect: CGRect? = nil
    ) -> AutoMeasurementResult? {
        // 정규화 Vision 좌표 → 처리 이미지 픽셀 좌표.
        // 반환/저장은 처리 이미지 기준 좌표를 유지하고, Depth 샘플링만 원본 이미지 좌표로 매핑한다.
        let pixelPoint1 = CGPoint(
            x: normalizedPoint1.x * imageSize.width,
            y: (1.0 - normalizedPoint1.y) * imageSize.height  // Y축 반전 (Vision 좌표계 → UIKit 좌표계)
        )
        let pixelPoint2 = CGPoint(
            x: normalizedPoint2.x * imageSize.width,
            y: (1.0 - normalizedPoint2.y) * imageSize.height
        )

        let calculationImageSize = depthImageSize ?? imageSize
        let depthPoint1 = mapProcessedPointToDepthImage(
            pixelPoint1,
            processedImageSize: imageSize,
            depthImageSize: calculationImageSize,
            cropRect: cropRect
        )
        let depthPoint2 = mapProcessedPointToDepthImage(
            pixelPoint2,
            processedImageSize: imageSize,
            depthImageSize: calculationImageSize,
            cropRect: cropRect
        )

        // PhotoMeasurementCalculator 활용 (교정 계수 포함)
        guard let result = PhotoMeasurementCalculator.calculateDistance(
            from: depthPoint1,
            to: depthPoint2,
            depthMap: depthMap,
            imageSize: calculationImageSize,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution,
            measurementType: measurementType,
            clothingType: clothingType
        ) else {
            return nil
        }

        return AutoMeasurementResult(
            distance: result.distance,
            confidence: Double(confidence) * result.confidence,
            point1: pixelPoint1,
            point2: pixelPoint2
        )
    }

    private func mapProcessedPointToDepthImage(
        _ point: CGPoint,
        processedImageSize: CGSize,
        depthImageSize: CGSize,
        cropRect: CGRect?
    ) -> CGPoint {
        guard processedImageSize.width > 0, processedImageSize.height > 0,
              depthImageSize.width > 0, depthImageSize.height > 0 else {
            return point
        }

        let mapped: CGPoint
        if let cropRect = cropRect, cropRect.width > 0, cropRect.height > 0 {
            mapped = CGPoint(
                x: cropRect.minX + point.x * cropRect.width / processedImageSize.width,
                y: cropRect.minY + point.y * cropRect.height / processedImageSize.height
            )
        } else {
            mapped = CGPoint(
                x: point.x * depthImageSize.width / processedImageSize.width,
                y: point.y * depthImageSize.height / processedImageSize.height
            )
        }

        return CGPoint(
            x: max(0, min(mapped.x, depthImageSize.width)),
            y: max(0, min(mapped.y, depthImageSize.height))
        )
    }
}

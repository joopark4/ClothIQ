//
//  BottomMeasurementAnchorRepairService.swift
//  ClothIQ
//
//  Created on 2026-05-02
//
//  Description:
//  저장된 하의 밑위/밑단/총장 앵커를 최신 자동 검출 결과로 재평가합니다.
//

import Foundation
import UIKit
import CoreVideo
import simd

enum BottomMeasurementAnchorRepairService {
    static func repairIfNeeded(
        item: ClothingItemModel,
        measuredAt: Date = Date()
    ) async -> [MeasurementType] {
        guard let inputs = makeRepairInputs(for: item) else {
            return []
        }

        let autoService = AutoMeasurementService()
        guard let contour = try? await autoService.detectClothingContour(
            from: inputs.pixelBuffer,
            depthMap: inputs.depthMap
        ) else {
            return []
        }

        let featurePoints = autoreleasepool {
            autoService.extractForegroundFeaturePoints(
                from: inputs.image,
                clothingType: inputs.clothingType
            ) ?? autoService.extractFeaturePoints(from: contour, clothingType: inputs.clothingType)
        }

        let results = autoreleasepool {
            autoService.performKeypointBasedMeasurement(
                contour: contour,
                clothingType: inputs.clothingType,
                depthMap: inputs.depthMap,
                imageSize: inputs.imageSize,
                cameraIntrinsics: inputs.cameraIntrinsics,
                cameraResolution: inputs.cameraResolution,
                depthImageSize: inputs.depthImageSize,
                cropRect: inputs.cropRect,
                featurePointsOverride: featurePoints
            )
        }

        var repairedTypes: [MeasurementType] = []

        for measurementType in [MeasurementType.rise, .hem, .totalLength] {
            guard let measurement = item.measurement(for: measurementType),
                  let result = results[measurementType],
                  let normalizedPoints = BottomMeasurementAnchorRepairPolicy.normalizedPoints(
                    from: result,
                    imageSize: inputs.imageSize
                  ),
                  BottomMeasurementAnchorRepairPolicy.shouldRepair(
                    measurement: measurement,
                    replacementStart: normalizedPoints.start,
                    replacementEnd: normalizedPoints.end,
                    itemCreatedAt: item.createdAt
                  ) else {
                continue
            }

            if BottomMeasurementAnchorRepairPolicy.apply(
                result: result,
                to: measurement,
                imageSize: inputs.imageSize,
                measuredAt: measuredAt
            ) {
                repairedTypes.append(measurementType)
            }
        }

        return repairedTypes
    }

    private static func makeRepairInputs(for item: ClothingItemModel) -> BottomMeasurementRepairInputs? {
        autoreleasepool {
            guard let clothingType = item.clothingType,
                  clothingType.category == .bottom,
                  item.measurement(for: .rise) != nil ||
                    item.measurement(for: .hem) != nil ||
                    item.measurement(for: .totalLength) != nil,
                  let image = item.loadImage()?.normalizedOrientation(),
                  let depthMapPath = item.depthMapPath,
                  let depthMap = DepthDataProcessor.loadDepthMap(from: depthMapPath),
                  let pixelBuffer = image.pixelBuffer() else {
                return nil
            }

            return BottomMeasurementRepairInputs(
                clothingType: clothingType,
                image: image,
                depthMap: depthMap,
                pixelBuffer: pixelBuffer,
                imageSize: item.processedImageSize ?? image.size,
                depthImageSize: item.originalImageSize ?? image.size,
                cameraIntrinsics: item.cameraIntrinsicsMatrix,
                cameraResolution: item.cameraResolutionSize,
                cropRect: item.cropRect
            )
        }
    }
}

private struct BottomMeasurementRepairInputs {
    let clothingType: ClothingType
    let image: UIImage
    let depthMap: CVPixelBuffer
    let pixelBuffer: CVPixelBuffer
    let imageSize: CGSize
    let depthImageSize: CGSize
    let cameraIntrinsics: simd_float3x3?
    let cameraResolution: CGSize?
    let cropRect: CGRect?
}

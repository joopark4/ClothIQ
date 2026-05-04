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

enum BottomMeasurementAnchorRepairService {
    static func repairIfNeeded(
        item: ClothingItemModel,
        measuredAt: Date = Date()
    ) async -> [MeasurementType] {
        guard let clothingType = item.clothingType,
              clothingType.category == .bottom,
              item.measurement(for: .rise) != nil ||
                item.measurement(for: .hem) != nil ||
                item.measurement(for: .totalLength) != nil,
              let image = item.loadImage()?.normalizedOrientation(),
              let depthMapPath = item.depthMapPath,
              let depthMap = DepthDataProcessor.loadDepthMap(from: depthMapPath),
              let pixelBuffer = image.pixelBuffer() else {
            return []
        }

        let autoService = AutoMeasurementService()
        guard let contour = try? await autoService.detectClothingContour(
            from: pixelBuffer,
            depthMap: depthMap
        ) else {
            return []
        }

        let imageSize = item.processedImageSize ?? image.size
        let featurePoints = autoService.extractForegroundFeaturePoints(
            from: image,
            clothingType: clothingType
        ) ?? autoService.extractFeaturePoints(from: contour, clothingType: clothingType)

        let results = autoService.performKeypointBasedMeasurement(
            contour: contour,
            clothingType: clothingType,
            depthMap: depthMap,
            imageSize: imageSize,
            cameraIntrinsics: item.cameraIntrinsicsMatrix,
            cameraResolution: item.cameraResolutionSize,
            depthImageSize: item.originalImageSize ?? image.size,
            cropRect: item.cropRect,
            featurePointsOverride: featurePoints
        )

        var repairedTypes: [MeasurementType] = []

        for measurementType in [MeasurementType.rise, .hem, .totalLength] {
            guard let measurement = item.measurement(for: measurementType),
                  let result = results[measurementType],
                  let normalizedPoints = BottomMeasurementAnchorRepairPolicy.normalizedPoints(
                    from: result,
                    imageSize: imageSize
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
                imageSize: imageSize,
                measuredAt: measuredAt
            ) {
                repairedTypes.append(measurementType)
            }
        }

        return repairedTypes
    }
}

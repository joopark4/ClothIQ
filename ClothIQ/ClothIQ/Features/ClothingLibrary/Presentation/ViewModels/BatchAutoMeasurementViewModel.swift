//
//  BatchAutoMeasurementViewModel.swift
//  ClothIQ
//
//  Created on 2026-02-19
//
//  Description:
//  상세화면에서 일괄 자동 측정을 수행하는 ViewModel입니다.
//  윤곽선 감지 → 의류 타입 확인 → 일괄 측정 → 결과 저장의 전체 플로우를 오케스트레이션합니다.
//
//  Key Responsibilities:
//  - 이미지/depth map 로드
//  - 윤곽선 감지 및 의류 타입 분류
//  - 일괄 자동 측정 수행
//  - 결과 검토 및 저장
//

import Foundation
import SwiftUI
import SwiftData
import Combine
import Vision
import simd

/// 일괄 자동 측정 ViewModel
@MainActor
final class BatchAutoMeasurementViewModel: ObservableObject {

    // MARK: - Phase

    enum Phase: Equatable {
        case idle
        case detectingContour
        case classifyingType
        case typeConfirmation
        case measuring
        case results
        case error(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.detectingContour, .detectingContour),
                 (.classifyingType, .classifyingType),
                 (.typeConfirmation, .typeConfirmation),
                 (.measuring, .measuring),
                 (.results, .results):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - Published Properties

    @Published var phase: Phase = .idle
    @Published var progressMessage = ""
    @Published var detectedType: ClothingType?
    @Published var detectedTypeConfidence: Float = 0
    @Published var measurementResults: [MeasurementType: AutoMeasurementResult] = [:]
    @Published var selectedResults: Set<MeasurementType> = []

    // MARK: - Properties

    let item: ClothingItemModel
    private let modelContext: ModelContext
    private let autoService = AutoMeasurementService()
    private let featureAnalyzer = ClothingFeatureAnalyzer()
    private let classifier = VisionClothingClassifier()

    private var image: UIImage?
    private var depthMap: CVPixelBuffer?
    private var contour: VNContoursObservation?
    private var confirmedType: ClothingType?

    // MARK: - Initialization

    init(item: ClothingItemModel, modelContext: ModelContext) {
        self.item = item
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    /// 일괄 측정 플로우 시작
    func startBatchMeasurement() async {
        phase = .detectingContour
        progressMessage = "이미지 로드 중..."

        // 1. 이미지 로드
        guard let loadedImage = item.loadImage() else {
            phase = .error("이미지를 로드할 수 없습니다.")
            return
        }
        self.image = loadedImage.normalizedOrientation()

        // 2. Depth map 로드
        guard let depthMapPath = item.depthMapPath,
              let loadedDepthMap = DepthDataProcessor.loadDepthMap(from: depthMapPath) else {
            phase = .error("Depth map을 로드할 수 없습니다.")
            return
        }
        self.depthMap = loadedDepthMap

        // 3. 이미지 → CVPixelBuffer
        guard let pixelBuffer = self.image?.pixelBuffer() else {
            phase = .error("이미지를 변환할 수 없습니다.")
            return
        }

        // 4. 윤곽선 감지
        progressMessage = "윤곽선 감지 중..."
        do {
            let detectedContour = try await autoService.detectClothingContour(
                from: pixelBuffer,
                depthMap: loadedDepthMap
            )
            guard let contour = detectedContour else {
                phase = .error("의류 윤곽선을 감지할 수 없습니다.\n의류를 평평하게 펼쳐서 다시 촬영해주세요.")
                return
            }
            self.contour = contour
        } catch {
            phase = .error("윤곽선 감지 실패: \(error.localizedDescription)")
            return
        }

        // 5. 의류 타입 분류
        await classifyClothingType()
    }

    /// 의류 타입 확정 후 측정 진행
    func confirmType(_ type: ClothingType) async {
        confirmedType = type
        await performMeasurement()
    }

    /// 현재 타입 유지하고 측정 진행
    func keepCurrentType() async {
        confirmedType = item.clothingType
        await performMeasurement()
    }

    /// 선택된 측정값만 저장
    func saveSelectedMeasurements() {
        saveMeasurements(types: selectedResults)
    }

    /// 전체 측정값 저장
    func saveAllMeasurements() {
        saveMeasurements(types: Set(measurementResults.keys))
    }

    /// 특정 측정 타입의 기존 값 조회
    func existingValue(for type: MeasurementType) -> Double? {
        item.measurements.first { $0.type == type.rawValue }?.calibratedValue()
    }

    // MARK: - Private Methods

    /// 의류 타입 분류
    private func classifyClothingType() async {
        phase = .classifyingType
        progressMessage = "의류 타입 확인 중..."

        guard let image = self.image, let contour = self.contour else {
            phase = .error("분류에 필요한 데이터가 없습니다.")
            return
        }

        // 방법 1: 윤곽선 기반 분류
        let features = featureAnalyzer.extractFeatures(from: contour)
        let contourType = featureAnalyzer.detectClothingCategory(from: features)
        let contourConfidence = features.confidence

        // 방법 2: 종횡비 기반 분류
        let classifierResult = classifier.classify(image: image)

        // 높은 신뢰도 결과 선택
        let bestType: ClothingType
        let bestConfidence: Float
        if contourConfidence > Float(classifierResult.confidence) {
            bestType = contourType
            bestConfidence = contourConfidence
        } else {
            bestType = classifierResult.type
            bestConfidence = Float(classifierResult.confidence)
        }

        detectedType = bestType
        detectedTypeConfidence = bestConfidence

        print("🏷️ [BatchAuto] 타입 분류 결과:")
        print("  - 윤곽선 기반: \(contourType.displayName) (\(String(format: "%.1f%%", contourConfidence * 100)))")
        print("  - 종횡비 기반: \(classifierResult.type.displayName) (\(String(format: "%.1f%%", classifierResult.confidence * 100)))")
        print("  - 최종 선택: \(bestType.displayName) (\(String(format: "%.1f%%", bestConfidence * 100)))")

        // 현재 타입과 비교
        if bestType == item.clothingType {
            // 일치 → 바로 측정 진행
            confirmedType = bestType
            await performMeasurement()
        } else {
            // 불일치 → 사용자에게 확인
            phase = .typeConfirmation
        }
    }

    /// 일괄 측정 수행
    private func performMeasurement() async {
        phase = .measuring
        progressMessage = "측정 중..."

        guard let contour = self.contour,
              let depthMap = self.depthMap,
              let image = self.image,
              let clothingType = confirmedType else {
            phase = .error("측정에 필요한 데이터가 없습니다.")
            return
        }

        let imageSize = item.processedImageSize ?? image.size
        let cameraIntrinsics = item.cameraIntrinsicsMatrix
        let cameraResolution = item.cameraResolutionSize

        // 키포인트 기반 일괄 측정
        let results = autoService.performKeypointBasedMeasurement(
            contour: contour,
            clothingType: clothingType,
            depthMap: depthMap,
            imageSize: imageSize,
            cameraIntrinsics: cameraIntrinsics,
            cameraResolution: cameraResolution
        )

        if results.isEmpty {
            // 폴백 1: Saliency 기반 키포인트로 재시도
            progressMessage = "Saliency 기반 측정 중..."
            print("⚠️ [BatchAuto] 키포인트 실패 → Saliency 폴백 시도")

            if let saliencyKeypoints = try? await VisionMLService.shared.detectKeypointsUsingSaliency(
                from: image,
                clothingType: clothingType
            ), !saliencyKeypoints.isEmpty {
                print("  - Saliency 키포인트: \(saliencyKeypoints.count)개")

                // saliency 키포인트로 측정 라인 생성
                let keypointDetector = ClothingKeypointDetector()
                let lines = keypointDetector.generateMeasurementLines(
                    from: saliencyKeypoints,
                    clothingType: clothingType
                )

                if !lines.isEmpty {
                    // 각 라인에 대한 거리 측정
                    for line in lines {
                        // 정규화 좌표 → 픽셀 좌표
                        let pixelStart = CGPoint(
                            x: line.start.x * imageSize.width,
                            y: (1.0 - line.start.y) * imageSize.height
                        )
                        let pixelEnd = CGPoint(
                            x: line.end.x * imageSize.width,
                            y: (1.0 - line.end.y) * imageSize.height
                        )

                        // 라인 길이 체크 (너무 짧으면 스킵)
                        let lineLength = hypot(pixelEnd.x - pixelStart.x, pixelEnd.y - pixelStart.y)
                        guard lineLength > 5 else { continue }

                        if let result = PhotoMeasurementCalculator.calculateDistance(
                            from: pixelStart,
                            to: pixelEnd,
                            depthMap: depthMap,
                            imageSize: imageSize,
                            cameraIntrinsics: cameraIntrinsics,
                            cameraResolution: cameraResolution,
                            measurementType: line.type,
                            clothingType: clothingType
                        ) {
                            measurementResults[line.type] = AutoMeasurementResult(
                                distance: result.distance,
                                confidence: result.confidence * 0.7,  // saliency 기반이므로 신뢰도 감쇠
                                point1: pixelStart,
                                point2: pixelEnd
                            )
                        }
                    }
                    print("  - Saliency 측정 결과: \(measurementResults.count)개")
                }
            }

            // 폴백 2: 윤곽선 기반 측정 (기존)
            if measurementResults.isEmpty {
                progressMessage = "윤곽선 기반 측정 중..."
                print("⚠️ [BatchAuto] Saliency도 실패 → 윤곽선 폴백")
                let fallbackResults = autoService.performAutoMeasurement(
                    contour: contour,
                    clothingType: clothingType,
                    depthMap: depthMap,
                    imageSize: imageSize,
                    cameraIntrinsics: cameraIntrinsics,
                    cameraResolution: cameraResolution
                )
                measurementResults = fallbackResults
            }
        } else {
            measurementResults = results
        }

        if measurementResults.isEmpty {
            phase = .error("측정 결과를 생성할 수 없습니다.\n의류가 잘 보이도록 다시 촬영해주세요.")
            return
        }

        // 전체 결과를 기본 선택 상태로 설정
        selectedResults = Set(measurementResults.keys)
        phase = .results

        print("✅ [BatchAuto] 측정 완료: \(measurementResults.count)개 항목")
        for (type, result) in measurementResults {
            print("  - \(type.displayName): \(String(format: "%.1f", result.distance))cm (신뢰도: \(String(format: "%.0f%%", result.confidence * 100)))")
        }
    }

    /// 측정값 저장
    private func saveMeasurements(types: Set<MeasurementType>) {
        guard !types.isEmpty else { return }

        let imageSize = item.processedImageSize ?? image?.size ?? CGSize(width: 1, height: 1)

        for type in types {
            guard let result = measurementResults[type] else { continue }

            // pixel 좌표 → 정규화 Vision 좌표 (bottom-left origin, 0~1)
            let normalizedStart = normalizeToVisionCoords(result.point1, imageSize: imageSize)
            let normalizedEnd = normalizeToVisionCoords(result.point2, imageSize: imageSize)

            // 기존 측정값이 있으면 업데이트, 없으면 새로 생성
            if let existing = item.measurements.first(where: { $0.type == type.rawValue }) {
                existing.value = result.distance
                existing.confidence = result.confidence
                existing.measuredAt = Date()
                existing.startPointX = Double(normalizedStart.x)
                existing.startPointY = Double(normalizedStart.y)
                existing.endPointX = Double(normalizedEnd.x)
                existing.endPointY = Double(normalizedEnd.y)
                existing.measurementMethodRaw = MeasurementMethod.photo.rawValue
            } else {
                let measurement = MeasurementModel(
                    type: type.rawValue,
                    value: result.distance,
                    confidence: result.confidence,
                    startPointX: Double(normalizedStart.x),
                    startPointY: Double(normalizedStart.y),
                    endPointX: Double(normalizedEnd.x),
                    endPointY: Double(normalizedEnd.y),
                    measurementMethodRaw: MeasurementMethod.photo.rawValue
                )
                item.measurements.append(measurement)
            }
        }

        item.updatedAt = Date()

        do {
            try modelContext.save()
            print("✅ [BatchAuto] \(types.count)개 측정값 저장 완료")
        } catch {
            print("❌ [BatchAuto] 저장 실패: \(error)")
        }
    }

    /// UIKit pixel 좌표 → 정규화 Vision 좌표 (bottom-left origin)
    private func normalizeToVisionCoords(_ point: CGPoint, imageSize: CGSize) -> CGPoint {
        CGPoint(
            x: clamp(point.x / imageSize.width, min: 0, max: 1),
            y: clamp(1.0 - (point.y / imageSize.height), min: 0, max: 1)
        )
    }

    private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minVal), maxVal)
    }
}

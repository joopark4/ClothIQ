//
//  VisionMLService.swift
//  ClothIQ
//
//  Created on 2025-11-10
//
//  Description:
//  Vision Framework와 Core ML을 통합한 고급 키포인트 감지 서비스입니다.
//  의류 특화 ML 모델을 사용하여 더 정확한 측정 포인트를 감지합니다.
//
//  Key Features:
//  - Core ML 모델 통합
//  - Vision Framework 파이프라인
//  - 의류별 특화 감지
//  - 신뢰도 기반 필터링
//

import Foundation
@preconcurrency import Vision
import CoreML
import UIKit
import CoreImage

/// ML 기반 키포인트 감지 결과
struct MLKeypointResult {
    /// 감지된 키포인트들
    let keypoints: [MLKeypoint]

    /// 전체 신뢰도 (0.0 ~ 1.0)
    let confidence: Float

    /// 의류 타입 예측
    let predictedClothingType: ClothingType?

    /// 처리 시간 (밀리초)
    let processingTime: TimeInterval
}

/// ML 키포인트
struct MLKeypoint {
    /// 키포인트 식별자
    let identifier: String

    /// 정규화된 위치 (0.0 ~ 1.0)
    let position: CGPoint

    /// 신뢰도 (0.0 ~ 1.0)
    let confidence: Float

    /// 키포인트 타입 (매핑)
    let type: KeypointType?

    /// 3D 깊이 값 (있는 경우)
    let depth: Float?
}

/// Vision ML 서비스
final class VisionMLService {

    // MARK: - Properties

    /// 싱글톤 인스턴스
    static let shared = VisionMLService()

    /// Vision 요청 큐
    private let requestQueue = DispatchQueue(label: "com.clothiq.vision.ml", qos: .userInitiated)

    /// 캐시된 모델
    private var cachedModel: VNCoreMLModel?

    /// 최소 신뢰도 임계값
    private let minConfidence: Float = 0.6

    /// 키포인트 매핑 딕셔너리
    private let keypointMapping: [String: KeypointType] = [
        "left_shoulder": .leftShoulder,
        "right_shoulder": .rightShoulder,
        "left_armpit": .leftArmpit,
        "right_armpit": .rightArmpit,
        "left_sleeve": .leftSleeveEnd,
        "right_sleeve": .rightSleeveEnd,
        "neckline": .neckline,
        "hem_center": .hemCenter,
        "chest_left": .chestLeft,
        "chest_right": .chestRight,
        "waist_left": .waistLeft,
        "waist_right": .waistRight,
        "hip_left": .hipLeft,
        "hip_right": .hipRight,
        "crotch": .crotch,
        "hem_left": .leftHem,
        "hem_right": .rightHem
    ]

    // MARK: - Initialization

    private init() {
        setupModel()
    }

    // MARK: - Public Methods

    /// ML 기반 키포인트 감지
    ///
    /// - Parameters:
    ///   - image: 입력 이미지
    ///   - clothingType: 의류 타입 (힌트)
    /// - Returns: ML 키포인트 감지 결과
    func detectKeypointsWithML(
        from image: UIImage,
        clothingType: ClothingType? = nil
    ) async throws -> MLKeypointResult {

        let startTime = Date()

        // 이미지 전처리
        guard let processedImage = preprocessImage(image) else {
            throw VisionMLError.imagePreprocessingFailed
        }

        // Vision 요청 생성
        let request = try createVisionRequest()

        // 요청 실행
        let keypoints = try await performVisionRequest(request, on: processedImage)

        // 의류 타입 예측 (있는 경우)
        let predictedType = predictClothingType(from: keypoints) ?? clothingType

        // 후처리 및 필터링
        let filteredKeypoints = postprocessKeypoints(keypoints, for: predictedType)

        let processingTime = Date().timeIntervalSince(startTime) * 1000 // 밀리초

        return MLKeypointResult(
            keypoints: filteredKeypoints,
            confidence: calculateOverallConfidence(filteredKeypoints),
            predictedClothingType: predictedType,
            processingTime: processingTime
        )
    }

    /// Saliency 기반 키포인트 감지
    ///
    /// VNGenerateObjectnessBasedSaliencyImageRequest로 시각적으로
    /// 두드러진 영역의 중심점들을 키포인트 후보로 반환합니다.
    ///
    /// - Parameters:
    ///   - image: 입력 이미지
    ///   - clothingType: 의류 타입
    /// - Returns: 감지된 키포인트 배열
    func detectKeypointsUsingSaliency(
        from image: UIImage,
        clothingType: ClothingType
    ) async throws -> [MeasurementKeypoint] {
        guard let ciImage = CIImage(image: image) else {
            throw VisionMLError.imagePreprocessingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            requestQueue.async {
                let request = VNGenerateObjectnessBasedSaliencyImageRequest()
                let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])

                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observation = request.results?.first as? VNSaliencyImageObservation,
                      let salientObjects = observation.salientObjects, !salientObjects.isEmpty else {
                    continuation.resume(returning: [])
                    return
                }

                print("🔬 [Saliency] \(salientObjects.count)개 salient region 감지")

                // 바운딩 박스 중심점을 키포인트 후보로 변환
                var candidates: [(center: CGPoint, confidence: Float)] = []
                for obj in salientObjects {
                    let box = obj.boundingBox  // Vision 좌표계 (bottom-left origin, 0~1)
                    let center = CGPoint(x: box.midX, y: box.midY)
                    candidates.append((center: center, confidence: obj.confidence))
                }

                // Y좌표 기준 정렬 (상단→하단: Vision 좌표계에서 큰 Y가 상단)
                candidates.sort { $0.center.y > $1.center.y }

                let keypoints = self.mapSaliencyToKeypoints(
                    candidates: candidates,
                    clothingType: clothingType
                )

                print("✅ [Saliency] \(keypoints.count)개 키포인트 매핑 완료")
                for kp in keypoints {
                    print("  - \(kp.description)")
                }

                continuation.resume(returning: keypoints)
            }
        }
    }

    /// 하이브리드 키포인트 감지 (ML + Saliency + 휴리스틱)
    ///
    /// ML 모델, Saliency 감지, 기존 휴리스틱 알고리즘을 결합하여 최적의 결과를 제공합니다.
    func detectKeypointsHybrid(
        from image: UIImage,
        contour: VNContoursObservation?,
        clothingType: ClothingType
    ) async throws -> [MeasurementKeypoint] {

        print("🤖 [VisionML] 하이브리드 키포인트 감지 시작")

        // 1. ML 기반 감지
        var mlKeypoints: [MLKeypoint] = []
        do {
            let mlResult = try await detectKeypointsWithML(from: image, clothingType: clothingType)
            mlKeypoints = mlResult.keypoints
            print("  - ML 키포인트: \(mlKeypoints.count)개 감지")
        } catch {
            print("⚠️ ML 감지 실패: \(error)")
        }

        // 2. 휴리스틱 기반 감지 (기존 ClothingKeypointDetector 사용)
        var heuristicKeypoints: [MeasurementKeypoint] = []
        if let contour = contour {
            let featurePoints = extractFeaturePoints(from: contour)
            let detector = ClothingKeypointDetector()
            heuristicKeypoints = detector.detectKeypoints(
                from: contour,
                clothingType: clothingType,
                featurePoints: featurePoints
            )
            print("  - 휴리스틱 키포인트: \(heuristicKeypoints.count)개 감지")
        }

        // 3. Saliency 기반 감지 (NEW)
        var saliencyKeypoints: [MeasurementKeypoint] = []
        do {
            saliencyKeypoints = try await detectKeypointsUsingSaliency(
                from: image,
                clothingType: clothingType
            )
            print("  - Saliency 키포인트: \(saliencyKeypoints.count)개 감지")
        } catch {
            print("⚠️ Saliency 감지 실패: \(error)")
        }

        // 4. 3-way 병합: ML > Saliency > 휴리스틱 우선순위
        let mergedKeypoints = mergeKeypointsThreeWay(
            mlKeypoints: mlKeypoints,
            saliencyKeypoints: saliencyKeypoints,
            heuristicKeypoints: heuristicKeypoints
        )

        print("✅ [VisionML] 하이브리드 감지 완료: \(mergedKeypoints.count)개 키포인트")

        return mergedKeypoints
    }

    // MARK: - Private Methods - Model Setup

    /// 모델 초기화
    private func setupModel() {
        // 현재는 내장 Vision 모델 사용
        // 추후 커스텀 Core ML 모델로 교체 가능
        print("🤖 [VisionML] Vision ML 서비스 초기화")
    }

    /// Vision 요청 생성
    private func createVisionRequest() throws -> VNRequest {
        // 옵션 1: 커스텀 Core ML 모델 사용 (있는 경우)
        if let customModel = loadCustomModel() {
            let request = VNCoreMLRequest(model: customModel) { request, error in
                if let error = error {
                    print("❌ [VisionML] ML 모델 실행 실패: \(error)")
                }
            }
            request.imageCropAndScaleOption = .centerCrop
            return request
        }

        // 옵션 2: 윤곽선 감지 (평면 의류에 적합)
        // VNDetectHumanBodyPoseRequest는 사람 포즈 전용이라 평면 의류에는 무용
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 2.0
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 512
        return request
    }

    /// 커스텀 Core ML 모델 로드
    private func loadCustomModel() -> VNCoreMLModel? {
        // 커스텀 모델이 있다면 여기서 로드
        // 예: ClothingKeypoints.mlmodel

        // 현재는 nil 반환 (커스텀 모델 없음)
        return nil
    }

    // MARK: - Private Methods - Image Processing

    /// 이미지 전처리
    private func preprocessImage(_ image: UIImage) -> CIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }

        // 이미지 정규화 및 리사이징
        let filter = CIFilter(name: "CILanczosScaleTransform")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(0.5, forKey: kCIInputScaleKey) // 50% 스케일
        filter?.setValue(1.0, forKey: kCIInputAspectRatioKey)

        return filter?.outputImage ?? ciImage
    }

    /// Vision 요청 실행
    private func performVisionRequest(_ request: VNRequest, on image: CIImage) async throws -> [MLKeypoint] {
        return try await withCheckedThrowingContinuation { continuation in
            requestQueue.async {
                let handler = VNImageRequestHandler(ciImage: image, options: [:])

                do {
                    try handler.perform([request])

                    // 결과 파싱
                    let keypoints = self.parseVisionResults(request.results)
                    continuation.resume(returning: keypoints)

                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Vision 결과 파싱
    private func parseVisionResults(_ results: [Any]?) -> [MLKeypoint] {
        guard let results = results else { return [] }

        var keypoints: [MLKeypoint] = []

        // 사람 포즈 감지 결과 처리
        if #available(iOS 14.0, *) {
            if let bodyPoseResults = results as? [VNHumanBodyPoseObservation] {
                keypoints.append(contentsOf: parseBodyPoseResults(bodyPoseResults))
            }
        }

        // 윤곽선 감지 결과 처리
        if let contourResults = results as? [VNContoursObservation] {
            keypoints.append(contentsOf: parseContourResults(contourResults))
        }

        // Core ML 모델 결과 처리 (있는 경우)
        if let mlResults = results as? [VNCoreMLFeatureValueObservation] {
            keypoints.append(contentsOf: parseMLResults(mlResults))
        }

        return keypoints
    }

    /// 사람 포즈 결과를 의류 키포인트로 변환
    @available(iOS 14.0, *)
    private func parseBodyPoseResults(_ results: [VNHumanBodyPoseObservation]) -> [MLKeypoint] {
        guard let observation = results.first else { return [] }

        var keypoints: [MLKeypoint] = []

        // 어깨 포인트 추출
        if let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
           leftShoulder.confidence > minConfidence {
            keypoints.append(MLKeypoint(
                identifier: "left_shoulder",
                position: CGPoint(x: leftShoulder.location.x, y: 1.0 - leftShoulder.location.y),
                confidence: Float(leftShoulder.confidence),
                type: .leftShoulder,
                depth: nil
            ))
        }

        if let rightShoulder = try? observation.recognizedPoint(.rightShoulder),
           rightShoulder.confidence > minConfidence {
            keypoints.append(MLKeypoint(
                identifier: "right_shoulder",
                position: CGPoint(x: rightShoulder.location.x, y: 1.0 - rightShoulder.location.y),
                confidence: Float(rightShoulder.confidence),
                type: .rightShoulder,
                depth: nil
            ))
        }

        // 팔꿈치 (소매 길이 추정용)
        if let leftElbow = try? observation.recognizedPoint(.leftElbow),
           leftElbow.confidence > minConfidence {
            keypoints.append(MLKeypoint(
                identifier: "left_sleeve",
                position: CGPoint(x: leftElbow.location.x, y: 1.0 - leftElbow.location.y),
                confidence: Float(leftElbow.confidence) * 0.8, // 신뢰도 보정
                type: .leftSleeveEnd,
                depth: nil
            ))
        }

        // 허리 (엉덩이 포인트로 추정)
        if let leftHip = try? observation.recognizedPoint(.leftHip),
           let rightHip = try? observation.recognizedPoint(.rightHip),
           leftHip.confidence > minConfidence && rightHip.confidence > minConfidence {

            keypoints.append(MLKeypoint(
                identifier: "waist_left",
                position: CGPoint(x: leftHip.location.x, y: 1.0 - leftHip.location.y),
                confidence: Float(leftHip.confidence),
                type: .waistLeft,
                depth: nil
            ))

            keypoints.append(MLKeypoint(
                identifier: "waist_right",
                position: CGPoint(x: rightHip.location.x, y: 1.0 - rightHip.location.y),
                confidence: Float(rightHip.confidence),
                type: .waistRight,
                depth: nil
            ))
        }

        return keypoints
    }

    /// 윤곽선 결과 파싱
    private func parseContourResults(_ results: [VNContoursObservation]) -> [MLKeypoint] {
        // 윤곽선에서 특징점 추출 (기존 로직 활용)
        guard let contour = results.first else { return [] }

        var keypoints: [MLKeypoint] = []

        // 최상단 점 (목선 또는 상단)
        if let topPoint = findExtremumPoint(in: contour, direction: .top) {
            keypoints.append(MLKeypoint(
                identifier: "neckline",
                position: topPoint,
                confidence: 0.7,
                type: .neckline,
                depth: nil
            ))
        }

        // 최하단 점 (밑단)
        if let bottomPoint = findExtremumPoint(in: contour, direction: .bottom) {
            keypoints.append(MLKeypoint(
                identifier: "hem_center",
                position: bottomPoint,
                confidence: 0.7,
                type: .hemCenter,
                depth: nil
            ))
        }

        return keypoints
    }

    /// Core ML 모델 결과 파싱
    private func parseMLResults(_ results: [VNCoreMLFeatureValueObservation]) -> [MLKeypoint] {
        // 커스텀 모델 결과 파싱 (추후 구현)
        return []
    }

    // MARK: - Private Methods - Helper Functions

    /// 극값 찾기
    private func findExtremumPoint(in contour: VNContoursObservation, direction: ExtremumDirection) -> CGPoint? {
        guard contour.contourCount > 0,
              let mainContour = try? contour.contour(at: 0) else { return nil }

        let points = mainContour.normalizedPath.points()
        guard !points.isEmpty else { return nil }

        switch direction {
        case .top:
            return points.max(by: { $0.y < $1.y })
        case .bottom:
            return points.min(by: { $0.y < $1.y })
        case .left:
            return points.min(by: { $0.x < $1.x })
        case .right:
            return points.max(by: { $0.x < $1.x })
        }
    }

    /// 의류 타입 예측
    private func predictClothingType(from keypoints: [MLKeypoint]) -> ClothingType? {
        // 감지된 키포인트 패턴으로 의류 타입 추정

        let hasShoulders = keypoints.contains { $0.type == .leftShoulder || $0.type == .rightShoulder }
        let hasSleeves = keypoints.contains { $0.type == .leftSleeveEnd || $0.type == .rightSleeveEnd }
        let hasWaist = keypoints.contains { $0.type == .waistLeft || $0.type == .waistRight }
        let hasHips = keypoints.contains { $0.type == .hipLeft || $0.type == .hipRight }

        if hasShoulders && hasSleeves {
            return .longSleeve
        } else if hasShoulders && !hasSleeves {
            return .shortSleeve
        } else if hasWaist && hasHips {
            return .pants
        } else if hasWaist && !hasHips {
            return .shorts
        } else {
            return nil
        }
    }

    /// 키포인트 후처리
    private func postprocessKeypoints(_ keypoints: [MLKeypoint], for clothingType: ClothingType?) -> [MLKeypoint] {
        // 신뢰도 필터링
        var filtered = keypoints.filter { $0.confidence >= minConfidence }

        // 의류 타입별 필터링
        if let type = clothingType {
            filtered = filtered.filter { keypoint in
                isKeypointRelevant(keypoint, for: type)
            }
        }

        // 중복 제거 (같은 타입의 키포인트)
        var uniqueKeypoints: [MLKeypoint] = []
        var seenTypes: Set<KeypointType> = []

        for keypoint in filtered.sorted(by: { $0.confidence > $1.confidence }) {
            if let type = keypoint.type {
                if !seenTypes.contains(type) {
                    uniqueKeypoints.append(keypoint)
                    seenTypes.insert(type)
                }
            } else {
                uniqueKeypoints.append(keypoint)
            }
        }

        return uniqueKeypoints
    }

    /// 키포인트 관련성 확인
    private func isKeypointRelevant(_ keypoint: MLKeypoint, for clothingType: ClothingType) -> Bool {
        guard let type = keypoint.type else { return true }

        switch clothingType {
        case .shortSleeve, .longSleeve, .shirt, .polo, .hoodie, .vest, .cardigan:
            return [.leftShoulder, .rightShoulder, .leftSleeveEnd, .rightSleeveEnd,
                    .neckline, .hemCenter, .chestLeft, .chestRight].contains(type)
        case .shorts, .pants, .jeans, .leggings:
            return [.waistLeft, .waistRight, .hipLeft, .hipRight,
                    .crotch, .leftHem, .rightHem, .hemCenter].contains(type)
        case .skirt:
            return [.waistLeft, .waistRight, .hipLeft, .hipRight, .hemCenter].contains(type)
        case .jacket, .coat:
            return [.leftShoulder, .rightShoulder, .leftSleeveEnd, .rightSleeveEnd,
                    .neckline, .hemCenter, .chestLeft, .chestRight].contains(type)
        case .dress, .jumpsuit:
            return true  // 모든 키포인트 관련
        }
    }

    /// 전체 신뢰도 계산
    private func calculateOverallConfidence(_ keypoints: [MLKeypoint]) -> Float {
        guard !keypoints.isEmpty else { return 0 }

        let totalConfidence = keypoints.reduce(Float(0)) { $0 + $1.confidence }
        return totalConfidence / Float(keypoints.count)
    }

    /// 키포인트 병합
    private func mergeKeypoints(
        mlKeypoints: [MLKeypoint],
        heuristicKeypoints: [MeasurementKeypoint]
    ) -> [MeasurementKeypoint] {

        var mergedKeypoints: [MeasurementKeypoint] = []
        var usedMLKeypoints: Set<String> = []

        // ML 키포인트를 MeasurementKeypoint로 변환
        for mlKeypoint in mlKeypoints {
            if let type = mlKeypoint.type {
                mergedKeypoints.append(MeasurementKeypoint(
                    type: type,
                    position: mlKeypoint.position,
                    confidence: mlKeypoint.confidence
                ))
                usedMLKeypoints.insert(mlKeypoint.identifier)
            }
        }

        // 휴리스틱 키포인트 중 ML에 없는 것 추가
        for heuristicKeypoint in heuristicKeypoints {
            let hasMLVersion = mergedKeypoints.contains { $0.type == heuristicKeypoint.type }

            if !hasMLVersion {
                mergedKeypoints.append(heuristicKeypoint)
            } else if heuristicKeypoint.confidence > 0.8 {
                // 휴리스틱 신뢰도가 매우 높으면 평균값 사용
                if let index = mergedKeypoints.firstIndex(where: { $0.type == heuristicKeypoint.type }) {
                    let mlKeypoint = mergedKeypoints[index]
                    let averagePosition = CGPoint(
                        x: (mlKeypoint.position.x + heuristicKeypoint.position.x) / 2,
                        y: (mlKeypoint.position.y + heuristicKeypoint.position.y) / 2
                    )
                    mergedKeypoints[index] = MeasurementKeypoint(
                        type: heuristicKeypoint.type,
                        position: averagePosition,
                        confidence: max(mlKeypoint.confidence, heuristicKeypoint.confidence)
                    )
                }
            }
        }

        return mergedKeypoints
    }

    /// Saliency 후보를 의류 타입 기반 키포인트로 매핑
    private func mapSaliencyToKeypoints(
        candidates: [(center: CGPoint, confidence: Float)],
        clothingType: ClothingType
    ) -> [MeasurementKeypoint] {
        guard !candidates.isEmpty else { return [] }

        var keypoints: [MeasurementKeypoint] = []

        // Y좌표 범위 계산 (이미 상단→하단 정렬됨)
        let allY = candidates.map { $0.center.y }
        let minY = allY.min() ?? 0
        let maxY = allY.max() ?? 1
        let rangeY = max(maxY - minY, 0.01)

        // 각 후보를 상/중/하 영역으로 분류
        var topCandidates: [(center: CGPoint, confidence: Float)] = []
        var midCandidates: [(center: CGPoint, confidence: Float)] = []
        var bottomCandidates: [(center: CGPoint, confidence: Float)] = []

        for c in candidates {
            let relativeY = (c.center.y - minY) / rangeY  // 0(하단)~1(상단)
            if relativeY > 0.66 {
                topCandidates.append(c)
            } else if relativeY > 0.33 {
                midCandidates.append(c)
            } else {
                bottomCandidates.append(c)
            }
        }

        // 좌/우 분리 (X 중앙 기준)
        let centerX: CGFloat = candidates.map { $0.center.x }.reduce(0, +) / CGFloat(candidates.count)

        switch clothingType {
        case .shortSleeve, .longSleeve, .shirt, .polo, .hoodie, .vest, .cardigan, .jacket, .coat, .dress, .jumpsuit:
            // 상의: 상단 좌/우 → 어깨, 중간 좌/우 → 가슴, 하단 → 밑단
            if let topLeft = topCandidates.filter({ $0.center.x < centerX }).first {
                keypoints.append(MeasurementKeypoint(type: .leftShoulder, position: topLeft.center, confidence: topLeft.confidence * 0.7))
            }
            if let topRight = topCandidates.filter({ $0.center.x >= centerX }).first {
                keypoints.append(MeasurementKeypoint(type: .rightShoulder, position: topRight.center, confidence: topRight.confidence * 0.7))
            }
            if let midLeft = midCandidates.filter({ $0.center.x < centerX }).first {
                keypoints.append(MeasurementKeypoint(type: .chestLeft, position: midLeft.center, confidence: midLeft.confidence * 0.6))
            }
            if let midRight = midCandidates.filter({ $0.center.x >= centerX }).first {
                keypoints.append(MeasurementKeypoint(type: .chestRight, position: midRight.center, confidence: midRight.confidence * 0.6))
            }
            if let bottom = bottomCandidates.max(by: { $0.confidence < $1.confidence }) {
                keypoints.append(MeasurementKeypoint(type: .hemCenter, position: bottom.center, confidence: bottom.confidence * 0.6))
            }
            // 목선: 상단 중앙
            if let topCenter = topCandidates.min(by: { abs($0.center.x - centerX) < abs($1.center.x - centerX) }) {
                keypoints.append(MeasurementKeypoint(type: .neckline, position: CGPoint(x: centerX, y: topCenter.center.y), confidence: topCenter.confidence * 0.6))
            }

        case .pants, .shorts, .jeans, .leggings:
            // 하의: 상단 좌/우 → 허리, 중간 → 밑위, 하단 좌/우 → 밑단
            if let topLeft = topCandidates.filter({ $0.center.x < centerX }).first {
                keypoints.append(MeasurementKeypoint(type: .waistLeft, position: topLeft.center, confidence: topLeft.confidence * 0.7))
            }
            if let topRight = topCandidates.filter({ $0.center.x >= centerX }).first {
                keypoints.append(MeasurementKeypoint(type: .waistRight, position: topRight.center, confidence: topRight.confidence * 0.7))
            }
            if let midCenter = midCandidates.min(by: { abs($0.center.x - centerX) < abs($1.center.x - centerX) }) {
                keypoints.append(MeasurementKeypoint(type: .crotch, position: midCenter.center, confidence: midCenter.confidence * 0.6))
            }
            if let bottomLeft = bottomCandidates.filter({ $0.center.x < centerX }).first {
                keypoints.append(MeasurementKeypoint(type: .leftHem, position: bottomLeft.center, confidence: bottomLeft.confidence * 0.6))
            }
            if let bottomRight = bottomCandidates.filter({ $0.center.x >= centerX }).first {
                keypoints.append(MeasurementKeypoint(type: .rightHem, position: bottomRight.center, confidence: bottomRight.confidence * 0.6))
            }

        case .skirt:
            if let topLeft = topCandidates.filter({ $0.center.x < centerX }).first {
                keypoints.append(MeasurementKeypoint(type: .waistLeft, position: topLeft.center, confidence: topLeft.confidence * 0.7))
            }
            if let topRight = topCandidates.filter({ $0.center.x >= centerX }).first {
                keypoints.append(MeasurementKeypoint(type: .waistRight, position: topRight.center, confidence: topRight.confidence * 0.7))
            }
            if let bottom = bottomCandidates.max(by: { $0.confidence < $1.confidence }) {
                keypoints.append(MeasurementKeypoint(type: .hemCenter, position: bottom.center, confidence: bottom.confidence * 0.6))
            }
        }

        return keypoints
    }

    /// 3-way 키포인트 병합 (ML > Saliency > 휴리스틱 우선순위)
    private func mergeKeypointsThreeWay(
        mlKeypoints: [MLKeypoint],
        saliencyKeypoints: [MeasurementKeypoint],
        heuristicKeypoints: [MeasurementKeypoint]
    ) -> [MeasurementKeypoint] {
        // 1단계: ML + 휴리스틱 병합 (기존 로직)
        var merged = mergeKeypoints(
            mlKeypoints: mlKeypoints,
            heuristicKeypoints: heuristicKeypoints
        )

        // 2단계: Saliency 키포인트 중 아직 없는 타입만 추가
        var existingTypes = Set(merged.map { $0.type })

        for saliencyKeypoint in saliencyKeypoints {
            if !existingTypes.contains(saliencyKeypoint.type) {
                merged.append(saliencyKeypoint)
                existingTypes.insert(saliencyKeypoint.type)
            }
        }

        return merged
    }

    /// 특징점 추출 (간단한 버전)
    private func extractFeaturePoints(from contour: VNContoursObservation) -> ClothingFeaturePoints {
        guard contour.contourCount > 0,
              let mainContour = try? contour.contour(at: 0) else {
            return ClothingFeaturePoints(
                topPoint: CGPoint(x: 0.5, y: 1.0),
                bottomPoint: CGPoint(x: 0.5, y: 0.0),
                leftmostPoint: CGPoint(x: 0.0, y: 0.5),
                rightmostPoint: CGPoint(x: 1.0, y: 0.5),
                allPoints: []
            )
        }

        let points = mainContour.normalizedPath.points()

        let topPoint = points.max(by: { $0.y < $1.y }) ?? CGPoint(x: 0.5, y: 1.0)
        let bottomPoint = points.min(by: { $0.y < $1.y }) ?? CGPoint(x: 0.5, y: 0.0)
        let leftmostPoint = points.min(by: { $0.x < $1.x }) ?? CGPoint(x: 0.0, y: 0.5)
        let rightmostPoint = points.max(by: { $0.x < $1.x }) ?? CGPoint(x: 1.0, y: 0.5)

        return ClothingFeaturePoints(
            topPoint: topPoint,
            bottomPoint: bottomPoint,
            leftmostPoint: leftmostPoint,
            rightmostPoint: rightmostPoint,
            allPoints: points
        )
    }
}

// MARK: - Supporting Types

/// 극값 방향
private enum ExtremumDirection {
    case top, bottom, left, right
}

/// Vision ML 에러
enum VisionMLError: LocalizedError {
    case modelNotFound
    case imagePreprocessingFailed
    case visionRequestFailed
    case noKeypointsDetected

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "ML 모델을 찾을 수 없습니다"
        case .imagePreprocessingFailed:
            return "이미지 전처리 실패"
        case .visionRequestFailed:
            return "Vision 요청 실패"
        case .noKeypointsDetected:
            return "키포인트를 감지할 수 없습니다"
        }
    }
}

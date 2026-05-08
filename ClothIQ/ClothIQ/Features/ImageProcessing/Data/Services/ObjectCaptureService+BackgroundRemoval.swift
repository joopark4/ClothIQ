//
//  ObjectCaptureService+BackgroundRemoval.swift
//  ClothIQ
//
//  Created on 2025-01-23
//
//  Description:
//  ObjectCaptureService의 배경 제거 관련 메서드 확장입니다.
//

import UIKit
import Vision
import CoreImage
import CoreVideo
import CoreGraphics

private let colorThresholdFilterName = "CIColorThreshold"
private let colorThresholdInputKey = "inputThreshold"

extension ObjectCaptureService {

    // MARK: - Background Removal

    /// 이미지에서 배경을 제거합니다.
    ///
    /// - Parameters:
    ///   - image: 크롭된 이미지
    ///   - depthMap: LiDAR depth map (우선 사용)
    /// - Returns: 배경이 제거된 이미지 (실패 시 nil)
    /// - Throws: Vision 요청 실패 시 에러
    ///
    /// ## Background Removal Process (우선순위)
    /// 1. **Vision 단독** (최우선) - VNGenerateForegroundInstanceMaskRequest (iOS 17+)
    /// 2. **LiDAR + Vision 하이브리드** (폴백1) - Depth로 영역 구분 + Vision으로 윤곽 정제
    /// 3. Saliency Detection (폴백2) - 시각적 주목도 기반
    /// 4. 중앙 80% 영역 (최종 폴백)
    ///
    /// - Note: 배경은 밝은 그레이(RGB 245)로 처리됩니다.
    ///
    func removeBackground(from image: UIImage, depthMap: CVPixelBuffer?) throws -> UIImage? {
        print("🎨 [BackgroundRemoval] ===== 배경 제거 파이프라인 시작 =====")
        let startTime = Date()

        // 이미 정규화된 이미지가 전달됨 (processImage에서 정규화)
        guard let cgImage = image.cgImage else {
            print("❌ [BackgroundRemoval] 이미지 변환 실패")
            throw ObjectCaptureError.invalidImage
        }

        print("📊 [BackgroundRemoval] 이미지 크기: \(cgImage.width)x\(cgImage.height)")
        print("📊 [BackgroundRemoval] Depth map 있음: \(depthMap != nil)")

        // 마스크 생성 우선순위
        let maskBuffer: CVPixelBuffer?
        var maskMethod = ""

        // 1. Vision 단독 (최우선) - iOS의 강력한 전경 분리 기능
        print("🔍 [BackgroundRemoval] 1단계: Vision Framework 전경 마스크 생성 시도...")
        if let visionMask = detectForegroundMask(cgImage: cgImage) {
            print("✅ [BackgroundRemoval] Vision 마스크 생성 성공!")

            // 마스크 품질 평가
            let coverage = calculateWhitePixelRatio(in: visionMask, threshold: Constants.maskThreshold)
            print("📊 [BackgroundRemoval] Vision 마스크 커버리지: \(String(format: "%.1f", coverage * 100))%")

            // Vision 마스크를 그대로 사용 (Depth 결합 비활성화)
            // 이유: Depth와 AND 연산 시 마스크가 축소되어 객체가 제거되는 문제 발생
            maskBuffer = visionMask
            maskMethod = "Vision Framework"

            // Depth 정보는 로깅만 수행
            if let depth = depthMap {
                print("📊 [BackgroundRemoval] Depth map 정보: \(CVPixelBufferGetWidth(depth))x\(CVPixelBufferGetHeight(depth))")
                _ = createDepthMask(from: depth, imageSize: CGSize(width: cgImage.width, height: cgImage.height))
            }
        }
        // 2. LiDAR 기반 (폴백1)
        else if let depth = depthMap {
            print("⚠️ [BackgroundRemoval] Vision 마스크 실패 → Depth 기반 폴백 사용")
            let depthMask = createDepthMask(from: depth, imageSize: CGSize(width: cgImage.width, height: cgImage.height))
            maskBuffer = convertCIImageToPixelBuffer(depthMask)
            maskMethod = "Depth Map (Fallback 1)"

            if let mask = maskBuffer {
                let coverage = calculateWhitePixelRatio(in: mask, threshold: Constants.maskThreshold)
                print("📊 [BackgroundRemoval] Depth 마스크 커버리지: \(String(format: "%.1f", coverage * 100))%")
            }
        }
        // 3. Saliency Detection (폴백2)
        else {
            print("⚠️ [BackgroundRemoval] Vision + Depth 실패 → Saliency Detection 시도")
            if let saliency = detectSaliency(cgImage: cgImage) {
                print("✅ [BackgroundRemoval] Saliency Detection 성공")
                maskBuffer = saliency
                maskMethod = "Saliency Detection (Fallback 2)"

                let coverage = calculateWhitePixelRatio(in: saliency, threshold: Constants.maskThreshold)
                print("📊 [BackgroundRemoval] Saliency 마스크 커버리지: \(String(format: "%.1f", coverage * 100))%")
            }
            // 4. 중앙 영역 (최종 폴백)
            else {
                print("⚠️ [BackgroundRemoval] 모든 감지 실패 → 중앙 80% 영역 사용 (최종 폴백)")
                let centerMask = createCenterMask(for: cgImage)
                maskBuffer = convertCIImageToPixelBuffer(centerMask)
                maskMethod = "Center Crop 80% (Final Fallback)"
            }
        }

        guard let finalMask = maskBuffer else {
            print("❌ [BackgroundRemoval] 마스크 생성 완전 실패")
            return nil
        }

        print("🎯 [BackgroundRemoval] 사용된 마스크 방법: \(maskMethod)")

        // 마스크를 사용하여 배경을 밝은 그레이로 변경
        print("🖌️ [BackgroundRemoval] 마스크 적용 중...")
        guard let backgroundRemovedImage = applyMask(to: image, mask: finalMask) else {
            print("❌ [BackgroundRemoval] 마스크 적용 실패")
            print("🎨 [BackgroundRemoval] ===== 배경 제거 파이프라인 종료 =====\n")
            return nil
        }

        let processingTime = Date().timeIntervalSince(startTime)
        print("✅ [BackgroundRemoval] 배경 제거 완료! (소요 시간: \(String(format: "%.2f", processingTime))초)")
        print("🎨 [BackgroundRemoval] ===== 배경 제거 파이프라인 종료 =====\n")

        return backgroundRemovedImage
    }

    /// Saliency Detection 수행 (헬퍼 메서드)
    func detectSaliency(cgImage: CGImage) -> CVPixelBuffer? {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let semaphore = DispatchSemaphore(value: 0)
        var saliencyMap: CVPixelBuffer?

        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
            defer { semaphore.signal() }

            guard error == nil,
                  let results = request.results as? [VNSaliencyImageObservation],
                  let firstResult = results.first else {
                return
            }

            saliencyMap = firstResult.pixelBuffer
        }

        try? handler.perform([saliencyRequest])
        _ = semaphore.wait(timeout: .now() + 3.0)

        return saliencyMap
    }

    /// Vision Framework로 전경 마스크 감지 (정밀한 윤곽)
    ///
    /// generateScaledMaskForImage를 사용하여 고해상도 마스크 생성
    /// 마스크 후처리를 통해 품질 개선
    func detectForegroundMask(cgImage: CGImage) -> CVPixelBuffer? {
        print("   🔍 [Vision] VNGenerateForegroundInstanceMaskRequest 시작...")

        // 이미지는 이미 정규화되어 있으므로 orientation은 .up
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(.up), options: [:])
        let semaphore = DispatchSemaphore(value: 0)
        var foregroundMask: CVPixelBuffer?
        var visionError: Error?

        let maskRequest = VNGenerateForegroundInstanceMaskRequest { request, error in
            defer { semaphore.signal() }

            if let error = error {
                visionError = error
                print("   ❌ [Vision] Vision Framework 에러: \(error.localizedDescription)")
                return
            }

            guard let results = request.results as? [VNInstanceMaskObservation] else {
                print("   ❌ [Vision] 결과를 VNInstanceMaskObservation으로 변환 실패")
                return
            }

            guard let firstResult = results.first else {
                print("   ❌ [Vision] 감지된 객체 없음 (results.first == nil)")
                return
            }

            print("   ✅ [Vision] 객체 감지 성공! (인스턴스 수: \(firstResult.allInstances.count))")

            // 고해상도 마스크 생성 (generateScaledMaskForImage 사용)
            do {
                let scaledMask = try firstResult.generateScaledMaskForImage(
                    forInstances: firstResult.allInstances,
                    from: handler
                )

                // 마스크 통계 출력
                let maskWidth = CVPixelBufferGetWidth(scaledMask)
                let maskHeight = CVPixelBufferGetHeight(scaledMask)
                print("   📊 [Vision] 마스크 크기: \(maskWidth)x\(maskHeight)")

                // 마스크 품질 분석
                let coverage = self.calculateWhitePixelRatio(in: scaledMask, threshold: Constants.maskThreshold)
                print("   📊 [Vision] 마스크 커버리지: \(String(format: "%.1f", coverage * 100))%")

                foregroundMask = scaledMask
                print("   ✅ [Vision] 고해상도 마스크 생성 성공")

            } catch {
                print("   ⚠️ [Vision] 고해상도 마스크 생성 실패: \(error.localizedDescription)")
                print("   🔄 [Vision] 저해상도 마스크로 폴백")
                // 폴백: 저해상도 마스크 사용
                foregroundMask = firstResult.instanceMask
            }
        }

        do {
            try handler.perform([maskRequest])
        } catch {
            print("   ❌ [Vision] Vision 요청 실행 실패: \(error.localizedDescription)")
            return nil
        }

        let waitResult = semaphore.wait(timeout: .now() + 5.0)  // Vision mask는 시간이 더 걸림
        if waitResult == .timedOut {
            print("   ⏱️ [Vision] 타임아웃 (5초 초과)")
            return nil
        }

        if let error = visionError {
            print("   ❌ [Vision] Vision 처리 중 에러 발생: \(error.localizedDescription)")
            return nil
        }

        // 마스크 후처리: Morphological 연산으로 품질 개선
        if let mask = foregroundMask {
            print("   🔧 [Vision] 마스크 품질 개선 (Morphological 연산) 시작...")
            let refinedMask = refineMaskQuality(mask)
            print("   ✅ [Vision] 마스크 품질 개선 완료")
            return refinedMask
        }

        print("   ❌ [Vision] 최종 마스크 생성 실패")
        return foregroundMask
    }

    /// 마스크 품질 개선 (Morphological 연산 + 이진화)
    ///
    /// - Parameter mask: 원본 마스크
    /// - Returns: 개선된 마스크
    ///
    /// Closing 연산(Dilation → Erosion)으로 마스크 내부의 작은 구멍을 메우고
    /// 노이즈를 제거한 후, 이진화하여 명확한 경계를 만듭니다.
    ///
    /// ## Processing Pipeline
    /// 1. Dilation (radius: 6) → 구멍 메우기
    /// 2. Erosion (radius: 5) → 약간의 확장 유지 (순 확장: 1픽셀)
    /// 3. Binarization (contrast: 10) → 0 또는 255로 명확히 구분
    /// 4. Quality Check → 전경 비율 검증
    ///
    func refineMaskQuality(_ mask: CVPixelBuffer) -> CVPixelBuffer {
        let ciMask = CIImage(cvPixelBuffer: mask)
        var refinedMask = ciMask


        // 1. Dilation: 전경 영역 확장 (더 큰 구멍 메우기)
        if let morphologyMax = CIFilter(name: "CIMorphologyMaximum") {
            morphologyMax.setValue(refinedMask, forKey: kCIInputImageKey)
            morphologyMax.setValue(Constants.morphologyDilationRadius, forKey: kCIInputRadiusKey)
            if let dilated = morphologyMax.outputImage {
                refinedMask = dilated
            }
        }

        // 2. Erosion: 확장된 영역 복원 (순 확장 2픽셀 유지)
        if let morphologyMin = CIFilter(name: "CIMorphologyMinimum") {
            morphologyMin.setValue(refinedMask, forKey: kCIInputImageKey)
            morphologyMin.setValue(Constants.morphologyErosionRadius, forKey: kCIInputRadiusKey)
            if let eroded = morphologyMin.outputImage {
                refinedMask = eroded
            }
        }

        // 3. Gaussian Blur: 가장자리 부드럽게 (anti-aliasing 효과)
        if let gaussianBlur = CIFilter(name: "CIGaussianBlur") {
            gaussianBlur.setValue(refinedMask, forKey: kCIInputImageKey)
            gaussianBlur.setValue(1.5, forKey: kCIInputRadiusKey)  // 작은 blur로 가장자리 부드럽게
            if let blurred = gaussianBlur.outputImage {
                refinedMask = blurred
            }
        }

        // 4. 마스크 이진화 (부드러운 contrast 적용)
        // 중간 회색 값을 부드럽게 0 또는 255로 구분
        if let colorControls = CIFilter(name: "CIColorControls") {
            colorControls.setValue(refinedMask, forKey: kCIInputImageKey)
            colorControls.setValue(6.0, forKey: kCIInputContrastKey)  // 10 → 6 감소 (덜 날카롭게)
            if let binarized = colorControls.outputImage {
                refinedMask = binarized
            }
        }

        // CIImage를 CVPixelBuffer로 변환
        if let refinedBuffer = convertCIImageToPixelBuffer(refinedMask) {
            return refinedBuffer
        } else {
            return mask
        }
    }

    /// Vision 마스크를 Depth 정보로 개선 (선택적)
    ///
    /// - Parameters:
    ///   - visionMask: Vision 기반 마스크 (정밀한 윤곽)
    ///   - depthMask: LiDAR depth 기반 마스크 (거친 영역 구분)
    /// - Returns: 개선된 마스크
    ///
    /// Vision 마스크를 우선 사용하되, Depth 정보로 false positive를 제거
    ///
    func refineVisionMaskWithDepth(visionMask: CVPixelBuffer, depthMask: CIImage) -> CVPixelBuffer {

        // Vision 마스크를 CIImage로 변환
        let visionCIMask = CIImage(cvPixelBuffer: visionMask)

        // Depth 마스크를 Vision 마스크와 같은 크기로 스케일
        let visionWidth = CVPixelBufferGetWidth(visionMask)
        let visionHeight = CVPixelBufferGetHeight(visionMask)
        let imageSize = CGSize(width: visionWidth, height: visionHeight)

        let maskExtent = depthMask.extent
        let scaleX = imageSize.width / maskExtent.width
        let scaleY = imageSize.height / maskExtent.height

        let scaledDepthMask = depthMask
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: CGRect(origin: .zero, size: imageSize))

        // Vision 마스크와 Depth 마스크를 곱셈(AND 연산)으로 결합
        // 두 마스크 모두 전경인 영역만 선택
        guard let multiplyFilter = CIFilter(name: "CIMultiplyBlendMode") else {
            return visionMask
        }

        multiplyFilter.setValue(visionCIMask, forKey: kCIInputImageKey)
        multiplyFilter.setValue(scaledDepthMask, forKey: kCIInputBackgroundImageKey)

        guard let combinedMask = multiplyFilter.outputImage else {
            return visionMask
        }

        // CIImage를 CVPixelBuffer로 변환
        if let refinedBuffer = convertCIImageToPixelBuffer(combinedMask) {
            return refinedBuffer
        } else {
            return visionMask
        }
    }

    /// 마스크를 적용하여 배경을 밝은 그레이로 변경합니다 (픽셀 단위 블렌딩).
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - mask: CIImage 마스크 (흰색=전경, 검은색=배경)
    /// - Returns: 배경이 밝은 그레이로 처리된 이미지
    ///
    func applyMask(to image: UIImage, mask: CIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }


        // 마스크를 CGImage로 변환
        let maskExtent = mask.extent
        guard let maskCGImage = ciContext.createCGImage(mask, from: maskExtent) else {
            return nil
        }

        // 마스크와 이미지 해상도 검증
        let imageWidth = cgImage.width
        let imageHeight = cgImage.height
        let maskWidth = maskCGImage.width
        let maskHeight = maskCGImage.height

        let finalMask: CGImage

        // 해상도가 다른 경우에만 리사이즈
        if maskWidth != imageWidth || maskHeight != imageHeight {
            guard let resized = resizeMask(maskCGImage, to: CGSize(width: imageWidth, height: imageHeight)) else {
                return nil
            }
            finalMask = resized
        } else {
            // 해상도가 같으면 리사이즈 건너뛰기
            finalMask = maskCGImage
        }

        guard let compositingMask = hardenMaskForCompositing(finalMask) else {
            return nil
        }

        // GPU 가속 마스크 적용 (CIBlendWithMask)
        let result = applyMaskWithCoreImage(image: cgImage, mask: compositingMask)

        return result.map { UIImage(cgImage: $0, scale: 1.0, orientation: .up) }
    }

    /// 마스크를 특정 크기로 리사이즈
    func resizeMask(_ mask: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)

        // Grayscale 컬러 스페이스 명시
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray) else {
            return nil
        }

        // bytesPerRow를 0으로 설정하면 시스템이 자동으로 적절한 값 계산
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,  // 시스템이 자동으로 alignment를 고려하여 계산
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(mask, in: CGRect(origin: .zero, size: size))

        guard let resizedImage = context.makeImage() else {
            return nil
        }

        return resizedImage
    }

    /// 픽셀 단위로 마스크를 적용하여 배경을 회색으로 변경
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - mask: 마스크 (흰색=전경, 검은색=배경)
    /// - Returns: 배경이 회색으로 처리된 CGImage
    ///
    /// ## Threshold Strategy
    /// 마스크 임계값을 100으로 낮춰서 더 많은 전경 픽셀을 보존합니다.
    /// (이전 128 → 현재 100)
    ///
    /// GPU 가속 마스크 적용 (CIBlendWithMask 사용)
    ///
    /// Core Image의 CIBlendWithMask 필터를 사용하여 GPU에서 병렬 처리합니다.
    /// CPU 기반 픽셀 처리 대비 4-10배 성능 향상이 기대됩니다.
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - mask: 이진화된 마스크 (흰색=전경, 검은색=배경)
    /// - Returns: 배경이 밝은 회색(245,245,245)으로 처리된 CGImage
    func applyMaskWithCoreImage(image: CGImage, mask: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let ciMask = CIImage(cgImage: mask)

        // 마스크 크기를 이미지 크기에 맞추기
        let scaleX = CGFloat(image.width) / ciMask.extent.width
        let scaleY = CGFloat(image.height) / ciMask.extent.height
        let scaledMask = ciMask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // 배경 색상 이미지 생성 (245, 245, 245)
        let backgroundColor = CIColor(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 245.0 / 255.0)
        let backgroundImage = CIImage(color: backgroundColor)
            .cropped(to: ciImage.extent)

        // CIBlendWithMask: mask가 흰색인 영역은 inputImage(전경), 검은색인 영역은 backgroundImage
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            print("⚠️ [BackgroundRemoval] CIBlendWithMask 필터 생성 실패, CPU fallback 사용")
            return applyMaskPixelByPixelFallback(image: image, mask: mask)
        }

        blendFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blendFilter.setValue(backgroundImage, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(scaledMask, forKey: kCIInputMaskImageKey)

        guard let outputCIImage = blendFilter.outputImage else {
            print("⚠️ [BackgroundRemoval] CIBlendWithMask 출력 생성 실패, CPU fallback 사용")
            return applyMaskPixelByPixelFallback(image: image, mask: mask)
        }

        // CIImage → CGImage 변환 (GPU 렌더링)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(outputCIImage, from: outputCIImage.extent)
    }

    /// CPU 기반 마스크 적용 (GPU 실패 시 fallback)
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - mask: 이진화된 마스크
    /// - Returns: 배경이 회색으로 처리된 CGImage
    func applyMaskPixelByPixelFallback(image: CGImage, mask: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height

        // RGB 컨텍스트 생성 (알파 없음)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            return nil
        }

        // 원본 이미지 그리기
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let imageData = context.data else {
            return nil
        }

        // 마스크 데이터 읽기
        // bytesPerRow를 0으로 설정하여 시스템이 자동으로 alignment를 고려한 값을 계산하도록 함
        guard let maskColorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let maskContext = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,  // 시스템이 자동으로 alignment를 고려하여 계산
                space: maskColorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return nil
        }

        maskContext.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let maskData = maskContext.data else {
            return nil
        }

        let imageBuffer = imageData.assumingMemoryBound(to: UInt8.self)
        let maskBuffer = maskData.assumingMemoryBound(to: UInt8.self)

        // 실제 mask의 bytesPerRow 가져오기 (alignment 포함)
        let maskBytesPerRow = maskContext.bytesPerRow

        let backgroundColor: (r: UInt8, g: UInt8, b: UInt8) = (245, 245, 245)

        // 임계값을 128로 설정 (이진화된 마스크에 최적)
        // 이유: 마스크가 이진화되어 0 또는 255 값만 가지므로 중간 값 128이 적절
        let threshold = Constants.maskThreshold

        var foregroundPixels = 0
        var backgroundPixels = 0

        // 픽셀 단위로 블렌딩
        for y in 0..<height {
            for x in 0..<width {
                // 수정: maskBytesPerRow를 사용하여 정확한 픽셀 위치 계산
                let maskIndex = y * maskBytesPerRow + x
                let imageIndex = (y * width + x) * 4

                let maskValue = maskBuffer[maskIndex]

                // 마스크가 임계값보다 작으면 배경으로 처리
                if maskValue < threshold {
                    imageBuffer[imageIndex] = backgroundColor.r      // R
                    imageBuffer[imageIndex + 1] = backgroundColor.g  // G
                    imageBuffer[imageIndex + 2] = backgroundColor.b  // B
                    // imageBuffer[imageIndex + 3]은 이미 255 (불투명)
                    backgroundPixels += 1
                } else {
                    // 마스크가 임계값 이상이면 원본 유지
                    foregroundPixels += 1
                }
            }
        }

        return context.makeImage()
    }

    /// 마스크를 적용하여 배경을 밝은 그레이로 변경합니다 (CVPixelBuffer 버전).
    ///
    /// - Parameters:
    ///   - image: 원본 이미지
    ///   - mask: Vision에서 생성된 마스크
    /// - Returns: 배경이 밝은 그레이로 처리된 이미지
    ///
    func applyMask(to image: UIImage, mask: CVPixelBuffer) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }


        // CVPixelBuffer를 CGImage로 변환
        let maskCIImage = CIImage(cvPixelBuffer: mask)
        guard let maskCGImage = ciContext.createCGImage(maskCIImage, from: maskCIImage.extent) else {
            return nil
        }

        // 마스크를 이미지 크기에 맞게 리사이즈
        let resizedMask = resizeMask(maskCGImage, to: CGSize(width: cgImage.width, height: cgImage.height))
        guard let finalMask = resizedMask else {
            return nil
        }

        // Vision 마스크는 회색 경계값을 포함할 수 있으므로 합성 전 이진화한다.
        // CIBlendWithMask에 부드러운 마스크를 그대로 넘기면 배경색이 일부 섞여 남는다.
        guard let compositingMask = hardenMaskForCompositing(finalMask) else {
            return nil
        }

        // GPU 가속 마스크 적용 (CIBlendWithMask)
        let result = applyMaskWithCoreImage(image: cgImage, mask: compositingMask)

        return result.map { UIImage(cgImage: $0, scale: 1.0, orientation: .up) }
    }

    /// 합성 직전 마스크를 0/255 값으로 고정해 낮은 신뢰도 배경 픽셀이 남지 않게 합니다.
    func hardenMaskForCompositing(
        _ mask: CGImage,
        threshold: UInt8 = Constants.compositingMaskThreshold
    ) -> CGImage? {
        if let hardenedMask = hardenMaskForCompositingWithCoreImage(mask, threshold: threshold) {
            return hardenedMask
        }

        print("⚠️ [BackgroundRemoval] Core Image 마스크 이진화 실패, CPU fallback 사용")
        return hardenMaskForCompositingCPUFallback(mask, threshold: threshold)
    }

    private func hardenMaskForCompositingWithCoreImage(
        _ mask: CGImage,
        threshold: UInt8
    ) -> CGImage? {
        guard let thresholdFilter = CIFilter(name: colorThresholdFilterName) else {
            return nil
        }

        let inputImage = CIImage(cgImage: mask)
        let normalizedThreshold = CGFloat(threshold) / 255.0
        thresholdFilter.setValue(inputImage, forKey: kCIInputImageKey)
        thresholdFilter.setValue(normalizedThreshold, forKey: colorThresholdInputKey)

        guard let outputImage = thresholdFilter.outputImage?.cropped(to: inputImage.extent) else {
            return nil
        }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(outputImage, from: outputImage.extent)
    }

    private func hardenMaskForCompositingCPUFallback(
        _ mask: CGImage,
        threshold: UInt8
    ) -> CGImage? {
        let width = mask.width
        let height = mask.height

        guard width > 0,
              height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .none
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return nil
        }

        let buffer = data.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = context.bytesPerRow

        for y in 0..<height {
            let row = buffer + y * bytesPerRow
            for x in 0..<width {
                row[x] = row[x] >= threshold ? 255 : 0
            }
        }

        return context.makeImage()
    }

    /// 마스크를 반전 (흰색↔검은색)
    func invertMask(_ mask: CGImage) -> CGImage? {
        let width = mask.width
        let height = mask.height

        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearGray),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else {
            return nil
        }

        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }

        let buffer = data.assumingMemoryBound(to: UInt8.self)
        let totalPixels = width * height

        // 픽셀 반전
        for i in 0..<totalPixels {
            buffer[i] = 255 - buffer[i]
        }

        return context.makeImage()
    }
}

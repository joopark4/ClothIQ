//
//  MeasurementViewModel+ImageCapture.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  이미지 캡처 및 처리를 담당하는 extension입니다.
//
//  Key Responsibilities:
//  - 이미지 캡처 요청 및 처리
//  - 배경 제거 및 크롭
//  - Photos 앱 저장
//  - 의류 타입 선택 후 처리
//  - 캡처 에러 처리
//

import Foundation
import ARKit
import UIKit

// MARK: - Image Capture

extension MeasurementViewModelRefactored {
    
    /// 이미지 캡처 요청
    ///
    /// 카메라 포커스의 객체를 캡처하고, 다음 처리를 수행합니다:
    /// 1. 객체 감지 및 정사각형 크롭
    /// 2. 배경 제거
    /// 3. Photos 앱에 저장
    func captureImage() {
        captureRequested = true
    }

    /// 캡처된 이미지를 처리하여 배경을 제거하고 저장합니다.
    ///
    /// ## Post-Capture Workflow
    /// 1. 객체 촬영 (AR 카메라에서 캡처된 이미지)
    /// 2. 1:1 정사각형 크로핑 (객체 중심)
    /// 3. JPG로 임시 저장 (디스크에 임시 파일 생성)
    /// 4. 임시 저장된 JPG에 대해 배경 제거 실행
    /// 5. 최종 이미지를 Photos 앨범 및 로컬에 저장
    ///
    /// - Parameters:
    ///   - image: AR 카메라에서 캡처된 원본 이미지
    ///   - depthMap: LiDAR depth map (배경 제거 품질 향상용, 선택)
    ///
    func handleCapturedImage(
        _ image: UIImage,
        depthMap: CVPixelBuffer?,
        camera: ARCamera?
    ) {
        isLoading = true

        // Depth map 진단 로깅
        if depthMap != nil {
            print("✅ [ClothIQ-Capture] Depth map 캡처 성공!")
            print("  - Depth map size: \(CVPixelBufferGetWidth(depthMap!))x\(CVPixelBufferGetHeight(depthMap!))")
            print("  - Image size: \(image.size)")
            print("  - AR 초기화 상태: \(isARInitialized)")
            print("  - 추적 상태: \(trackingState)")
        } else {
            print("❌ [ClothIQ-Capture] Depth map 캡처 실패!")
            print("  - AR 초기화 상태: \(isARInitialized)")
            print("  - 추적 상태: \(trackingState)")
            print("  - 카메라 정보: \(camera != nil ? "있음" : "없음")")
        }

        // Depth map 저장 (사진 측정에 사용)
        self.capturedDepthMap = depthMap
        self.capturedOriginalImageSize = image.size
        self.capturedCameraIntrinsics = camera?.intrinsics
        if let resolution = camera?.imageResolution {
            self.capturedCameraResolution = CGSize(width: resolution.width, height: resolution.height)
        } else {
            self.capturedCameraResolution = nil
        }

        // 이전 임시 파일 정리
        cleanupTemporaryCaptureFile()

        // processImage 사용으로 변경 (테스트 뷰와 동일한 고품질 처리)
        objectCaptureService.processImage(image, depthMap: depthMap) { [weak self] result in
            guard let self = self else { return }

            Task { @MainActor in
                self.isLoading = false

                switch result {
                case .success(let processedResult):
                    let processedImage = processedResult.finalImage

                    // 임시 JPEG 저장 (Photos 앱 저장용)
                    if let jpegData = processedImage.jpegData(compressionQuality: 0.95),
                       let tempURL = try? self.createTemporaryJPEGURL() {
                        do {
                            try jpegData.write(to: tempURL)
                            self.lastTemporaryCaptureURL = tempURL
                        } catch {
                        }
                    }

                    // 처리된 이미지 상태 업데이트
                    self.capturedImage = processedImage
                    self.processedImageToSave = processedImage
                    self.capturedProcessedImageSize = processedImage.size
                    self.capturedOriginalImageSize = processedResult.originalImageSize
                    self.capturedCropRect = processedResult.cropRect

                    // Photos 앱에 최종 이미지 저장
                    self.saveToPhotosApp(processedImage)

                    // ===== 🎯 NEW: 자동 타입 인식 및 측정 수행 =====
                    print("🔍 [AutoFlow] 자동 타입 인식 및 측정 시작")
                    print("  - capturedPixelBuffer: \(self.capturedPixelBuffer != nil)")
                    print("  - capturedDepthMap: \(self.capturedDepthMap != nil)")
                    print("  - capturedOriginalImageSize: \(self.capturedOriginalImageSize != nil)")

                    if self.capturedPixelBuffer == nil {
                        print("❌ [AutoFlow] 실패: capturedPixelBuffer가 nil입니다!")
                    }
                    if self.capturedDepthMap == nil {
                        print("❌ [AutoFlow] 실패: capturedDepthMap이 nil입니다!")
                    }
                    if self.capturedOriginalImageSize == nil {
                        print("❌ [AutoFlow] 실패: capturedOriginalImageSize가 nil입니다!")
                    }

                    if let pixelBuffer = self.capturedPixelBuffer,
                       let depthMap = self.capturedDepthMap,
                       let imageSize = self.capturedOriginalImageSize {

                        // ===== AutoSize02.md: ARFrame 즉시 복사하여 보관 =====
                        // 배경 제거 처리 중에도 `currentARFrame`은 계속 업데이트되므로
                        // 지금 이 시점의 ARFrame을 즉시 복사해서 별도 상수에 저장
                        let savedARFrame = await self.getCapturedFrame()
                        print("🔍 [AutoFlow] ARFrame 즉시 저장 - frame: \(savedARFrame != nil)")

                        Task {
                            do {
                                // 1. 윤곽선 감지
                                guard let contour = try await self.autoMeasurementService.detectClothingContour(
                                    from: pixelBuffer,
                                    depthMap: depthMap
                                ) else {
                                    print("⚠️ [AutoFlow] 윤곽선 감지 실패 - 타입 선택 화면 표시")
                                    await MainActor.run {
                                        self.showingTypeSelection = true
                                    }
                                    return
                                }
                                print("✅ [AutoFlow] 윤곽선 분석 완료!")

                                // 2. 의류 타입 자동 인식
                                let features = ClothingFeatureAnalyzer().extractFeatures(from: contour)
                                let recognizedType = ClothingFeatureAnalyzer().detectClothingCategory(from: features)
                                print("🎯 [AutoFlow] 인식된 의류 타입: \(recognizedType.displayName)")

                                // 3. 특징점 추출
                                let featurePoints = self.autoMeasurementService.extractFeaturePoints(
                                    from: contour,
                                    clothingType: recognizedType
                                )

                                // 4. 측정 포인트 감지
                                let candidates = self.autoMeasurementService.detectMeasurementPoints(
                                    featurePoints: featurePoints,
                                    contour: contour,
                                    clothingType: recognizedType
                                )

                                print("📍 [AutoFlow] 측정 후보 포인트: \(candidates.count)개")

                                if !candidates.isEmpty {
                                    // 5. 2D → 3D 변환 및 측정 (저장된 ARFrame 사용)
                                    print("🔍 [AutoFlow] 저장된 ARFrame 사용 중...")
                                    if let frame = savedARFrame {
                                        print("✅ [AutoFlow] ARFrame 있음 - 측정 시작")
                                        let measurements = try await self.processCandidates(candidates, frame: frame, clothingType: recognizedType)

                                        await MainActor.run {
                                            self.autoMeasurementResults = measurements

                                            // 측정값 저장
                                            for measurement in measurements {
                                                self.session.setMeasurement(measurement.value, for: measurement.type)
                                            }

                                            // 인식된 타입 설정
                                            self.session.clothingType = recognizedType

                                            print("✅ [AutoFlow] 자동 측정 완료: \(measurements.count)개")
                                            for measurement in measurements {
                                                print("  - \(measurement.type.displayName): \(String(format: "%.1f", measurement.value))cm (startPoint: \(measurement.startPoint), endPoint: \(measurement.endPoint))")
                                            }
                                        }
                                    } else {
                                        print("❌ [AutoFlow] ARFrame 없음 - 측정 실패")
                                        print("  - currentARFrame: \(await MainActor.run { self.currentARFrame != nil })")
                                        // ARFrame이 없어도 타입은 설정하고 저장
                                        await MainActor.run {
                                            self.autoMeasurementResults = []
                                            self.session.clothingType = recognizedType
                                        }
                                    }
                                } else {
                                    await MainActor.run {
                                        self.autoMeasurementResults = []
                                        self.session.clothingType = recognizedType
                                    }
                                    print("⚠️ [AutoFlow] 측정 후보 포인트 없음")
                                }

                                // 6. 즉시 저장 (타입 선택 화면 스킵)
                                await MainActor.run {
                                    self.saveWithClothingType(recognizedType)
                                    self.showSuccess("촬영 완료! \(recognizedType.displayName) 저장됨")
                                    print("💾 [AutoFlow] 저장 완료: \(recognizedType.displayName)")

                                    // ARFrame 해제 (메모리 누수 방지)
                                    self.currentARFrame = nil
                                }

                            } catch {
                                print("❌ [AutoFlow] 자동 측정 실패: \(error.localizedDescription)")
                                // 실패 시 타입 선택 화면 표시
                                await MainActor.run {
                                    self.showingTypeSelection = true
                                }
                            }
                        }
                    } else {
                        print("❌ [AutoFlow] 필수 데이터 부족 - 타입 선택 화면 표시")
                        self.showingTypeSelection = true
                    }

                case .failure(let error):
                    self.capturedOriginalImageSize = nil
                    self.capturedProcessedImageSize = nil
                    self.capturedCropRect = nil
                    self.capturedCameraIntrinsics = nil
                    self.capturedCameraResolution = nil
                    self.handleCaptureError(error)
                }

                // 캡처 플래그 리셋
                self.captureRequested = false
            }
        }
    }

    /// ARFrame을 가져오는 헬퍼 메서드
    private func getCapturedFrame() async -> ARFrame? {
        return await MainActor.run {
            return self.currentARFrame
        }
    }

    /// 의류 타입 선택 후 처리
    ///
    /// 선택된 의류 타입으로 자동 측정을 실행하고 결과를 저장합니다.
    /// AutoSize02.md: ARFrame은 이 메서드 내에서만 사용하고, 메서드 종료 시 자동 해제되도록 함
    ///
    /// - Parameters:
    ///   - type: 선택된 의류 타입
    ///   - frame: 현재 AR 프레임 (메서드 스코프에서만 유지, 저장하지 않음)
    func handleTypeSelection(
        _ type: ClothingType,
        frame: ARFrame?
    ) {
        guard processedImageToSave != nil else {
            showError("처리된 이미지가 없습니다")
            return
        }

        // Sheet 닫기
        showingTypeSelection = false

        // 의류 타입 설정
        session.clothingType = type

        // AR 프레임이 있으면 자동 측정 실행
        if let frame = frame {
            isLoading = true

            Task {
                do {

                    // 1. 윤곽선 감지
                    guard let contour = try await autoMeasurementService.detectClothingContour(
                        from: frame.capturedImage,
                        depthMap: frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
                    ) else {
                        await MainActor.run {
                            // 자동 측정 실패해도 저장은 진행
                            saveWithClothingType(type)
                            isLoading = false
                        }
                        return
                    }

                    // 2. 특징점 추출 (템플릿 기반)
                    let featurePoints = autoMeasurementService.extractFeaturePoints(from: contour, clothingType: type)

                    // 3. 측정 포인트 감지
                    let candidates = autoMeasurementService.detectMeasurementPoints(
                        featurePoints: featurePoints,
                        contour: contour,
                        clothingType: type
                    )

                    if !candidates.isEmpty {
                        // 4. 2D → 3D 변환 및 측정
                        let measurements = try await processCandidates(candidates, frame: frame, clothingType: type)

                        // 5. 측정값 저장
                        await MainActor.run {
                            autoMeasurementResults = measurements
                            for measurement in measurements {
                                session.setMeasurement(measurement.value, for: measurement.type)
                            }
                        }
                    } else {
                        await MainActor.run {
                            autoMeasurementResults = []
                        }
                    }

                    // 6. SwiftData 저장
                    await MainActor.run {
                        saveWithClothingType(type)
                        showSuccess("촬영 완료! \(type.displayName) 저장됨")
                        isLoading = false
                    }

                } catch {
                    await MainActor.run {
                        // 실패해도 이미지는 저장
                        saveWithClothingType(type)
                        showSuccess("촬영 완료! \(type.displayName) 저장됨")
                        isLoading = false
                    }
                }
            }
        } else {
            // AR 프레임이 없으면 측정 없이 저장
            saveWithClothingType(type)
            showSuccess("촬영 완료! \(type.displayName) 저장됨")
        }
    }

    /// Photos 앱에 이미지 저장
    ///
    /// - Parameter image: 저장할 이미지
    ///
    /// ## Behavior
    /// - 권한이 없으면 자동으로 요청합니다.
    /// - ClothIQ 전용 앨범에 저장됩니다.
    /// - 저장 성공/실패 메시지를 표시합니다.
    func saveToPhotosApp(_ image: UIImage) {
        photoLibraryService.requestPermissionAndSave(image) { [weak self] success, error in
            guard let self = self else { return }

            Task { @MainActor in
                if success {
                    self.showSuccess("이미지가 Photos 앱에 저장되었습니다")
                } else {
                    let errorMsg = error?.localizedDescription ?? "알 수 없는 오류"
                    self.showError("Photos 저장 실패: \(errorMsg)")
                }
            }
        }
    }

    /// 캡처 에러 처리
    ///
    /// - Parameter error: 발생한 에러
    func handleCaptureError(_ error: Error) {
        if let captureError = error as? ObjectCaptureError {
            switch captureError {
            case .objectNotDetected:
                showError("객체를 감지할 수 없습니다. 의류를 카메라 중앙에 배치해주세요.")
            case .invalidImage:
                showError("유효하지 않은 이미지입니다.")
            case .cropFailed:
                showError("이미지 크롭에 실패했습니다.")
            case .backgroundRemovalFailed:
                showError("배경 제거에 실패했습니다.")
            case .maskGenerationFailed:
                showError("마스크 생성에 실패했습니다. 다시 시도해주세요.")
            case .processingFailed:
                showError("이미지 처리에 실패했습니다.")
            }
        } else {
            showError("이미지 캡처 중 오류가 발생했습니다: \(error.localizedDescription)")
        }
    }

    /// 이미지를 파일로 저장
    func saveImageToFile() async throws -> String {
        guard let image = capturedImage else {
            throw ImageFileError.saveFailed
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let relativePath = try imageFileManager.saveImage(image, quality: .high)
            showSuccess("이미지가 저장되었습니다")
            return relativePath
        } catch {
            showError("이미지 저장에 실패했습니다")
            throw error
        }
    }

    /// 캡처된 이미지 삭제
    func clearCapturedImage() {
        capturedImage = nil
        session.capturedImageData = nil
    }
}

// MARK: - Helper Methods

extension MeasurementViewModelRefactored {
    
    /// 임시 JPEG URL 생성
    func createTemporaryJPEGURL() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "capture_\(UUID().uuidString).jpg"
        return tempDirectory.appendingPathComponent(fileName)
    }

    /// 임시로 저장된 캡처 이미지를 정리합니다.
    func cleanupTemporaryCaptureFile() {
        guard let url = lastTemporaryCaptureURL else { return }

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
        }

        lastTemporaryCaptureURL = nil
    }
}

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
//  - 의류 타입 선택 후 저장
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
    /// 4. 의류 타입 선택 화면 표시
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
    /// 6. 의류 타입 선택 화면 표시
    ///
    /// - Parameters:
    ///   - image: AR 카메라에서 캡처된 원본 이미지
    ///   - depthMap: LiDAR depth map (배경 제거 품질 향상용, 선택)
    ///   - camera: AR 카메라 (intrinsics, 해상도 저장용)
    func handleCapturedImage(
        _ image: UIImage,
        depthMap: CVPixelBuffer?,
        camera: ARCamera?
    ) {
        isLoading = true

        // Depth map 및 카메라 메타데이터 저장 (사진 측정에 사용)
        self.capturedDepthMap = depthMap
        self.capturedOriginalImageSize = image.size
        self.capturedCameraIntrinsics = camera?.intrinsics
        self.capturedCameraResolution = camera.map {
            CGSize(width: $0.imageResolution.width, height: $0.imageResolution.height)
        }

        // 이전 임시 파일 정리
        cleanupTemporaryCaptureFile()

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
                        try? jpegData.write(to: tempURL)
                        self.lastTemporaryCaptureURL = tempURL
                    }

                    // 처리된 이미지 상태 업데이트
                    self.capturedImage = processedImage
                    self.processedImageToSave = processedImage
                    self.capturedProcessedImageSize = processedImage.size
                    self.capturedOriginalImageSize = processedResult.originalImageSize
                    self.capturedCropRect = processedResult.cropRect

                    // Photos 앱에 최종 이미지 저장
                    self.saveToPhotosApp(processedImage)

                    // 타입 선택 화면 표시
                    self.showingTypeSelection = true

                case .failure(let error):
                    self.capturedOriginalImageSize = nil
                    self.capturedProcessedImageSize = nil
                    self.capturedCropRect = nil
                    self.capturedCameraIntrinsics = nil
                    self.capturedCameraResolution = nil
                    self.handleCaptureError(error)
                }

                self.captureRequested = false
            }
        }
    }

    /// 의류 타입 선택 후 이미지를 저장합니다.
    ///
    /// 선택된 의류 타입과 함께 촬영된 이미지를 SwiftData에 저장합니다.
    /// 측정은 저장 후 사진 측정 화면에서 수동으로 수행합니다.
    ///
    /// - Parameters:
    ///   - type: 선택된 의류 타입
    ///   - frame: 현재 AR 프레임 (미사용, 호환성 유지)
    func handleTypeSelection(
        _ type: ClothingType,
        frame: ARFrame?
    ) {
        guard processedImageToSave != nil else {
            showError("처리된 이미지가 없습니다")
            return
        }

        showingTypeSelection = false
        session.clothingType = type

        saveWithClothingType(type)
        showSuccess("촬영 완료! \(type.displayName) 저장됨")

        // 메모리 해제
        currentARFrame = nil
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

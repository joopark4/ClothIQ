//
//  ImageFileManager.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  이미지 파일 저장 및 관리 서비스입니다.
//  Documents 디렉토리에 이미지를 저장하고 불러옵니다.
//
//  Key Responsibilities:
//  - 이미지 파일 저장
//  - 이미지 파일 로드
//  - 이미지 파일 삭제
//  - 저장 공간 관리
//

import Foundation
import UIKit

/// 이미지 파일 관리자
///
/// 앱의 Documents 디렉토리에 이미지를 저장하고 관리합니다.
///
final class ImageFileManager {

    // MARK: - Singleton

    static let shared = ImageFileManager()

    // MARK: - Properties

    private let fileManager = FileManager.default

    /// 이미지 저장 디렉토리
    private let imageDirectory: URL

    // MARK: - Initialization

    private init() {
        // Documents/clothing_images 디렉토리
        let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        imageDirectory = documentsDirectory.appendingPathComponent("clothing_images")

        // 디렉토리 생성
        createImageDirectoryIfNeeded()
    }

    // MARK: - Directory Management

    /// 이미지 디렉토리 생성
    private func createImageDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: imageDirectory.path) {
            try? fileManager.createDirectory(
                at: imageDirectory,
                withIntermediateDirectories: true
            )
        }
    }

    // MARK: - Save Image

    /// 이미지 저장
    ///
    /// - Parameters:
    ///   - image: 저장할 이미지
    ///   - filename: 파일 이름 (nil이면 UUID 생성)
    ///   - quality: 이미지 품질 프리셋
    /// - Returns: 저장된 파일의 상대 경로
    /// - Throws: 저장 실패 시 에러
    func saveImage(
        _ image: UIImage,
        filename: String? = nil,
        quality: ImageCaptureUtility.ImageQuality = .high
    ) throws -> String {
        // 파일명 생성
        let fileName = filename ?? UUID().uuidString
        let fileURL = imageDirectory.appendingPathComponent("\(fileName).jpg")

        // 이미지 최적화 및 압축
        guard let imageData = ImageCaptureUtility.optimizeImage(image, quality: quality) else {
            throw ImageFileError.compressionFailed
        }

        // 파일 저장
        try imageData.write(to: fileURL)

        // 상대 경로 반환
        return "clothing_images/\(fileName).jpg"
    }

    /// 이미지 데이터 저장
    ///
    /// - Parameters:
    ///   - data: 이미지 데이터
    ///   - filename: 파일 이름
    /// - Returns: 저장된 파일의 상대 경로
    /// - Throws: 저장 실패 시 에러
    func saveImageData(
        _ data: Data,
        filename: String? = nil
    ) throws -> String {
        let fileName = filename ?? UUID().uuidString
        let fileURL = imageDirectory.appendingPathComponent("\(fileName).jpg")

        try data.write(to: fileURL)

        return "clothing_images/\(fileName).jpg"
    }

    // MARK: - Load Image

    /// 이미지 로드
    ///
    /// - Parameter relativePath: 상대 경로
    /// - Returns: 로드된 이미지
    /// - Throws: 로드 실패 시 에러
    func loadImage(at relativePath: String) throws -> UIImage {
        let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        let fileURL = documentsDirectory.appendingPathComponent(relativePath)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ImageFileError.fileNotFound
        }

        guard let image = UIImage(contentsOfFile: fileURL.path) else {
            throw ImageFileError.loadFailed
        }

        return image
    }

    /// 이미지 데이터 로드
    ///
    /// - Parameter relativePath: 상대 경로
    /// - Returns: 이미지 데이터
    /// - Throws: 로드 실패 시 에러
    func loadImageData(at relativePath: String) throws -> Data {
        let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        let fileURL = documentsDirectory.appendingPathComponent(relativePath)

        return try Data(contentsOf: fileURL)
    }

    // MARK: - Delete Image

    /// 이미지 삭제
    ///
    /// - Parameter relativePath: 상대 경로
    /// - Throws: 삭제 실패 시 에러
    func deleteImage(at relativePath: String) throws {
        let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!

        let fileURL = documentsDirectory.appendingPathComponent(relativePath)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ImageFileError.fileNotFound
        }

        try fileManager.removeItem(at: fileURL)
    }

    // MARK: - Storage Management

    /// 모든 이미지 삭제
    ///
    /// - Throws: 삭제 실패 시 에러
    func deleteAllImages() throws {
        let contents = try fileManager.contentsOfDirectory(
            at: imageDirectory,
            includingPropertiesForKeys: nil
        )

        for fileURL in contents {
            try fileManager.removeItem(at: fileURL)
        }
    }

    /// 저장된 이미지 개수
    ///
    /// - Returns: 이미지 파일 개수
    func getImageCount() -> Int {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: imageDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        return contents.filter { $0.pathExtension == "jpg" }.count
    }

    /// 사용 중인 저장 공간 (바이트)
    ///
    /// - Returns: 총 크기 (바이트)
    func getTotalSize() -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: imageDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0

        for fileURL in contents {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }

    /// 사용 중인 저장 공간 (포맷된 문자열)
    ///
    /// - Returns: 포맷된 크기 (예: "15.3 MB")
    func getFormattedTotalSize() -> String {
        let bytes = getTotalSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Cleanup

    /// 오래된 이미지 정리
    ///
    /// - Parameter days: 보관 기간 (일)
    /// - Throws: 삭제 실패 시 에러
    func cleanupOldImages(olderThan days: Int) throws {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: Date()
        )!

        let contents = try fileManager.contentsOfDirectory(
            at: imageDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        )

        for fileURL in contents {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.creationDateKey]),
               let creationDate = resourceValues.creationDate,
               creationDate < cutoffDate {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }
}

// MARK: - Errors

/// 이미지 파일 에러
enum ImageFileError: LocalizedError {
    case compressionFailed
    case fileNotFound
    case loadFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "이미지 압축에 실패했습니다"
        case .fileNotFound:
            return "이미지 파일을 찾을 수 없습니다"
        case .loadFailed:
            return "이미지를 불러올 수 없습니다"
        case .saveFailed:
            return "이미지 저장에 실패했습니다"
        }
    }
}

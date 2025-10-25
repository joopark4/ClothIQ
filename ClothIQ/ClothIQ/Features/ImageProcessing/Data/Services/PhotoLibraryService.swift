//
//  PhotoLibraryService.swift
//  ClothIQ
//
//  Created on 2025-01-23
//
//  Description:
//  사진 라이브러리(Photos 앱) 연동 서비스입니다.
//  처리된 이미지를 Photos 앱에 저장하고 권한을 관리합니다.
//
//  Key Responsibilities:
//  - Photos 앱에 이미지 저장
//  - 사진 라이브러리 권한 확인 및 요청
//  - 앨범 생성 및 관리
//

import UIKit
import Photos

/// 사진 라이브러리 연동 서비스
///
/// Photos 프레임워크를 사용하여 처리된 이미지를 사용자의 사진 라이브러리에 저장합니다.
///
/// ## Topics
///
/// ### 권한 관리
/// - ``checkPermission()``
/// - ``requestPermission(completion:)``
///
/// ### 이미지 저장
/// - ``saveImage(_:completion:)``
/// - ``saveImageToAlbum(_:albumName:completion:)``
///
/// ### 앨범 관리
/// - ``createAlbum(named:completion:)``
/// - ``getAlbum(named:)``
///
final class PhotoLibraryService {

    // MARK: - Singleton

    static let shared = PhotoLibraryService()

    // MARK: - Properties

    /// ClothIQ 전용 앨범 이름
    private let defaultAlbumName = "ClothIQ"

    // MARK: - Initialization

    private init() {}

    // MARK: - Permission Management

    /// 현재 사진 라이브러리 권한 상태를 확인합니다.
    ///
    /// - Returns: 권한 상태
    ///
    /// ## Authorization Status
    /// - `.authorized`: 모든 권한 허용
    /// - `.limited`: 제한된 권한 (iOS 14+)
    /// - `.denied`: 권한 거부
    /// - `.notDetermined`: 아직 권한 요청 안함
    /// - `.restricted`: 기기 정책으로 제한됨
    ///
    /// - Note: 앨범 생성/수정을 위해 .readWrite 권한을 확인합니다.
    ///
    func checkPermission() -> PHAuthorizationStatus {
        if #available(iOS 14, *) {
            return PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            return PHPhotoLibrary.authorizationStatus()
        }
    }

    /// 사진 라이브러리 권한을 요청합니다.
    ///
    /// - Parameter completion: 권한 요청 결과 콜백 (메인 스레드에서 호출됨)
    ///
    /// - Note: Info.plist에 `NSPhotoLibraryUsageDescription` 또는 `NSPhotoLibraryAddUsageDescription` 키가 필수입니다.
    ///
    func requestPermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    completion(status == .authorized || status == .limited)
                }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    completion(status == .authorized)
                }
            }
        }
    }

    /// 사진 라이브러리 사용 가능 여부를 확인합니다.
    ///
    /// - Returns: 저장 가능 여부
    ///
    var isAuthorized: Bool {
        let status = checkPermission()
        return status == .authorized || status == .limited
    }

    // MARK: - Save Images

    /// 이미지를 사진 라이브러리에 저장합니다.
    ///
    /// - Parameters:
    ///   - image: 저장할 이미지
    ///   - completion: 저장 완료 콜백 (성공 여부, 에러)
    ///
    /// ## Usage Example
    /// ```swift
    /// PhotoLibraryService.shared.saveImage(processedImage) { success, error in
    ///     if success {
    ///         print("이미지가 Photos 앱에 저장되었습니다")
    ///     } else {
    ///         print("저장 실패: \(error?.localizedDescription ?? "")")
    ///     }
    /// }
    /// ```
    ///
    /// - Note: 권한이 없으면 자동으로 실패합니다. 먼저 권한을 확인하세요.
    ///
    func saveImage(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        // 권한 확인
        guard isAuthorized else {
            DispatchQueue.main.async {
                completion(false, PhotoLibraryError.permissionDenied)
            }
            return
        }

        // 사진 라이브러리에 저장
        PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(true, nil)
                } else {
                    completion(false, error ?? PhotoLibraryError.saveFailed)
                }
            }
        }
    }

    /// 이미지를 특정 앨범에 저장합니다.
    ///
    /// - Parameters:
    ///   - image: 저장할 이미지
    ///   - albumName: 앨범 이름 (기본값: "ClothIQ")
    ///   - completion: 저장 완료 콜백 (성공 여부, 에러)
    ///
    /// ## Behavior
    /// - 앨범이 없으면 자동으로 생성합니다.
    /// - 기존 앨범이 있으면 해당 앨범에 추가합니다.
    /// - 투명 배경 이미지는 PNG 형식으로 저장합니다.
    ///
    func saveImageToAlbum(_ image: UIImage, albumName: String = "ClothIQ", completion: @escaping (Bool, Error?) -> Void) {
        // 권한 확인
        guard isAuthorized else {
            print("❌ PhotoLibraryService: 권한 없음")
            DispatchQueue.main.async {
                completion(false, PhotoLibraryError.permissionDenied)
            }
            return
        }

        // 앨범 가져오기 또는 생성
        getOrCreateAlbum(named: albumName) { album, error in
            if let error = error {
                print("❌ PhotoLibraryService: 앨범 생성/조회 실패 - \(error.localizedDescription)")
            }

            guard let album = album else {
                DispatchQueue.main.async {
                    completion(false, error ?? PhotoLibraryError.albumNotFound)
                }
                return
            }

            print("✅ PhotoLibraryService: 앨범 준비됨 - \(albumName)")
            print("📐 PhotoLibraryService: 이미지 크기 - \(image.size)")

            // 앨범에 이미지 추가 (JPEG 형식으로 저장)
            PHPhotoLibrary.shared().performChanges {
                // JPEG 데이터로 변환 (고품질 압축)
                if let jpegData = image.jpegData(compressionQuality: 0.9) {
                    print("✅ PhotoLibraryService: JPEG 변환 성공 - \(jpegData.count) bytes")
                    let assetRequest = PHAssetCreationRequest.forAsset()
                    assetRequest.addResource(with: .photo, data: jpegData, options: nil)
                    print("📝 PhotoLibraryService: Asset 생성 요청 완료")

                    // 앨범에 추가
                    if let albumChangeRequest = PHAssetCollectionChangeRequest(for: album),
                       let placeholder = assetRequest.placeholderForCreatedAsset {
                        albumChangeRequest.addAssets([placeholder] as NSArray)
                        print("✅ PhotoLibraryService: 앨범에 추가 요청 완료")
                    } else {
                        print("❌ PhotoLibraryService: 앨범 변경 요청 또는 placeholder 생성 실패")
                    }
                } else {
                    print("❌ PhotoLibraryService: JPEG 데이터 변환 실패")
                }
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("✅ PhotoLibraryService: 이미지 저장 성공")
                        completion(true, nil)
                    } else {
                        if let error = error {
                            print("❌ PhotoLibraryService: 저장 실패 - \(error.localizedDescription)")
                        }
                        completion(false, error ?? PhotoLibraryError.saveFailed)
                    }
                }
            }
        }
    }

    // MARK: - Album Management

    /// 앨범을 가져오거나 없으면 생성합니다.
    ///
    /// - Parameters:
    ///   - albumName: 앨범 이름
    ///   - completion: 앨범 또는 에러 반환
    ///
    private func getOrCreateAlbum(named albumName: String, completion: @escaping (PHAssetCollection?, Error?) -> Void) {
        // 기존 앨범 검색
        if let existingAlbum = getAlbum(named: albumName) {
            completion(existingAlbum, nil)
            return
        }

        // 앨범 생성
        createAlbum(named: albumName, completion: completion)
    }

    /// 이름으로 앨범을 검색합니다.
    ///
    /// - Parameter albumName: 앨범 이름
    /// - Returns: 앨범 (없으면 nil)
    ///
    private func getAlbum(named albumName: String) -> PHAssetCollection? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: fetchOptions
        )

        return collections.firstObject
    }

    /// 새 앨범을 생성합니다.
    ///
    /// - Parameters:
    ///   - albumName: 생성할 앨범 이름
    ///   - completion: 생성된 앨범 또는 에러 반환
    ///
    private func createAlbum(named albumName: String, completion: @escaping (PHAssetCollection?, Error?) -> Void) {
        var albumPlaceholder: PHObjectPlaceholder?

        PHPhotoLibrary.shared().performChanges {
            let createRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
            albumPlaceholder = createRequest.placeholderForCreatedAssetCollection
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                if success, let placeholder = albumPlaceholder {
                    let collections = PHAssetCollection.fetchAssetCollections(
                        withLocalIdentifiers: [placeholder.localIdentifier],
                        options: nil
                    )
                    completion(collections.firstObject, nil)
                } else {
                    completion(nil, error ?? PhotoLibraryError.albumCreationFailed)
                }
            }
        }
    }

    // MARK: - Convenience Methods

    /// 기본 ClothIQ 앨범에 이미지를 저장합니다.
    ///
    /// - Parameters:
    ///   - image: 저장할 이미지
    ///   - completion: 저장 완료 콜백
    ///
    func saveToClothIQAlbum(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        saveImageToAlbum(image, albumName: defaultAlbumName, completion: completion)
    }

    /// 권한을 확인하고 필요시 요청한 후 이미지를 저장합니다.
    ///
    /// - Parameters:
    ///   - image: 저장할 이미지
    ///   - completion: 저장 완료 콜백
    ///
    /// ## Behavior
    /// - 권한이 있으면 즉시 저장
    /// - 권한이 없으면 요청 후 저장 시도
    ///
    func requestPermissionAndSave(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        if isAuthorized {
            saveToClothIQAlbum(image, completion: completion)
        } else {
            requestPermission { [weak self] granted in
                guard granted else {
                    completion(false, PhotoLibraryError.permissionDenied)
                    return
                }
                self?.saveToClothIQAlbum(image, completion: completion)
            }
        }
    }
}

// MARK: - Error Types

/// 사진 라이브러리 처리 중 발생할 수 있는 에러
enum PhotoLibraryError: LocalizedError {
    case permissionDenied
    case albumNotFound
    case albumCreationFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "사진 라이브러리 접근 권한이 없습니다."
        case .albumNotFound:
            return "앨범을 찾을 수 없습니다."
        case .albumCreationFailed:
            return "앨범 생성에 실패했습니다."
        case .saveFailed:
            return "이미지 저장에 실패했습니다."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "설정 > ClothIQ > 사진에서 접근 권한을 허용해주세요."
        default:
            return nil
        }
    }
}

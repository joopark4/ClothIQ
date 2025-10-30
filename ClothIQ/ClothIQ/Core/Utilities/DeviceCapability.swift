//
//  DeviceCapability.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  기기의 하드웨어 및 소프트웨어 기능을 확인하는 유틸리티입니다.
//  LiDAR 센서, AR 지원 여부 등을 체크합니다.
//
//  Key Responsibilities:
//  - LiDAR 센서 지원 여부 확인
//  - ARKit Scene Depth 지원 여부 확인
//  - 카메라 권한 확인
//

import Foundation
import ARKit
import AVFoundation
import Photos

/// 기기 기능 확인 유틸리티
///
/// LiDAR 센서 및 AR 관련 기능의 지원 여부를 확인합니다.
///
/// ## Example
/// ```swift
/// if DeviceCapability.supportsLiDAR {
///     // LiDAR 측정 기능 활성화
/// } else {
///     // 미지원 안내 표시
/// }
/// ```
///
enum DeviceCapability {

    // MARK: - LiDAR Support

    /// LiDAR 센서 지원 여부
    ///
    /// ARKit의 Scene Depth 기능을 통해 LiDAR 지원을 확인합니다.
    /// - iPhone 12 Pro 이후 Pro 모델
    /// - iPad Pro (2020년 이후 모델)
    static var supportsLiDAR: Bool {
        guard ARWorldTrackingConfiguration.isSupported else {
            return false
        }

        return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) ||
               ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// Scene Depth 지원 여부
    ///
    /// ARKit의 Scene Depth API 지원을 확인합니다.
    static var supportsSceneDepth: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// Smoothed Scene Depth 지원 여부
    ///
    /// 노이즈가 제거된 Depth 데이터 지원을 확인합니다.
    static var supportsSmoothedSceneDepth: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
    }

    // MARK: - AR Support

    /// ARKit World Tracking 지원 여부
    static var supportsARWorldTracking: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    /// 6DOF (6 Degrees of Freedom) 지원 여부
    ///
    /// 3D 공간에서의 완전한 위치 및 회전 추적 지원을 확인합니다.
    static var supports6DOF: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    // MARK: - Camera Support

    /// 카메라 사용 가능 여부
    static var hasCameraAccess: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// 카메라 권한 상태
    static var cameraAuthorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }


    // MARK: - Photo Library Support

    /// 사진 라이브러리 사용 가능 여부
    static var hasPhotoLibraryAccess: Bool {
        let status: PHAuthorizationStatus
        if #available(iOS 14, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }
        return status == .authorized || status == .limited
    }

    /// 사진 라이브러리 권한 상태
    static var photoLibraryAuthorizationStatus: PHAuthorizationStatus {
        if #available(iOS 14, *) {
            return PHPhotoLibrary.authorizationStatus(for: .addOnly)
        } else {
            return PHPhotoLibrary.authorizationStatus()
        }
    }

    // MARK: - Device Information

    /// 현재 기기 모델 이름
    static var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }

    /// iOS 버전
    static var iOSVersion: String {
        UIDevice.current.systemVersion
    }

    /// iOS 메이저 버전
    static var iOSMajorVersion: Int {
        let version = UIDevice.current.systemVersion
        let components = version.split(separator: ".")
        return Int(components.first ?? "0") ?? 0
    }

    // MARK: - Capability Check

    /// ClothIQ 앱 실행을 위한 최소 요구사항 충족 여부
    ///
    /// - Returns: 요구사항 충족 여부와 미충족 이유
    static func checkMinimumRequirements() -> (supported: Bool, reason: String?) {
        // iOS 버전 확인 (iOS 17.0 이상)
        guard iOSMajorVersion >= 17 else {
            return (false, "iOS 17.0 이상이 필요합니다. 현재 버전: \(iOSVersion)")
        }

        // ARKit 지원 확인
        guard supportsARWorldTracking else {
            return (false, "이 기기는 ARKit을 지원하지 않습니다.")
        }

        // LiDAR 지원 확인
        guard supportsLiDAR else {
            return (false, "이 기기는 LiDAR 센서를 지원하지 않습니다.\n\nLiDAR가 탑재된 기기:\n• iPhone 12 Pro 이후 Pro 모델\n• iPad Pro (2020년 이후 모델)")
        }

        return (true, nil)
    }

    // MARK: - Permission Request

    /// 카메라 권한 요청
    ///
    /// - Parameter completion: 권한 허용 여부를 반환하는 클로저
    static func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }

    /// 사진 라이브러리 권한 요청
    ///
    /// - Parameter completion: 권한 허용 여부를 반환하는 클로저
    ///
    /// ## Usage Example
    /// ```swift
    /// DeviceCapability.requestPhotoLibraryPermission { granted in
    ///     if granted {
    ///         // 사진 저장 가능
    ///     } else {
    ///         // 권한 거부됨
    ///     }
    /// }
    /// ```
    ///
    /// - Note: Info.plist에 `NSPhotoLibraryAddUsageDescription` 키가 필수입니다.
    static func requestPhotoLibraryPermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
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
}

// MARK: - Supported Device List

extension DeviceCapability {

    /// LiDAR를 지원하는 iPhone 모델 목록
    static let lidarSupportedIPhones: [String] = [
        "iPhone 12 Pro",
        "iPhone 12 Pro Max",
        "iPhone 13 Pro",
        "iPhone 13 Pro Max",
        "iPhone 14 Pro",
        "iPhone 14 Pro Max",
        "iPhone 15 Pro",
        "iPhone 15 Pro Max",
        "iPhone 16 Pro",
        "iPhone 16 Pro Max"
    ]

    /// LiDAR를 지원하는 iPad 모델 목록
    static let lidarSupportediPads: [String] = [
        "iPad Pro 11-inch (2nd generation) 이후",
        "iPad Pro 12.9-inch (4th generation) 이후"
    ]
}

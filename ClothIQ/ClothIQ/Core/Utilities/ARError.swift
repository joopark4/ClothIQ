//
//  ARError.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  AR 및 측정 관련 에러 타입을 정의합니다.
//  사용자 친화적인 에러 메시지를 제공합니다.
//

import Foundation

/// AR 및 측정 관련 에러
///
/// AR 세션 관리, LiDAR 측정, 권한 등과 관련된 에러를 정의합니다.
///
enum ARError: LocalizedError {

    // MARK: - Device Capability Errors

    /// LiDAR 센서가 지원되지 않음
    case lidarNotSupported

    /// ARKit이 지원되지 않음
    case arKitNotSupported

    /// iOS 버전이 너무 낮음
    case iOSVersionTooLow(required: String, current: String)

    // MARK: - Permission Errors

    /// 카메라 권한이 거부됨
    case cameraPermissionDenied

    /// 카메라 권한이 제한됨 (부모 제어 등)
    case cameraPermissionRestricted

    // MARK: - AR Session Errors

    /// AR 세션을 시작할 수 없음
    case sessionInitializationFailed(reason: String)

    /// AR 세션이 중단됨
    case sessionInterrupted

    /// AR 세션이 실행 중이지 않음
    case sessionNotRunning

    // MARK: - Measurement Errors

    /// 깊이 데이터가 불충분함
    case insufficientDepthData

    /// 측정 포인트가 유효하지 않음
    case invalidMeasurementPoints

    /// 측정 신뢰도가 너무 낮음
    case confidenceTooLow(score: Double)

    /// 측정 거리가 너무 가까움
    case tooClose(minimumDistance: Double)

    /// 측정 거리가 너무 멀음
    case tooFar(maximumDistance: Double)

    /// 유효하지 않은 샘플링 세션
    case invalidSamplingSession

    /// 수집된 샘플이 부족함
    case insufficientSamples

    // MARK: - Environment Errors

    /// 조명이 불충분함
    case insufficientLighting

    /// 표면 추적 실패
    case surfaceTrackingLost

    /// 카메라 이동이 너무 빠름
    case excessiveMotion

    // MARK: - LocalizedError Implementation

    var errorDescription: String? {
        switch self {
        // Device Capability
        case .lidarNotSupported:
            return "LiDAR 센서 미지원"

        case .arKitNotSupported:
            return "ARKit 미지원"

        case .iOSVersionTooLow(let required, let current):
            return "iOS 버전 부족 (필요: \(required), 현재: \(current))"

        // Permission
        case .cameraPermissionDenied:
            return "카메라 권한 거부됨"

        case .cameraPermissionRestricted:
            return "카메라 권한 제한됨"

        // AR Session
        case .sessionInitializationFailed(let reason):
            return "AR 세션 시작 실패: \(reason)"

        case .sessionInterrupted:
            return "AR 세션 중단됨"

        case .sessionNotRunning:
            return "AR 세션이 실행 중이지 않음"

        // Measurement
        case .insufficientDepthData:
            return "깊이 데이터 부족"

        case .invalidMeasurementPoints:
            return "유효하지 않은 측정 포인트"

        case .confidenceTooLow(let score):
            return "측정 신뢰도 낮음 (\(Int(score * 100))%)"

        case .tooClose(let distance):
            return "너무 가까움 (최소: \(String(format: "%.1f", distance))cm)"

        case .tooFar(let distance):
            return "너무 멀음 (최대: \(String(format: "%.1f", distance))cm)"

        case .invalidSamplingSession:
            return "유효하지 않은 샘플링 세션"

        case .insufficientSamples:
            return "수집된 샘플 부족"

        // Environment
        case .insufficientLighting:
            return "조명 부족"

        case .surfaceTrackingLost:
            return "표면 추적 손실"

        case .excessiveMotion:
            return "카메라 이동이 너무 빠름"
        }
    }

    var failureReason: String? {
        switch self {
        case .lidarNotSupported:
            return "이 기기에는 LiDAR 센서가 탑재되어 있지 않습니다."

        case .arKitNotSupported:
            return "이 기기는 ARKit을 지원하지 않습니다."

        case .iOSVersionTooLow:
            return "앱을 실행하기 위해서는 더 높은 iOS 버전이 필요합니다."

        case .cameraPermissionDenied:
            return "카메라 접근 권한이 거부되었습니다."

        case .cameraPermissionRestricted:
            return "카메라 접근이 제한되어 있습니다."

        case .sessionInitializationFailed:
            return "AR 세션을 초기화할 수 없습니다."

        case .sessionInterrupted:
            return "AR 세션이 다른 앱이나 시스템에 의해 중단되었습니다."

        case .sessionNotRunning:
            return "AR 세션이 시작되지 않았습니다."

        case .insufficientDepthData:
            return "측정에 필요한 깊이 데이터가 부족합니다."

        case .invalidMeasurementPoints:
            return "선택한 측정 포인트가 유효하지 않습니다."

        case .confidenceTooLow:
            return "측정 결과의 신뢰도가 낮아 정확하지 않을 수 있습니다."

        case .tooClose:
            return "의류가 카메라에 너무 가깝습니다."

        case .tooFar:
            return "의류가 카메라에서 너무 멉니다."

        case .invalidSamplingSession:
            return "샘플링 세션이 유효하지 않거나 이미 완료되었습니다."

        case .insufficientSamples:
            return "정확한 측정을 위한 샘플이 충분하지 않습니다."

        case .insufficientLighting:
            return "측정을 위한 조명이 부족합니다."

        case .surfaceTrackingLost:
            return "의류 표면 추적이 중단되었습니다."

        case .excessiveMotion:
            return "카메라가 너무 빠르게 움직이고 있습니다."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .lidarNotSupported:
            return """
            LiDAR가 탑재된 기기가 필요합니다:
            • iPhone 12 Pro 이후 Pro 모델
            • iPad Pro (2020년 이후 모델)
            """

        case .arKitNotSupported:
            return "ARKit을 지원하는 기기에서 앱을 실행해주세요."

        case .iOSVersionTooLow:
            return "설정 > 일반 > 소프트웨어 업데이트에서 iOS를 업데이트해주세요."

        case .cameraPermissionDenied:
            return "설정 > ClothIQ > 카메라에서 권한을 허용해주세요."

        case .cameraPermissionRestricted:
            return "기기 설정에서 카메라 제한을 해제해주세요."

        case .sessionInitializationFailed:
            return "앱을 다시 시작하거나 기기를 재부팅해주세요."

        case .sessionInterrupted:
            return "앱으로 돌아온 후 측정을 다시 시작해주세요."

        case .sessionNotRunning:
            return "AR 측정을 시작해주세요."

        case .insufficientDepthData:
            return "의류에 더 가까이 다가가거나 각도를 조정해주세요."

        case .invalidMeasurementPoints:
            return "측정 포인트를 다시 선택해주세요."

        case .confidenceTooLow:
            return "더 나은 조명과 거리에서 재측정을 권장합니다."

        case .tooClose:
            return "카메라를 의류에서 멀리 이동해주세요."

        case .tooFar:
            return "카메라를 의류에 더 가까이 이동해주세요."

        case .invalidSamplingSession:
            return "새로운 측정을 시작해주세요."

        case .insufficientSamples:
            return "측정을 다시 시도하고 카메라를 안정적으로 유지해주세요."

        case .insufficientLighting:
            return "밝은 곳에서 측정하거나 조명을 켜주세요."

        case .surfaceTrackingLost:
            return "카메라를 천천히 움직이며 의류를 다시 추적해주세요."

        case .excessiveMotion:
            return "카메라를 천천히 움직여주세요."
        }
    }
}

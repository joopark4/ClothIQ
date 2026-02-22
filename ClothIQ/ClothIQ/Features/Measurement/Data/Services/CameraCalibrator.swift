//
//  CameraCalibrator.swift
//  ClothIQ
//
//  카메라 보정 시스템 - 카메라 각도와 거리에 따른 측정 보정
//

import Foundation
import ARKit
import CoreMotion

/// 카메라 보정 시스템
/// 카메라 각도, 거리, 렌즈 왜곡을 보정하여 측정 정확도 향상
class CameraCalibrator {

    // MARK: - Properties

    /// 보정 설정
    struct CalibrationSettings {
        var enableAngleCorrection: Bool = true
        var enableDistanceCorrection: Bool = true
        var enableLensDistortionCorrection: Bool = true
        var optimalDistance: Float = 0.8  // 미터
        var optimalAngle: Float = 0  // 라디안 (0 = 수직)
    }

    private var settings = CalibrationSettings()

    /// 카메라 보정 프로파일
    private var cameraCalibrationProfile: CameraCalibrationProfile?

    /// 모션 매니저 (자이로스코프 데이터)
    private let motionManager = CMMotionManager()

    /// 현재 디바이스 모션
    private var currentDeviceMotion: CMDeviceMotion?

    // MARK: - Initialization

    init() {
        setupMotionManager()
        loadCalibrationProfile()
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - Setup

    /// 모션 매니저 설정
    private func setupMotionManager() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 0.1  // 10Hz
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let motion = motion else { return }
            self?.currentDeviceMotion = motion
        }
    }

    /// 보정 프로파일 로드
    private func loadCalibrationProfile() {
        // 디바이스별 보정 프로파일 로드
        let deviceModel = UIDevice.current.model

        if deviceModel.contains("iPhone") {
            if deviceModel.contains("Pro") {
                cameraCalibrationProfile = CameraCalibrationProfile.iPhonePro()
            } else {
                cameraCalibrationProfile = CameraCalibrationProfile.iPhone()
            }
        } else if deviceModel.contains("iPad") {
            cameraCalibrationProfile = CameraCalibrationProfile.iPadPro()
        }
    }

    // MARK: - Public Methods

    /// 카메라 각도 계산
    /// - Parameter transform: 카메라 변환 매트릭스
    /// - Returns: 카메라 각도 (라디안)
    func calculateCameraAngle(from transform: simd_float4x4) -> CameraAngle {
        // 변환 매트릭스에서 회전 추출
        let rotation = simd_quatf(transform)

        // 오일러 각 계산
        let pitch = asin(-2.0 * (rotation.imag.x * rotation.imag.z - rotation.real * rotation.imag.y))
        let yaw = atan2(2.0 * (rotation.imag.y * rotation.imag.z + rotation.real * rotation.imag.x),
                        rotation.real * rotation.real - rotation.imag.x * rotation.imag.x - rotation.imag.y * rotation.imag.y + rotation.imag.z * rotation.imag.z)
        let roll = atan2(2.0 * (rotation.imag.x * rotation.imag.y + rotation.real * rotation.imag.z),
                         rotation.real * rotation.real + rotation.imag.x * rotation.imag.x - rotation.imag.y * rotation.imag.y - rotation.imag.z * rotation.imag.z)

        return CameraAngle(pitch: pitch, yaw: yaw, roll: roll)
    }

    /// 보정 계수 계산
    /// - Parameter angle: 카메라 각도
    /// - Returns: 보정 계수
    func getCalibrationFactor(for angle: CameraAngle) -> Float {
        var factor: Float = 1.0

        if settings.enableAngleCorrection {
            factor *= calculateAngleCorrectionFactor(angle)
        }

        return factor
    }

    /// 거리 기반 보정 계수
    /// - Parameter distance: 측정 거리 (미터)
    /// - Returns: 보정 계수
    func getDistanceCalibrationFactor(_ distance: Float) -> Float {
        guard settings.enableDistanceCorrection else { return 1.0 }

        // 최적 거리에서 멀어질수록 보정 필요
        let optimalDistance = settings.optimalDistance
        let distanceRatio = distance / optimalDistance

        // 거리별 보정 계수 (경험적 값)
        if distanceRatio < 0.5 {
            return 1.15  // 너무 가까움
        } else if distanceRatio < 0.8 {
            return 1.05  // 가까움
        } else if distanceRatio < 1.2 {
            return 1.0   // 최적
        } else if distanceRatio < 1.5 {
            return 0.97  // 멀음
        } else {
            return 0.93  // 너무 멀음
        }
    }

    /// 렌즈 왜곡 보정
    /// - Parameters:
    ///   - point: 화면 좌표
    ///   - imageSize: 이미지 크기
    /// - Returns: 보정된 좌표
    func correctLensDistortion(
        point: CGPoint,
        imageSize: CGSize
    ) -> CGPoint {
        guard settings.enableLensDistortionCorrection,
              let profile = cameraCalibrationProfile else {
            return point
        }

        // 정규화된 좌표로 변환 (-1 ~ 1)
        let normalizedX = (2.0 * point.x / imageSize.width) - 1.0
        let normalizedY = (2.0 * point.y / imageSize.height) - 1.0

        // 방사 거리 계산
        let r2 = normalizedX * normalizedX + normalizedY * normalizedY
        let r4 = r2 * r2
        let r6 = r4 * r2

        // Brown-Conrady 모델 적용
        let radialDistortion = 1.0 + profile.k1 * r2 + profile.k2 * r4 + profile.k3 * r6

        // 왜곡 보정
        let correctedX = normalizedX * radialDistortion
        let correctedY = normalizedY * radialDistortion

        // 픽셀 좌표로 변환
        let pixelX = (correctedX + 1.0) * imageSize.width / 2.0
        let pixelY = (correctedY + 1.0) * imageSize.height / 2.0

        return CGPoint(x: pixelX, y: pixelY)
    }

    /// 종합 보정 적용
    /// - Parameters:
    ///   - measurement: 원본 측정값
    ///   - cameraTransform: 카메라 변환
    ///   - distance: 측정 거리
    /// - Returns: 보정된 측정값
    func applyFullCalibration(
        measurement: Float,
        cameraTransform: simd_float4x4,
        distance: Float
    ) -> CalibratedMeasurement {

        let angle = calculateCameraAngle(from: cameraTransform)

        // 각 보정 계수 계산
        let angleCorrection = settings.enableAngleCorrection ?
            calculateAngleCorrectionFactor(angle) : 1.0

        let distanceCorrection = settings.enableDistanceCorrection ?
            getDistanceCalibrationFactor(distance) : 1.0

        // 종합 보정 계수
        let totalCorrection = angleCorrection * distanceCorrection

        // 보정된 측정값
        let calibratedValue = measurement * totalCorrection

        return CalibratedMeasurement(
            originalValue: measurement,
            calibratedValue: calibratedValue,
            angleCorrection: angleCorrection,
            distanceCorrection: distanceCorrection,
            totalCorrection: totalCorrection,
            cameraAngle: angle,
            measurementDistance: distance
        )
    }

    // MARK: - Private Methods

    /// 각도 보정 계수 계산
    private func calculateAngleCorrectionFactor(_ angle: CameraAngle) -> Float {
        // 피치 각도 보정 (수직에서 벗어날수록 보정 필요)
        let pitchDeviation = abs(angle.pitch - settings.optimalAngle)

        // 코사인 보정 (각도가 클수록 실제 거리가 길어짐)
        let cosineFactor = 1.0 / cos(pitchDeviation)

        // 보정 계수 제한 (최대 20% 보정)
        return min(1.2, max(0.8, cosineFactor))
    }

    /// 자이로스코프 데이터 기반 안정성 평가
    func evaluateStability() -> StabilityLevel {
        guard let motion = currentDeviceMotion else {
            return .unknown
        }

        // 회전 속도 계산
        let x = motion.rotationRate.x
        let y = motion.rotationRate.y
        let z = motion.rotationRate.z
        let rotationRate = sqrt(x * x + y * y + z * z)

        // 안정성 레벨 결정
        switch rotationRate {
        case 0..<0.1:
            return .veryStable
        case 0.1..<0.3:
            return .stable
        case 0.3..<0.5:
            return .moderate
        case 0.5..<1.0:
            return .unstable
        default:
            return .veryUnstable
        }
    }
}

// MARK: - Supporting Types

/// 카메라 각도
struct CameraAngle {
    let pitch: Float  // X축 회전 (상하)
    let yaw: Float    // Y축 회전 (좌우)
    let roll: Float   // Z축 회전 (기울기)

    /// 각도를 도 단위로 변환
    var pitchDegrees: Float { return pitch * 180.0 / .pi }
    var yawDegrees: Float { return yaw * 180.0 / .pi }
    var rollDegrees: Float { return roll * 180.0 / .pi }

    /// 수직으로부터의 편차
    var deviationFromVertical: Float {
        return abs(pitch)
    }
}

/// 카메라 보정 프로파일
struct CameraCalibrationProfile {
    let deviceModel: String
    let k1: CGFloat  // 방사 왜곡 계수 1
    let k2: CGFloat  // 방사 왜곡 계수 2
    let k3: CGFloat  // 방사 왜곡 계수 3
    let p1: CGFloat  // 접선 왜곡 계수 1
    let p2: CGFloat  // 접선 왜곡 계수 2

    /// iPhone Pro 보정 프로파일
    static func iPhonePro() -> CameraCalibrationProfile {
        return CameraCalibrationProfile(
            deviceModel: "iPhone Pro",
            k1: -0.28,
            k2: 0.15,
            k3: -0.03,
            p1: 0.001,
            p2: -0.0005
        )
    }

    /// iPhone 기본 보정 프로파일
    static func iPhone() -> CameraCalibrationProfile {
        return CameraCalibrationProfile(
            deviceModel: "iPhone",
            k1: -0.25,
            k2: 0.12,
            k3: -0.02,
            p1: 0.001,
            p2: -0.0003
        )
    }

    /// iPad Pro 보정 프로파일
    static func iPadPro() -> CameraCalibrationProfile {
        return CameraCalibrationProfile(
            deviceModel: "iPad Pro",
            k1: -0.22,
            k2: 0.10,
            k3: -0.02,
            p1: 0.0008,
            p2: -0.0002
        )
    }
}

/// 보정된 측정값
struct CalibratedMeasurement {
    let originalValue: Float
    let calibratedValue: Float
    let angleCorrection: Float
    let distanceCorrection: Float
    let totalCorrection: Float
    let cameraAngle: CameraAngle
    let measurementDistance: Float

    /// 보정 차이 (퍼센트)
    var correctionPercentage: Float {
        return ((calibratedValue - originalValue) / originalValue) * 100
    }

    /// 센티미터 단위
    var calibratedValueInCentimeters: Float {
        return calibratedValue * 100
    }

    var originalValueInCentimeters: Float {
        return originalValue * 100
    }
}

/// 안정성 레벨
enum StabilityLevel: String {
    case unknown = "Unknown"
    case veryStable = "Very Stable"
    case stable = "Stable"
    case moderate = "Moderate"
    case unstable = "Unstable"
    case veryUnstable = "Very Unstable"

    var color: String {
        switch self {
        case .unknown: return "gray"
        case .veryStable: return "green"
        case .stable: return "blue"
        case .moderate: return "yellow"
        case .unstable: return "orange"
        case .veryUnstable: return "red"
        }
    }

    var recommendation: String {
        switch self {
        case .unknown:
            return "안정성을 평가할 수 없습니다."
        case .veryStable:
            return "완벽한 측정 조건입니다."
        case .stable:
            return "측정하기 좋은 조건입니다."
        case .moderate:
            return "조금 더 안정적으로 유지해주세요."
        case .unstable:
            return "디바이스를 안정적으로 유지해주세요."
        case .veryUnstable:
            return "측정이 부정확할 수 있습니다. 안정적으로 유지해주세요."
        }
    }
}
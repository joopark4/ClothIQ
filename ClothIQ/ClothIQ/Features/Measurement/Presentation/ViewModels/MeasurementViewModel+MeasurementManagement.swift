//
//  MeasurementViewModel+MeasurementManagement.swift
//  ClothIQ
//
//  Created on 2025-11-05
//
//  Description:
//  측정 포인트 관리, 거리 계산, 환경 평가, 방향 모니터링을 담당하는 extension입니다.
//
//  Key Responsibilities:
//  - 측정 포인트 추가 및 삭제
//  - 2개 포인트 기반 거리 계산
//  - 환경 점수 평가 및 추적 상태 업데이트
//  - 디바이스 방향 모니터링
//

import Foundation
import ARKit
import UIKit
import Combine

// MARK: - Measurement Point Management

extension MeasurementViewModelRefactored {
    
    /// 화면 탭 처리 - 측정 포인트 추가
    ///
    /// - Parameters:
    ///   - location: 화면 좌표
    ///   - frame: AR 프레임
    func handleTap(at location: CGPoint, frame: ARFrame) {
        // 평면 추정을 위한 ARFrame 정보 저장
        lastDepthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
        lastCameraTransform = frame.camera.transform
        lastCameraIntrinsics = frame.camera.intrinsics

        do {
            // Service를 통해 측정 포인트 추출
            guard let point = try measurementService.extractMeasurementPoint(
                at: location,
                from: frame
            ) else {
                showError("측정 포인트를 추가할 수 없습니다.")
                return
            }

            addMeasurementPoint(point)

        } catch let error as ARError {
            handleARError(error)
        } catch {
            showError("측정 중 오류가 발생했습니다: \(error.localizedDescription)")
        }
    }

    /// 측정 포인트 추가
    func addMeasurementPoint(_ point: MeasurementPoint) {
        measurementPoints.append(point)
        session.addPoint(point)
        selectedPointIndex = measurementPoints.count - 1

        // 2개 이상의 포인트가 있으면 거리 계산
        if measurementPoints.count >= 2 {
            calculateDistance()
        }
    }

    /// 마지막 측정 포인트 제거
    func removeLastPoint() {
        guard !measurementPoints.isEmpty else { return }
        _ = measurementPoints.popLast()
        session.removeLastPoint()

        if measurementPoints.isEmpty {
            selectedPointIndex = nil
        } else {
            selectedPointIndex = measurementPoints.count - 1
        }
    }

    /// 모든 측정 포인트 제거
    func clearAllPoints() {
        measurementPoints.removeAll()
        session.clearPoints()
        selectedPointIndex = nil
    }

    /// 의류 타입 설정
    ///
    /// 선택된 의류 타입을 변경하고 관련 상태를 초기화합니다.
    /// - Parameter type: 새로 선택된 의류 타입
    func setClothingType(_ type: ClothingType) {
        let isSameType = session.clothingType == type

        // 타입이 변경되면 Kalman 필터 리셋
        if !isSameType {
            measurementFilter.resetAll()
        }

        if isSameType {
            session.state = .measuring
            return
        }

        session = MeasurementSession(
            clothingType: type,
            state: .measuring
        )
        measurementPoints.removeAll()
        selectedPointIndex = nil
        currentMeasurementType = nil
        captureRequested = false
        capturedImage = nil
        showSuccess("\(type.displayName) 측정을 시작하세요")
    }
}

// MARK: - Distance Calculation

extension MeasurementViewModelRefactored {
    
    /// 거리 계산 (가장 최근 2개 포인트 기준)
    func calculateDistance() {
        guard measurementPoints.count >= 2 else { return }

        let lastIndex = measurementPoints.count - 1
        let startPoint = measurementPoints[lastIndex - 1]
        let endPoint = measurementPoints[lastIndex]

        // 거리 계산: 평면 추정 우선, 실패 시 각도 보정 사용
        let rawDistanceInCm: Double

        // ARFrame 데이터가 모두 있으면 평면 추정 사용 (가장 정확)
        if let depthMap = lastDepthMap,
           let transform = lastCameraTransform,
           let intrinsics = lastCameraIntrinsics {
            rawDistanceInCm = MeasurementCalculator.calculateDistanceOnPlane(
                from: startPoint,
                to: endPoint,
                depthMap: depthMap,
                cameraTransform: transform,
                cameraIntrinsics: intrinsics
            )
        } else {
            // ARFrame 데이터 없으면 각도 보정 방식 사용
            rawDistanceInCm = MeasurementCalculator.calculateCorrectedDistance(
                from: startPoint,
                to: endPoint,
                useAngleCorrection: true
            )
        }

        // 측정 타입이 지정되어 있으면 저장
        if let measurementType = currentMeasurementType {
            // 신뢰도 계산 (양쪽 포인트의 평균 신뢰도)
            let avgConfidence = (startPoint.confidence + endPoint.confidence) / 2.0

            // 각도 기반 신뢰도 조정
            let avgAngle = (startPoint.cameraPitchAngle + endPoint.cameraPitchAngle) / 2.0
            let angleConfidence = AngleCorrectionService.assessConfidence(for: avgAngle)
            let totalConfidence = avgConfidence * angleConfidence

            // Kalman 필터 적용
            let filteredDistance = measurementFilter.update(
                id: measurementType.rawValue,
                value: rawDistanceInCm,
                confidence: totalConfidence
            )

            // 측정값 검증
            let validation = MeasurementCalculator.validateMeasurement(
                value: filteredDistance,
                type: measurementType
            )

            if !validation.isValid {
                showError(validation.warning ?? "측정값이 유효하지 않습니다")
                return
            }

            // 각도 경고 (60도 이상일 때만)
            if avgAngle > 60 {
                showSuccess("⚠️ 카메라 각도가 큽니다 (현재: \(Int(avgAngle))°)")
            } else if let warning = validation.warning {
                showSuccess("⚠️ \(warning)")
            }

            session.setMeasurement(filteredDistance, for: measurementType)

            // 측정 품질 표시
            let qualityDesc = AngleCorrectionService.qualityDescription(for: avgAngle)
            showSuccess("측정 완료: \(measurementType.displayName) = \(String(format: "%.1f", filteredDistance)) cm (품질: \(qualityDesc))")
        }
    }

    /// 특정 측정 타입 시작
    func startMeasurement(for type: MeasurementType) {
        currentMeasurementType = type
        clearAllPoints()
        showSuccess("\(type.displayName) 측정을 시작합니다\n\n\(type.measurementGuide)")
    }

    /// 측정 완료
    func completeMeasurement() {
        guard session.isComplete else {
            showError("필수 측정 항목이 모두 완료되지 않았습니다")
            return
        }

        // 세션 검증
        let validation = session.validate()
        guard validation.isValid else {
            showError(validation.error ?? "측정 세션이 유효하지 않습니다")
            return
        }

        session.complete()
        session.state = .reviewing

        // SwiftData에 저장
        saveToSwiftData()
    }
}

// MARK: - Environment Assessment

extension MeasurementViewModelRefactored {
    
    // 마지막 경고 시간 추적
    private var lastWarningTime: Date? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.lastWarningTime) as? Date
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.lastWarningTime, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    private var warningCooldown: TimeInterval { 5.0 }  // 5초에 한 번만 경고

    /// AR 프레임 업데이트 처리
    func updateEnvironment(from frame: ARFrame) {
        // Service를 통해 환경 평가
        environmentScore = measurementService.assessEnvironment(from: frame)

        // 환경 점수가 매우 낮을 때만 경고 (기준을 0.3으로 낮춤)
        if environmentScore < 0.3 && isARSessionRunning {
            let now = Date()
            // 쿨다운 체크
            if let lastWarning = lastWarningTime,
               now.timeIntervalSince(lastWarning) < warningCooldown {
                return
            }

            lastWarningTime = now
            showError("측정 환경이 좋지 않습니다. 밝은 곳에서 의류를 수평으로 펼쳐 촬영해주세요.")
        }
    }

    /// AR 추적 상태 업데이트 처리
    func updateTrackingState(_ state: ARCamera.TrackingState) {
        trackingState = state

        // TrackingState가 Normal이면 초기화 완료
        if case .normal = state {
            if !isARInitialized {
                isARInitialized = true
            }
        } else {
            // Normal이 아니면 초기화 미완료
            if isARInitialized {
                isARInitialized = false
            }
        }
    }

    /// TrackingState를 사용자 친화적 메시지로 변환
    func trackingStateMessage(_ state: ARCamera.TrackingState) -> String? {
        switch state {
        case .notAvailable:
            return "AR을 사용할 수 없습니다"

        case .limited(let reason):
            switch reason {
            case .initializing:
                return "LiDAR 센서 초기화 중..."
            case .insufficientFeatures:
                return "아이폰을 천천히 움직여주세요"
            case .excessiveMotion:
                return "카메라가 너무 빠릅니다. 천천히 움직여주세요"
            case .relocalizing:
                return "공간을 다시 인식하는 중..."
            @unknown default:
                return "AR 추적 제한됨"
            }

        case .normal:
            return nil  // 정상 상태일 때는 메시지 없음
        }
    }

    /// TrackingState 설명 (디버깅용)
    func trackingStateDescription(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .notAvailable:
            return "Not Available"
        case .limited(let reason):
            return "Limited (\(reason))"
        case .normal:
            return "Normal"
        }
    }
}

// MARK: - Orientation Monitoring

extension MeasurementViewModelRefactored {
    
    func setupOrientationMonitoring() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()

        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.validateCurrentOrientation()
            }
            .store(in: &cancellables)

        validateCurrentOrientation()
    }

    @discardableResult
    func validateCurrentOrientation() -> Bool {
        let orientation = UIDevice.current.orientation

        var isLandscape = orientation.isLandscape
        var isPortrait = orientation.isPortrait

        if orientation == .unknown || orientation == .faceUp || orientation == .faceDown {
            if let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first {
                let orientation = windowScene.effectiveGeometry.interfaceOrientation
                switch orientation {
                case .landscapeLeft, .landscapeRight:
                    isLandscape = true
                    isPortrait = false
                case .portrait, .portraitUpsideDown:
                    isPortrait = true
                    isLandscape = false
                default:
                    break
                }
            }
        }

        // 모든 방향 허용 - 가로/세로 모두 정상 촬영 가능
        if isLandscape {
            if !hasShownOrientationWarning {
                // 가로 모드도 지원한다는 안내 메시지
                showSuccess("가로 모드로 촬영이 가능합니다.")
                hasShownOrientationWarning = true
            }
            return true  // 가로 모드 허용
        } else if isPortrait {
            if hasShownOrientationWarning {
                showSuccess("세로 모드로 촬영이 가능합니다.")
                hasShownOrientationWarning = false
            }
            return true
        }

        return true
    }
}

// MARK: - Associated Keys for Runtime Properties

private struct AssociatedKeys {
    static var lastWarningTime: UInt8 = 0
}

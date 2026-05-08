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
    
    /// 화면 탭 처리 - 다중 샘플링 시작
    ///
    /// - Parameters:
    ///   - location: 화면 좌표
    ///   - frame: AR 프레임
    func handleTap(at location: CGPoint, frame: ARFrame) {
        // 이미 샘플링 중이면 무시
        guard !isSampling else {
            return
        }

        // 평면 추정을 위한 ARFrame 정보 저장
        lastDepthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
        lastCameraTransform = frame.camera.transform
        lastCameraIntrinsics = frame.camera.intrinsics

        // 다중 샘플링 시작
        startPointSampling(at: location)
    }

    /// 포인트 샘플링 시작
    private func startPointSampling(at location: CGPoint) {
        print("🎯 [ViewModel] 포인트 샘플링 시작 at \(location)")

        // 샘플링 세션 시작
        let samplingID = measurementService.startPointSampling(at: location)

        // 상태 업데이트
        currentSamplingID = samplingID
        isSampling = true
        samplingProgress = 0.0
        currentSampleCount = 0

        print("  - 샘플링 ID: \(samplingID)")
        print("  - 목표 샘플 수: \(targetSampleCount)")
    }

    /// AR 프레임 업데이트 시 호출 - 샘플 수집
    func handleARFrameUpdate(_ frame: ARFrame) {
        // 환경 점수 업데이트
        updateEnvironment(from: frame)

        // 샘플링 중이면 샘플 수집
        if isSampling, currentSamplingID != nil {
            collectSampleForCurrentSession(from: frame)
        }
    }

    /// 현재 샘플링 세션에 샘플 수집
    private func collectSampleForCurrentSession(from frame: ARFrame) {
        guard let samplingID = currentSamplingID else { return }

        do {
            // 샘플 수집
            if let progress = try measurementService.collectSample(for: samplingID, from: frame) {
                // 진행률 업데이트
                samplingProgress = progress
                currentSampleCount = Int(progress * Float(targetSampleCount))

                print("📊 [ViewModel] 샘플 수집 진행: \(Int(progress * 100))% (\(currentSampleCount)/\(targetSampleCount))")
            } else {
                // nil 반환 = 샘플링 완료
                finalizeSampledPoint()
            }
        } catch let error as ARError {
            // 샘플링 실패 - 취소하고 에러 표시
            cancelSampling()
            handleARError(error)
        } catch {
            cancelSampling()
            showError("샘플 수집 중 오류: \(error.localizedDescription)")
        }
    }

    /// 샘플링 완료 및 포인트 추가
    private func finalizeSampledPoint() {
        guard let samplingID = currentSamplingID else { return }

        do {
            print("✅ [ViewModel] 샘플링 완료, 포인트 정제 중...")

            // 정제된 포인트 받기
            let refinedPoint = try measurementService.finalizeSampledPoint(for: samplingID)

            // 측정 포인트 추가
            addMeasurementPoint(refinedPoint)

            // 샘플링 상태 초기화
            resetSamplingState()

            print("✅ [ViewModel] 정제된 포인트 추가 완료!")

        } catch let error as ARError {
            cancelSampling()
            handleARError(error)
        } catch {
            cancelSampling()
            showError("포인트 정제 중 오류: \(error.localizedDescription)")
        }
    }

    /// 샘플링 취소
    func cancelSampling() {
        guard let samplingID = currentSamplingID else { return }

        print("❌ [ViewModel] 샘플링 취소")

        measurementService.cancelSampling(for: samplingID)
        resetSamplingState()
    }

    /// 샘플링 상태 초기화
    private func resetSamplingState() {
        currentSamplingID = nil
        isSampling = false
        samplingProgress = 0.0
        currentSampleCount = 0
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

        if measurementPoints.count < 2 {
            pendingMeasurement = nil
        }

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
        pendingMeasurement = nil
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
        completedMeasurements.removeAll() // 옷 타입이 바뀌면 전체 측정도 초기화
        pendingMeasurement = nil
        selectedPointIndex = nil
        currentMeasurementType = type.requiredMeasurements.first
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

            // ✅ 교정 계수 적용 (AR 실시간 측정 방식)
            let calibratedDistance: Double
            if let clothingType = session.clothingType {
                calibratedDistance = MeasurementSettings.shared.applyCorrectionFactor(
                    type: measurementType,
                    clothingType: clothingType,
                    value: filteredDistance,
                    method: .ar  // AR 실시간 측정용 교정 계수 사용
                )

                // 교정 적용 로그
                if abs(calibratedDistance - filteredDistance) > 0.01 {
                    print("📏 [AR Calibration] 교정 계수 적용")
                    print("  - 측정 타입: \(measurementType.displayName)")
                    print("  - 의류 타입: \(clothingType.displayName)")
                    print("  - 원본 값: \(String(format: "%.2f", filteredDistance))cm")
                    print("  - 교정 후: \(String(format: "%.2f", calibratedDistance))cm")
                    print("  - 보정: \(String(format: "%.2f", calibratedDistance - filteredDistance))cm (\(String(format: "%.1f", (calibratedDistance / filteredDistance - 1.0) * 100.0))%)")
                }
            } else {
                calibratedDistance = filteredDistance
            }

            // 값 자체가 비정상(NaN/무한/0이하)일 때만 차단
            guard calibratedDistance.isFinite, calibratedDistance > 0 else {
                pendingMeasurement = nil
                showError("측정값 계산에 실패했습니다. 다시 측정해주세요.")
                return
            }

            // 각도 경고 (60도 이상일 때만)
            if avgAngle > 60 {
                showSuccess("⚠️ 카메라 각도가 큽니다 (현재: \(Int(avgAngle))°)")
            }

            // 교정된 값으로 저장 (임시 저장 상태)
            session.setMeasurement(calibratedDistance, for: measurementType)

            // 적용 버튼에서 사용할 최근 계산 결과 캐시
            pendingMeasurement = CompletedMeasurement(
                type: measurementType,
                startPoint: startPoint,
                endPoint: endPoint,
                distanceInCm: calibratedDistance,
                confidence: Double(totalConfidence),
                measurementMethod: .ar
            )

            // 진행 중 오버레이 리스트에 임시 추가 (아직 확정은 아니지만, 시각적인 정보와 함께)
            // 화면상에 거리가 텍스트로 보일 테지만 measurementPoints에 의해 선이 파란색으로 그려질 것입니다.

            showSuccess("예상 측정 거리: \(measurementType.displayName) = \(String(format: "%.1f", calibratedDistance)) cm")
        }
    }
    
    /// 현재의 측정을 확정하고 다음 측정으로 넘어감 ("적용" 버튼에서 호출)
    func applyCurrentMeasurement() {
        guard let measurementType = currentMeasurementType else {
            showError("측정 항목을 선택해주세요.")
            return
        }

        let candidate: CompletedMeasurement
        if measurementPoints.count >= 2 {
            let lastIndex = measurementPoints.count - 1
            let startPoint = measurementPoints[lastIndex - 1]
            let endPoint = measurementPoints[lastIndex]

            let measuredValue = session.measurements[measurementType] ?? startPoint.distanceInCentimeters(to: endPoint)
            candidate = CompletedMeasurement(
                type: measurementType,
                startPoint: startPoint,
                endPoint: endPoint,
                distanceInCm: measuredValue,
                measurementMethod: .ar
            )
        } else if let pending = pendingMeasurement, pending.type == measurementType {
            candidate = pending
            if session.measurements[measurementType] == nil {
                session.setMeasurement(pending.distanceInCm, for: measurementType)
            }
        } else {
            showError("저장할 두 개의 측정 포인트가 필요합니다.")
            return
        }

        let savedValue = session.measurements[measurementType] ?? candidate.distanceInCm
        
        // 오버레이 리스트에 추가 (중복 덮어쓰기)
        let completed = CompletedMeasurement(
            type: measurementType,
            startPoint: candidate.startPoint,
            endPoint: candidate.endPoint,
            distanceInCm: savedValue,
            confidence: candidate.confidence,
            coordinateSpace: candidate.coordinateSpace,
            measurementMethod: candidate.measurementMethod
        )
        completedMeasurements.removeAll { $0.type == measurementType }
        completedMeasurements.append(completed)

        // 측정 완료 품질 표시
        showSuccess("\(measurementType.displayName) 측정 완료!")

        // 다음 측정을 준비하기 위해 방금 찍은 포인트를 초기화
        clearAllPoints()
        
        // 다음 권장 항목 선택
        if let clothingType = session.clothingType {
            let nextType = clothingType.requiredMeasurements.first { !completedMeasurements.map({$0.type}).contains($0) }
            if let nextType = nextType {
                currentMeasurementType = nextType
                showSuccess("다음 항목: \(nextType.displayName)")
            } else {
                showSuccess("모든 필수 측정 완료. 촬영(완료) 버튼을 눌러주세요.")
            }
        }
    }

    /// 특정 측정 타입 시작 (In-Camera Picker에서 호출될 때)
    func startMeasurement(for type: MeasurementType) {
        currentMeasurementType = type
        clearAllPoints()
        pendingMeasurement = nil
        
        if completedMeasurements.contains(where: { $0.type == type }) {
            showSuccess("\(type.displayName) 항목을 다시 측정합니다.\n이전 측정선은 덮어씌워집니다.")
        } else {
            showSuccess("\(type.displayName) 측정을 시작합니다\n\n\(type.measurementGuide)")
        }
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

extension MeasurementViewModelRefactored {
    /// 현재 측정 항목을 적용할 수 있는지 여부
    var canApplyCurrentMeasurement: Bool {
        guard let measurementType = currentMeasurementType else { return false }
        if measurementPoints.count >= 2 {
            return true
        }
        return pendingMeasurement?.type == measurementType
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

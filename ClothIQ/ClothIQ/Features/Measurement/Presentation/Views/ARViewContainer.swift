//
//  ARViewContainer.swift
//  ClothIQ
//
//  Created on 2025-10-22
//
//  Description:
//  ARKit의 ARView를 SwiftUI에 통합하는 UIViewRepresentable입니다.
//  AR 카메라 화면을 표시하고 사용자 상호작용을 처리합니다.
//
//  Key Responsibilities:
//  - AR 세션 설정 및 관리
//  - LiDAR Scene Depth 활성화
//  - 탭 제스처 처리
//  - AR 프레임 데이터 전달
//

import SwiftUI
import RealityKit
import ARKit
import AVFoundation

/// AR 뷰 컨테이너
///
/// ARKit의 ARView를 SwiftUI에서 사용할 수 있도록 래핑합니다.
///
struct ARViewContainer: UIViewRepresentable {
    /// AR 세션 시작 시 콜백
    var onSessionStarted: (() -> Void)?

    /// 탭 이벤트 콜백
    ///
    /// - Parameters:
    ///   - location: 화면 좌표
    ///   - frame: 현재 AR 프레임
    var onTap: ((CGPoint, ARFrame) -> Void)?

    /// AR 프레임 업데이트 콜백
    var onFrameUpdate: ((ARFrame) -> Void)?

    /// 깊이 데이터 업데이트 콜백
    var onDepthUpdate: ((CVPixelBuffer) -> Void)?

    /// AR 추적 상태 변경 콜백
    var onTrackingStateChanged: ((ARCamera.TrackingState) -> Void)?

    /// 앵커 업데이트 콜백 (평면 감지용)
    var onAnchorsUpdate: (([ARAnchor]) -> Void)?

    /// 스크린샷 캡처 요청 (외부에서 트리거)
    @Binding var captureRequested: Bool

    /// 캡처된 이미지 콜백 (이미지, depth map, 카메라)
    var onImageCaptured: ((UIImage, CVPixelBuffer?, ARCamera?) -> Void)?

    // MARK: - UIViewRepresentable

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // AR 세션 설정
        let configuration = configureARSession()

        // AR 세션 실행
        arView.session.run(configuration)

        // Delegate 설정
        arView.session.delegate = context.coordinator

        // 탭 제스처 추가
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        // 디버그 옵션 (개발 중에만 활성화)
        #if DEBUG
        // arView.debugOptions = [.showFeaturePoints, .showWorldOrigin]
        #endif

        // 세션 시작 콜백
        DispatchQueue.main.async {
            onSessionStarted?()
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // 캡처 요청 처리 (한 번만 실행되도록)
        if captureRequested {
            print("🟡 [ARViewContainer] captureRequested = true 감지")
            print("🟡 [ARViewContainer] isCapturing = \(context.coordinator.isCapturing)")

            if !context.coordinator.isCapturing {
                context.coordinator.isCapturing = true
                print("🟢 [ARViewContainer] 캡처 시작")

                // 캡처 실행 (비동기로 한 번만)
                DispatchQueue.main.async {
                    self.captureRequested = false  // 즉시 플래그 리셋 (중복 캡처 방지)
                    print("🟢 [ARViewContainer] captureRequested 리셋")

                    if let image = ImageCaptureUtility.captureARFrame(from: uiView) {
                        print("🟢 [ARViewContainer] AR 프레임 캡처 성공 - 크기: \(image.size)")

                        // 현재 AR 프레임의 depth map도 함께 전달
                        let currentFrame = uiView.session.currentFrame
                        let depthMap = currentFrame?.smoothedSceneDepth?.depthMap
                            ?? currentFrame?.sceneDepth?.depthMap

                        print("📊 [ARViewContainer] Depth map 캡처: \(depthMap != nil ? "성공" : "실패")")

                        if self.onImageCaptured != nil {
                            print("🟢 [ARViewContainer] onImageCaptured 콜백 호출")
                            self.onImageCaptured?(image, depthMap, currentFrame?.camera)
                        } else {
                            print("🔴 [ARViewContainer] onImageCaptured 콜백이 nil!")
                        }
                    } else {
                        print("🔴 [ARViewContainer] AR 프레임 캡처 실패")
                    }
                    // 캡처 완료 후 플래그 리셋
                    context.coordinator.isCapturing = false
                    print("🟢 [ARViewContainer] isCapturing 리셋")
                }
            } else {
                print("⚠️ [ARViewContainer] 이미 캡처 중 - 건너뜀")
            }
        }
    }

    // MARK: - AR Configuration

    /// AR 세션 설정
    ///
    /// - Returns: ARWorldTrackingConfiguration
    private func configureARSession() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()

        // LiDAR Scene Depth 활성화
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }

        // 평면 감지 활성화
        configuration.planeDetection = [.horizontal, .vertical]

        // 환경 텍스처링 활성화
        configuration.environmentTexturing = .automatic

        return configuration
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onFrameUpdate: onFrameUpdate,
            onDepthUpdate: onDepthUpdate,
            onTrackingStateChanged: onTrackingStateChanged,
            onAnchorsUpdate: onAnchorsUpdate
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, ARSessionDelegate {
        var onTap: ((CGPoint, ARFrame) -> Void)?
        var onFrameUpdate: ((ARFrame) -> Void)?
        var onDepthUpdate: ((CVPixelBuffer) -> Void)?
        var onTrackingStateChanged: ((ARCamera.TrackingState) -> Void)?
        var onAnchorsUpdate: (([ARAnchor]) -> Void)?
        var isCapturing: Bool = false  // 중복 캡처 방지 플래그
        var lastTrackingState: ARCamera.TrackingState?  // 상태 변경 감지용

        // ARFrame 메모리 누수 방지를 위한 프레임 레이트 제한
        private var lastFrameUpdateTime: Date?
        private let frameUpdateInterval: TimeInterval = 0.033  // 30fps (33ms)

        init(
            onTap: ((CGPoint, ARFrame) -> Void)?,
            onFrameUpdate: ((ARFrame) -> Void)?,
            onDepthUpdate: ((CVPixelBuffer) -> Void)?,
            onTrackingStateChanged: ((ARCamera.TrackingState) -> Void)?,
            onAnchorsUpdate: (([ARAnchor]) -> Void)?
        ) {
            self.onTap = onTap
            self.onFrameUpdate = onFrameUpdate
            self.onDepthUpdate = onDepthUpdate
            self.onTrackingStateChanged = onTrackingStateChanged
            self.onAnchorsUpdate = onAnchorsUpdate
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = gesture.view as? ARView else { return }

            let location = gesture.location(in: arView)

            // 카메라 포커스 설정
            setFocus(at: location, in: arView)

            // 필요한 경우 onTap 콜백 호출 (현재는 포커스만 설정)
            // guard let currentFrame = arView.session.currentFrame else { return }
            // onTap?(location, currentFrame)
        }

        /// 탭한 위치에 카메라 포커스 설정
        ///
        /// - Parameters:
        ///   - point: 화면 좌표
        ///   - arView: AR 뷰
        private func setFocus(at point: CGPoint, in arView: ARView) {
            // ARKit의 카메라는 자동으로 조절되므로 AVCaptureDevice를 사용하여 포커스 설정
            // ARSession의 카메라 디바이스에 접근
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("⚠️ 카메라 디바이스를 찾을 수 없습니다")
                return
            }

            // 화면 좌표를 0~1 범위로 정규화
            let normalizedPoint = CGPoint(
                x: point.x / arView.bounds.width,
                y: point.y / arView.bounds.height
            )

            do {
                try device.lockForConfiguration()

                // 포커스 모드 설정
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = normalizedPoint
                    device.focusMode = .autoFocus
                    print("✅ 카메라 포커스 설정: \(normalizedPoint)")
                }

                // 노출 설정
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.autoExpose) {
                    device.exposurePointOfInterest = normalizedPoint
                    device.exposureMode = .autoExpose
                    print("✅ 카메라 노출 설정: \(normalizedPoint)")
                }

                device.unlockForConfiguration()

                // 시각적 피드백 (선택적)
                showFocusIndicator(at: point, in: arView)

            } catch {
                print("❌ 카메라 설정 실패: \(error.localizedDescription)")
            }
        }

        /// 포커스 위치에 시각적 인디케이터 표시
        ///
        /// - Parameters:
        ///   - point: 화면 좌표
        ///   - arView: AR 뷰
        private func showFocusIndicator(at point: CGPoint, in arView: ARView) {
            // 기존 인디케이터 제거
            arView.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }

            // 포커스 인디케이터 뷰 생성
            let indicatorSize: CGFloat = 80
            let indicator = UIView(frame: CGRect(
                x: point.x - indicatorSize / 2,
                y: point.y - indicatorSize / 2,
                width: indicatorSize,
                height: indicatorSize
            ))
            indicator.tag = 999
            indicator.layer.borderColor = UIColor.systemYellow.cgColor
            indicator.layer.borderWidth = 2
            indicator.layer.cornerRadius = indicatorSize / 2
            indicator.backgroundColor = UIColor.clear
            indicator.alpha = 0

            arView.addSubview(indicator)

            // 애니메이션
            UIView.animate(withDuration: 0.2, animations: {
                indicator.alpha = 1
                indicator.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            }) { _ in
                UIView.animate(withDuration: 0.3, delay: 0.5, options: [], animations: {
                    indicator.alpha = 0
                    indicator.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
                }) { _ in
                    indicator.removeFromSuperview()
                }
            }
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // ARFrame 메모리 누수 방지: autoreleasepool 사용
            autoreleasepool {
                // ARFrame 메모리 누수 방지: 프레임 레이트 제한 (30fps)
                let now = Date()
                if let lastTime = lastFrameUpdateTime,
                   now.timeIntervalSince(lastTime) < frameUpdateInterval {
                    return  // 프레임 건너뛰기
                }
                lastFrameUpdateTime = now

                onFrameUpdate?(frame)

                // 추적 상태 변경 감지
                let currentTrackingState = frame.camera.trackingState
                if lastTrackingState == nil || !areSameTrackingState(lastTrackingState!, currentTrackingState) {
                    lastTrackingState = currentTrackingState
                    DispatchQueue.main.async {
                        self.onTrackingStateChanged?(currentTrackingState)
                    }
                }

                // 앵커 업데이트 전달 (평면 감지용)
                let anchors = frame.anchors
                onAnchorsUpdate?(anchors)

                // 깊이 데이터 전달
                if let depthData = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap {
                    onDepthUpdate?(depthData)
                }
            }
        }

        /// 두 TrackingState가 같은지 비교 (enum associated value 때문에 직접 비교 필요)
        private func areSameTrackingState(_ lhs: ARCamera.TrackingState, _ rhs: ARCamera.TrackingState) -> Bool {
            switch (lhs, rhs) {
            case (.normal, .normal):
                return true
            case (.notAvailable, .notAvailable):
                return true
            case (.limited(let reason1), .limited(let reason2)):
                return reason1 == reason2
            default:
                return false
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            print("AR Session failed: \(error.localizedDescription)")
        }

        func sessionWasInterrupted(_ session: ARSession) {
            print("AR Session was interrupted")
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            print("AR Session interruption ended")
        }
    }
}

// MARK: - ARView Helpers

extension ARView {
    /// AR 세션 일시정지
    func pauseSession() {
        session.pause()
    }

    /// AR 세션 재개
    func resumeSession() {
        let configuration = ARWorldTrackingConfiguration()

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }

        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic

        session.run(configuration)
    }
}

// MARK: - Preview

#Preview {
    ARViewContainer(
        onSessionStarted: {
            print("AR Session started")
        },
        onTap: { location, frame in
            print("Tapped at: \(location)")
        },
        onFrameUpdate: { frame in
            // Frame updates
        },
        onDepthUpdate: { depthData in
            print("Depth data updated")
        },
        captureRequested: .constant(false),
        onImageCaptured: { image, depthMap, camera in
            print("Image captured: \(image.size), Depth: \(depthMap != nil)")
        }
    )
}

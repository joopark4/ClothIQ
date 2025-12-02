# iOS 의류 측정 앱 구현: LiDAR와 AI 비전의 통합

**Smartsizer 앱의 핵심 기술 4가지는 ARKit LiDAR, AI 컴퓨터 비전, CoreML/Vision 프레임워크 통합, 그리고 3D 포인트 클라우드 측정 알고리즘으로 구성됩니다.** iPhone 12 Pro 이상의 LiDAR 센서는 0.2~5미터 범위에서 256×192 해상도의 깊이 맵을 초당 60프레임으로 생성하며, 이를 MobileNet 기반 객체 감지, HRNet 키포인트 추출, DeepLab 세그멘테이션과 결합하여 1.59~2.08% 오차 범위 내에서 의류를 측정합니다. 이 시스템은 iOS 14.0+, A12 Bionic 이상의 칩셋이 필요하며, CoreML과 Vision Framework를 통해 실시간 추론을 수행합니다.

## 핵심 기술 구조: LiDAR와 Size Assist 마커의 이중 시스템

**LiDAR 센서는 Direct Time-of-Flight 방식으로 30,000개의 픽셀을 측정하며, 나노초 단위의 광 펄스 반사 시간을 통해 깊이를 계산합니다.** ARKit은 이 원시 데이터를 RGB 카메라 영상과 머신러닝으로 융합하여 256×192 해상도의 `depthMap`과 신뢰도 맵(`confidenceMap`)을 생성합니다. Size Assist 마커는 알려진 크기의 참조 객체로, 픽셀-미터 변환에 필수적인 스케일 팩터를 제공합니다.

**이중 기술 아키텍처는 LiDAR의 절대 깊이 측정과 마커 기반 스케일 보정을 결합합니다.** LiDAR가 3D 구조를 제공하면, 마커는 실제 세계 단위로의 변환을 담당합니다. 수식은 다음과 같습니다:

```
scale_factor = L_real / L_pixel  [mm/pixel]
actual_measurement = distance_3D × scale_factor
```

**ARKit 구현은 세 가지 핵심 API로 구성됩니다.** `ARFrame`은 매 프레임의 데이터 컨테이너로, `capturedImage`(1920×1440 YCbCr 포맷), `sceneDepth`(실시간 깊이), `smoothedSceneDepth`(시간 평활화된 깊이)를 포함합니다. `ARDepthData`는 Float32 픽셀 버퍼의 `depthMap`(미터 단위)과 UInt8의 `confidenceMap`(신뢰도 1-3)을 제공합니다. `ARMeshAnchor`는 약 1m×1m 크기의 3D 메쉬 세그먼트를 표현하며, 버텍스, 노멀, 면 데이터와 표면 분류(바닥, 벽, 천장 등)를 포함합니다.

**깊이 데이터 접근을 위한 Swift 구현:**

```swift
import ARKit

class DepthProcessor: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let sceneDepth = frame.sceneDepth,
              let depthMap = sceneDepth.depthMap,
              let confidenceMap = sceneDepth.confidenceMap else {
            return
        }
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        let floatBuffer = unsafeBitCast(
            CVPixelBufferGetBaseAddress(depthMap),
            to: UnsafeMutablePointer<Float32>.self
        )
        
        // 특정 픽셀의 깊이 값 추출 (미터 단위)
        let depthInMeters = floatBuffer[y * width + x]
        
        // 신뢰도 필터링
        let confidenceBuffer = unsafeBitCast(
            CVPixelBufferGetBaseAddress(confidenceMap),
            to: UnsafeMutablePointer<UInt8>.self
        )
        let confidence = ARConfidenceLevel(rawValue: Int(confidenceBuffer[y * width + x]))
        guard confidence == .high else { return }
    }
}
```

**참조 마커 감지는 ARReferenceImage를 사용합니다.** 알려진 크기의 이미지를 ARWorldTrackingConfiguration에 등록하면, ARKit이 자동으로 추적하고 물리적 크기를 보고합니다:

```swift
let configuration = ARWorldTrackingConfiguration()

if let trackedImages = ARReferenceImage.referenceImages(
    inGroupNamed: "AR Resources", 
    bundle: nil
) {
    configuration.detectionImages = trackedImages
    configuration.maximumNumberOfTrackedImages = 1
}

func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    guard let imageAnchor = anchor as? ARImageAnchor else { return }
    
    let physicalSize = imageAnchor.referenceImage.physicalSize
    let scaleX = physicalSize.width / imageWidthPixels
    let scaleY = physicalSize.height / imageHeightPixels
    
    // 평균 스케일 팩터 계산
    let scaleFactor = (scaleX + scaleY) / 2.0
}
```

## AI 컴퓨터 비전 처리: 의류 인식부터 측정 포인트까지

**의류 자동 인식은 YOLOv5/v8과 MobileNetV2의 조합으로 구현됩니다.** YOLO는 단일 단계 객체 감지기로, iPhone에서 17-30 FPS의 실시간 성능을 제공합니다. MobileNetV2는 깊이별 분리 가능 컨볼루션을 사용하여 VGGNet 대비 10배 빠르면서 비슷한 정확도를 유지합니다. 이 백본은 약 7MB(16비트 정밀도)로, 구형 iPhone에서도 30 FPS로 실행됩니다.

**YOLOv8의 iOS 구현 아키텍처는 세 단계로 구성됩니다.** 입력 이미지는 640×640으로 리사이즈되고, CNN 백본을 통과하여 특징 맵을 추출하며, 감지 헤드가 바운딩 박스, 클래스 확률, 신뢰도를 예측합니다. CoreML 변환 시 INT8 양자화를 적용하면 모델 크기가 75% 감소하고 추론 속도가 2-3배 향상되며 정확도 손실은 1% 미만입니다.

**측정 포인트 추출은 HRNet(High-Resolution Network)이 최고 성능을 제공합니다.** HRNet은 네트워크 전체에 걸쳐 고해상도 표현을 유지하는 독특한 아키텍처로, COCO Keypoints에서 89.0% mAP@0.5를 달성합니다. DeepFashion2 데이터셋에서 학습된 HRNet은 294개의 의류 랜드마크(13개 카테고리에 걸쳐 평균 20개/아이템)를 감지합니다.

**의류 경계 검출은 DeepLabV3+ 또는 U-Net 세그멘테이션으로 구현됩니다.** DeepLabV3+는 MobileNetV2 백본과 결합 시 Pascal VOC2012에서 70.51% mIOU를 달성하지만, U-Net이 모바일 배포에 더 적합합니다. U-Net은 4.59MB의 파라미터로 더 빠른 학습(50 에폭에 4분)과 실시간 추론(86% IoU)을 제공합니다.

**Mask R-CNN은 인스턴스 세그멘테이션이 필요할 때 사용됩니다.** 이는 Faster R-CNN에 마스크 예측 브랜치를 추가한 구조로, DeepFashion2에서 79.2% AP(감지), 37% Mask AP를 달성합니다. 하지만 계산 비용이 높아 iOS 배포 시 최적화가 필수입니다.

**의류 경계 검출을 위한 전통적인 컴퓨터 비전 기법:**

Canny 에지 감지는 다단계 알고리즘으로 얇고 명확한 경계를 생성합니다:

```swift
// OpenCV Canny 구현 (Objective-C++)
cv::Mat grayImage, edges;
cv::cvtColor(inputImage, grayImage, cv::COLOR_BGR2GRAY);
cv::GaussianBlur(grayImage, grayImage, cv::Size(5,5), 1.4);
cv::Canny(grayImage, edges, 50, 150);  // threshold1=50, threshold2=150

// 컨투어 검출
std::vector<std::vector<cv::Point>> contours;
cv::findContours(edges, contours, cv::RETR_EXTERNAL, cv::CHAIN_APPROX_SIMPLE);

// 가장 큰 컨투어 선택 (의류 경계로 가정)
double maxArea = 0;
int maxIdx = -1;
for(int i = 0; i < contours.size(); i++) {
    double area = cv::contourArea(contours[i]);
    if(area > maxArea) {
        maxArea = area;
        maxIdx = i;
    }
}
```

**키포인트 추출 알고리즘의 구체적 접근법:**

1. **YOLOv5 + HRNet 결합**: YOLO로 의류 감지 → 크롭된 영역에 HRNet 적용 → 294개 랜드마크 중 관련 포인트 추출
2. **정확도**: Human 3.6M 데이터셋에서 94.8% PCK, 99.2% PDJ@0.4, 평균 오차 5.14 픽셀
3. **속도**: 55 FPS (모바일에서는 최적화 후 15-25 FPS)

**LiDAR와 결합된 자동 의류 측정 시스템:**

최근 연구(MDPI Applied Sciences, 2022)에서 제안된 방법은 HRNet 키포인트 감지를 LiDAR 포인트 클라우드와 결합하여 1.59-2.08%의 측정 오차를 달성했습니다. 이는 수동 측정(3.25% 오차)보다 우수합니다.

## iOS 네이티브 아키텍처: ARKit, CoreML, Vision의 삼중주

**CoreML은 Apple의 네이티브 머신러닝 프레임워크로, 자동 하드웨어 가속을 제공합니다.** Neural Engine(11-15+ TOPS), GPU, CPU 중 최적의 실행 경로를 자동 선택합니다. 두 가지 모델 포맷을 지원합니다: **.mlmodel**(레거시 바이너리, iOS 11+)과 **.mlpackage**(현대적 패키지 구조, iOS 15+).

**모델 변환은 coremltools를 통해 수행됩니다:**

```python
import coremltools as ct
import torch

# PyTorch 모델 변환
torch_model.eval()
example_input = torch.rand(1, 3, 224, 224)
traced_model = torch.jit.trace(torch_model, example_input)

# 이미지 전처리 설정 (정규화)
scale = 1/(0.226*255.0)
bias = [-0.485/0.229, -0.456/0.224, -0.406/0.225]

image_input = ct.ImageType(
    name="input",
    shape=(1, 3, 224, 224),
    scale=scale,
    bias=bias,
    color_layout=ct.colorlayout.RGB
)

model = ct.convert(
    traced_model,
    inputs=[image_input],
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS15
)

# INT8 양자화 적용
import coremltools.optimize as cto

config = cto.coreml.OpLinearQuantizerConfig(
    mode="linear_symmetric",
    dtype="int8"
)
quantized_model = cto.coreml.linear_quantize_weights(model, config)
quantized_model.save("YOLOv8_INT8.mlpackage")
```

**Vision Framework는 CoreML 모델을 이미지 분석 파이프라인에 통합합니다.** `VNCoreMLRequest`는 CoreML 모델을 래핑하고, `VNImageRequestHandler`는 다양한 소스(UIImage, CIImage, CVPixelBuffer)에서 추론을 실행합니다.

**실시간 비디오 처리 아키텍처:**

```swift
import AVFoundation
import Vision
import CoreML

class RealtimeProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private let captureSession = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInitiated)
    private var visionRequests = [VNRequest]()
    private let semaphore = DispatchSemaphore(value: 1)
    
    func setupVision() throws {
        // CoreML 모델 로드
        let config = MLModelConfiguration()
        config.computeUnits = .all  // CPU + GPU + Neural Engine
        config.allowLowPrecisionAccumulationOnGPU = true
        
        let coreMLModel = try YOLOv8(configuration: config)
        let visionModel = try VNCoreMLModel(for: coreMLModel.model)
        
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            self?.handleDetections(request: request, error: error)
        }
        request.imageCropAndScaleOption = .scaleFill
        visionRequests = [request]
    }
    
    func captureOutput(_ output: AVCaptureOutput, 
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        
        // 프레임 스로틀링 (동시 처리 방지)
        guard semaphore.wait(timeout: .now()) == .success else {
            return
        }
        defer { semaphore.signal() }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        
        do {
            try handler.perform(visionRequests)
        } catch {
            print("Vision error: \(error)")
        }
    }
    
    private func handleDetections(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return
        }
        
        DispatchQueue.main.async {
            // UI 업데이트 (메인 스레드)
            for observation in results {
                let bbox = observation.boundingBox
                let label = observation.labels.first?.identifier ?? "unknown"
                let confidence = observation.confidence
                
                print("\(label): \(confidence) at \(bbox)")
            }
        }
    }
}
```

**ARKit 카메라 피드와 Vision Framework 통합:**

```swift
import ARKit

class ARVisionIntegration: UIViewController, ARSessionDelegate {
    
    let sceneView = ARSCNView()
    var segmentationRequest: VNCoreMLRequest!
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        
        let orientation = CGImagePropertyOrientation(
            rawValue: UInt32(UIDevice.current.orientation.rawValue)
        ) ?? .up
        
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: orientation,
                options: [:]
            )
            
            do {
                try handler.perform([self.segmentationRequest])
            } catch {
                print("Vision failed: \(error)")
            }
        }
    }
    
    func processSegmentationMask(_ observation: VNPixelBufferObservation) {
        // 세그멘테이션 마스크를 ARKit 3D 공간에 투영
        guard let currentFrame = sceneView.session.currentFrame else { return }
        
        let maskBuffer = observation.pixelBuffer
        // 마스크 픽셀을 순회하며 의류 영역 식별
        // 해당 픽셀의 3D 좌표 계산하여 측정 수행
    }
}
```

**Core Image를 사용한 전처리 파이프라인:**

```swift
import CoreImage

func preprocessImage(_ image: CIImage) -> CIImage? {
    var processed = image
    
    // 1. 리사이즈 (성능 향상)
    let scale = 224.0 / max(image.extent.width, image.extent.height)
    let scaleFilter = CIFilter(name: "CILanczosScaleTransform")!
    scaleFilter.setValue(processed, forKey: kCIInputImageKey)
    scaleFilter.setValue(scale, forKey: kCIInputScaleKey)
    scaleFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)
    processed = scaleFilter.outputImage!
    
    // 2. 대비 향상
    let contrastFilter = CIFilter(name: "CIColorControls")!
    contrastFilter.setValue(processed, forKey: kCIInputImageKey)
    contrastFilter.setValue(1.5, forKey: kCIInputContrastKey)
    processed = contrastFilter.outputImage!
    
    // 3. 가우시안 블러 (노이즈 제거)
    let blurFilter = CIFilter.gaussianBlur()
    blurFilter.inputImage = processed
    blurFilter.radius = 1.0
    processed = blurFilter.outputImage!
    
    return processed
}
```

**컴퓨트 유닛 선택 및 최적화:**

| 컴퓨트 유닛 | 최적 사용 사례 | 성능 |
|------------|------------|------|
| Neural Engine | INT8 양자화 모델, 소형 배치 | 11-15+ TOPS |
| GPU | FP16 정밀도, 대형 배치 | 중간 처리량 |
| CPU | 비지원 연산, 소형 모델 | 범용 폴백 |

Neural Engine은 A12 Bionic(2 TOPS)에서 시작하여 A15(15 TOPS)까지 발전했습니다. INT8 양자화 모델은 Neural Engine에서 최대 성능을 발휘합니다.

## 부위별 측정 구현: 3D 포인트 클라우드에서 2D 측정값으로

**3D 포인트 클라우드 생성은 ARKit 깊이 맵을 언프로젝션하여 수행됩니다.** 각 픽셀(u, v)을 깊이 Z와 결합하여 3D 좌표를 계산합니다:

```
X = Z × (u - cx) / fx
Y = Z × (v - cy) / fy
Z = depthMap[u, v]
```

여기서 (fx, fy)는 초점 거리, (cx, cy)는 주점입니다. ARCamera의 `intrinsics` 속성이 이 값들을 제공합니다.

**포인트 클라우드 생성 Swift 구현:**

```swift
func generatePointCloud(frame: ARFrame) -> [SIMD3<Float>] {
    guard let depthData = frame.sceneDepth,
          let depthBuffer = PixelBuffer<Float32>(pixelBuffer: depthData.depthMap),
          let confidenceBuffer = PixelBuffer<UInt8>(pixelBuffer: depthData.confidenceMap!) else {
        return []
    }
    
    var points: [SIMD3<Float>] = []
    let intrinsics = frame.camera.intrinsics
    let fx = intrinsics[0][0]
    let fy = intrinsics[1][1]
    let cx = intrinsics[2][0]
    let cy = intrinsics[2][1]
    
    for row in 0..<depthBuffer.size.height {
        for col in 0..<depthBuffer.size.width {
            // 신뢰도 필터링
            let confidence = ARConfidenceLevel(rawValue: Int(confidenceBuffer.value(x: col, y: row)))
            guard confidence == .high else { continue }
            
            let depth = depthBuffer.value(x: col, y: row)
            guard depth > 0 && depth < 5.0 else { continue }
            
            // 정규화된 좌표
            let normalizedX = Float(col) / Float(depthBuffer.size.width)
            let normalizedY = Float(row) / Float(depthBuffer.size.height)
            
            // 이미지 좌표로 변환
            let imageSize = CGSize(width: 1920, height: 1440)
            let imageX = normalizedX * Float(imageSize.width)
            let imageY = normalizedY * Float(imageSize.height)
            
            // 카메라 로컬 좌표로 언프로젝트
            let localX = (imageX - cx) / fx * depth
            let localY = (imageY - cy) / fy * depth
            let localZ = depth
            
            let localPoint = SIMD3<Float>(localX, localY, localZ)
            
            // 월드 좌표로 변환
            let cameraTransform = frame.camera.transform
            let worldPoint = cameraTransform * SIMD4<Float>(localPoint, 1)
            
            points.append(SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z))
        }
    }
    
    return points
}
```

**3D 유클리드 거리 계산:**

두 점 P₁(x₁, y₁, z₁)과 P₂(x₂, y₂, z₂) 사이의 거리:

```
d = √[(x₂ - x₁)² + (y₂ - y₁)² + (z₂ - z₁)²]
```

Swift 구현:

```swift
func distance3D(_ p1: SIMD3<Float>, _ p2: SIMD3<Float>) -> Float {
    return simd_distance(p1, p2)
}

// 또는 수동 계산
func euclideanDistance(_ p1: SIMD3<Float>, _ p2: SIMD3<Float>) -> Float {
    let dx = p2.x - p1.x
    let dy = p2.y - p1.y
    let dz = p2.z - p1.z
    return sqrt(dx*dx + dy*dy + dz*dz)
}
```

**스케일 캘리브레이션 알고리즘:**

참조 마커를 사용한 픽셀-미터 변환:

```swift
func calibrateScale(referenceMarker: ARImageAnchor) -> Float {
    let knownWidth = 0.1  // 10cm 마커
    let pixelWidth = measurePixelWidth(referenceMarker)
    
    let scaleFactor = knownWidth / pixelWidth  // [meters/pixel]
    return scaleFactor
}

func applyScaleToMeasurement(pixelDistance: Float, scaleFactor: Float) -> Float {
    return pixelDistance * scaleFactor
}
```

**완전한 측정 프로세스:**

```swift
class GarmentMeasurement {
    
    func measureGarment(frame: ARFrame, keypoints: [SIMD2<Float>]) -> [String: Float] {
        var measurements: [String: Float] = [:]
        
        // 1. 키포인트를 3D로 변환
        let points3D = keypoints.map { kp -> SIMD3<Float>? in
            return get3DPoint(imagePoint: kp, frame: frame)
        }.compactMap { $0 }
        
        guard points3D.count >= 4 else { return [:] }
        
        // 2. 어깨 너비 측정 (키포인트 0, 1)
        let shoulderWidth = simd_distance(points3D[0], points3D[1])
        measurements["shoulder_width"] = shoulderWidth * 100  // cm 단위
        
        // 3. 소매 길이 측정 (키포인트 1, 2)
        let sleeveLength = simd_distance(points3D[1], points3D[2])
        measurements["sleeve_length"] = sleeveLength * 100
        
        // 4. 상의 길이 측정 (키포인트 0, 3)
        let topLength = simd_distance(points3D[0], points3D[3])
        measurements["top_length"] = topLength * 100
        
        return measurements
    }
    
    func get3DPoint(imagePoint: SIMD2<Float>, frame: ARFrame) -> SIMD3<Float>? {
        // 깊이 맵에서 깊이 값 추출
        guard let depthData = frame.sceneDepth else { return nil }
        let depthMap = depthData.depthMap
        
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        
        // 이미지 좌표를 깊이 맵 좌표로 변환
        let depthX = Int(imagePoint.x * Float(depthWidth))
        let depthY = Int(imagePoint.y * Float(depthHeight))
        
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let floatBuffer = unsafeBitCast(
            CVPixelBufferGetBaseAddress(depthMap),
            to: UnsafeMutablePointer<Float32>.self
        )
        
        let depth = floatBuffer[depthY * depthWidth + depthX]
        guard depth > 0 && depth < 5.0 else { return nil }
        
        // 3D로 언프로젝트
        let intrinsics = frame.camera.intrinsics
        let fx = intrinsics[0][0]
        let fy = intrinsics[1][1]
        let cx = intrinsics[2][0]
        let cy = intrinsics[2][1]
        
        let x = (Float(depthX) - cx) / fx * depth
        let y = (Float(depthY) - cy) / fy * depth
        let z = depth
        
        let localPoint = SIMD3<Float>(x, y, z)
        
        // 월드 좌표로 변환
        let cameraTransform = frame.camera.transform
        let worldPoint = cameraTransform * SIMD4<Float>(localPoint, 1)
        
        return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
    }
}
```

**원주 측정 (허리, 가슴 등):**

```swift
func measureCircumference(points: [SIMD3<Float>]) -> Float {
    guard points.count >= 3 else { return 0 }
    
    var totalLength: Float = 0
    
    // 연속된 점들 사이의 거리를 합산
    for i in 0..<points.count {
        let current = points[i]
        let next = points[(i + 1) % points.count]
        totalLength += simd_distance(current, next)
    }
    
    return totalLength * 100  // cm 단위
}

// 3D 포인트를 2D 평면에 투영 (예: 수평 평면)
func projectToHorizontalPlane(points: [SIMD3<Float>], height: Float) -> [SIMD3<Float>] {
    return points.filter { abs($0.y - height) < 0.05 }  // ±5cm 범위
}
```

**측정 정확도 향상 기법:**

1. **번들 조정(Bundle Adjustment)**: 다중 뷰에서 3D 구조와 카메라 파라미터를 동시에 최적화

```
minimize Σᵢ Σⱼ ||xᵢⱼ - π(Pⱼ, Xᵢ)||²
```

여기서 xᵢⱼ는 관측된 2D 점, π(Pⱼ, Xᵢ)는 3D 점 Xᵢ를 카메라 Pⱼ로 투영한 결과입니다.

2. **Levenberg-Marquardt 최적화**:

```
θₖ₊₁ = θₖ - (JᵀJ + λI)⁻¹Jᵀe
```

여기서 θ는 파라미터, J는 자코비안, e는 오차, λ는 댐핑 파라미터입니다.

3. **RANSAC 아웃라이어 제거**:

```swift
func ransacLineFitting(points: [SIMD3<Float>], iterations: Int = 1000, threshold: Float = 0.01) -> (SIMD3<Float>, SIMD3<Float>)? {
    var bestInliers: [SIMD3<Float>] = []
    var bestLine: (SIMD3<Float>, SIMD3<Float>)?
    
    for _ in 0..<iterations {
        // 랜덤하게 2개 점 선택
        let sample = points.shuffled().prefix(2)
        guard sample.count == 2 else { continue }
        
        let p1 = sample[0]
        let p2 = sample[1]
        let direction = normalize(p2 - p1)
        
        // 인라이어 카운트
        var inliers: [SIMD3<Float>] = []
        for point in points {
            let distance = pointToLineDistance(point, linePoint: p1, lineDirection: direction)
            if distance < threshold {
                inliers.append(point)
            }
        }
        
        if inliers.count > bestInliers.count {
            bestInliers = inliers
            bestLine = (p1, direction)
        }
    }
    
    return bestLine
}

func pointToLineDistance(_ point: SIMD3<Float>, linePoint: SIMD3<Float>, lineDirection: SIMD3<Float>) -> Float {
    let v = point - linePoint
    let cross = simd_cross(v, lineDirection)
    return simd_length(cross)
}
```

## 통합 구현: 전체 의류 측정 파이프라인

**완전한 구현 워크플로우는 다섯 단계로 구성됩니다:**

**단계 1: ARKit 세션 설정 및 초기화**

```swift
import ARKit
import RealityKit

class ClothingMeasurementApp: UIViewController, ARSessionDelegate {
    
    @IBOutlet var arView: ARView!
    private var mlModel: VNCoreMLModel!
    private var keypointDetector: VNCoreMLRequest!
    private var capturedPoints: [SIMD3<Float>] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupARSession()
        setupMLModels()
    }
    
    func setupARSession() {
        // LiDAR 지원 확인
        guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
              ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            showAlert("이 기기는 LiDAR를 지원하지 않습니다")
            return
        }
        
        arView.session.delegate = self
        arView.automaticallyConfigureSession = false
        
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .mesh
        config.planeDetection = [.horizontal, .vertical]
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        
        // 바디 트래킹 활성화 (A12+)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.bodyDetection) {
            config.frameSemantics.insert(.bodyDetection)
        }
        
        // 참조 이미지 로드
        if let trackedImages = ARReferenceImage.referenceImages(
            inGroupNamed: "SizeAssistMarkers",
            bundle: nil
        ) {
            config.detectionImages = trackedImages
            config.maximumNumberOfTrackedImages = 1
        }
        
        arView.session.run(config)
    }
    
    func setupMLModels() {
        do {
            // HRNet 키포인트 감지 모델
            let modelConfig = MLModelConfiguration()
            modelConfig.computeUnits = .all
            
            let hrnetModel = try HRNetKeypoints(configuration: modelConfig)
            mlModel = try VNCoreMLModel(for: hrnetModel.model)
            
            keypointDetector = VNCoreMLRequest(model: mlModel) { [weak self] request, error in
                self?.processKeypoints(request: request, error: error)
            }
            keypointDetector.imageCropAndScaleOption = .scaleFill
            
        } catch {
            print("모델 로딩 실패: \(error)")
        }
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 프레임마다 처리 (또는 N번째 프레임만)
        processFrame(frame)
    }
}
```

**단계 2: 실시간 비전 처리 및 키포인트 감지**

```swift
extension ClothingMeasurementApp {
    
    private var isProcessingFrame = false
    private let visionQueue = DispatchQueue(label: "visionQueue", qos: .userInitiated)
    
    func processFrame(_ frame: ARFrame) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true
        
        let pixelBuffer = frame.capturedImage
        
        visionQueue.async { [weak self] in
            defer { self?.isProcessingFrame = false }
            
            let handler = VNImageRequestHandler(
                cvPixelBuffer: pixelBuffer,
                orientation: .up,
                options: [:]
            )
            
            do {
                try handler.perform([self!.keypointDetector])
            } catch {
                print("Vision 실패: \(error)")
            }
        }
    }
    
    func processKeypoints(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedPointsObservation] else {
            return
        }
        
        guard let frame = arView.session.currentFrame else { return }
        
        // 키포인트를 3D로 변환
        var points3D: [SIMD3<Float>] = []
        
        for observation in results {
            if let recognizedPoints = try? observation.recognizedPoints(.all) {
                for (name, point) in recognizedPoints where point.confidence > 0.5 {
                    // 정규화된 좌표 (0-1 범위)
                    let normalizedPoint = SIMD2<Float>(Float(point.location.x), Float(point.location.y))
                    
                    if let point3D = get3DPoint(imagePoint: normalizedPoint, frame: frame) {
                        points3D.append(point3D)
                    }
                }
            }
        }
        
        // 측정 수행
        performMeasurements(points3D: points3D)
    }
}
```

**단계 3: 스케일 캘리브레이션 및 마커 인식**

```swift
extension ClothingMeasurementApp {
    
    private var scaleFactor: Float = 1.0
    private var isCalibrated = false
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let imageAnchor = anchor as? ARImageAnchor {
                handleReferenceMarker(imageAnchor)
            }
        }
    }
    
    func handleReferenceMarker(_ imageAnchor: ARImageAnchor) {
        let referenceImage = imageAnchor.referenceImage
        let physicalWidth = Float(referenceImage.physicalSize.width)  // meters
        let physicalHeight = Float(referenceImage.physicalSize.height)
        
        // 이미지 좌표계에서 픽셀 크기 계산
        // ARKit은 실제 크기를 제공하므로 직접 사용
        
        scaleFactor = 1.0  // ARKit은 이미 미터 단위
        isCalibrated = true
        
        print("스케일 캘리브레이션 완료: \(physicalWidth)m × \(physicalHeight)m")
        
        // 마커 위치에 시각적 피드백 표시
        let sphere = MeshResource.generateSphere(radius: 0.05)
        let material = SimpleMaterial(color: .green, isMetallic: false)
        let entity = ModelEntity(mesh: sphere, materials: [material])
        
        let anchor = AnchorEntity(anchor: imageAnchor)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
    }
}
```

**단계 4: 의류 측정 수행**

```swift
extension ClothingMeasurementApp {
    
    struct GarmentMeasurements {
        var shoulderWidth: Float?
        var chestWidth: Float?
        var sleeveLength: Float?
        var totalLength: Float?
        var waistWidth: Float?
        
        var description: String {
            var result = "의류 측정 결과:\n"
            if let sw = shoulderWidth { result += "어깨 너비: \(String(format: "%.1f", sw)) cm\n" }
            if let cw = chestWidth { result += "가슴 너비: \(String(format: "%.1f", cw)) cm\n" }
            if let sl = sleeveLength { result += "소매 길이: \(String(format: "%.1f", sl)) cm\n" }
            if let tl = totalLength { result += "총 길이: \(String(format: "%.1f", tl)) cm\n" }
            if let ww = waistWidth { result += "허리 너비: \(String(format: "%.1f", ww)) cm\n" }
            return result
        }
    }
    
    func performMeasurements(points3D: [SIMD3<Float>]) {
        guard points3D.count >= 4 else {
            print("측정을 위한 키포인트 부족: \(points3D.count)/4")
            return
        }
        
        var measurements = GarmentMeasurements()
        
        // 키포인트 인덱스 정의 (HRNet 출력에 따라 조정 필요)
        // 0: 왼쪽 어깨, 1: 오른쪽 어깨, 2: 왼쪽 팔꿈치, 3: 왼쪽 손목
        // 4: 왼쪽 허리, 5: 오른쪽 허리, 6: 밑단 왼쪽, 7: 밑단 오른쪽
        
        if points3D.count >= 2 {
            // 어깨 너비
            let shoulderDist = simd_distance(points3D[0], points3D[1])
            measurements.shoulderWidth = shoulderDist * 100 * scaleFactor
        }
        
        if points3D.count >= 4 {
            // 소매 길이 (어깨 → 팔꿈치 → 손목)
            let upperArm = simd_distance(points3D[1], points3D[2])
            let forearm = simd_distance(points3D[2], points3D[3])
            measurements.sleeveLength = (upperArm + forearm) * 100 * scaleFactor
        }
        
        if points3D.count >= 6 {
            // 가슴 너비 (수평 거리만 계산)
            let chestLeft = SIMD2<Float>(points3D[0].x, points3D[0].z)
            let chestRight = SIMD2<Float>(points3D[1].x, points3D[1].z)
            let chestDist = simd_distance(chestLeft, chestRight)
            measurements.chestWidth = chestDist * 100 * scaleFactor
        }
        
        if points3D.count >= 8 {
            // 총 길이
            let topPoint = points3D[0]
            let bottomPoint = points3D[7]
            let length = abs(topPoint.y - bottomPoint.y)
            measurements.totalLength = length * 100 * scaleFactor
            
            // 허리 너비
            let waistDist = simd_distance(points3D[4], points3D[5])
            measurements.waistWidth = waistDist * 100 * scaleFactor
        }
        
        // UI 업데이트
        DispatchQueue.main.async { [weak self] in
            self?.displayMeasurements(measurements)
        }
    }
    
    func displayMeasurements(_ measurements: GarmentMeasurements) {
        print(measurements.description)
        
        // 측정값을 AR 공간에 시각화
        visualizeMeasurements(measurements)
    }
    
    func visualizeMeasurements(_ measurements: GarmentMeasurements) {
        // 3D 텍스트로 측정값 표시
        // RealityKit을 사용하여 공간에 라벨 배치
    }
}
```

**단계 5: 오차 최소화 및 결과 검증**

```swift
extension ClothingMeasurementApp {
    
    func refineMeasurementsWithBundleAdjustment(
        measurements: [GarmentMeasurements],
        frames: [ARFrame]
    ) -> GarmentMeasurements {
        
        // 다중 프레임에서 측정값의 중간값 계산
        let shoulderWidths = measurements.compactMap { $0.shoulderWidth }
        let chestWidths = measurements.compactMap { $0.chestWidth }
        let sleeveLengths = measurements.compactMap { $0.sleeveLength }
        let totalLengths = measurements.compactMap { $0.totalLength }
        
        var refined = GarmentMeasurements()
        
        if !shoulderWidths.isEmpty {
            refined.shoulderWidth = median(shoulderWidths)
        }
        if !chestWidths.isEmpty {
            refined.chestWidth = median(chestWidths)
        }
        if !sleeveLengths.isEmpty {
            refined.sleeveLength = median(sleeveLengths)
        }
        if !totalLengths.isEmpty {
            refined.totalLength = median(totalLengths)
        }
        
        return refined
    }
    
    func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count/2 - 1] + sorted[count/2]) / 2
        } else {
            return sorted[count/2]
        }
    }
    
    func calculateConfidenceInterval(_ values: [Float], confidence: Float = 0.95) -> (mean: Float, lower: Float, upper: Float) {
        let mean = values.reduce(0, +) / Float(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Float(values.count)
        let stdDev = sqrt(variance)
        
        // 95% 신뢰 구간 (±1.96σ)
        let z = 1.96
        let marginOfError = z * (stdDev / sqrt(Float(values.count)))
        
        return (mean, mean - marginOfError, mean + marginOfError)
    }
    
    func validateMeasurements(_ measurements: GarmentMeasurements) -> Bool {
        // 합리성 검사
        if let sw = measurements.shoulderWidth, (sw < 20 || sw > 100) {
            return false  // 20-100cm 범위 벗어남
        }
        if let tl = measurements.totalLength, (tl < 40 || tl > 150) {
            return false  // 40-150cm 범위 벗어남
        }
        
        // 비율 검사 (어깨 너비 vs 총 길이)
        if let sw = measurements.shoulderWidth,
           let tl = measurements.totalLength {
            let ratio = sw / tl
            if ratio < 0.2 || ratio > 0.8 {
                return false  // 비정상적 비율
            }
        }
        
        return true
    }
}
```

## 필수 하드웨어 및 SDK 요구사항

**하드웨어 요구사항:**

| 기능 | 최소 요구사항 | 권장 사양 |
|-----|------------|---------|
| **LiDAR 스캐닝** | iPhone 12 Pro, iPad Pro 2020 (4세대) | iPhone 15 Pro |
| **ARKit 기본** | iPhone 6s 이상, A9 칩 | A12 Bionic 이상 |
| **Neural Engine** | A11 Bionic (iPhone 8 이후) | A15 Bionic 이상 |
| **바디 트래킹** | A12 Bionic (iPhone XS 이후) | A14 Bionic 이상 |

**LiDAR 지원 기기 전체 목록:**
- iPhone 12 Pro / 12 Pro Max (2020)
- iPhone 13 Pro / 13 Pro Max (2021)
- iPhone 14 Pro / 14 Pro Max (2022)
- iPhone 15 Pro / 15 Pro Max (2023)
- iPad Pro 11" (2세대 이상, 2020+)
- iPad Pro 12.9" (4세대 이상, 2020+)

**iOS SDK 버전 요구사항:**

| 기능 | 최소 iOS | 최적 iOS | Xcode |
|-----|---------|---------|-------|
| **Scene Reconstruction** | iOS 13.4 | iOS 17.0 | Xcode 11.4+ |
| **Depth API (sceneDepth)** | iOS 14.0 | iOS 17.0 | Xcode 12.0+ |
| **ML Programs** | iOS 15.0 | iOS 17.0 | Xcode 13.0+ |
| **Body Tracking** | iOS 13.0 | iOS 17.0 | Xcode 11.0+ |

**프레임워크 버전:**
- ARKit 3.5+ (iOS 13.4+) - LiDAR 지원
- ARKit 4 (iOS 14.0+) - Depth API
- ARKit 5 (iOS 15.0+) - Object Capture
- ARKit 6 (iOS 16.0+) - 4K 비디오, HDR
- CoreML 4+ (iOS 14.0+) - 개선된 모델 포맷
- Vision (iOS 11.0+, 최신 iOS 17.0)

**성능 벤치마크:**

| 기기 | Neural Engine | 프레임률 (YOLO) | 프레임률 (세그멘테이션) |
|-----|-------------|------------|---------------|
| iPhone 11 (A13) | 2 TOPS | 17-20 FPS | 8-10 FPS |
| iPhone 12 Pro (A14) | 11 TOPS | 25-30 FPS | 12-15 FPS |
| iPhone 13 Pro (A15) | 15 TOPS | 30+ FPS | 15-20 FPS |
| iPhone 14 Pro (A16) | 17 TOPS | 30+ FPS | 20-25 FPS |
| iPhone 15 Pro (A17) | 35 TOPS | 30+ FPS | 25-30 FPS |

## 고급 최적화 기법 및 고려사항

**메모리 관리 최적화:**

```swift
// autoreleasepool을 사용한 메모리 정리
func processBatchFrames(_ frames: [ARFrame]) {
    for frame in frames {
        autoreleasepool {
            processFrame(frame)
            // 프레임 처리 후 자동으로 메모리 해제
        }
    }
}

// CVPixelBuffer 수동 잠금 해제
func safeProcessPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    }
    
    // 픽셀 버퍼 처리
}
```

**모델 캐싱 및 사전 로딩:**

```swift
class ModelManager {
    static let shared = ModelManager()
    
    private var cachedModels: [String: VNCoreMLModel] = [:]
    
    func preloadModels() {
        DispatchQueue.global(qos: .background).async {
            // 앱 시작 시 백그라운드에서 모델 로드
            do {
                let yolo = try VNCoreMLModel(for: YOLOv8().model)
                let hrnet = try VNCoreMLModel(for: HRNetKeypoints().model)
                
                self.cachedModels["yolo"] = yolo
                self.cachedModels["hrnet"] = hrnet
            } catch {
                print("모델 사전 로딩 실패: \(error)")
            }
        }
    }
    
    func getModel(_ name: String) -> VNCoreMLModel? {
        return cachedModels[name]
    }
}
```

**적응형 프레임 처리:**

```swift
class AdaptiveFrameProcessor {
    private var processingTime: TimeInterval = 0
    private var skipFrameCount: Int = 1
    private var frameCounter: Int = 0
    
    func shouldProcessFrame() -> Bool {
        frameCounter += 1
        
        // 처리 시간에 따라 적응적으로 프레임 스킵
        if processingTime > 0.1 {  // 100ms 이상
            skipFrameCount = 3  // 3프레임마다 1번 처리
        } else if processingTime > 0.05 {  // 50-100ms
            skipFrameCount = 2  // 2프레임마다 1번 처리
        } else {
            skipFrameCount = 1  // 모든 프레임 처리
        }
        
        return frameCounter % skipFrameCount == 0
    }
    
    func updateProcessingTime(_ time: TimeInterval) {
        // 지수 이동 평균
        processingTime = 0.7 * processingTime + 0.3 * time
    }
}
```

## 결론: 정밀한 의류 측정을 위한 통합 시스템

**Smartsizer 앱의 구현은 하드웨어, 소프트웨어, 알고리즘의 정교한 조화를 요구합니다.** LiDAR 센서는 Direct Time-of-Flight 방식으로 0.2-5미터 범위의 깊이를 측정하며, ARKit의 `sceneDepth` API를 통해 256×192 해상도의 깊이 맵을 60 FPS로 제공합니다. 이 데이터는 YOLOv5/v8(17-30 FPS), HRNet(키포인트 감지 94.8% PCK), DeepLabV3+ 또는 U-Net(세그멘테이션)과 같은 AI 모델로 처리됩니다.

**실제 측정 정확도는 1.59-2.08%의 상대 오차를 달성하며, 이는 수동 측정(3.25%)보다 우수합니다.** 이를 위해 번들 조정, Levenberg-Marquardt 최적화, RANSAC 아웃라이어 제거와 같은 오차 최소화 기법이 필수적입니다. Size Assist 마커는 픽셀-미터 변환을 위한 스케일 팩터를 제공하며, ARKit의 ARReferenceImage를 통해 자동으로 감지되고 추적됩니다.

**CoreML과 Vision Framework의 통합은 실시간 온디바이스 추론을 가능하게 합니다.** INT8 양자화는 모델 크기를 75% 줄이고 추론 속도를 2-3배 향상시키며, Neural Engine(11-35 TOPS)은 이러한 양자화 모델에 최적화되어 있습니다. 메모리 관리, 모델 캐싱, 적응형 프레임 처리는 실시간 성능을 유지하는 데 중요합니다.

**핵심 구현 체크리스트:**
- ARWorldTrackingConfiguration에서 `frameSemantics = .sceneDepth` 활성화
- 신뢰도 맵을 사용하여 `ARConfidenceLevel.high` 포인트만 필터링
- 카메라 intrinsics를 사용한 2D↔3D 좌표 변환 구현
- coremltools로 PyTorch/TensorFlow 모델을 CoreML로 변환
- VNCoreMLRequest와 VNImageRequestHandler로 Vision 파이프라인 구성
- 유클리드 거리 공식 `d = √[(x₂-x₁)² + (y₂-y₁)² + (z₂-z₁)²]`로 3D 측정
- ARReferenceImage로 참조 마커 감지 및 스케일 보정
- 다중 프레임 평균화 및 신뢰 구간 계산으로 정확도 향상

**이 시스템은 iOS 14.0+, LiDAR 지원 기기(iPhone 12 Pro 이상), Xcode 12.0+ 환경에서 구현 가능하며, 실제 프로덕션 배포를 위해서는 엄격한 테스트와 최적화가 필요합니다.** 최신 A17 Pro 칩과 iOS 17의 향상된 ARKit 6 기능을 활용하면 더 높은 정확도와 성능을 기대할 수 있습니다.
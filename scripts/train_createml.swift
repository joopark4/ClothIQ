#!/usr/bin/swift
//
// train_createml.swift
// ClothIQ CreateML 모델 학습 스크립트
//
// 사용법:
//   swift train_createml.swift [데이터_경로] [출력_경로]
//
// 요구사항:
//   - macOS 12.0 이상
//   - Xcode 13.0 이상
//   - CreateML 프레임워크
//

import Foundation
import CreateML
import CoreML
import Vision

// MARK: - 학습 데이터 구조체

struct TrainingData: Codable {
    let annotations: [Annotation]
}

struct Annotation: Codable {
    let image: String
    let keypoints: [Keypoint]
}

struct Keypoint: Codable {
    let label: String
    let coordinates: Coordinates
    let visibility: Float
}

struct Coordinates: Codable {
    let x: Float
    let y: Float
}

// MARK: - 모델 학습 클래스

class ClothingKeypointTrainer {

    let dataPath: URL
    let outputPath: URL
    let projectName = "ClothingKeypointDetector"

    init(dataPath: String, outputPath: String) {
        self.dataPath = URL(fileURLWithPath: dataPath)
        self.outputPath = URL(fileURLWithPath: outputPath)
    }

    /// 학습 데이터 준비
    func prepareData() throws -> MLDataTable {
        print("📂 학습 데이터 준비 중...")

        let jsonURL = dataPath.appendingPathComponent("createml_data.json")
        let imagesURL = dataPath.appendingPathComponent("images")

        // JSON 로드
        let jsonData = try Data(contentsOf: jsonURL)
        let annotations = try JSONDecoder().decode([Annotation].self, from: jsonData)

        print("✅ \(annotations.count)개의 샘플 로드됨")

        // MLDataTable 생성
        var imageURLs: [URL] = []
        var annotationsData: [[String: Any]] = []

        for annotation in annotations {
            let imageURL = imagesURL.appendingPathComponent(annotation.image)
            imageURLs.append(imageURL)

            // 키포인트를 CreateML 형식으로 변환
            let points = annotation.keypoints.map { keypoint -> [String: Any] in
                return [
                    "label": keypoint.label,
                    "x": keypoint.coordinates.x,
                    "y": keypoint.coordinates.y,
                    "confidence": keypoint.visibility
                ]
            }

            annotationsData.append([
                "imageURL": imageURL.path,
                "keypoints": points
            ])
        }

        // 데이터 테이블 생성
        let dataTable = try MLDataTable(dictionary: [
            "image": imageURLs.map { $0.path },
            "annotations": annotationsData
        ])

        return dataTable
    }

    /// 모델 학습
    func trainModel() throws {
        print("\n🎯 모델 학습 시작...")

        // 데이터 준비
        let dataTable = try prepareData()

        // 학습/검증 데이터 분할 (80/20)
        let (trainingData, validationData) = dataTable.randomSplit(by: 0.8, seed: 42)

        print("  - 학습 데이터: \(trainingData.rows.count)개")
        print("  - 검증 데이터: \(validationData.rows.count)개")

        // 학습 파라미터 설정
        let parameters = MLObjectDetector.ModelParameters(
            algorithm: .yolov2,
            validation: .dataSource(validationData),
            maxIterations: 10000,
            gridSize: 13,
            featureExtractor: .scenePrint(revision: 2)
        )

        // 진행 상황 핸들러
        let progressHandler = { (progress: MLProgress) in
            switch progress {
            case .progress(let fractionComplete):
                let percentage = Int(fractionComplete * 100)
                print("📊 진행률: \(percentage)%", terminator: "\r")
                fflush(stdout)
            case .completed:
                print("\n✅ 학습 완료!")
            case .cancelled:
                print("\n⚠️ 학습 취소됨")
            @unknown default:
                break
            }
        }

        // 모델 학습
        let model = try MLObjectDetector(
            trainingData: trainingData,
            parameters: parameters,
            sessionParameters: MLTrainingSessionParameters(
                sessionDirectory: outputPath.appendingPathComponent("sessions"),
                reportInterval: 100,
                checkpointInterval: 1000,
                iterations: 10000
            )
        )

        // 모델 평가
        evaluateModel(model, on: validationData)

        // 모델 저장
        try saveModel(model)
    }

    /// 모델 평가
    func evaluateModel(_ model: MLObjectDetector, on testData: MLDataTable) {
        print("\n📈 모델 평가 중...")

        // 평가 메트릭 계산
        let evaluation = model.evaluation(on: testData)

        print("  - 정확도: \(String(format: "%.2f", evaluation.classificationError * 100))%")

        // 클래스별 성능 출력
        if let classMetrics = evaluation.precisionRecall(forClass: "keypoint") {
            print("  - Keypoint 감지 성능:")
            print("    • Precision: \(String(format: "%.2f", classMetrics.precision * 100))%")
            print("    • Recall: \(String(format: "%.2f", classMetrics.recall * 100))%")
        }
    }

    /// 모델 저장
    func saveModel(_ model: MLObjectDetector) throws {
        print("\n📦 모델 저장 중...")

        let modelURL = outputPath.appendingPathComponent("\(projectName).mlmodel")

        // Core ML 모델로 변환
        let coreMLModel = model.model

        // 메타데이터 추가
        coreMLModel.modelDescription.metadata[MLModelMetadataKey.author] = "ClothIQ"
        coreMLModel.modelDescription.metadata[MLModelMetadataKey.license] = "MIT"
        coreMLModel.modelDescription.metadata[MLModelMetadataKey.description] =
            "의류 키포인트 감지 모델 - CreateML로 학습됨"
        coreMLModel.modelDescription.metadata[MLModelMetadataKey.versionString] =
            DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)

        // 모델 저장
        try coreMLModel.write(to: modelURL)

        print("✅ 모델 저장 완료: \(modelURL.path)")

        // 모델 정보 저장
        saveModelInfo(to: outputPath)
    }

    /// 모델 정보 저장
    func saveModelInfo(to outputPath: URL) {
        let info: [String: Any] = [
            "created": ISO8601DateFormatter().string(from: Date()),
            "framework": "CreateML",
            "algorithm": "YOLOv2",
            "platform": "iOS 15.0+",
            "input_size": [416, 416],
            "classes": ["keypoint"],
            "training_tool": "train_createml.swift"
        ]

        let infoURL = outputPath.appendingPathComponent("model_info.plist")

        do {
            let plistData = try PropertyListSerialization.data(
                fromPropertyList: info,
                format: .xml,
                options: 0
            )
            try plistData.write(to: infoURL)
            print("\n📊 모델 정보 저장됨: \(infoURL.path)")
        } catch {
            print("⚠️ 모델 정보 저장 실패: \(error)")
        }
    }
}

// MARK: - 메인 함수

func main() {
    print("🚀 ClothIQ CreateML 모델 학습 시작")
    print("=" * 50)

    // 커맨드라인 인자 처리
    let arguments = CommandLine.arguments

    let dataPath: String
    let outputPath: String

    if arguments.count >= 3 {
        dataPath = arguments[1]
        outputPath = arguments[2]
    } else {
        // 기본 경로 사용
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!.path

        dataPath = "\(documentsPath)/MLTrainingData"
        outputPath = "\(documentsPath)/Models"

        print("ℹ️ 기본 경로 사용:")
        print("  - 데이터: \(dataPath)")
        print("  - 출력: \(outputPath)")
    }

    // 출력 디렉토리 생성
    try? FileManager.default.createDirectory(
        at: URL(fileURLWithPath: outputPath),
        withIntermediateDirectories: true,
        attributes: nil
    )

    // 트레이너 생성 및 실행
    let trainer = ClothingKeypointTrainer(
        dataPath: dataPath,
        outputPath: outputPath
    )

    do {
        try trainer.trainModel()
        print("\n🎉 모든 작업이 성공적으로 완료되었습니다!")
    } catch {
        print("\n❌ 오류 발생: \(error)")
        print("\n상세 정보:")
        print(error.localizedDescription)
        exit(1)
    }
}

// 실행
main()
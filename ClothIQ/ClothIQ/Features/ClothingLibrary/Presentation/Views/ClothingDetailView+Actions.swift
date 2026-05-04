//
//  ClothingDetailView+Actions.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  ClothingDetailView의 액션 메서드들입니다.
//  삭제, 공유, 진단 기능을 포함합니다.
//

import SwiftUI
import SwiftData
import UIKit

struct SharePayload: Identifiable {
    let id = UUID()
    let text: String
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension ClothingDetailView {

    // MARK: - Actions

    func repairBottomMeasurementAnchorsIfNeeded() async {
        guard !hasAttemptedBottomAnchorRepair else { return }
        hasAttemptedBottomAnchorRepair = true

        let removedDuplicates = item.deduplicateMeasurements(modelContext: modelContext)
        let repairedTypes = await BottomMeasurementAnchorRepairService.repairIfNeeded(item: item)
        guard removedDuplicates > 0 || !repairedTypes.isEmpty else { return }

        item.updatedAt = Date()

        do {
            try modelContext.save()
            let repairedNames = repairedTypes.map(\.displayName).joined(separator: ", ")
            if repairedTypes.isEmpty {
                print("✅ [BottomAnchorRepair] 중복 측정값 \(removedDuplicates)개 정리 완료")
            } else {
                print("✅ [BottomAnchorRepair] 저장된 하의 앵커 보정 완료: \(repairedNames), 중복 정리: \(removedDuplicates)개")
            }
        } catch {
            print("❌ [BottomAnchorRepair] 저장 실패: \(error)")
        }
    }

    func deleteItem() {
        // 이미지 파일 삭제
        if let imagePath = item.imagePath {
            _ = try? ImageFileManager.shared.deleteImage(at: imagePath)
        }

        // SwiftData에서 삭제
        modelContext.delete(item)

        // 화면 닫기
        dismiss()
    }

    func shareItem() {
        var shareText = """
        의류 정보
        타입: \(item.clothingType?.displayName ?? "알 수 없음")
        측정값: \(item.completedMeasurements)/\(item.totalRequiredMeasurements) 완료
        """

        if !item.displayMeasurements.isEmpty {
            shareText += "\n\n측정값:\n"
            for measurement in item.displayMeasurements {
                if let type = MeasurementType(rawValue: measurement.type) {
                    shareText += "\(type.displayName): \(measurement.formattedCalibratedValue())\n"
                }
            }
        }

        sharePayload = SharePayload(text: shareText)
    }

    /// 진단 도구: 이미지 및 측정 데이터 분석
    func printDiagnostics() {
        print("\n" + String(repeating: "=", count: 80))
        print("ClothIQ 진단 도구 - 이미지 및 측정 데이터 분석")
        print(String(repeating: "=", count: 80))

        // 1. 이미지 정보
        if let image = item.loadImage() {
            let imageSize = image.size
            let aspectRatio = imageSize.height / imageSize.width

            print("\n이미지 정보:")
            print("  - 이미지 크기: \(imageSize.width) x \(imageSize.height)")
            print("  - 종횡비: \(String(format: "%.3f", aspectRatio)) (높이/너비)")
            print("  - 이미지 경로: \(item.imagePath ?? "없음")")

            if let originalSize = item.originalImageSize {
                print("  - 원본 크기: \(originalSize.width) x \(originalSize.height)")
            }
            if let processedSize = item.processedImageSize {
                print("  - 처리된 크기: \(processedSize.width) x \(processedSize.height)")
            }

            // 2. 의류 분류 재실행
            let classifier = VisionClothingClassifier()
            let result = classifier.classify(image: image)

            print("\n의류 분류:")
            print("  - 현재 분류: \(item.clothingType?.displayName ?? "없음") (\(item.type))")
            print("  - 재분류 결과: \(result.type.displayName) (\(result.type.rawValue))")
            print("  - 분류 신뢰도: \(String(format: "%.1f%%", result.confidence * 100))")
            print("  - 분류 방법: \(result.method)")

            if result.type.rawValue != item.type {
                print("  불일치! 현재 '\(item.type)'로 저장되어 있지만, 재분류 시 '\(result.type.rawValue)'로 분류됨")
            }
        } else {
            print("\n이미지를 로드할 수 없습니다")
        }

        // 3. 측정값 정보
        print("\n측정값 (\(item.measurements.count)개):")
        if item.measurements.isEmpty {
            print("  - 측정값 없음")
        } else {
            for (index, measurement) in item.measurements.enumerated() {
                let measurementType = MeasurementType(rawValue: measurement.type)
                print("\n  [\(index + 1)] \(measurementType?.displayName ?? measurement.type)")
                print("     - 값: \(String(format: "%.2f", measurement.value)) \(measurement.unit)")
                print("     - 신뢰도: \(String(format: "%.1f%%", measurement.confidence * 100))")
                print("     - 측정 시간: \(measurement.measuredAt)")

                if let startX = measurement.startPointX,
                   let startY = measurement.startPointY,
                   let endX = measurement.endPointX,
                   let endY = measurement.endPointY {
                    print("     - 시작점: (\(String(format: "%.4f", startX)), \(String(format: "%.4f", startY)))")
                    print("     - 끝점: (\(String(format: "%.4f", endX)), \(String(format: "%.4f", endY)))")
                } else {
                    print("     좌표 정보 없음")
                }
            }
        }

        // 4. 요약
        let progress = item.totalRequiredMeasurements > 0
            ? Double(item.completedMeasurements) / Double(item.totalRequiredMeasurements)
            : 0.0
        print("\n요약:")
        print("  - 총 측정 항목: \(item.totalRequiredMeasurements)개")
        print("  - 완료된 측정: \(item.completedMeasurements)개")
        print("  - 진행률: \(String(format: "%.1f%%", progress * 100))")

        print(String(repeating: "=", count: 80) + "\n")
    }
}

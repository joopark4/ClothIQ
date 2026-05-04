//
//  ClothingKeypointDetector+MeasurementLines.swift
//  ClothIQ
//
//  Created on 2025-11-10
//
//  Description:
//  키포인트로부터 측정 라인을 생성하는 메서드 모음.
//  의류 타입별 측정 항목(어깨너비, 가슴둘레, 소매길이 등)의 시작/끝 좌표를 매핑합니다.
//

import Foundation
import CoreGraphics

// MARK: - Measurement Line Generation

extension ClothingKeypointDetector {

    /// 키포인트로부터 측정 라인 생성
    ///
    /// - Parameters:
    ///   - keypoints: 감지된 키포인트들
    ///   - clothingType: 의류 타입
    /// - Returns: 측정 타입과 시작/끝 포인트 매핑
    func generateMeasurementLines(
        from keypoints: [MeasurementKeypoint],
        clothingType: ClothingType
    ) -> [(type: MeasurementType, start: CGPoint, end: CGPoint)] {

        var lines: [(type: MeasurementType, start: CGPoint, end: CGPoint)] = []

        switch clothingType {
        // 기본 상의
        case .shortSleeve, .longSleeve, .shirt, .polo, .hoodie:
            // 어깨너비
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder }) {
                lines.append((.shoulderWidth, leftShoulder.position, rightShoulder.position))
            }

            // 가슴둘레
            if let leftChest = keypoints.first(where: { $0.type == .chestLeft }),
               let rightChest = keypoints.first(where: { $0.type == .chestRight }) {
                lines.append((.chestCircumference, leftChest.position, rightChest.position))
            }

            // 소매길이
            if clothingType.requiredMeasurements.contains(.sleeveLength) {
                if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
                   let leftSleeve = keypoints.first(where: { $0.type == .leftSleeveEnd }) {
                    lines.append((.sleeveLength, leftShoulder.position, leftSleeve.position))
                }
            }

            // 팔둘레
            if clothingType.requiredMeasurements.contains(.armCircumference),
               let armLine = sleeveCrossSectionLine(from: keypoints, location: .midArm) {
                lines.append((.armCircumference, armLine.start, armLine.end))
            }

            // 총길이
            if let neckline = keypoints.first(where: { $0.type == .neckline }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, neckline.position, hem.position))
            }

            // 목둘레 (셔츠의 경우)
            if clothingType == .shirt {
                if let neckLine = neckCircumferenceLine(from: keypoints) {
                    lines.append((.neckCircumference, neckLine.start, neckLine.end))
                }
            }

        // 아우터
        case .jacket, .coat, .cardigan:
            // 어깨너비
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder }) {
                lines.append((.shoulderWidth, leftShoulder.position, rightShoulder.position))
            }

            // 가슴둘레
            if let leftChest = keypoints.first(where: { $0.type == .chestLeft }),
               let rightChest = keypoints.first(where: { $0.type == .chestRight }) {
                lines.append((.chestCircumference, leftChest.position, rightChest.position))
            }

            // 소매길이
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let leftSleeve = keypoints.first(where: { $0.type == .leftSleeveEnd }) {
                lines.append((.sleeveLength, leftShoulder.position, leftSleeve.position))
            }

            // 총길이
            if let neckline = keypoints.first(where: { $0.type == .neckline }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, neckline.position, hem.position))
            }

            // 소매단둘레 (재킷의 경우)
            if clothingType == .jacket {
                if let cuffLine = sleeveCrossSectionLine(from: keypoints, location: .cuff) {
                    lines.append((.cuffCircumference, cuffLine.start, cuffLine.end))
                }
            }

        // 조끼
        case .vest:
            // 어깨너비
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder }) {
                lines.append((.shoulderWidth, leftShoulder.position, rightShoulder.position))
            }

            // 가슴둘레
            if let leftChest = keypoints.first(where: { $0.type == .chestLeft }),
               let rightChest = keypoints.first(where: { $0.type == .chestRight }) {
                lines.append((.chestCircumference, leftChest.position, rightChest.position))
            }

            // 총길이
            if let neckline = keypoints.first(where: { $0.type == .neckline }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, neckline.position, hem.position))
            }

        // 원피스
        case .dress:
            // 어깨너비
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder }) {
                lines.append((.shoulderWidth, leftShoulder.position, rightShoulder.position))
            }

            // 가슴둘레
            if let leftChest = keypoints.first(where: { $0.type == .chestLeft }),
               let rightChest = keypoints.first(where: { $0.type == .chestRight }) {
                lines.append((.chestCircumference, leftChest.position, rightChest.position))
            }

            // 허리둘레
            if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
               let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                lines.append((.waistCircumference, leftWaist.position, rightWaist.position))
            }

            // 엉덩이둘레
            if let leftHip = keypoints.first(where: { $0.type == .hipLeft }),
               let rightHip = keypoints.first(where: { $0.type == .hipRight }) {
                lines.append((.hipCircumference, leftHip.position, rightHip.position))
            }

            // 총길이
            if let neckline = keypoints.first(where: { $0.type == .neckline }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, neckline.position, hem.position))
            }

        // 점프수트
        case .jumpsuit:
            // 어깨너비
            if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder }),
               let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder }) {
                lines.append((.shoulderWidth, leftShoulder.position, rightShoulder.position))
            }

            // 가슴둘레
            if let leftChest = keypoints.first(where: { $0.type == .chestLeft }),
               let rightChest = keypoints.first(where: { $0.type == .chestRight }) {
                lines.append((.chestCircumference, leftChest.position, rightChest.position))
            }

            // 허리둘레
            if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
               let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                lines.append((.waistCircumference, leftWaist.position, rightWaist.position))
            }

            // 엉덩이둘레
            if let leftHip = keypoints.first(where: { $0.type == .hipLeft }),
               let rightHip = keypoints.first(where: { $0.type == .hipRight }) {
                lines.append((.hipCircumference, leftHip.position, rightHip.position))
            }

            // 밑위
            if let crotch = keypoints.first(where: { $0.type == .crotch }) {
                if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
                   let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                    let riseStart = CGPoint(
                        x: crotch.position.x,
                        y: (leftWaist.position.y + rightWaist.position.y) * 0.5
                    )
                    lines.append((.rise, riseStart, crotch.position))
                } else if let waist = keypoints.first(where: { $0.type == .waistLeft }) {
                    lines.append((.rise, waist.position, crotch.position))
                }
            }

            // 총길이
            if let neckline = keypoints.first(where: { $0.type == .neckline }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, neckline.position, hem.position))
            }

        // 하의
        case .shorts, .pants, .jeans:
            // 허리둘레
            if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
               let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                lines.append((.waistCircumference, leftWaist.position, rightWaist.position))
            }

            // 총길이: 허리에서 같은 쪽 밑단까지의 대표 side line
            if let lengthLine = bottomLengthLine(from: keypoints) {
                lines.append((.totalLength, lengthLine.start, lengthLine.end))
            }

            // 엉덩이둘레 (청바지는 필수가 아님)
            if clothingType != .jeans {
                if let leftHip = keypoints.first(where: { $0.type == .hipLeft }),
                   let rightHip = keypoints.first(where: { $0.type == .hipRight }) {
                    lines.append((.hipCircumference, leftHip.position, rightHip.position))
                }
            }

            // 밑위
            if let crotch = keypoints.first(where: { $0.type == .crotch }) {
                if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
                   let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                    let riseStart = CGPoint(
                        x: crotch.position.x,
                        y: (leftWaist.position.y + rightWaist.position.y) * 0.5
                    )
                    lines.append((.rise, riseStart, crotch.position))
                } else if let waist = keypoints.first(where: { $0.type == .waistLeft }) {
                    lines.append((.rise, waist.position, crotch.position))
                }
            }

            // 밑단
            if let leftHem = keypoints.first(where: { $0.type == .leftHem }),
               let rightHem = keypoints.first(where: { $0.type == .rightHem }) {
                lines.append((.hem, leftHem.position, rightHem.position))
            }

            // 허벅지둘레 (긴바지, 청바지의 경우)
            if clothingType == .pants || clothingType == .jeans {
                if let thighLine = bottomThighLine(from: keypoints) {
                    lines.append((.thighCircumference, thighLine.start, thighLine.end))
                }
            }

        // 레깅스
        case .leggings:
            // 허리둘레
            if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
               let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                lines.append((.waistCircumference, leftWaist.position, rightWaist.position))
            }

            // 엉덩이둘레
            if let leftHip = keypoints.first(where: { $0.type == .hipLeft }),
               let rightHip = keypoints.first(where: { $0.type == .hipRight }) {
                lines.append((.hipCircumference, leftHip.position, rightHip.position))
            }

            // 총길이
            if let waist = keypoints.first(where: { $0.type == .waistLeft }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, waist.position, hem.position))
            }

        case .skirt:
            // 허리둘레
            if let leftWaist = keypoints.first(where: { $0.type == .waistLeft }),
               let rightWaist = keypoints.first(where: { $0.type == .waistRight }) {
                lines.append((.waistCircumference, leftWaist.position, rightWaist.position))
            }

            // 엉덩이둘레 (스커트는 선택)
            if let leftHip = keypoints.first(where: { $0.type == .hipLeft }),
               let rightHip = keypoints.first(where: { $0.type == .hipRight }) {
                lines.append((.hipCircumference, leftHip.position, rightHip.position))
            }

            // 총길이
            if let waist = keypoints.first(where: { $0.type == .waistLeft }),
               let hem = keypoints.first(where: { $0.type == .hemCenter }) {
                lines.append((.totalLength, waist.position, hem.position))
            }
        }

        return lines
    }

    private func bottomLengthLine(
        from keypoints: [MeasurementKeypoint]
    ) -> (start: CGPoint, end: CGPoint)? {
        if let leftWaist = keypoints.first(where: { $0.type == .waistLeft })?.position,
           let rightWaist = keypoints.first(where: { $0.type == .waistRight })?.position,
           let leftHem = keypoints.first(where: { $0.type == .leftHem })?.position,
           let rightHem = keypoints.first(where: { $0.type == .rightHem })?.position {
            let waistCenterX = (leftWaist.x + rightWaist.x) * 0.5
            let hemCenterX = (leftHem.x + rightHem.x) * 0.5
            let hemIsRightLeg = hemCenterX >= waistCenterX
            let start = hemIsRightLeg ? rightWaist : leftWaist
            let end = hemIsRightLeg
                ? (leftHem.x >= rightHem.x ? leftHem : rightHem)
                : (leftHem.x <= rightHem.x ? leftHem : rightHem)

            if abs(start.y - end.y) > 0.12 {
                return (start, end)
            }
        }

        guard let hemCenter = keypoints.first(where: { $0.type == .hemCenter })?.position else {
            return nil
        }

        if let leftWaist = keypoints.first(where: { $0.type == .waistLeft })?.position,
           let rightWaist = keypoints.first(where: { $0.type == .waistRight })?.position {
            let waistCenter = CGPoint(
                x: (leftWaist.x + rightWaist.x) * 0.5,
                y: (leftWaist.y + rightWaist.y) * 0.5
            )
            return (waistCenter, hemCenter)
        }

        return nil
    }

    private enum SleeveCrossSectionLocation {
        case midArm
        case cuff
    }

    private func neckCircumferenceLine(
        from keypoints: [MeasurementKeypoint]
    ) -> (start: CGPoint, end: CGPoint)? {
        guard let neckline = keypoints.first(where: { $0.type == .neckline })?.position else {
            return nil
        }

        let referenceWidth: CGFloat
        if let leftShoulder = keypoints.first(where: { $0.type == .leftShoulder })?.position,
           let rightShoulder = keypoints.first(where: { $0.type == .rightShoulder })?.position {
            referenceWidth = abs(rightShoulder.x - leftShoulder.x)
        } else if let leftChest = keypoints.first(where: { $0.type == .chestLeft })?.position,
                  let rightChest = keypoints.first(where: { $0.type == .chestRight })?.position {
            referenceWidth = abs(rightChest.x - leftChest.x)
        } else {
            referenceWidth = 0.30
        }

        let halfWidth = max(0.025, min(referenceWidth * 0.14, 0.07))
        return nonZeroLine(
            start: clampedPoint(CGPoint(x: neckline.x - halfWidth, y: neckline.y)),
            end: clampedPoint(CGPoint(x: neckline.x + halfWidth, y: neckline.y))
        )
    }

    private func sleeveCrossSectionLine(
        from keypoints: [MeasurementKeypoint],
        location: SleeveCrossSectionLocation
    ) -> (start: CGPoint, end: CGPoint)? {
        guard let sleevePair = sleeveMeasurementPair(from: keypoints) else {
            return nil
        }

        let shoulder = sleevePair.shoulder
        let sleeveEnd = sleevePair.sleeveEnd
        let dx = sleeveEnd.x - shoulder.x
        let dy = sleeveEnd.y - shoulder.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        let normal = CGPoint(x: -dy / length, y: dx / length)

        let center: CGPoint
        let widthScale: CGFloat
        switch location {
        case .midArm:
            center = CGPoint(
                x: shoulder.x + dx * 0.58,
                y: shoulder.y + dy * 0.58
            )
            widthScale = 0.24
        case .cuff:
            center = sleeveEnd
            widthScale = 0.18
        }

        let halfWidth = max(0.018, min(length * widthScale, 0.08)) * 0.5
        return nonZeroLine(
            start: clampedPoint(CGPoint(
                x: center.x - normal.x * halfWidth,
                y: center.y - normal.y * halfWidth
            )),
            end: clampedPoint(CGPoint(
                x: center.x + normal.x * halfWidth,
                y: center.y + normal.y * halfWidth
            ))
        )
    }

    private func sleeveMeasurementPair(
        from keypoints: [MeasurementKeypoint]
    ) -> (shoulder: CGPoint, sleeveEnd: CGPoint)? {
        let pairs: [(shoulder: CGPoint, sleeveEnd: CGPoint)?] = [
            pair(
                shoulderType: .leftShoulder,
                sleeveType: .leftSleeveEnd,
                keypoints: keypoints
            ),
            pair(
                shoulderType: .rightShoulder,
                sleeveType: .rightSleeveEnd,
                keypoints: keypoints
            )
        ]

        return pairs
            .compactMap { $0 }
            .max {
                distance(from: $0.shoulder, to: $0.sleeveEnd) <
                    distance(from: $1.shoulder, to: $1.sleeveEnd)
            }
    }

    private func pair(
        shoulderType: KeypointType,
        sleeveType: KeypointType,
        keypoints: [MeasurementKeypoint]
    ) -> (shoulder: CGPoint, sleeveEnd: CGPoint)? {
        guard let shoulder = keypoints.first(where: { $0.type == shoulderType })?.position,
              let sleeveEnd = keypoints.first(where: { $0.type == sleeveType })?.position else {
            return nil
        }
        return (shoulder, sleeveEnd)
    }

    private func bottomThighLine(
        from keypoints: [MeasurementKeypoint]
    ) -> (start: CGPoint, end: CGPoint)? {
        if let crotch = keypoints.first(where: { $0.type == .crotch })?.position,
           let leftHem = keypoints.first(where: { $0.type == .leftHem })?.position,
           let rightHem = keypoints.first(where: { $0.type == .rightHem })?.position {
            let hemCenter = CGPoint(
                x: (leftHem.x + rightHem.x) * 0.5,
                y: (leftHem.y + rightHem.y) * 0.5
            )
            let hemWidth = max(abs(rightHem.x - leftHem.x), 0.05)
            let centerY = crotch.y - abs(crotch.y - hemCenter.y) * 0.18
            let halfWidth = max(hemWidth * 0.70, 0.04)
            return nonZeroLine(
                start: clampedPoint(CGPoint(x: hemCenter.x - halfWidth, y: centerY)),
                end: clampedPoint(CGPoint(x: hemCenter.x + halfWidth, y: centerY))
            )
        }

        if let leftHip = keypoints.first(where: { $0.type == .hipLeft })?.position,
           let rightHip = keypoints.first(where: { $0.type == .hipRight })?.position {
            return nonZeroLine(start: leftHip, end: rightHip)
        }

        return nil
    }

    private func nonZeroLine(
        start: CGPoint,
        end: CGPoint
    ) -> (start: CGPoint, end: CGPoint)? {
        guard distance(from: start, to: end) > 0.005 else {
            return nil
        }
        return (start, end)
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0.0, min(1.0, point.x)),
            y: max(0.0, min(1.0, point.y))
        )
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        sqrt(pow(rhs.x - lhs.x, 2) + pow(rhs.y - lhs.y, 2))
    }
}

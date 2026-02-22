//
//  UIImage+Orientation.swift
//  ClothIQ
//
//  Created on 2025-10-30
//
//  Description:
//  UIImage의 orientation을 정규화하는 확장입니다.
//  배경 제거 시 마스크와 이미지의 좌표계를 일치시킵니다.
//
//  Key Responsibilities:
//  - 이미지 orientation을 .up으로 정규화
//  - CGImage 처리 전 좌표계 일치
//

import UIKit

extension UIImage {
    /// 이미지의 orientation을 .up으로 정규화합니다.
    ///
    /// CGImage 기반 작업(크롭, 마스크 등) 전에 호출하여
    /// 좌표계 불일치 문제를 방지합니다.
    ///
    /// - Returns: orientation이 .up으로 정규화된 이미지
    func normalizedOrientation() -> UIImage {
        // 이미 .up이면 그대로 반환
        if imageOrientation == .up {
            return self
        }

        // 그래픽 컨텍스트에 그려서 orientation 적용
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage ?? self
    }
}
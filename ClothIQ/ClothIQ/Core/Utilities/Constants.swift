//
//  Constants.swift
//  ClothIQ
//
//  Created on 2025-01-23
//
//  Description:
//  앱 전역에서 사용되는 상수 정의
//

import Foundation

/// 앱 전역 상수
enum Constants {

    // MARK: - UserDefaults Keys

    /// UserDefaults 키 모음
    enum UserDefaultsKeys {
        /// 측정 단위 (cm/inch)
        static let measurementUnit = "measurementUnit"
    }

    // MARK: - Measurement

    /// 측정 관련 상수
    enum Measurement {
        /// 최소 측정 거리 (미터)
        static let minimumDistance: Float = 0.2

        /// 최대 측정 거리 (미터)
        static let maximumDistance: Float = 2.0

        /// 최소 신뢰도 임계값
        static let minimumConfidence: Float = 0.7
    }

    // MARK: - File System

    /// 파일 시스템 관련 상수
    enum FileSystem {
        /// 이미지 저장 디렉토리 이름
        static let imagesDirectory = "ClothingImages"

        /// JPEG 품질 (0.0 ~ 1.0)
        static let defaultJPEGQuality: CGFloat = 0.9
    }
}

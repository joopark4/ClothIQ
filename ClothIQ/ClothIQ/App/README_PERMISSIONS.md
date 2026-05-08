# 권한 설정 가이드

최종 업데이트: 2026-05-08

ClothIQ 앱이 정상적으로 작동하려면 Xcode 프로젝트 설정에서 다음 권한 설명을 추가해야 합니다.

## Xcode 설정 방법

1. Xcode에서 프로젝트를 엽니다
2. 프로젝트 네비게이터에서 **ClothIQ** 프로젝트를 선택
3. **TARGETS** > **ClothIQ** 선택
4. **Info** 탭 선택
5. **Custom iOS Target Properties** 섹션에서 다음 항목들을 추가:

## 필수 권한 설명

### NSCameraUsageDescription
**Key**: Privacy - Camera Usage Description
**Value**: ClothIQ는 LiDAR 센서를 활용하여 의류의 정확한 사이즈를 측정하기 위해 카메라 접근이 필요합니다.

### NSPhotoLibraryUsageDescription (선택)
**Key**: Privacy - Photo Library Usage Description
**Value**: 측정한 의류 사진을 저장하기 위해 사진 라이브러리 접근이 필요합니다.

### NSPhotoLibraryAddUsageDescription (선택)
**Key**: Privacy - Photo Library Additions Usage Description
**Value**: 측정 결과 이미지를 사진 라이브러리에 저장하기 위해 접근 권한이 필요합니다.

## 필수 기기 기능

Info.plist에 다음 항목도 추가 권장:

### UIRequiredDeviceCapabilities
- arkit
- arm64

이는 App Store에서 ARKit/arm64 미지원 기기를 제외하는 데 도움이 됩니다. LiDAR 지원 여부는 런타임에서 추가로 확인해야 하며, LiDAR 미지원 기기에서는 핵심 AR 측정 기능이 제한됩니다.

## 현재 앱 동작과 권한 관계

- AR 측정과 촬영 저장에는 카메라 권한이 필요합니다.
- 측정 결과 이미지를 사진 앱에 저장하려면 사진 추가 권한이 필요합니다.
- 앱 내부 학습 데이터(`Documents/MLTrainingData`) 저장에는 별도 사용자 권한이 필요하지 않습니다.
- 촬영 원본, depth map, SwiftData 저장소, ML 라벨은 앱 컨테이너 내부에 저장됩니다.

## 프로그래밍 방식으로 추가하는 방법 (대안)

`Info.plist` 파일을 수동으로 생성하는 대신, Xcode의 프로젝트 설정 UI를 사용하는 것을 권장합니다.

최신 Xcode (15+)에서는 Info.plist가 자동으로 생성되며,
프로젝트 설정 UI를 통해 관리됩니다.

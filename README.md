# ClothIQ

LiDAR 기반 의류 실측 iOS 앱입니다. AR 카메라에서 2점 앵커 측정으로 의류 부위 길이를 측정하고, 촬영 이미지와 측정 메타데이터를 로컬에 저장/관리합니다.

- 저장소 루트: 현재 작업 디렉터리
- 앱 프로젝트: `ClothIQ/ClothIQ.xcodeproj`
- 스킴: `ClothIQ`

## 현재 구현 상태 (2026-02-22 기준)

- AR 실시간 측정 플로우
  - 의류 타입 선택
  - 측정 항목 선택
  - 2개 앵커 탭 측정
  - `적용`(저장) / `다시 찍기`(취소)
  - 다른 측정 항목 선택 시 재측정 및 덮어쓰기
- 카메라 오버레이
  - 진행 중 측정선 + 완료된 측정선 누적 표시
- 촬영 후 미리보기
  - 촬영 이미지 표시
  - 측정선/앵커/측정값 라벨 오버레이 표시
  - 저장/취소 확정
- 저장 후 상세 화면
  - 측정선/앵커 오버레이 표시
  - 측정값 목록 및 편집 흐름 연동
- 측정 보정/검증
  - AR/Photo 측정 방식 분리된 교정 계수 지원
  - 측정 방식 메타데이터(`ar`/`photo`) 저장
- 이미지 처리
  - 객체 중심 크롭
  - 배경 제거(Vision/Depth 기반)
  - Photos 저장 연동
- ML/자동화
  - 키포인트/자동측정 서비스
  - 학습 데이터 수집/통계/내보내기 UI
- 라이브 디버깅
  - 실시간 메트릭 패널
  - 런타임 임계값 슬라이더 조정

## 기술 스택

- SwiftUI
- ARKit + RealityKit
- Vision + Core ML
- SwiftData
- Combine

## 시스템 요구사항

- iOS Deployment Target: `26.0` (`ClothIQ/ClothIQ.xcodeproj/project.pbxproj`)
- 개발 대상: iPad 중심(특히 iPad Pro) 개발/테스트 기준
- LiDAR 센서 탑재 단말 필수 (iPad Pro 2020+ 권장)
- Xcode 15+
- macOS Sonoma+

## 프로젝트 규모

- Swift 파일 수: `99` (`find ClothIQ/ClothIQ -name "*.swift" | wc -l` 기준)
- 주요 모듈
  - `ClothIQ/Features/Measurement`
  - `ClothIQ/Features/ClothingLibrary`
  - `ClothIQ/Features/ImageProcessing`
  - `ClothIQ/Features/Settings`

## 빠른 실행

### Xcode

```bash
cd ClothIQ
open ClothIQ.xcodeproj
```

### CLI 디바이스 배포

```bash
cd scripts
./ios_device_tools.sh list-devices
./ios_device_tools.sh full-deploy
```


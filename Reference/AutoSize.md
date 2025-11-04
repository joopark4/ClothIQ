자동 측정 파이프라인

AR 세션이 매 프레임 업데이트될 때 MeasurementView가 현재 ARFrame을 저장하고 전경 마스크/깊이 정보를 주기적으로 갱신합니다 (ClothIQ/ClothIQ/Features/Measurement/Presentation/Views/MeasurementView.swift:53).
자동 측정이 호출되면 MeasurementViewModel_Refactored.performAutoMeasurement가 Vision 기반 전처리부터 결과 저장까지 전체 파이프라인을 실행합니다 (ClothIQ/ClothIQ/Features/Measurement/Presentation/ViewModels/MeasurementViewModel_Refactored.swift:939).
전경 분리와 마스크 정제

ForegroundSegmentationService.generateForegroundMask가 VNDetectContours/VNDetectRectangles 조합으로 의류 윤곽을 추출하고, 커버리지·깊이·평면 감지 기준으로 마스크 품질을 검증합니다 (ClothIQ/ClothIQ/Features/Measurement/Data/Services/ForegroundSegmentationService.swift:58, :553).
윤곽 감지가 실패하면 사각형 기반 대체 경로를 사용하고, Core Graphics로 직접 마스크 버퍼를 생성해 노이즈를 줄입니다 (ClothIQ/ClothIQ/Features/Measurement/Data/Services/ForegroundSegmentationService.swift:261, :369).
촬영 직후 후처리 파이프라인에서는 Morpho 연산(확장 후 침식)으로 마스크를 매끈하게 다듬어 측정 포인트 후보가 안정적으로 나오도록 합니다 (ClothIQ/ClothIQ/Features/ImageProcessing/Data/Services/ObjectCaptureService.swift:811, :1514).
윤곽선 특징 추출

AutoMeasurementService.detectClothingContour가 전경 마스크에서 최대 컨투어를 추출하고, extractFeaturePoints가 최상단/최하단/좌우 끝과 가슴·허리·엉덩이 높이를 계산합니다 (ClothIQ/ClothIQ/Features/Measurement/Data/Services/AutoMeasurementService.swift:32, :55).
계산된 ClothingFeaturePoints는 정규화 좌표계에서 중심선, 높이/너비, 특정 높이에서 좌우 끝점을 빠르게 조회할 수 있는 헬퍼를 제공합니다 (ClothIQ/ClothIQ/Features/Measurement/Domain/Entities/ClothingFeaturePoints.swift:29, :91).
의류 타입별 포인트 감지기

상의는 TopMeasurementDetector가 어깨/가슴/총길이/소매 포인트를 추출하며, 소매 끝은 상단 우측에서 아래로 40% 범위를 탐색해 찾습니다 (ClothIQ/ClothIQ/Features/Measurement/Domain/Entities/MeasurementPointDetector.swift:79, :251).
하의는 BottomMeasurementDetector가 허리·엉덩이 폭, 총길이, 중앙 수축부(밑위)를 감지하고, 중심 ±10% X 범위의 중간 Y 포인트를 밑위 지점으로 선택합니다 (ClothIQ/ClothIQ/Features/Measurement/Domain/Entities/MeasurementPointDetector.swift:274, :436).
치마 전용 감지기는 허리/엉덩이/총길이만 생성해 필요 없는 포인트를 생략합니다 (ClothIQ/ClothIQ/Features/Measurement/Domain/Entities/MeasurementPointDetector.swift:462).
2D 좌표 → 3D 치수 계산

후보 포인트는 AR 카메라 해상도에 맞게 픽셀 좌표로 변환된 뒤 ARMeasurementService.extractMeasurementPoint를 통해 LiDAR 깊이·카메라 intrinsics 기반 월드 좌표로 매핑됩니다 (ClothIQ/ClothIQ/Features/Measurement/Presentation/ViewModels/MeasurementViewModel_Refactored.swift:1069, ClothIQ/ClothIQ/Features/Measurement/Data/Services/ARMeasurementService.swift:53).
DepthDataProcessor는 정규화 좌표에서 깊이를 추출하고, 카메라 공간을 월드 좌표로 변환하면서 깊이 품질과 신뢰도 맵을 함께 계산합니다 (ClothIQ/ClothIQ/Features/Measurement/Data/Services/DepthDataProcessor.swift:31, :176).
타입별 후보 그룹은 거리 또는 둘레로 환산되며, 둘레는 좌우 폭×2로 근사한 뒤 cm 단위로 변환하고 평균 confidence를 보존합니다 (ClothIQ/ClothIQ/Features/Measurement/Presentation/ViewModels/MeasurementViewModel_Refactored.swift:1102).
결과값은 MeasurementCalculator가 제공하는 범위 검증 로직으로 필터링해 비정상 값에 경고를 붙입니다 (ClothIQ/ClothIQ/Features/Measurement/Data/Services/MeasurementCalculator.swift:132).
저장 및 후속 처리

성공한 측정값은 세션에 반영되고, 촬영 이미지/Depth map과 함께 SwiftData 모델에 저장됩니다 (ClothIQ/ClothIQ/Features/Measurement/Presentation/ViewModels/MeasurementViewModel_Refactored.swift:989, :823).
신뢰도는 환경 점수·LiDAR 품질을 종합해 계산하며, 리스트 카드/상세화면에서 실시간으로 확인할 수 있습니다 (ClothIQ/ClothIQ/Features/Measurement/Presentation/ViewModels/MeasurementViewModel_Refactored.swift:1138).
추가 고려사항

밑위·소매처럼 곡선이 필요한 항목은 현재 직선 근사에 의존하므로, 필요 시 후보 수를 늘려 MeasurementCalculator.calculateTotalDistance로 폴리라인 길이를 구하는 개선이 가능합니다 (ClothIQ/ClothIQ/Features/Measurement/Data/Services/MeasurementCalculator.swift:43).
마스크 커버리지/깊이 임계값을 조정하면 특정 원단(얇은 실크 등)의 감지를 개선할 수 있으나, 과도하게 완화하면 배경 잡음이 늘 수 있습니다 (ClothIQ/ClothIQ/Features/Measurement/Data/Services/ForegroundSegmentationService.swift:568).
성능 측면에서는 ForegroundSegmentationService가 30fps 이하로 처리되도록 프레임 간 최소 간격을 두고 있으니, 고주파수 업데이트가 필요한 경우 processingInterval 조정이 필요합니다 (ClothIQ/ClothIQ/Features/Measurement/Data/Services/ForegroundSegmentationService.swift:35).
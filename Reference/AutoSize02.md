문제 짚어보기

MeasurementViewModel_Refactored.swift:1040 로그에 따르면 총길이(second point)가 정규화 Y≈0이라 화면 좌표가 1440px 경계로 나가면서 DepthDataProcessor.extractDepth가 nil을 반환해 전체 길이 계산이 건너뛰어집니다. 그 뒤 측정 결과가 세션마다 달라지고 있습니다.
같은 로그 블록에서 허리/엉덩이 폭은 단 1쌍의 포인트에 의존하고, 3D 좌표 차가 0.33m/0.79m로 잡혀 2.2배 근사 시 각각 73cm, 173cm가 됩니다. 목표치(40cm)에 비해 크게 벗어나는 이유는 좌우 포인트가 마스크의 실질적인 좌우 가장자리와 맞지 않기 때문입니다(MeasurementPointDetector.swift:304).
측정 중 ARSession이 “delegates retaining 12 ARFrames” 경고를 연속으로 출력하는데, 이는 MeasurementView.swift:32에서 @State로 강하게 참조하는 currentARFrame과 전경 분리 비동기 처리가 프레임을 오래 붙잡고 있음을 의미합니다. 프레임이 지연되면 자동 측정이 오래된 데이터를 사용하게 되어 결과가 흔들립니다.
전체적으로 자동 측정이 윤곽선의 하나의 스냅샷에 의존하는데, 마스크 커버리지(1727%)와 깊이(0.831.27m)가 프레임마다 달라지면서 동일한 바지를 촬영해도 포인트 위치가 조금씩 틀어집니다.
개선 아이디어

MeasurementViewModel_Refactored.processCandidates와 DepthDataProcessor.extractDepth에서 스크린 좌표/정규좌표를 0...(resolution-1) 범위로 clamp하면 경계값 프레임에서도 총길이 포인트가 유효한 depth를 얻어 일관된 계산이 가능합니다.
허리/엉덩이 폭은 한 줄이 아닌, ClothingFeaturePoints.pointsInYRange를 이용해 상단·중단의 여러 Y band에서 좌우 포인트를 추출한 후 평균하거나 중앙값을 사용하는 방식으로 보강하세요 (MeasurementPointDetector.swift). 이렇게 하면 마스크가 약간 기울어져도 급격한 폭 변화가 줄어듭니다.
3D 포인트를 그대로 거리로 쓰기 전에, 감지된 좌표들로 평면을 추정(least squares plane fit)하고 모든 포인트를 해당 평면에 투영한 뒤 거리/둘레를 계산하면 카메라 기울어짐·깊이 잡음의 영향이 크게 감소합니다.
둘레 근사 계수(현재 2.2)는 임의 상수이므로, 실제 측정값(예: 허리 40cm)과 기록된 폭(0.333m)으로 보정 계수를 역산한 후, 의류 타입별/사이즈별 회귀식이나 룩업 테이블로 대체하는 것이 좋습니다.
자동 측정 직전에 전경 마스크를 추출하는 동안 currentARFrame을 강하게 잡지 말고 필요한 데이터(카메라 행렬, depthMap)만 복사해두고 프레임 참조를 즉시 해제하세요. 동시에 segmentationQueue에서 처리한 뒤 autoreleasepool 내부에서 pixel buffer를 사용하는 현재 패턴을 유지하되, 필요 없는 로그와 대기 시간을 줄이면 ARSession 프레임 경고와 지연을 없앨 수 있습니다.
윤곽 선택 시 현재는 VNContoursObservation을 contour count 기반으로 선택합니다 (AutoMeasurementService.swift:118). boundingBox 면적 기준으로 최대 윤곽을 고르도록 변경하면 복잡도가 높은 작은 윤곽이 선택되는 경우를 피할 수 있어 포인트 위치의 변동 폭이 줄어듭니다.
마지막으로, 촬영 거리를 0.81.0m로 고정하고(로그상 0.831.27m로 들쭉날쭉) 초기화 메시지를 통해 사용자에게 안내하면 depth precision과 커버리지 모두 안정됩니다.
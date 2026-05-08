# iOS 디바이스 개발 도구 가이드 (현재 구현 기준)

최종 업데이트: 2026-05-08

이 문서는 `scripts/ios_device_tools.sh`를 기준으로 ClothIQ를 실제 iPhone/iPad에 빌드/설치/실행/로그 수집하는 운영 가이드입니다.

## 1) 스크립트 구성

```text
scripts/
├── ios_device_tools.sh
├── ios_device_config.template
├── ios_device_config.sh
├── quick_deploy.sh
├── collect_logs.sh
├── automated_test.sh
├── test_data_collection.sh
├── validate_build.sh
├── qa_check.sh
├── pull_training_snapshot.sh
└── ml_training_workflow.sh
```

## 2) 선행 조건

- macOS + Xcode 설치
- Apple 개발자 서명 가능 상태
- USB 또는 Wi-Fi로 연결된 iOS 디바이스
- `scripts/ios_device_config.sh` 설정 완료

## 3) 설정 파일 확인

`ios_device_tools.sh`는 기본적으로 `scripts/ios_device_config.sh`를 읽습니다.

필수 항목:

- `PROJECT_PATH`
- `SCHEME`
- `BUNDLE_ID`

주요 선택 항목:

- `DEVICE_ID` (비우면 자동 감지)
- `CONFIGURATION` (`Debug`/`Release`)
- `DEVELOPMENT_TEAM`

## 4) 기본 워크플로우

### A. 디바이스 확인

```bash
cd scripts
./ios_device_tools.sh list-devices
```

### B. 빌드

```bash
./ios_device_tools.sh build
```

### C. 설치

```bash
./ios_device_tools.sh install
```

### D. 실행

```bash
./ios_device_tools.sh launch
```

### E. 로그 스트리밍

```bash
./ios_device_tools.sh logs
```

### F. 권장 원클릭 배포

```bash
./ios_device_tools.sh full-deploy
```

`full-deploy`는 다음을 순서대로 수행합니다.

1. 빌드
2. 설치
3. 기존 앱 프로세스 종료
4. 앱 실행 + 콘솔 연결

## 5) 명령어 레퍼런스

| 명령어 | 설명 |
|---|---|
| `list-devices` | 연결된 실기기 목록 확인 |
| `build` | Xcode 빌드 실행 |
| `install` | 디바이스에 앱 설치 |
| `launch` | 앱 실행 (콘솔 연결) |
| `logs` | log stream 기반 실시간 로그 |
| `stop` | 실행 중 앱 종료 |
| `full-deploy` | 빌드→설치→실행 통합 |
| `monitor` | 프로세스 상태 확인 |
| `crash-logs` | 크래시 로그 수집 |
| `profile` | Instruments 프로파일링 |

## 6) 운영 팁

### 앱 프로세스가 남아있을 때

```bash
./ios_device_tools.sh stop
./ios_device_tools.sh launch
```

### launch 시 즉시 종료(`signal 9`, `signal 15`)가 보일 때

- 디바이스에서 해당 앱 완전 종료 후 재실행
- 다음 순서 권장

```bash
./ios_device_tools.sh stop
./ios_device_tools.sh install
./ios_device_tools.sh launch
```

### `Launch prevented due to "prevent launch" assertion` 오류

대부분 SpringBoard 상태/기기 잠금/이전 디버그 세션 충돌 케이스입니다.

권장 조치:

1. 기기 잠금 해제 및 홈 화면 전환
2. `stop` 후 재실행
3. 필요 시 케이블 재연결 후 `launch`

## 7) 로그/크래시 수집

### 실시간 로그

```bash
./ios_device_tools.sh logs
./ios_device_tools.sh logs ClothIQ info
./ios_device_tools.sh logs ClothIQ error
```

### 크래시 로그

```bash
./ios_device_tools.sh crash-logs
./ios_device_tools.sh crash-logs ./crash_$(date +%Y%m%d_%H%M%S)
```

### 프로세스 점검

```bash
./ios_device_tools.sh monitor
```

## 8) 성능 프로파일링

```bash
./ios_device_tools.sh profile
./ios_device_tools.sh profile "Time Profiler" 60
```

## 9) ClothIQ 권장 디버깅 루틴

1. 코드 수정
2. `./scripts/validate_build.sh --quick`
3. `./scripts/qa_check.sh --changed`
4. `build`
5. `install`
6. `launch`
7. 재현 테스트 수행
8. `monitor`로 생존 확인
9. 필요 시 `crash-logs`

## 10) ML 촬영 데이터 추출 루틴

새 촬영/수동 보정 데이터가 들어온 뒤에는 앱 컨테이너 전체 스냅샷을 먼저 추출합니다.

```bash
bash scripts/pull_training_snapshot.sh \
  --device-id <device-id> \
  --output-dir tmp/latest-training-snapshot \
  --completion-audit \
  --collection-plan tmp/ml-training-collection-plan-current-audit.md \
  --capture-checklist tmp/ml-training-required-capture-checklist.md
```

이 명령은 `Documents/MLTrainingData`, `Documents`, `Library/Application Support`를 복사하고 SwiftData 저장소에서 복구 가능한 학습 라벨을 병합합니다.

현재 타입별 ML 학습/배포는 촬영 데이터 기준 미달로 보류 중입니다. 기준을 충족하기 전까지 `.mlmodelc` 배포를 시도하지 않습니다.

## 11) 관련 문서

- 루트 개요: `README.md`
- 스크립트 개요: `scripts/README.md`
- 라이브 디버그: `DOC/LIVE_DEBUG_ANALYSIS.md`
- ML 데이터 수집: `DOC/ML_DATA_COLLECTION_GUIDE.md`

# iOS 디바이스 개발 도구 가이드

## 개요

이 도구는 연결된 iOS 디바이스(iPhone/iPad)에서 앱을 빌드, 설치, 실행하고 로그를 수집하는 CLI 기반 자동화 스크립트입니다. Claude Code CLI에서 완전히 자동화된 개발 워크플로우를 제공합니다.

## 시스템 요구사항

- macOS (Sonoma 이상 권장)
- Xcode 15.0 이상
- 연결된 iOS 디바이스 (USB 또는 Wi-Fi)
- 개발자 계정 및 프로비저닝 프로필

## 파일 구조

```
scripts/
├── ios_device_tools.sh         # 메인 스크립트
├── ios_device_config.template  # 설정 파일 템플릿
└── ios_device_config.sh        # 프로젝트별 설정 파일 (생성 필요)
```

## 빠른 시작

### 1. 설정 파일 생성

```bash
# scripts 디렉토리로 이동
cd scripts

# 템플릿 복사
cp ios_device_config.template ios_device_config.sh

# 설정 파일 편집
nano ios_device_config.sh
```

### 2. 설정 파일 편집

`ios_device_config.sh` 파일을 열어서 프로젝트에 맞게 수정:

```bash
# 필수 설정
PROJECT_PATH="/path/to/YourProject.xcodeproj"
SCHEME="YourScheme"
BUNDLE_ID="com.yourcompany.YourApp"

# 선택적 설정
CONFIGURATION="Debug"  # 또는 "Release"
DEVICE_ID=""  # 비워두면 자동 감지
```

**설정 값 찾는 방법:**

- **PROJECT_PATH**: Xcode 프로젝트 파일(.xcodeproj)의 절대 경로
- **SCHEME**: Xcode → Product → Scheme → Manage Schemes에서 확인
- **BUNDLE_ID**: Xcode → Target → General → Bundle Identifier

### 3. 디바이스 연결 확인

```bash
./ios_device_tools.sh list-devices
```

출력 예시:
```
cauca-iPadP (26.1) (00008027-001A65243499802E)
```

### 4. 첫 번째 배포

```bash
# 빌드 + 설치 + 실행 + 로그 한번에
./ios_device_tools.sh full-deploy
```

## 명령어 가이드

### 디바이스 관리

#### 연결된 디바이스 목록
```bash
./ios_device_tools.sh list-devices
```

연결된 모든 iOS 디바이스와 시뮬레이터를 표시합니다.

---

### 빌드 및 배포

#### 프로젝트 빌드
```bash
./ios_device_tools.sh build
```

설정 파일의 프로젝트를 빌드합니다. 빌드 결과는 DerivedData에 저장됩니다.

**옵션:**
- 설정 파일에서 `CONFIGURATION` 변수로 Debug/Release 선택
- 자동 프로비저닝: `ALLOW_PROVISIONING_UPDATES="true"`

#### 앱 설치
```bash
./ios_device_tools.sh install
```

빌드된 앱을 연결된 디바이스에 설치합니다.

**주의사항:**
- 먼저 빌드를 실행해야 합니다
- 기존 앱이 있으면 업데이트됩니다

#### 전체 배포 (권장)
```bash
./ios_device_tools.sh full-deploy
```

다음 단계를 자동으로 실행합니다:
1. 프로젝트 빌드
2. 앱 설치
3. 기존 프로세스 종료
4. 앱 실행
5. 실시간 로그 스트리밍

**종료:** Ctrl+C

---

### 앱 실행 및 제어

#### 앱 실행
```bash
./ios_device_tools.sh launch
```

설치된 앱을 실행하고 콘솔 로그를 연결합니다.

#### 앱 종료
```bash
# 기본 (자동으로 PID 찾아서 종료)
./ios_device_tools.sh stop
```

실행 중인 앱을 자동으로 찾아서 종료합니다.

**종료 과정:**
1. 실행 중인 앱의 PID(Process ID) 자동 감지
2. 정상 종료 시도 (SIGTERM)
3. 종료 확인 (2초 대기)
4. 정상 종료 실패 시 강제 종료 시도 (SIGKILL)
5. 최종 종료 확인

**출력 예시:**
```
[INFO] 앱 종료 중...
[INFO] 앱 프로세스 발견 (PID: 2037)
[INFO] 정상 종료 시도 중...
[SUCCESS] 앱 종료 완료 (PID: 2037)
```

**종료 실패 시:**
```
[INFO] 앱 종료 중...
[INFO] 앱 프로세스 발견 (PID: 2037)
[INFO] 정상 종료 시도 중...
[WARNING] 정상 종료 실패. 강제 종료 시도 중...
[SUCCESS] 앱 강제 종료 완료 (PID: 2037)
```

**주의사항:**
- 앱이 디버깅 세션에서 실행 중이면 종료가 지연될 수 있습니다
- 강제 종료는 앱이 정리 작업을 수행하지 못할 수 있습니다
- 데이터 손실을 방지하려면 앱에서 자동 저장 기능을 구현하세요

---

### 로그 수집

#### 실시간 로그 스트리밍
```bash
# 기본 (debug 레벨)
./ios_device_tools.sh logs

# 프로세스명과 로그 레벨 지정
./ios_device_tools.sh logs MyApp info

# 에러만 표시
./ios_device_tools.sh logs MyApp error
```

**로그 레벨:**
- `debug`: 모든 로그 (기본값)
- `info`: 정보 레벨 이상
- `error`: 에러만

**종료:** Ctrl+C

**로그 필터링 팁:**
```bash
# 특정 키워드 검색
./ios_device_tools.sh logs | grep "ARKit"

# 파일로 저장
./ios_device_tools.sh logs > app_logs.txt
```

---

### 프로세스 모니터링

#### 프로세스 상태 확인
```bash
./ios_device_tools.sh monitor
```

실행 중인 앱의 프로세스 ID(PID)와 경로를 표시합니다.

---

### 크래시 로그 수집

#### 크래시 로그 수집
```bash
# 기본 (현재 디렉토리에 저장)
./ios_device_tools.sh crash-logs

# 출력 디렉토리 지정
./ios_device_tools.sh crash-logs ./my_crash_logs
```

수집되는 정보:
- 로컬 Mac의 DiagnosticReports에 저장된 크래시 로그(.ips 파일)
- (선택적) 디바이스 전체 진단 정보

**디바이스 진단 정보 추가 수집:**

`ios_device_config.sh`에서 설정:
```bash
COLLECT_DEVICE_DIAGNOSTICS="true"
```

---

### 성능 프로파일링

#### Time Profiler
```bash
# 기본 (30초)
./ios_device_tools.sh profile

# 시간 지정 (60초)
./ios_device_tools.sh profile "Time Profiler" 60

# 출력 파일 지정
./ios_device_tools.sh profile "Time Profiler" 60 my_profiling.trace
```

#### 다른 프로파일링 템플릿

**사용 가능한 템플릿 목록:**
```bash
xcrun xctrace list templates
```

**주요 템플릿:**
- `Time Profiler`: CPU 사용량 분석
- `Allocations`: 메모리 할당 분석
- `Leaks`: 메모리 누수 감지
- `Network`: 네트워크 활동 분석
- `Energy Log`: 배터리 사용량 분석
- `App Launch`: 앱 실행 시간 분석

**예시:**
```bash
# 메모리 누수 감지 (60초)
./ios_device_tools.sh profile "Leaks" 60

# 앱 실행 성능 측정
./ios_device_tools.sh profile "App Launch" 10

# 네트워크 분석
./ios_device_tools.sh profile "Network" 120
```

**결과 확인:**
```bash
# Instruments로 열기
open profiling_*.trace
```

---

## 실전 워크플로우

### 일반적인 개발 워크플로우

```bash
# 1. 디바이스 확인
./ios_device_tools.sh list-devices

# 2. 빌드 및 배포
./ios_device_tools.sh full-deploy

# 3. 문제 발생 시 로그 확인 (이미 실행 중)
# Ctrl+C로 종료

# 4. 수정 후 재배포
./ios_device_tools.sh full-deploy
```

### 크래시 디버깅 워크플로우

```bash
# 1. 앱 실행 및 로그 모니터링
./ios_device_tools.sh full-deploy

# 2. 크래시 발생 시 크래시 로그 수집
./ios_device_tools.sh crash-logs ./crash_$(date +%Y%m%d_%H%M%S)

# 3. 크래시 로그 분석
cat crash_*/ClothIQ*.ips
```

### 성능 분석 워크플로우

```bash
# 1. 앱 실행
./ios_device_tools.sh launch

# 2. Time Profiler로 60초 프로파일링
./ios_device_tools.sh profile "Time Profiler" 60

# 3. Instruments로 결과 분석
open profiling_*.trace

# 4. 메모리 분석
./ios_device_tools.sh profile "Allocations" 60
```

---

## 다른 프로젝트에 적용하기

### 단계별 가이드

#### 1. 스크립트 복사

프로젝트 루트에 `scripts` 디렉토리 생성:

```bash
# 새 프로젝트 디렉토리로 이동
cd /path/to/NewProject

# scripts 디렉토리 생성
mkdir -p scripts

# 스크립트 복사
cp /path/to/ClothIQ/scripts/ios_device_tools.sh scripts/
cp /path/to/ClothIQ/scripts/ios_device_config.template scripts/

# 실행 권한 부여
chmod +x scripts/ios_device_tools.sh
```

#### 2. 설정 파일 생성

```bash
cd scripts
cp ios_device_config.template ios_device_config.sh
```

#### 3. 프로젝트 정보 수집

**Xcode에서 확인:**

1. **프로젝트 경로:**
   ```bash
   # 프로젝트 디렉토리에서
   pwd
   # 출력 예: /Users/username/Projects/MyApp
   ```
   프로젝트 경로 = `/Users/username/Projects/MyApp/MyApp.xcodeproj`

2. **스킴 이름:**
   - Xcode 열기
   - Product → Scheme → Manage Schemes
   - 체크된 스킴 이름 확인

3. **번들 ID:**
   - Xcode에서 프로젝트 선택
   - Target 선택 → General 탭
   - Bundle Identifier 확인

4. **DerivedData 경로:**
   ```bash
   # 일반적으로 자동 감지되지만, 수동으로 확인:
   ls ~/Library/Developer/Xcode/DerivedData/
   ```

#### 4. 설정 파일 편집

`scripts/ios_device_config.sh`:

```bash
# 예시: MyApp 프로젝트
PROJECT_PATH="/Users/username/Projects/MyApp/MyApp.xcodeproj"
SCHEME="MyApp"
BUNDLE_ID="com.mycompany.MyApp"
CONFIGURATION="Debug"

# DerivedData 경로 (선택적)
DERIVED_DATA_PATH="${HOME}/Library/Developer/Xcode/DerivedData/MyApp-xxxxx"

# 기타 설정은 기본값 사용
DEVICE_ID=""
ALLOW_PROVISIONING_UPDATES="true"
```

#### 5. 테스트

```bash
# 디바이스 연결 확인
./ios_device_tools.sh list-devices

# 빌드 테스트
./ios_device_tools.sh build

# 전체 배포 테스트
./ios_device_tools.sh full-deploy
```

---

## 트러블슈팅

### 문제: "설정 파일을 찾을 수 없습니다"

**원인:** `ios_device_config.sh` 파일이 없음

**해결:**
```bash
cd scripts
cp ios_device_config.template ios_device_config.sh
# 파일 편집
```

---

### 문제: "연결된 디바이스를 찾을 수 없습니다"

**원인:** 디바이스가 연결되지 않았거나 신뢰되지 않음

**해결:**
1. 디바이스 USB 연결 확인
2. 디바이스에서 "이 컴퓨터를 신뢰하겠습니까?" 승인
3. 디바이스 목록 확인:
   ```bash
   xcrun xctrace list devices
   ```

---

### 문제: "앱을 찾을 수 없습니다"

**원인:** 빌드가 완료되지 않았거나 경로가 잘못됨

**해결:**
1. 먼저 빌드 실행:
   ```bash
   ./ios_device_tools.sh build
   ```
2. DerivedData 경로 확인:
   ```bash
   ls ~/Library/Developer/Xcode/DerivedData/
   ```
3. `ios_device_config.sh`의 `DERIVED_DATA_PATH` 업데이트

---

### 문제: "프로비저닝 프로필 에러"

**원인:** 서명 인증서 또는 프로비저닝 프로필 문제

**해결:**
1. 자동 프로비저닝 활성화:
   ```bash
   # ios_device_config.sh
   ALLOW_PROVISIONING_UPDATES="true"
   ```
2. Xcode에서 수동으로 서명 설정 확인:
   - Target → Signing & Capabilities
   - Team 선택
   - Automatically manage signing 체크

---

### 문제: "BUILD FAILED"

**원인:** 빌드 에러

**해결:**
1. Xcode에서 먼저 빌드 테스트 (Cmd+B)
2. 에러 메시지 확인:
   ```bash
   ./ios_device_tools.sh build 2>&1 | grep error
   ```
3. 빌드 설정 확인:
   - `ios_device_config.sh`의 `SCHEME` 이름 확인
   - `CONFIGURATION` 확인 (Debug/Release)

---

### 문제: "로그가 표시되지 않음"

**원인:** 프로세스 이름이 잘못됨

**해결:**
1. 실행 중인 프로세스 확인:
   ```bash
   ./ios_device_tools.sh monitor
   ```
2. 정확한 프로세스 이름으로 로그 확인:
   ```bash
   ./ios_device_tools.sh logs ActualProcessName
   ```

---

### 문제: "앱이 종료되지 않음"

**원인:** 앱이 디버깅 세션에 연결되어 있거나 응답하지 않음

**해결:**

1. **스크립트 자동 재시도:**
   ```bash
   ./ios_device_tools.sh stop
   ```
   스크립트가 자동으로 정상 종료 → 강제 종료를 시도합니다.

2. **수동으로 PID 확인 및 종료:**
   ```bash
   # PID 확인
   ./ios_device_tools.sh monitor
   # 출력: 2037   /private/.../ClothIQ.app/ClothIQ

   # 강제 종료
   xcrun devicectl device process terminate \
     --device 00008027-001A65243499802E \
     --pid 2037 \
     --kill
   ```

3. **디바이스에서 수동 종료:**
   - 아이패드에서 앱 스와이프하여 종료
   - 또는 디바이스 재부팅

**예상 출력:**
```
[INFO] 앱 종료 중...
[INFO] 앱 프로세스 발견 (PID: 2037)
[INFO] 정상 종료 시도 중...
[WARNING] 정상 종료 실패. 강제 종료 시도 중...
[SUCCESS] 앱 강제 종료 완료 (PID: 2037)
```

**주의사항:**
- 강제 종료는 앱의 정리 작업(cleanup)을 건너뛰므로 데이터 손실 가능성이 있습니다
- 중요한 데이터는 앱에서 자동 저장 기능을 구현하는 것이 좋습니다

---

## 고급 사용법

### 여러 디바이스 관리

디바이스별 설정 파일 생성:

```bash
# iPad용
cp ios_device_config.template ios_device_config_ipad.sh
# 편집: DEVICE_ID="iPad-UUID"

# iPhone용
cp ios_device_config.template ios_device_config_iphone.sh
# 편집: DEVICE_ID="iPhone-UUID"
```

사용:
```bash
# iPad에 배포
CONFIG_FILE=ios_device_config_ipad.sh ./ios_device_tools.sh full-deploy

# iPhone에 배포
CONFIG_FILE=ios_device_config_iphone.sh ./ios_device_tools.sh full-deploy
```

---

### CI/CD 통합

GitHub Actions 예시:

```yaml
name: iOS Device Testing

on:
  push:
    branches: [ main ]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup
        run: |
          cd scripts
          cp ios_device_config.template ios_device_config.sh
          # 환경 변수로 설정 주입

      - name: Build and Test
        run: |
          ./scripts/ios_device_tools.sh build
          ./scripts/ios_device_tools.sh install
```

---

### 자동화 스크립트 예시

**자동 야간 빌드 및 프로파일링:**

```bash
#!/bin/bash
# nightly_build.sh

cd /path/to/project/scripts

# 빌드 및 배포
./ios_device_tools.sh build
./ios_device_tools.sh install
./ios_device_tools.sh launch

# 성능 프로파일링
./ios_device_tools.sh profile "Time Profiler" 300
./ios_device_tools.sh profile "Allocations" 300

# 크래시 로그 수집
./ios_device_tools.sh crash-logs ./nightly_$(date +%Y%m%d)

# 정리
./ios_device_tools.sh stop
```

cron 등록:
```bash
# 매일 오전 3시 실행
0 3 * * * /path/to/nightly_build.sh
```

---

## 참고 자료

### Apple 공식 문서
- [xcodebuild - Apple Developer](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)
- [Instruments User Guide](https://help.apple.com/instruments/mac/current/)
- [Debugging with Xcode](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/debugging_with_xcode/chapters/about_debugging_w_xcode.html)

### 유용한 명령어
```bash
# Xcode 명령줄 도구 경로 확인
xcode-select -p

# 스킴 목록 확인
xcodebuild -list -project YourProject.xcodeproj

# 빌드 설정 확인
xcodebuild -showBuildSettings -project YourProject.xcodeproj -scheme YourScheme

# 사용 가능한 대상 확인
xcodebuild -showdestinations -project YourProject.xcodeproj -scheme YourScheme
```

---

## 버전 히스토리

### v1.0.0 (2025-11-05)
- 초기 릴리스
- 기본 빌드/배포/로그 기능
- 성능 프로파일링 지원
- 크래시 로그 수집

---

## 라이선스

이 도구는 ClothIQ 프로젝트의 일부로 제공되며, 자유롭게 수정 및 재배포할 수 있습니다.

---

## 기여

개선 사항이나 버그 리포트는 환영합니다!

**연락처:**
- GitHub Issues: [프로젝트 저장소]
- 이메일: [담당자 이메일]

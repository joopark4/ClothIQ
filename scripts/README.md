# iOS Device Development Tools

연결된 iOS 디바이스에서 앱을 빌드, 배포, 디버깅하는 자동화 도구입니다.

## 빠른 시작

```bash
# 1. 설정 파일 생성
cp ios_device_config.template ios_device_config.sh

# 2. 설정 파일 편집 (프로젝트 경로, 스킴, 번들 ID)
nano ios_device_config.sh

# 3. 디바이스 연결 확인
./ios_device_tools.sh list-devices

# 4. 빌드 + 배포 + 로그
./ios_device_tools.sh full-deploy
```

## 주요 명령어

| 명령어 | 설명 |
|--------|------|
| `list-devices` | 연결된 디바이스 목록 |
| `build` | 프로젝트 빌드 |
| `install` | 앱 설치 |
| `launch` | 앱 실행 |
| `logs` | 실시간 로그 스트리밍 |
| `stop` | 앱 종료 |
| `full-deploy` | 빌드→설치→실행→로그 (권장) |
| `monitor` | 프로세스 모니터링 |
| `crash-logs` | 크래시 로그 수집 |
| `profile` | 성능 프로파일링 |

## 상세 가이드

전체 사용 가이드는 프로젝트 루트의 **[IOS_DEVICE_GUIDE.md](../IOS_DEVICE_GUIDE.md)** 를 참조하세요.

## 다른 프로젝트에 적용하기

1. `ios_device_tools.sh`와 `ios_device_config.template`을 복사
2. 설정 파일 생성 및 편집
3. 프로젝트 정보 입력 (프로젝트 경로, 스킴, 번들 ID)
4. `./ios_device_tools.sh full-deploy` 실행

자세한 내용은 [IOS_DEVICE_GUIDE.md](../IOS_DEVICE_GUIDE.md)의 "다른 프로젝트에 적용하기" 섹션을 참조하세요.

## 파일 설명

- **ios_device_tools.sh**: 메인 스크립트 (실행 파일)
- **ios_device_config.template**: 설정 파일 템플릿
- **ios_device_config.sh**: 프로젝트별 설정 (생성 필요, .gitignore에 추가 권장)

## 요구사항

- macOS (Sonoma 이상)
- Xcode 15.0+
- 연결된 iOS 디바이스

## 라이선스

MIT License - 자유롭게 수정 및 재배포 가능

---

# ClothIQ 자동화 스크립트 (추가)

ClothIQ 개발 워크플로우를 더욱 간소화하는 추가 자동화 스크립트입니다.

## 추가 스크립트 목록

### 1. `quick_deploy.sh` - 빠른 빌드 및 배포

빌드 → 설치 → 실행 → 로그 스트리밍을 한 번에 수행합니다.

**사용법**:
```bash
cd scripts
./quick_deploy.sh
```

**실행 내용**:
1. 📦 프로젝트 빌드
2. 📲 디바이스에 앱 설치
3. 🚀 앱 실행
4. 📋 실시간 로그 스트리밍 (Ctrl+C로 종료)

---

### 2. `collect_logs.sh` - 로그 수집

디바이스에서 최근 5분간의 로그를 파일로 저장합니다.

**사용법**:
```bash
cd scripts
./collect_logs.sh
```

**출력**:
- `Reference/device_log_YYYYMMDD_HHMMSS.txt`

**내용**:
- ClothIQ 앱의 모든 진단 로그
- 자동으로 주요 키워드(ClothingType, 측정, confidence, 좌표) 필터링하여 표시

---

### 3. `automated_test.sh` - 자동화 테스트

빌드부터 테스트 결과 분석까지 전체 워크플로우를 자동화합니다.

**사용법**:
```bash
cd scripts
./automated_test.sh
```

**실행 순서**:
1. 📦 빌드
2. 📲 설치
3. 🚀 실행
4. 📋 로그 수집 시작
5. ⏳ 사용자 테스트 대기
   - 의류 라이브러리 열기
   - 아이템 선택 (반바지)
   - "재측정" 버튼 탭
   - 측정 완료
   - **ENTER 키 입력**
6. 🔍 결과 자동 분석
   - 의류 분류 검증
   - 신뢰도 검증
   - 좌표 검증

**출력**:
- `TestResults/test_result_YYYYMMDD_HHMMSS.txt` - 테스트 결과 요약
- `TestResults/test_log_YYYYMMDD_HHMMSS.txt` - 전체 로그

**결과 예시**:
```
🧪 [ClothIQ Automated Test]
Timestamp: 20251106_230000

📦 Step 1: Building...
✅ Build: PASS

📲 Step 2: Installing...
✅ Install: PASS

🚀 Step 3: Launching app...
✅ Launch: PASS

🔍 Step 6: Analyzing results...
✅ Classification: PASS (shorts)
✅ Confidence: PASS (>70%)
   Value: 0.846
✅ Coordinates: FOUND
   start=(0.59, 0.85) end=(0.56, 0.12)

📊 Test Summary:
   Build: ✅
   Install: ✅
   Launch: ✅
   Classification: ✅
   Confidence: ✅
```

---

## 환경 변수 설정 (선택)

`~/.zshrc` 또는 `~/.bash_profile`에 다음을 추가하면 더 편리하게 사용할 수 있습니다:

```bash
# ClothIQ 개발 환경 변수
export CLOTHIQ_DEVICE_ID="00008027-001A65243499802E"
export CLOTHIQ_BUNDLE_ID="com.eunyeon.ClothIQ"
export CLOTHIQ_PROJECT_DIR="/Users/cauca/Projects/ClothIQ-ClaudeCode/ClothIQ"

# 단축 명령어 (aliases)
alias ciq-deploy='cd /Users/cauca/Projects/ClothIQ-ClaudeCode/scripts && ./quick_deploy.sh'
alias ciq-logs='cd /Users/cauca/Projects/ClothIQ-ClaudeCode/scripts && ./collect_logs.sh'
alias ciq-test='cd /Users/cauca/Projects/ClothIQ-ClaudeCode/scripts && ./automated_test.sh'
```

설정 후:
```bash
source ~/.zshrc
ciq-deploy  # 원클릭 배포!
```

---

## 상세 개발 워크플로우

전체 개발 워크플로우 및 트러블슈팅 가이드는 [DEVELOP_WF.md](../DEVELOP_WF.md)를 참조하세요.

**마지막 업데이트**: 2025년 11월 6일

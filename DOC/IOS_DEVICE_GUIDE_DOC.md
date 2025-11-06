⏺ iOS 디바이스 개발 도구의 사용 방법을 단계별로 설명드리겠습니다!

  🚀 빠른 시작 가이드

  1단계: 설정 파일 확인

  cd /Users/cauca/Projects/ClothIQ-ClaudeCode/scripts

  # 설정 파일이 이미 생성되어 있습니다
  ls ios_device_config.sh

  설정 파일 내용 (이미 ClothIQ용으로 설정됨):
  - 프로젝트 경로: ClothIQ.xcodeproj
  - 스킴: ClothIQ
  - 번들 ID: com.eunyeon.ClothIQ

  ---
  2단계: 디바이스 연결 확인

  # 연결된 아이패드/아이폰 확인
  ./ios_device_tools.sh list-devices

  출력 예시:
  [INFO] 연결된 iOS 디바이스 목록:
  cauca-iPadP (26.1) (00008027-001A65243499802E)
  cauca'iPhone14 (18.5) (00008120-00110C813A00C01E)

  ---
  3단계: 앱 실행하기

  방법 1: 전체 자동 배포 (권장 ⭐)

  # 빌드 + 설치 + 실행 + 로그 한번에
  ./ios_device_tools.sh full-deploy

  실행 과정:
  1. 프로젝트 빌드 (Clean + Build)
  2. 아이패드에 앱 설치
  3. 기존 실행 중인 앱 종료
  4. 새 앱 실행
  5. 실시간 로그 스트리밍 시작

  종료: Ctrl+C

  ---
  방법 2: 단계별 실행

  # 1. 빌드만
  ./ios_device_tools.sh build

  # 2. 설치만
  ./ios_device_tools.sh install

  # 3. 실행만
  ./ios_device_tools.sh launch

  # 4. 로그만
  ./ios_device_tools.sh logs

  ---
  📱 주요 명령어 설명

  1. 빌드

  ./ios_device_tools.sh build

  기능:
  - Xcode 프로젝트 빌드
  - Debug 또는 Release 구성 선택 가능
  - 빌드 결과 DerivedData에 저장

  출력:
  [INFO] 프로젝트 빌드 시작...
  warning: Some warning messages...
  ** BUILD SUCCEEDED **
  [SUCCESS] 빌드 성공!

  ---
  2. 설치

  ./ios_device_tools.sh install

  기능:
  - 빌드된 앱을 디바이스에 설치
  - 기존 앱이 있으면 업데이트

  출력:
  [INFO] 앱 설치 중...
  App installed:
  • bundleID: com.eunyeon.ClothIQ
  • installationURL: file:///...
  [SUCCESS] 앱 설치 완료!

  ---
  3. 실행

  ./ios_device_tools.sh launch

  기능:
  - 설치된 앱 실행
  - 콘솔 로그 자동 연결

  출력:
  [INFO] 앱 실행 중...
  Launched application with com.eunyeon.ClothIQ bundle identifier.
  [SUCCESS] 앱 실행 완료!

  ---
  4. 로그 확인

  # 기본 (모든 로그)
  ./ios_device_tools.sh logs

  # 특정 레벨만
  ./ios_device_tools.sh logs ClothIQ info
  ./ios_device_tools.sh logs ClothIQ error

  # 파일로 저장
  ./ios_device_tools.sh logs > app_logs.txt

  로그 레벨:
  - debug: 모든 로그 (기본값)
  - info: 정보 이상
  - error: 에러만

  출력 예시:
  2025-11-05 19:53:27.585 ClothIQ[2037:411593] PSO compilation completed...
  2025-11-05 19:53:27.586 ClothIQ[2037:411593] ARKit initialized...

  ---
  5. 앱 종료

  ./ios_device_tools.sh stop

  기능:
  - 자동으로 PID 찾기
  - 정상 종료 시도
  - 실패 시 강제 종료

  출력:
  [INFO] 앱 종료 중...
  [INFO] 앱 프로세스 발견 (PID: 2037)
  [INFO] 정상 종료 시도 중...
  [SUCCESS] 앱 종료 완료 (PID: 2037)

  ---
  6. 프로세스 모니터링

  ./ios_device_tools.sh monitor

  출력:
  [INFO] 프로세스 모니터링...
  2037   /private/var/containers/Bundle/Application/.../ClothIQ.app/ClothIQ

  ---
  7. 크래시 로그 수집

  # 기본
  ./ios_device_tools.sh crash-logs

  # 특정 폴더에 저장
  ./ios_device_tools.sh crash-logs ./crash_$(date +%Y%m%d)

  수집 내용:
  - 로컬 Mac의 크래시 로그 (.ips 파일)
  - 선택적으로 디바이스 진단 정보

  ---
  8. 성능 프로파일링

  # CPU 프로파일링 (30초)
  ./ios_device_tools.sh profile "Time Profiler" 30

  # 메모리 분석 (60초)
  ./ios_device_tools.sh profile "Allocations" 60

  # 메모리 누수 감지 (60초)
  ./ios_device_tools.sh profile "Leaks" 60

  # 앱 실행 성능
  ./ios_device_tools.sh profile "App Launch" 10

  결과 확인:
  # Instruments로 열기
  open profiling_*.trace

  ---
  🎯 실전 사용 시나리오

  시나리오 1: 개발 중 테스트

  # 1. 코드 수정 후...

  # 2. 빌드 + 배포 + 테스트
  ./ios_device_tools.sh full-deploy

  # 3. 앱 사용하면서 로그 확인 (자동 스트리밍 중)

  # 4. 문제 발견 시 Ctrl+C로 종료

  # 5. 코드 수정 후 다시 full-deploy

  ---
  시나리오 2: 로그만 확인

  # 앱이 이미 실행 중일 때

  # 로그만 스트리밍
  ./ios_device_tools.sh logs

  # 특정 키워드 검색
  ./ios_device_tools.sh logs | grep "ERROR"
  ./ios_device_tools.sh logs | grep "ARKit"

  ---
  시나리오 3: 크래시 디버깅

  # 1. 앱 실행 및 로그 모니터링
  ./ios_device_tools.sh full-deploy

  # 2. 크래시 발생!

  # 3. 크래시 로그 수집
  ./ios_device_tools.sh crash-logs ./crash_$(date +%Y%m%d_%H%M%S)

  # 4. 크래시 로그 확인
  cat crash_*/ClothIQ*.ips

  ---
  시나리오 4: 성능 분석

  # 1. 앱 실행
  ./ios_device_tools.sh launch

  # 2. 성능 프로파일링 시작 (60초)
  ./ios_device_tools.sh profile "Time Profiler" 60

  # 3. 앱 사용 (프로파일링 진행 중)

  # 4. 자동 종료 후 결과 확인
  open profiling_*.trace

  ---
  🔧 다른 프로젝트에 적용하기

  1단계: 파일 복사

  # 새 프로젝트로 이동
  cd /path/to/NewProject

  # scripts 폴더 생성
  mkdir -p scripts

  # 파일 복사
  cp /Users/cauca/Projects/ClothIQ-ClaudeCode/scripts/ios_device_tools.sh scripts/
  cp /Users/cauca/Projects/ClothIQ-ClaudeCode/scripts/ios_device_config.template scripts/

  # 실행 권한
  chmod +x scripts/ios_device_tools.sh

  ---
  2단계: 설정 파일 생성

  cd scripts
  cp ios_device_config.template ios_device_config.sh
  nano ios_device_config.sh

  ---
  3단계: 프로젝트 정보 입력

  필수 설정:

  # Xcode에서 확인할 정보
  PROJECT_PATH="/Users/username/Projects/MyApp/MyApp.xcodeproj"
  SCHEME="MyApp"                    # Product → Scheme
  BUNDLE_ID="com.company.MyApp"     # Target → General → Bundle ID

  # 기타
  CONFIGURATION="Debug"
  DEVICE_ID=""  # 비워두면 자동 감지

  프로젝트 정보 찾는 방법:

  1. 프로젝트 경로:
  # 프로젝트 폴더에서
  pwd
  # 출력: /Users/username/Projects/MyApp
  # 프로젝트 경로 = /Users/username/Projects/MyApp/MyApp.xcodeproj
  2. 스킴 이름:
    - Xcode → Product → Scheme → Manage Schemes
    - 체크된 스킴 이름 확인
  3. 번들 ID:
    - Xcode → 프로젝트 선택 → Target → General
    - Bundle Identifier 복사

  ---
  4단계: 실행

  # 디바이스 확인
  ./ios_device_tools.sh list-devices

  # 빌드 테스트
  ./ios_device_tools.sh build

  # 전체 배포
  ./ios_device_tools.sh full-deploy

  ---
  💡 유용한 팁

  팁 1: 여러 디바이스 관리

  # iPad용 설정
  cp ios_device_config.template ios_device_config_ipad.sh
  # 편집: DEVICE_ID="iPad-UUID"

  # iPhone용 설정
  cp ios_device_config.template ios_device_config_iphone.sh
  # 편집: DEVICE_ID="iPhone-UUID"

  # 사용
  CONFIG_FILE=ios_device_config_ipad.sh ./ios_device_tools.sh full-deploy
  CONFIG_FILE=ios_device_config_iphone.sh ./ios_device_tools.sh full-deploy

  ---
  팁 2: 로그 필터링

  # 에러만 보기
  ./ios_device_tools.sh logs | grep -i "error"

  # ARKit 관련만
  ./ios_device_tools.sh logs | grep -i "arkit"

  # 파일로 저장하면서 화면에도 표시
  ./ios_device_tools.sh logs | tee app_logs.txt

  ---
  팁 3: 빠른 재배포

  # 앨리어스 설정 (~/.zshrc 또는 ~/.bashrc)
  alias deploy='cd /path/to/project/scripts && ./ios_device_tools.sh full-deploy'

  # 사용
  deploy

  ---
  📚 도움말 보기

  # 명령어 목록
  ./ios_device_tools.sh help

  # 상세 가이드
  cat ../IOS_DEVICE_GUIDE.md

  # 또는
  open ../IOS_DEVICE_GUIDE.md

  ---
  ⚡ 자주 사용하는 명령어 요약

  # 가장 많이 사용
  ./ios_device_tools.sh full-deploy    # 빌드+배포+로그

  # 개발 중
  ./ios_device_tools.sh stop           # 앱 종료
  ./ios_device_tools.sh logs           # 로그만 보기
  ./ios_device_tools.sh monitor        # 프로세스 확인

  # 디버깅
  ./ios_device_tools.sh crash-logs     # 크래시 로그
  ./ios_device_tools.sh profile        # 성능 분석

  ---
  ❓ 문제 해결

  문제: "설정 파일을 찾을 수 없습니다"

  cd scripts
  cp ios_device_config.template ios_device_config.sh

  문제: "디바이스를 찾을 수 없습니다"

  # USB 연결 확인
  # 디바이스에서 "이 컴퓨터 신뢰" 승인
  ./ios_device_tools.sh list-devices

  문제: "빌드 실패"

  # Xcode에서 먼저 빌드 테스트 (Cmd+B)
  # 스킴 이름 확인
  xcodebuild -list -project YourProject.xcodeproj

  ---
  더 자세한 내용은 IOS_DEVICE_GUIDE.md 문서를 참조하세요! 📖
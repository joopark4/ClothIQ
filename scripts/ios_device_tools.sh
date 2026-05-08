#!/bin/bash

###############################################################################
# iOS Device Build & Debug Tools
#
# 이 스크립트는 연결된 iOS 디바이스에서 앱을 빌드, 설치, 실행하고
# 로그를 수집하는 범용 도구입니다.
#
# 사용법:
#   ./ios_device_tools.sh [command] [options]
#
# 명령어:
#   list-devices      : 연결된 디바이스 목록
#   build            : 프로젝트 빌드
#   install          : 앱 설치
#   launch           : 앱 실행
#   logs             : 실시간 로그 스트리밍
#   stop             : 앱 종료
#   full-deploy      : 빌드 + 설치 + 실행 + 로그
#   monitor          : 프로세스 모니터링
#   crash-logs       : 크래시 로그 수집
#   profile          : 성능 프로파일링
#
###############################################################################

set -e  # 에러 발생 시 스크립트 중단

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로깅 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 설정 파일 로드
load_config() {
    local config_file="${1:-ios_device_config.sh}"

    if [ ! -f "$config_file" ]; then
        log_error "설정 파일을 찾을 수 없습니다: $config_file"
        log_info "ios_device_config.template을 복사하여 ios_device_config.sh를 생성하세요."
        exit 1
    fi

    source "$config_file"
    log_success "설정 파일 로드: $config_file"
}

# 디바이스 목록 조회
list_devices() {
    log_info "연결된 iOS 디바이스 목록:"
    local device_output
    device_output="$(xcrun devicectl list devices 2>&1 || true)"
    if echo "$device_output" | grep -E "iPhone|iPad" | grep -v "Simulator"; then
        return 0
    fi

    device_output="$(xcrun xctrace list devices 2>&1 || true)"
    if echo "$device_output" | grep -E "iPhone|iPad" | grep -v "Simulator"; then
        return 0
    fi

    {
        log_warning "연결된 디바이스가 없습니다."
        return 1
    }
}

# 첫 번째 연결된 디바이스 ID 자동 감지
auto_detect_device() {
    local uuid_pattern='[A-F0-9]\{8\}-[A-F0-9]\{4\}-[A-F0-9]\{4\}-[A-F0-9]\{4\}-[A-F0-9]\{12\}'
    local device_output
    local device_id

    device_output="$(xcrun devicectl list devices 2>/dev/null || true)"
    device_id=$(echo "$device_output" | \
        grep -E "iPhone|iPad" | \
        grep -E "available|connected" | \
        grep -o "$uuid_pattern" | \
        head -1)

    if [ -z "$device_id" ]; then
        device_output="$(xcrun xctrace list devices 2>&1 || true)"
        device_id=$(echo "$device_output" | \
            grep -E "iPhone|iPad" | \
            grep -v "Simulator" | \
            grep -o "($uuid_pattern)" | \
            head -1 | \
            tr -d '()')
    fi

    if [ -z "$device_id" ]; then
        log_error "연결된 디바이스를 찾을 수 없습니다."
        exit 1
    fi

    echo "$device_id"
}

# 프로젝트 빌드
build_project() {
    log_info "프로젝트 빌드 시작..."

    local device_id="${DEVICE_ID:-$(auto_detect_device)}"

    # 실제 디바이스로 빌드
    log_info "디바이스 ID: $device_id"

    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -sdk iphoneos \
        -configuration "${CONFIGURATION:-Debug}" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        ${ALLOW_PROVISIONING_UPDATES:+-allowProvisioningUpdates} \
        DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
        clean build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:|warning:)" | tail -30

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        log_success "빌드 성공!"
    else
        log_error "빌드 실패!"
        exit 1
    fi
}

# 앱 설치
install_app() {
    log_info "앱 설치 중..."

    local device_id="${DEVICE_ID:-$(auto_detect_device)}"
    local app_path="${APP_PATH:-$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION:-Debug}-iphoneos/$SCHEME.app}"

    if [ ! -d "$app_path" ]; then
        log_error "앱을 찾을 수 없습니다: $app_path"
        log_info "먼저 빌드를 실행하세요: ./ios_device_tools.sh build"
        exit 1
    fi

    xcrun devicectl device install app \
        --device "$device_id" \
        "$app_path"

    log_success "앱 설치 완료!"
}

# 앱 실행
launch_app() {
    log_info "앱 실행 중..."

    local device_id="${DEVICE_ID:-$(auto_detect_device)}"
    local console_flag="${1:---console}"

    xcrun devicectl device process launch \
        --device "$device_id" \
        $console_flag \
        "$BUNDLE_ID"

    log_success "앱 실행 완료!"
}

# 실시간 로그 스트리밍
stream_logs() {
    log_info "실시간 로그 스트리밍 시작 (Ctrl+C로 중지)..."

    local process_name="${1:-${SCHEME}}"
    local log_level="${2:-debug}"

    log stream \
        --predicate "process == \"$process_name\"" \
        --level "$log_level" \
        --style compact
}

# 앱 종료
stop_app() {
    log_info "앱 종료 중..."

    local device_id="${DEVICE_ID:-$(auto_detect_device)}"
    local force="${1:-false}"

    # PID 찾기
    local pid=$(xcrun devicectl device info processes \
        --device "$device_id" 2>&1 | \
        grep "$SCHEME" | \
        awk '{print $1}' | \
        head -1)

    if [ -z "$pid" ]; then
        log_warning "실행 중인 앱이 없습니다."
        return 0
    fi

    log_info "앱 프로세스 발견 (PID: $pid)"

    # 일반 종료 시도
    if [ "$force" != "true" ]; then
        log_info "정상 종료 시도 중..."
        xcrun devicectl device process terminate \
            --device "$device_id" \
            --pid "$pid" 2>&1 | grep -v "Acquired"

        # 종료 확인 (2초 대기)
        sleep 2
        local check_pid=$(xcrun devicectl device info processes \
            --device "$device_id" 2>&1 | \
            grep "$SCHEME" | \
            awk '{print $1}' | \
            head -1)

        if [ -z "$check_pid" ]; then
            log_success "앱 종료 완료 (PID: $pid)"
            return 0
        fi

        log_warning "정상 종료 실패. 강제 종료 시도 중..."
    fi

    # 강제 종료
    xcrun devicectl device process terminate \
        --device "$device_id" \
        --pid "$pid" \
        --kill 2>&1 | grep -v "Acquired"

    # 최종 확인
    sleep 1
    local final_check=$(xcrun devicectl device info processes \
        --device "$device_id" 2>&1 | \
        grep "$SCHEME" | \
        awk '{print $1}' | \
        head -1)

    if [ -z "$final_check" ]; then
        log_success "앱 강제 종료 완료 (PID: $pid)"
    else
        log_error "앱 종료 실패 (PID: $pid)"
        log_info "아이패드에서 수동으로 앱을 종료해주세요."
        return 1
    fi
}

# 전체 배포 (빌드 + 설치 + 실행 + 로그)
full_deploy() {
    log_info "=== 전체 배포 시작 ==="

    build_project
    install_app

    # 기존 프로세스 종료
    stop_app || true

    # 백그라운드에서 앱 실행
    log_info "앱 실행 및 로그 모니터링 중..."
    local device_id="${DEVICE_ID:-$(auto_detect_device)}"

    xcrun devicectl device process launch \
        --device "$device_id" \
        --console \
        "$BUNDLE_ID" &

    local launch_pid=$!

    # 잠시 대기 후 로그 스트리밍
    sleep 2

    log_info "=== 앱 로그 ==="
    log_info "앱 종료: Ctrl+C"
    echo ""

    wait $launch_pid || log_warning "앱이 종료되었습니다."
}

# 프로세스 모니터링
monitor_process() {
    log_info "프로세스 모니터링..."

    local device_id="${DEVICE_ID:-$(auto_detect_device)}"

    xcrun devicectl device info processes \
        --device "$device_id" 2>&1 | \
        grep -i "$SCHEME" || log_warning "실행 중인 프로세스가 없습니다."
}

# 크래시 로그 수집
collect_crash_logs() {
    log_info "크래시 로그 수집 중..."

    local output_dir="${1:-./crash_logs_$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$output_dir"

    # 로컬 크래시 로그 복사
    if ls ~/Library/Logs/DiagnosticReports/*${SCHEME}*.ips 2>/dev/null; then
        cp ~/Library/Logs/DiagnosticReports/*${SCHEME}*.ips "$output_dir/"
        log_success "크래시 로그를 $output_dir 에 저장했습니다."
    else
        log_info "크래시 로그가 없습니다."
    fi

    # 디바이스 진단 정보 수집 (선택적)
    if [ "${COLLECT_DEVICE_DIAGNOSTICS:-false}" = "true" ]; then
        local device_id="${DEVICE_ID:-$(auto_detect_device)}"
        log_info "디바이스 진단 정보 수집 중..."

        xcrun devicectl diagnose \
            --devices "$device_id" \
            --archive-destination "$output_dir/diagnostics.zip"

        log_success "진단 정보를 $output_dir/diagnostics.zip 에 저장했습니다."
    fi
}

# 성능 프로파일링
profile_app() {
    local template="${1:-Time Profiler}"
    local duration="${2:-30}"
    local output_file="${3:-profiling_$(date +%Y%m%d_%H%M%S).trace}"

    log_info "성능 프로파일링 시작 (템플릿: $template, 시간: ${duration}초)..."

    local device_id="${DEVICE_ID:-$(auto_detect_device)}"

    xcrun xctrace record \
        --template "$template" \
        --device "$device_id" \
        --attach "$SCHEME" \
        --time-limit "${duration}s" \
        --output "$output_file"

    log_success "프로파일링 완료: $output_file"
    log_info "Instruments로 열기: open $output_file"
}

# 사용법 출력
usage() {
    cat << EOF
사용법: $0 [command] [options]

명령어:
  list-devices              연결된 디바이스 목록
  build                     프로젝트 빌드
  install                   앱 설치
  launch                    앱 실행
  logs [process] [level]    실시간 로그 스트리밍
  stop                      앱 종료
  full-deploy               빌드 + 설치 + 실행 + 로그
  monitor                   프로세스 모니터링
  crash-logs [output_dir]   크래시 로그 수집
  profile [template] [sec]  성능 프로파일링

설정:
  설정 파일: ios_device_config.sh
  (ios_device_config.template을 복사하여 생성)

예시:
  $0 list-devices
  $0 build
  $0 full-deploy
  $0 logs MyApp info
  $0 profile "Time Profiler" 60
  $0 crash-logs ./my_crash_logs

EOF
}

# 메인 로직
main() {
    local command="${1:-help}"

    case "$command" in
        list-devices)
            list_devices
            ;;
        build)
            load_config
            build_project
            ;;
        install)
            load_config
            install_app
            ;;
        launch)
            load_config
            launch_app
            ;;
        logs)
            load_config
            stream_logs "$2" "$3"
            ;;
        stop)
            load_config
            stop_app
            ;;
        full-deploy)
            load_config
            full_deploy
            ;;
        monitor)
            load_config
            monitor_process
            ;;
        crash-logs)
            load_config
            collect_crash_logs "$2"
            ;;
        profile)
            load_config
            profile_app "$2" "$3" "$4"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            log_error "알 수 없는 명령어: $command"
            echo ""
            usage
            exit 1
            ;;
    esac
}

# 스크립트 실행
main "$@"

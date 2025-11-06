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

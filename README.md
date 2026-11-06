# AI Credit Checker

Codex, Claude Code, Grok의 사용량과 남은 한도를 확인하는 macOS 메뉴바 앱입니다. SwiftUI로 구현했으며, 각 CLI의 기존 로그인 정보를 사용합니다.

## 기능

- 서비스별 사용률과 한도 초기화 시각 표시
- 응답에 포함된 구독 플랜과 크레딧 사용량 표시
- 10분마다 자동 갱신 및 수동 새로고침
- 설치 여부, 로그인 필요, 토큰 만료 등의 상태 안내
- 로그인 시 자동 실행 설정

표시되는 항목은 계정 플랜과 서비스 응답에 따라 달라집니다.

## 실행

macOS 14 이상과 Swift 5.9 이상의 개발 환경이 필요합니다. 먼저 조회할 서비스의 CLI에서 로그인하세요.

- Codex: `codex login`으로 ChatGPT 계정 로그인 (API 키 모드는 지원하지 않음)
- Claude Code: `claude` 실행 후 `/login`
- Grok: `grok` 실행 후 로그인 (API 키 모드는 지원하지 않음)

개발 실행:

```sh
swift run
```

Dock 아이콘이 없는 메뉴바 전용 앱 번들 생성 및 실행:

```sh
bash scripts/build-app.sh
open build/AICreditChecker.app
```

빌드 스크립트는 현재 Mac의 아키텍처(Apple Silicon 또는 Intel)에 맞춰 릴리스 빌드하고, 로컬 실행용 임시 서명과 번들 검증을 수행합니다. 결과물은 `build/AICreditChecker.app`입니다.

응용 프로그램 폴더에 설치하려면:

```sh
cp -R build/AICreditChecker.app /Applications/
open /Applications/AICreditChecker.app
```

## 인증 정보

Codex는 `$CODEX_HOME/auth.json` (기본값: `~/.codex/auth.json`), Claude Code는 macOS 키체인 또는 `~/.claude/.credentials.json`, Grok은 `$GROK_HOME/auth.json` (기본값: `~/.grok/auth.json`)에서 인증 정보를 읽습니다. 토큰은 해당 서비스의 사용량 조회 요청에 사용하며, 앱에서 갱신하거나 수정하지 않습니다. 만료되면 해당 CLI를 실행해 인증을 갱신하세요.

Grok은 구독 세션의 주간 사용률을 보여 줍니다. 월간 포함 한도나 추가 사용량 한도가 있는 계정은 그 금액도 함께 표시합니다. xAI Console의 API 선불 크레딧은 별도 Management Key가 필요해 조회하지 않습니다.

## 구조

- `Sources/AICreditChecker/`: SwiftUI 화면, 상태 관리, 서비스별 조회 및 모델
- `scripts/build-app.sh`: 릴리스 빌드 및 `.app` 번들 생성
- `assets/AppIcon.png`: 앱 아이콘 원본 (빌드 시 `.icns`로 변환하여 포함)
- `Package.swift`: Swift Package 설정

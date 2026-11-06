# 작업 지침

## 프로젝트

- Swift Package 기반 macOS 14+ 메뉴바 앱이며 SwiftUI와 Observation을 사용한다.
- Codex, Claude Code, Grok의 기존 인증 정보로 사용량을 조회한다.
- 설명과 사용자 안내 문구는 기본적으로 한국어로 작성한다.

## 코드 변경

- 화면은 `MenuContentView.swift`, 상태와 갱신 주기는 `UsageStore.swift`에서 관리한다.
- 서비스별 인증·요청·응답 파싱은 `CodexProvider.swift`, `ClaudeProvider.swift`, `GrokProvider.swift`에 유지한다.
- 공통 모델과 유틸리티는 `Models.swift`, 앱 진입점은 `App.swift`를 참고한다.
- 인증 정보는 읽기 전용으로 다룬다. 토큰을 갱신하거나 인증 파일·키체인을 수정하지 않는다.
- 토큰과 인증 응답 원문을 로그, 문서, 테스트 데이터 또는 커밋에 포함하지 않는다.
- 네트워크 오류, 로그인 필요, 토큰 만료 상태를 UI에서 구분할 수 있도록 유지한다.

## 검증

- 코드 변경 후 `swift build`로 컴파일을 확인한다.
- 앱 번들 관련 변경은 `bash scripts/build-app.sh`로 확인한다.
- UI 변경은 메뉴바에서 표시와 새로고침 동작을 확인한다. 확인하지 못한 항목은 결과에 명시한다.
- 실행 방법이나 인증 처리 방식이 바뀌면 `README.md`도 갱신한다.

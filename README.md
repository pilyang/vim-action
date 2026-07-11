# VimAction

macOS 전역에서 Vim 모달 키 바인딩을 쓸 수 있게 해주는 메뉴바 백그라운드 앱입니다. Notion, Slack, Apple Notes, Mail, Safari 주소창, 네이티브 텍스트 필드 등 — 텍스트를 입력하는 거의 모든 곳에서 에디터의 Vim 근육 기억을 그대로 살립니다. 무료 오픈소스를 지향합니다.

> ⚠️ **현재 상태 — 초기 스캐폴드 단계.** 지금 저장소에는 Xcode SwiftUI 앱 템플릿(기본 "Hello, world!" 창)만 들어 있습니다. 메뉴바 앱, 모드 엔진, 이벤트 탭, 전략 디스패처 등 핵심 기능은 **아직 구현 전**입니다. 아래 설계·로드맵은 앞으로의 방향입니다.

## 개요

개발자와 Vim 사용자는 하루의 상당 시간을 Vim이 동작하지 않는 앱(Notion, Slack, Notes, Mail, 브라우저)에서 보내며, 그때마다 방향키와 마우스로 되돌아가는 컨텍스트 전환 마찰을 겪습니다. VimAction은 시스템 전역 수준에서 키 입력을 가로채, Vim 모션·편집을 **Accessibility API 텍스트 조작** 또는 **합성 키 입력**으로 변환합니다. 이때 각 대상 앱이 가장 잘 지원하는 방식을 골라 OS 전반에서 모달 편집 경험을 제공합니다.

대상은 이미 Vim에 익숙한 엔지니어·테크니컬 라이터·파워 유저입니다. 완전한 Vim 에뮬레이터가 아니라, 텍스트 내비게이션과 기본 편집의 대부분을 커버하는 엄선된 모션·편집 부분집합을 목표로 합니다.

## 동작 방식 — 두 가지 전략

macOS 앱마다 텍스트를 노출하는 방식이 크게 다르기 때문에, 각 Vim 동작을 두 전략 중 하나로 변환하고 앱별(때로는 요소별)로 전략을 선택합니다.

- **Accessibility 전략 (선호)** — `AXUIElement` API로 선택 범위·값을 읽고 씁니다. 정밀하고 결정론적이며, 접근성을 올바르게 구현한 앱(대부분의 네이티브 Cocoa 앱, Safari, 애플 앱)에서 동작합니다.
- **Keyboard 전략 (폴백)** — Vim 동작을 하나 이상의 합성 키 이벤트로 변환합니다(예: `w` → `Option-Right`). 정밀도는 낮지만 거의 모든 곳(AX 지원이 불안정한 Electron 앱 포함)에서 동작합니다.

전략은 **기본적으로 자동 감지**되며(앱을 처음 만났을 때 AX 지원 여부 탐지), 사용자 설정과 앱별 프로파일(YAML)로 **재정의**할 수 있습니다.

## 기술 스택

- **Swift 5** — 주 언어.
- **SwiftUI** — 설정·온보딩 UI. **AppKit** 브리징으로 메뉴바(`NSStatusItem`)와 저수준 UI 처리 *(예정)*.
- **Quartz Event Services / Accessibility API** — 전역 키 입력 가로채기·합성, 텍스트 조작 *(예정)*.
- **YAML(Yams)** — 사용자 설정과 앱별 프로파일 *(예정)*.
- **Swift Package Manager 멀티 타깃** — 모드 엔진을 앱 셸과 분리된, 독립적으로 테스트 가능한 순수 Swift 라이브러리로 구성 *(예정 — 현재는 단일 Xcode 앱 타깃)*.
- 대상 플랫폼: macOS.

## 프로젝트 구조

```
VimACtion/
├── VimACtion/            # 앱 소스 (현재: SwiftUI 템플릿)
├── VimACtionTests/       # 단위 테스트
├── VimACtionUITests/     # UI 테스트
└── VimACtion.xcodeproj   # Xcode 프로젝트
```

## 로드맵

작고 독립적으로 배포 가능한 단계로 출시합니다. 날짜는 확정하지 않습니다.

- **Stage 0 — 스파이크(버릴 코드).** 전역 키 캡처, 포커스 앱/요소 감지, AX·Keyboard 두 전략 모두 종단 간 실현 가능성 확인.
- **Stage 1 — Normal 모드 모션(Accessibility 전용, 내부 알파).** 모달 상태 머신, `h j k l` · `w b e` · `0 ^ $` · `gg` · `G`, 메뉴바 인디케이터, 권한 온보딩, 안전장치 킬 스위치.
- **Stage 2 — 편집 + Visual 모드(퍼블릭 베타).** `x dd yy p P u`, Visual/Visual-line, Insert 진입 명령, 프로파일 로더, 첫 내장 프로파일(Notes·Mail·Safari).
- **Stage 3 — Keyboard 전략 & 앱별 전략 선택(v1.0).** Keyboard 어댑터, 자동 전략 선택기, Electron 앱 프로파일, 시스템 전역 스크롤 바인딩.
- **Stage 4 — 다듬기 & 배포.** 전체 설정 UI, 온스크린 HUD 인디케이터, Homebrew Cask, 커뮤니티 프로파일 저장소.

## 라이선스

오픈소스로 배포 예정입니다. 라이선스는 아직 확정되지 않았습니다

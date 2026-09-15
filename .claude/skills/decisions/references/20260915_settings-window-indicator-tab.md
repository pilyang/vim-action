# 설정 창에 Indicator 탭 — General / Indicator / Apps / About

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-09-15

## 결정

설정 창을 4탭으로 확장한다: **General / Indicator / Apps / About**. 온스크린 모드 인디케이터 항목 셋(on/off 토글 · "Show" Picker · "Indicator style" Picker와 각주 셋)을 General > Behavior에서 **Indicator** 탭의 단일 그룹 `Form` 섹션으로 **옮기기만** 한다 — 새 컨트롤·문구·설정 키 없음, 순서와 `.disabled` 조건 불변. General의 Behavior에는 "Launch at login"과 "Exit Normal mode on ⌘/⌥ shortcuts"만 남는다. 탭 아이콘은 SF Symbol `text.cursor`.

[20260809_settings-window-three-tabs.md](20260809_settings-window-three-tabs.md)의 **탭 수(3탭)만** 이 결정이 대체한다. 나머지 규칙 — 권한 섹션의 신뢰 상태별 자리 이동, Diagnostics 접기, 460×560 고정, 기본 선택 Apps(온보딩 첫 창만 General) — 은 그대로 유효하다.

## 배경·근거 (왜)

- **인디케이터 항목이 Behavior 섹션을 밀어냈다.** PR 3 확장([20260914_mode-indicator-optin-flash-only-and-window-border.md](20260914_mode-indicator-optin-flash-only-and-window-border.md))으로 토글 하나가 컨트롤 셋 + 각주 셋이 되어 섹션의 대부분을 차지했다.
- **성격이 다른 것이 한 섹션에 섞였다.** 로그인 시 자동 시작·Normal 탈출은 시스템 동작이고, 인디케이터는 화면 표시 취향이다.
- **색상·투명도 후속에서 항목이 더 는다.** 09-14 결정은 그 후속에서 탭 분리를 검토하기로 했지만, 자리를 먼저 마련해 두면 후속은 탭에 항목만 더하면 된다.

## 검토한 대안

- **General에 유지**: 위 두 문제(밀어냄·혼재)가 그대로 남고, 후속 항목이 붙으면 더 나빠진다.
- **색상·투명도 후속까지 대기**(09-14 결정의 원래 시점): 지금 이미 섹션이 과밀하다. 분리 비용이 뷰 이동뿐이라 미룰 이유가 없다.
- **탭 이름 "Visual"**(플랜 가칭): 기능명이 아니다 — Vim의 Visual 모드와도 헷갈린다. 탭에 담기는 것은 인디케이터 기능이다.
- **About 바로 앞 배치**(General / Apps / Indicator / About): 인디케이터는 설정성 항목이라 General 곁이 자연스럽고, 참조용 탭(Apps 상태·About)은 뒤에 모인다.

## 영향 범위

- 갱신한 architecture reference: [app-shell.md](../../architecture/references/app-shell.md)(설정 창 탭 구성), [mode-indicator-overlay.md](../../architecture/references/mode-indicator-overlay.md)(설정 위치)
- 코드: `VimAction/SettingsView.swift` — `SettingsTab.indicator`, `IndicatorTab` 추가, `GeneralTab`에서 인디케이터 항목·바인딩 제거. `ModeIndicatorController`·`Preferences.swift`·테스트 무변경(값·영속 소유는 컨트롤러, 뷰는 바인딩만).
- Dock 아이콘 훅(`SettingsWindowReader`·`onAppear`)은 계속 `TabView` 루트에 있다.

## Supersedes

- [20260809_settings-window-three-tabs.md](20260809_settings-window-three-tabs.md) — 부분: 탭 수(3탭 → 4탭)만. 나머지 규칙은 유효해 인덱스에 남긴다.

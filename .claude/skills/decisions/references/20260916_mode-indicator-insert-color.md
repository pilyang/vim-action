# 인디케이터 Insert 색 추가 — 모드별 색을 Normal / Insert / Visual 셋으로

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-09-16

## 결정

온스크린 모드 인디케이터의 사용자 색에 **Insert 색**을 더해 Normal / Insert / Visual 셋으로 한다. Insert 색은 모드 전환 때 뜨는 **INSERT flash**의 배경색이다 — Insert에는 상시 표시가 없다는 정책은 그대로다.

- 키 `onScreenModeIndicatorInsertColor`, 형식·기본값·소유·못 읽는 값 처리·재도색 규칙은 [20260916_mode-indicator-per-mode-colors.md](20260916_mode-indicator-per-mode-colors.md)의 두 색과 **완전히 같다**(sRGB `#RRGGBBAA`, 미설정이 기본 = 시스템 강조색, `ModeIndicatorController` 소유, 색 변경은 AX 재읽기 없이 즉시 재도색).
- Settings Indicator 탭 "Colors" 섹션의 `ColorPicker`는 **Normal / Insert / Visual** 순서(Vim 상태줄 관례), "Reset to system accent"는 셋 다 지우고 셋 다 미설정이면 비활성.

## 배경·근거 (왜)

- 사용자 요청(2026-09-16): 모드가 바뀔 때 뜨는 INSERT flash도 사용자 색이 필요하다. 첫 결정이 Insert를 뺀 근거("Insert는 중립 상태라 강조색이 '평소 타이핑으로 복귀' 신호")는 flash가 **매 전환마다 뜨는 신호**라는 점에서 약하다 — 사용자가 Normal·Visual을 바꿔 놓으면 INSERT만 시스템 색으로 남아 오히려 이질적이다.
- 세 모드가 같은 규칙을 타면 모델에 예외가 없다: "모드별 색, 미설정은 강조색". 키 하나를 더하는 additive 확장이라 첫 결정이 예고한 대로 마이그레이션이 없다.

## 검토한 대안

- **Insert flash를 Normal 색으로 그리기**: 기각 — Insert 진입 flash가 Normal과 같은 색이면 전환이 색으로 보이지 않는다.
- **강조색 고정 유지(첫 결정)**: 기각 — 위 근거.

## 영향 범위

- 갱신할 architecture reference(구현 PR에서): [mode-indicator-overlay.md](../../architecture/references/mode-indicator-overlay.md)(색 셋), [profiles-and-config.md](../../architecture/references/profiles-and-config.md)(키 셋), [app-shell.md](../../architecture/references/app-shell.md)(ColorPicker 셋).
- 코드: `Preferences.swift`(키 추가), `ModeIndicatorColor.color(for:normal:insert:visual:)`, `ModeIndicatorController.insertColor`, `SettingsView` Colors 섹션, 테스트(모드→색 표·Insert 키 영속·Reset 셋 제거).

## Supersedes

- [20260916_mode-indicator-per-mode-colors.md](20260916_mode-indicator-per-mode-colors.md) — **부분**: "INSERT flash는 계속 시스템 강조색이다 — 설정 없음" 항목과 기각 대안 "Insert 색까지 셋: 보류"만 뒤집는다. 두 색의 형식·기본값·저장·UI·재도색 규칙은 유효하다.

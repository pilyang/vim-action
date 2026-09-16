> Superseded (부분) by [20260916_mode-indicator-insert-color.md](20260916_mode-indicator-insert-color.md) — INSERT flash 강조색 고정(설정 없음)은 뒤집힘 / 두 색의 형식·기본값·저장·UI·재도색 규칙은 유효

# 인디케이터 모드별 색상·투명도 — Normal/Visual 두 색, 기본은 시스템 강조색

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-09-16

## 결정

온스크린 모드 인디케이터의 색을 사용자가 고를 수 있게 한다 — **Normal 색**과 **Visual 색**(VISUAL·V-LINE 공유) 둘이고, 투명도는 색의 **알파 채널**로 같이 고른다. 알약(flash·배지·테두리 모서리 라벨)의 배경과 테두리 선이 그 색을 쓰고, 글씨는 불투명을 유지하며 글씨 색은 기존 luminance 파생(`ModeIndicatorPanel.textColor(on:)`)을 사용자 색에 그대로 적용한다(알파 무시). **INSERT flash는 계속 시스템 강조색**이다 — 설정 없음.

- **기본값은 둘 다 미설정 = 시스템 강조색(동적 색)** — 설정을 건드리지 않은 사용자에게 외양 변화가 없다.
- **저장은 UserDefaults 키 둘** `onScreenModeIndicatorNormalColor`·`onScreenModeIndicatorVisualColor`, 값은 sRGB `#RRGGBBAA` 문자열(대문자 8자리). 없는 키·못 읽는 값은 미설정(강조색)으로 접힌다. 소유자는 `ModeIndicatorController`(런타임 SSOT 프로퍼티 + didSet 영속 — 기존 세 키와 같은 모델), 미설정으로 되돌리면 키를 지운다.
- **UI는 Indicator 탭**에 `ColorPicker` 둘(Normal / Visual, `supportsOpacity: true`) + "Reset to system accent" 버튼(둘 다 미설정이면 비활성). Picker는 실효 색(사용자 색, 없으면 그 시점의 강조색을 sRGB로 해석한 값)을 보여 준다. 인디케이터가 꺼져 있으면 셋 다 비활성.
- **색 변경은 기하 재읽기 없이 즉시 다시 그린다** — 색은 `Presentation`에 싣지 않는다(기하가 같은데 AX 왕복이 나면 안 된다). 컨트롤러가 떠 있는 패널에 색을 직접 밀어 넣고, 각 패널은 자기가 표시 중인 모드의 색을 받는다. 설정 창이 열린 동안(자기 pid 경로) 이전 앱의 상시 표시가 남아 있는 기존 계약 덕에 색 변경이 그 자리에서 보인다.

## 배경·근거 (왜)

- PR 1~3([#66](https://github.com/pilyang/vim-action/pull/66)·[#67](https://github.com/pilyang/vim-action/pull/67)·[#68](https://github.com/pilyang/vim-action/pull/68))으로 표시 정책·앵커·스타일이 자리 잡았고, 플랜의 마지막 외양 항목이 색상·투명도다. 강조색 하나로는 사용자가 색을 바꿀 길이 시스템 설정뿐이고, 그 색은 시스템 전체를 바꾼다.
- **모드별인 이유**: 모드 인디케이터의 색은 모드를 한눈에 가르는 데 쓰인다 — Vim 상태줄(airline·lightline)의 관례도 모드별 색이다. 색만으로 구분하지 않는다는 PRD NFR은 라벨이 항상 동반되므로 유지된다 — 색은 라벨에 더해지는 두 번째 신호다. 사용자 확정(2026-09-16).
- **Insert를 뺀 이유**: Insert는 기본 상태(상시 표시 없음)이고, INSERT flash의 강조색은 "평소 타이핑으로 돌아왔다"는 중립 신호로 그대로 둔다. 필요가 실증되면 키 하나를 더하는 additive 확장이다.
- **hex 문자열인 이유**: `defaults write`로 읽고 쓸 수 있고, 파싱·직렬화가 순수 함수라 표로 검증되며, 외양(라이트/다크)에 묶이지 않는다.
- **투명도를 알파로 같이 받는 이유**: `ColorPicker`가 알파를 같은 컨트롤에서 제공해 별도 슬라이더·키가 필요 없다. 글씨를 불투명으로 두는 것은 반투명 배경 위에서도 라벨이 읽히게 하기 위해서다. 사용자 확정(2026-09-16).
- **재읽기가 없는 이유**: 색은 기하와 무관하다. 스타일 변경이 재읽기를 내는 것은 형태·앵커가 달라서지 외양 때문이 아니다.

## 검토한 대안

- **단일 색 하나**: 기각 — 모드 구분이 색으로 되지 않는다.
- **Insert 색까지 셋**: 보류 — 위 근거. additive라 나중에 더할 수 있다.
- **`NSKeyedArchiver`로 `NSColor` 보관**: 기각 — 불투명 blob이라 `defaults`로 다룰 수 없고, 동적 강조색을 보관하면 한 외양으로 굳는다.
- **"Use system accent color" 토글 + Bool 키**: 기각 — 토글 상태를 색 키의 nil 여부에서 파생하면 토글을 꺼도 색을 고르기 전까지 되돌아가고, 독립 키로 두면 끄는 순간 강조색을 키에 스냅샷해야 한다. "미설정 = 강조색" + Reset 버튼이 키 둘로 닫힌다.
- **별도 투명도 슬라이더·키**: 기각 — 알파 채널로 충분하다.
- **알파 하한**: 두지 않는다 — 글씨가 불투명이라 라벨은 남고, 완전 투명 배경은 사용자의 선택이다.
- **색을 `Presentation`에 실어 기존 `desired != current` 경로로 다시 그리기**: 기각 — 그 경로는 AX 재읽기를 낸다.
- **config.yaml 노출**: 기각 — [20260906_mode-indicator-settings-in-userdefaults.md](20260906_mode-indicator-settings-in-userdefaults.md)의 경계 그대로.

## 영향 범위

- 갱신할 architecture reference(구현 PR에서): [mode-indicator-overlay.md](../../architecture/references/mode-indicator-overlay.md)(글씨색·색 흐름·재읽기 없는 갱신 불변식), [profiles-and-config.md](../../architecture/references/profiles-and-config.md)(UserDefaults 키 둘), [app-shell.md](../../architecture/references/app-shell.md)(Indicator 탭 항목).
- 코드: `Preferences.swift`(키 둘), `ModeIndicatorController`(색 프로퍼티 둘·영속·패널로 밀어 넣기), `ModeIndicatorPanel`(`ModeIndicatorPillView` 배경색), `ModeIndicatorBorderPanel`(선 색), `SettingsView`(Indicator 탭 `ColorPicker` 둘 + Reset), 순수 hex 변환, 테스트(변환 왕복·영속·기본값·Reset·모드→색 표·글씨색).

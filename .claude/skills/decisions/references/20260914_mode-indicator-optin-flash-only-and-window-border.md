# 온스크린 인디케이터 opt-in 확장 — 순간 표시만 옵션 + 포커스 창 테두리 스타일

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-09-14

## 결정

온스크린 모드 인디케이터에 **opt-in 옵션 둘**을 추가한다. 기본값은 바꾸지 않는다 (전환 시 순간 표시 + 비-Insert 상시 배지).

1. **상시 표시 on/off** (`onScreenModeIndicatorPersistentEnabled`, 기본 on): off면 모드 전환 때의 순간 표시(flash)만 남고 Normal·Visual 동안 아무것도 남지 않는다. 기존 on/off 토글은 그대로 두고 그 아래 Picker("Only when the mode changes" / "Also while in Normal or Visual mode")로 고른다 — Bool 키 하나를 더하는 additive 방식이라 저장값 마이그레이션이 없다.
2. **상시 표시 스타일에 포커스 창 테두리 추가** (`ModeIndicatorPresentationStyle.windowBorder`): 포커스 창 rect 자체를 강조색 테두리로 두르고 창 안쪽 오른쪽 위에 모드 라벨을 놓는다. 배지 / 창 테두리 / 화면 테두리 셋 중 고른다. 창이 없으면 **폴백 없이** 아무것도 표시하지 않는다.

같이 확정한 것: 자기 pid 경로(설정 창·메뉴바 클릭으로 VimAction이 최전면)는 떠 있는 기하 읽기를 **무효화**하고 밀린 flash를 **만료**한다. 두 옵션 모두 설정 창에서 바꾸므로 이 경로의 정합성이 전제다 (PR #68 리뷰에서 지적된 구멍).

## 배경·근거 (왜)

PR 3 도그푸딩 피드백. [20260906_mode-indicator-hybrid-display-policy.md](20260906_mode-indicator-hybrid-display-policy.md)가 "순간 표시만"과 "창 단위 하이라이트"를 **기본으로는** 기각한 이유는 유지된다 — 순간 표시만으로는 사후 인지("딴 데 갔다 와서 지금 Normal이었나?")를 못 풀고, 창 단위 표시는 어느 입력칸인지 말하지 못한다. 그래서 기본값은 그대로다. 다만:

- 상시 배지가 **소음**으로 느껴지는 사용자에게는 순간 표시만이 더 낫다. 안전 장치를 통째로 끄는 것(토글 off)과 전환 피드백은 남기는 것 사이에 단계가 없었다.
- 창 테두리는 라벨을 동반하므로 "어느 모드인지"는 말한다(색만으로 구분하지 않는다는 NFR 유지). "어느 입력칸인지"를 포기하는 대신 시야 어디서든 보이는 큰 신호를 원하는 사용자의 선택지다 — 화면 테두리보다 덜 압도적이고 배지보다 눈에 띈다.
- 두 옵션은 기존 구조에 거의 공짜다: 순간 표시만은 Insert 경로(`showsBadge == false`)와 같은 코드이고, 창 테두리는 이미 있는 테두리 패널과 창 rect 읽기·창 이동/리사이즈 알림을 재사용한다.
- 자기 pid 토큰: 두 새 설정도 기존 스타일 설정과 같이 설정 창(= 자기 pid 경로)에서 바뀐다. 이 경로가 떠 있는 읽기를 살려 두면 이전 앱을 향해 떠 있던 읽기가 착지해 방금 감춘 옛 형태를 되살린다. 밀린 flash를 만료시키는 것은 "앵커를 못 찾은 flash는 버린다"는 기존 계약과 같은 원칙이다.

## 검토한 대안

- **on/off 토글을 3단 Picker(off / 전환 시만 / 항시)로 교체**: 기각 — 기존 Bool 키를 enum으로 바꾸려면 마이그레이션 코드와 테스트가 따라온다. 토글 + 하위 Picker면 UX가 같고 코드가 절반이다.
- **창 테두리를 창 사다리 폴백으로만 흡수**(09-06 결정의 원안): 유지 — 폴백은 그대로 있고, 이번 것은 사용자가 **고르는** 스타일이다. 둘은 다른 축이다.
- **창 테두리에서 창이 없을 때 요소·화면으로 폴백**: 기각 — "창 테두리"인데 다른 것을 두르면 사용자가 고른 스타일이 아니다. 배지가 앵커 없을 때와 같은 답("없음")이 일관된다.
- **테두리 모서리 반경을 스타일별로 가르기**: 보류 — 선 굵기의 2배(8pt)를 두 테두리가 공유한다. 실기기에서 창 모서리와 어긋나 보이지 않아 갈라야 할 이유가 아직 없다.
- **자기 pid 경로에서 밀린 flash 보존**: 기각 — 보존하면 복귀 시점의 앵커 이벤트에 얹혀 한참 전 전환의 라벨이 뒤늦게 번쩍인다.

## 영향 범위

- 갱신한 architecture reference: [mode-indicator-overlay.md](../../architecture/references/mode-indicator-overlay.md), [profiles-and-config.md](../../architecture/references/profiles-and-config.md)(UserDefaults 키 셋), [app-shell.md](../../architecture/references/app-shell.md)(Behavior 항목)
- 코드: `ModeIndicatorController`(설정 프로퍼티 셋, `borderPanelStyle`, 자기 pid 토큰 무효화, `usesBorderPanel`), `ModeIndicatorGeometryReader.read(processID:includesCaret:includesWindow:)`, `ModeIndicatorLayout.windowBorderLayout`/`screenBorderLayout`(개명), `Preferences.swift`, `SettingsView.swift`.
- Settings General > Behavior의 인디케이터 항목이 셋(토글·"Show" Picker·"Indicator style" Picker)이 됐다. 색상·투명도 후속에서 Visual 탭 분리를 검토할 때 이 셋도 같이 옮긴다 (탭 구성은 [20260809_settings-window-three-tabs.md](20260809_settings-window-three-tabs.md)).
- 09-06 결정 다섯 항목을 뒤집지 않는다 — Supersedes 없음.

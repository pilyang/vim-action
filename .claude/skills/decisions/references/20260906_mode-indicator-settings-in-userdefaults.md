# 온스크린 인디케이터 설정은 UserDefaults(Settings 토글) — config.yaml 비노출

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-09-06

## 결정

온스크린 모드 인디케이터의 on/off와 스타일(배지 / 화면 테두리)은 **UserDefaults**에 두고 Settings 창 General 탭의 토글로 조작한다. `config.yaml`에는 노출하지 않는다. PRD §5.x 초안의 "`config.yaml`에 모드 인디케이터 스타일"은 이 결정으로 대체된다. 기본값은 **on**(순간 표시·상시 배지 모두).

## 배경·근거 (왜)

- [20260801_userdefaults-yaml-ownership.md](20260801_userdefaults-yaml-ownership.md)의 경계 기준 — "사용자가 파일로 관리하고 싶은 설정"은 YAML, "앱이 스스로 쓰는 상태·Settings UI 토글"은 UserDefaults. 인디케이터는 표시 취향이지 앱별 동작 정의가 아니고, 탈출 옵션(`normalModeEscapeEnabled`)과 같은 부류다.
- YAML로 두면 Settings UI가 YAML을 써야 하는데 UI 쓰기는 라인 편집 예외로만 허용된다([20260809_config-yaml-line-edit-writes.md](20260809_config-yaml-line-edit-writes.md)). 토글 하나 때문에 라인 편집 표면을 넓힐 이유가 없다.
- dotfiles로 동기화할 동기가 약하다 — 표시 취향은 기기마다 달라도 무방하다. 수요가 실증되면 탈출 옵션과 함께 additive로 이관한다.
- **기본 on인 이유**: 이 기능은 "모드를 모르고 타이핑하는 사고"를 막는 안전 장치 성격이라 기본으로 켜져 있어야 첫 실행 사용자를 보호한다. PRD의 "선택적"은 끌 수 있음을 뜻한다.

## 검토한 대안

- **config.yaml 소유**: 기각 — 위 경계·UI 쓰기 충돌.
- **둘 다(YAML 우선 + UI 미러)**: 기각 — 이중 소유는 [20260812_launch-at-login-smappservice-status-ssot.md](20260812_launch-at-login-smappservice-status-ssot.md)가 피한 "어긋나는 두 진실"을 만든다.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)의 UserDefaults 경계 항목에 키를 추가하는 것은 **PR 2(토글 구현) 머지 시** 한다.
- 코드: `Preferences.swift`에 키 추가, Settings General 탭 토글. 영속 테스트는 `object(forKey:) != nil` 단언 함정을 지킨다.

# UserDefaults↔YAML 소유권 경계

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

- **UserDefaults = 런타임·안전 상태**: `interceptionEnabled`(마스터 토글)와 `normalModeEscapeEnabled`(Normal cmd/opt 탈출 옵션)는 UserDefaults에 남는다.
- **YAML = 사용자 편집 의도 설정**: 앱별 on/off(config.yaml)와 앱 프로파일 전부.

## 배경·근거 (왜)

- **마스터 토글은 킬스위치 안전 경로다**: 킬스위치 발동 시 전용 스레드가 UserDefaults로 직접 off를 영속한다([홉 무관 영속 결정](20260726_kill-switch-off-persistence-off-main.md) — SIGKILL 생존 실측). 이 경로를 YAML 쓰기로 바꾸면 안전장치가 파일 IO·직렬화·[UI 읽기 전용 결정](20260801_settings-ui-read-only-yaml.md)과 얽힌다 — 안전 경로는 가장 단순한 저장소를 유지한다.
- **탈출 옵션은 현상 유지**: 이미 Settings UI 토글 + UserDefaults로 동작 중이고, YAML로 옮기면 UI가 YAML을 써야 해서 읽기 전용 결정과 충돌한다. 사용자 편집 수요가 실증되면 이관을 후속 결정으로 — 그때 UI 토글 처리 방식도 함께 정한다.
- 경계 기준을 한 줄로: **"사용자가 파일로 관리하고 싶은 설정"은 YAML, "앱이 스스로 쓰는 상태"는 UserDefaults.**

## 검토한 대안

- **사용자 의도 설정 전부 YAML 통일** (탈출 옵션 포함): 일관성은 높지만 UI 쓰기 문제를 M4로 끌어들여 기각. additive 이관이 가능해 언제든 재개할 수 있다.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- `Preferences.swift`의 두 키는 M4에서 변경 없음. [20260718 설정 소유 모델](20260718_interception-toggle-semantics.md)(컨트롤러 프로퍼티 SSOT + didSet 영속)도 불변.

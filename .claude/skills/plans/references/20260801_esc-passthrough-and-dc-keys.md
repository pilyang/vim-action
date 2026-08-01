# M3 단계 4 선행 — Normal Esc passthrough + D/C 키 추가

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-08-01
- **갱신일**: 2026-08-01 (플랜 생성 — 착수 전)

## 목표

M3 단계 4(게이트 심사) **전에** 어휘·동작 변경 2건을 끝낸다: ① Normal 모드 Esc가 앱으로 전달되고(Esc 연타로 "Normal 진입 → 앱에 취소 전달"이 가능), ② `D`/`C`(커서부터 줄 끝까지 삭제/change)가 실행된다. 단계 4의 스킵 로그 전수 확인은 어휘가 확정된 뒤에 돌아야 하므로 이 작업이 선행이다. 상위 플랜: [20260726_m3-keyboard-edit-visual-resolver.md](20260726_m3-keyboard-edit-visual-resolver.md).

## 완료된 것

- [x] 가능성 체크 완료 (2026-08-01): 둘 다 엔진 중심 변경으로 어댑터·게시 인프라 무변경, 단계 3 도그푸딩 결과(리졸버·계열 분류)와 상호작용 없음 확인.

## 남은 것

- [ ] **① Normal Esc passthrough**: `VimEngine.swift:73-76`의 Esc 정확 매치 분기 변경 — **pending 없을 때만 `.passthrough`**(pending 있으면 현행대로 폐기+swallow, 취소로 소비). Insert의 Esc(→Normal, swallow)와 Visual의 Esc(clearSelection+Normal)는 현행 유지. 기존 픽스처 갱신(`CancellationFixtures` 등 Esc swallow 기대분) + 신규 픽스처(pending 유/무 갈림).
- [ ] **② D/C 추가**: 엔진 최상위(Normal)에서 `D`/`C` → `d$`/`c$`와 동일 출력(`.edit(.delete/.change, .motion(.lineEnd, count: 1))`)으로 완결. `C`의 Insert 전이는 기존 `complete` 헬퍼. 카운트(`3D`)는 Vim 의미(줄 끝+아래 N-1줄) 표현 불가 → 파괴적 편집 원칙대로 invalid. 픽스처 추가.
- [ ] **결정 문서 2건** (decisions 스킬 경유): Esc passthrough는 취소 최우선 결정([20260717_cancellation-first-ordering-premise.md](../../decisions/references/20260717_cancellation-first-ordering-premise.md))의 Esc swallow 의미론 부분 supersede, D/C는 어휘 추가 결정. architecture `mode-engine.md`의 처리 규칙·키셋 서술 갱신까지.
- [ ] **검증 + PR**: 엔진 테스트 그린(앱 테스트·빌드 포함 3종) → 소규모 PR 1개 → 병합 후 이 플랜 완료 처리, M3 플랜의 단계 4 착수.

## 진행 중 컨텍스트

- 착수 전. 코드 변경 없음.
- **pending 중 Esc = swallow 유지**는 권고안으로 플랜에 반영된 상태 — 착수 시 사용자 확인 1회 권장 (`d` 입력 후 Esc 취소가 앱 모달을 닫는 부작용을 막는 것이 근거, Esc 연타 시나리오는 두 번째 Esc부터 pending이 없어 영향 없음).
- 어댑터 무변경 근거: `$`가 opMotions charwise 화이트리스트에 이미 있어(`VimEngine.swift:465`) `d$`/`c$`가 현재도 완전 실행됨 — `D`/`C`는 동일 출력이라 `EditKeyMapper`·골든 무변경, 비텍스트 걸러내기 게이트 자동 적용.
- Esc passthrough는 마커·게시 인프라를 타지 않고, 래치 무효화는 passthrough 포함이라 버스트 중단도 현행 유지 — 안전장치 회귀 없음.
- 단계 4와의 순서: 이 작업이 죽은 키(`D`/`C` 미매핑 swallow)를 줄이고 무로그 삼킴을 만들지 않으므로 게이트 취지와 일치. **이 플랜이 닫히기 전에 단계 4를 시작하지 말 것.**

## 관련 링크

- architecture: [mode-engine.md](../../architecture/references/mode-engine.md) (Normal 처리 규칙 ① 취소 최우선, opMotions 화이트리스트)
- decisions: [20260717_cancellation-first-ordering-premise.md](../../decisions/references/20260717_cancellation-first-ordering-premise.md)

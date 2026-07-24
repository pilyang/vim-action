# 엔진 v1 어휘 완성 — 전체 흐름 (개요 플랜)

<!-- 이 문서는 남은 엔진 작업의 큰 흐름·순서·상태만 관리하는 상위 플랜이다.
     각 항목의 세부 실행 계획은 착수 시점에 별도 세부 플랜으로 만들고 여기서 링크한다 — 내용 중복 금지. -->

- **생성일**: 2026-07-21
- **갱신일**: 2026-07-25

## 목표

`Packages/VimActionCore` 엔진이 PRD v1(§7.2) 어휘를 전부 해석할 수 있는 상태. 각 항목은 `swift test` 픽스처로 커버되고, 새 출력 계약은 decisions에 기록된다. 순수 엔진 작업이라 탭/디스패처와 무관 — 스톨 측정 창([전용 스레드 플랜](20260719_dedicated-tap-runloop-thread.md))과 병행 안전.

## 완료된 것 (플랜 생성 시점의 엔진 현황)

- [x] 모드 Insert/Normal, 전이 `Esc i a I A`, 취소 최우선 규칙, 탈출 modifier 설정 주입
- [x] 모션 `h j k l / w b e / 0 ^ $ / gg G` + 선행 카운트
- [x] 편집 `x`, 오퍼레이터 `d/c/y` + 모션·`dd/cc/yy`·텍스트 오브젝트·linewise (PRD v2 범위 초과 달성분)
- [x] **① Visual 모드 (`v`/`V`)** (2026-07-23) — 진입·전환·이탈, 모션의 선택 확장 + 카운트, 선택 오퍼레이터 `y d x c`. PR #14 병합. 출력 계약 decisions 5건 + `mode-engine.md` 갱신 완료
- [x] **② 소형 묶음: `o`/`O`, `p`/`P`, `u`** (2026-07-24) — `openLine`/`paste`/`undo` 케이스 + 카운트 3정책, 결정 decisions 3건 + `mode-engine.md` 갱신 완료. PR #15 병합.
- [x] **③ Ctrl 콤보 묶음: `Ctrl-d/u/f/b` 스크롤, `Ctrl-r`, `Ctrl-[`** (2026-07-24) — `scroll`/`redo` 케이스 + Ctrl-[ 진입부 정규화, 취소 최우선 전제 재검토 해소(매핑 예외 셋). 결정 decisions 3건 + `mode-engine.md` 갱신 완료. PR #16 병합.

## 남은 것

<!-- 위에서부터 착수 순서. 각 항목 상세(목적·포함 내용·사이즈)는 2026-07-21 세션에서 정리 — 착수 시 세부 플랜으로 구체화. -->

- [ ] **④ `jk` 이스케이프 (옵트인)** — 순수 엔진에 시간 개념이 없어 타이머 소유권 설계 결정 선행. 우선순위 최하.

## 진행 중 컨텍스트

- v1 범위 밖(하지 않음): 마크·레지스터·매크로·검색·ex 명령(PRD v2+ 백로그), `f`/`t` 계열(PRD v1 모션 목록에 없음).
- 디스패처/어댑터 구현은 이 플랜 범위가 아니다 — 전용 스레드 결정 전까지 보류(전용 스레드 플랜 참조). 엔진이 새 액션을 내도 어댑터 실행은 디스패처 마일스톤 몫.
- 항목 완료 시: 이 문서 체크 + 세부 플랜은 삭제(스킬 워크플로우 4), 출력 계약 변경은 decisions·architecture(mode-engine.md) 갱신.

## 관련 링크

- 요구사항: 워크스페이스 `docs/prd.md` §7.2(어휘), §11(Stage), §14(미결: 카운트·이스케이프 매핑)
- architecture: [mode-engine.md](../../architecture/references/mode-engine.md)
- decisions: [20260717_cancellation-first-ordering-premise.md](../../decisions/references/20260717_cancellation-first-ordering-premise.md), [20260714_normal-mode-escape-modifiers.md](../../decisions/references/20260714_normal-mode-escape-modifiers.md)

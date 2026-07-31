# 비텍스트 걸러내기는 편집·Visual·명령 위임만 — 모션과 스크롤은 유지

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

`.nonText` 계열에서 걸러내는(`nil` 스킵) 것은 **편집(`.edit`) · Visual 세션 4종 · 네이티브 명령 위임(`.openLine`·`.paste`·`.undo`·`.redo`)** 이다. **`.move`와 `.scroll`은 그대로 게시한다.**

`.textField`에서 걸러내는 것은 `.openLine`(`o`/`O`) 하나뿐이다.

게이트는 **`KeyboardAdapter.mapping(for:)` 최상단의 판정 한 곳**에 둔다 — 매퍼가 아니다.

## 배경·근거 (왜)

플랜에는 "비텍스트 계열 **전체** `nil` 스킵"으로 적혀 있었다. 문자 그대로 읽으면 Finder 리스트의 `j`/`k` 이동과 Chrome 페이지 본문의 `j`/`k` 스크롤이 죽는다 — 엔진은 여전히 키를 삼키므로 스킵은 "네이티브 동작으로 돌아감"이 아니라 **완전 무동작**이고, M2부터 살아 있던 동작의 회귀다.

위험 등급을 가르는 축은 "비텍스트인가"가 아니라 **"앱이 이미 아는 명령인가"** 다. 이 축은 [비텍스트 UI 위험 결정](20260730_native-command-non-text-ui-hazard.md)이 직접 그은 것이다: 그 문서는 명령 어휘를 위험으로 승격시키면서 "텍스트가 아닌 곳에서 **모션은 화살표라 무해하게 흘러간다**"를 명시적 근거로 삼았다. 같은 문서의 근거를 그대로 적용하면 모션은 걸러낼 이유가 없다.

액션별 판정:

| 액션 | 비텍스트에서 무엇이 나가나 | 판정 |
|---|---|---|
| `.move` | 화살표 — 리스트 선택 이동, 페이지 스크롤 | **유지** (무해하고 유용) |
| `.scroll` | 화살표 반복(15/30) | **유지** — 이 매퍼에서 **유일하게 네이티브 명령에 위임하지 않는** 액션이다([스크롤은 화살표 반복](20260730_scroll-arrow-repetition.md)). 위험 축에서는 모션 편이다 |
| `.edit` | `Cmd-X`/`Cmd-C` — Finder 선택에 대한 `Cmd-X`는 **파일 이동**이다 | 스킵 |
| Visual 4종 | `Shift-↓` 등으로 선택을 키운 뒤 그 선택이 `.edit`으로 넘어간다 | 스킵 |
| `.openLine`·`.paste`·`.undo`·`.redo` | 정의상 앱이 아는 명령 — Finder `p`=파일 붙여넣기, `u`=파일 조작 취소 | 스킵 |

### 게이트가 어댑터에 있어야 하는 이유

매퍼 쪽에 두는 편이 "(action, family) 테이블" 설계와 결이 맞아 보이지만, 세 가지가 그것을 막는다:

1. **`.move`에는 family가 없다.** `MotionKeyMapper`는 계열 무관이 계약이고([모션 매핑 계약](20260726_motion-keystroke-mapping-contract.md)), 그 계약을 깨면 편집·Visual의 선택 재사용(`selectionStrokes`)까지 전부 family를 타야 한다.
2. **어댑터의 `.edit` 케이스는 매퍼 호출 *전에* 부수효과를 낸다** — `pasteWise.recordLinewiseEdit()`. 게시하지도 않을 편집을 기억하면 뒤따르는 `p`의 wise가 오염된다([wise는 우리 편집 기억](20260730_paste-wise-from-our-own-edit.md)).
3. **`.paste`도 매퍼 호출 전에 클립보드를 읽는다.** 순서가 반대면 걸러내기가 "클립보드에 텍스트 없음"(`.skipped`)으로 잘못 집계돼, 단계 4 게이트 심사가 읽는 **스킵 2종 구분이 무너진다**([명령 매퍼 신설](20260730_command-key-mapper-scope.md)).

셋 다 게이트를 부수효과보다 앞에 두면 함께 해소된다. 매퍼에는 `.nonText → nil` 봉쇄만 남겨 둔다 — 어댑터 게이트가 먼저 걸러 도달하지 않지만, `EditKeyMapper`의 `.selection` 조기 반환이 family 분기보다 **앞**에 있어 미래에 게이트를 우회할 함정을 만들기 때문이다.

## 검토한 대안

- **비텍스트에서 전부 스킵(플랜 문언 그대로)**: 가장 단순하고 새는 구멍이 원리적으로 없지만, Finder 리스트 이동·Chrome 페이지 스크롤의 회귀가 대가다. 위험 축이 "앱이 아는 명령"이라는 기존 근거와도 어긋난다 — 기각(사용자 확인).
- **`.scroll`도 스킵**: `CommandKeyMapper` 소속이라는 이유뿐인데, 그 매퍼에서 유일하게 명령 위임이 아닌 액션이라 소속이 위험 등급을 대변하지 못한다 — 기각.
- **매퍼별 `.nonText → nil`만으로 처리**: 위 세 가지 이유로 기각. 봉쇄용으로만 남긴다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) — 요소 계열 절
- `KeyboardAdapter.mapping(for:)`에 게이트 1개, `execute`에 `family:` 파라미터
- 걸러내기 스킵은 기존 **미지원(`.unsupported`) 경로**로 집계한다(스킵 2종 구분 유지). 단계 4 심사자가 "미구현"과 "의도적 걸러내기"를 구분할 수 있도록 요약 로그에 결정된 family를 함께 남긴다
- 해소하는 위험: [비텍스트 UI 위험](20260730_native-command-non-text-ui-hazard.md)이 단계 3에 위임한 구조적 해소
- 관련: [TextField 시퀀스 폐기](20260801_textfield-edit-sequences-scrapped.md), [폴백 기본값](20260801_resolver-fallback-defaults-to-text-area.md)

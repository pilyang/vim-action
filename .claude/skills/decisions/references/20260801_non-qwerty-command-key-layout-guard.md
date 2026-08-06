# 비-QWERTY 레이아웃 가드 — ANSI 문자 명령 키 합성 액션 보류

> Superseded (부분) by [20260806_non-qwerty-command-key-reverse-lookup.md](20260806_non-qwerty-command-key-reverse-lookup.md) — "통째 보류"는 역조회 실패 시 최후 방어선으로 좁아짐 / 판별(행동 검사)·게이트 위치·별도 요약 로그는 유효.

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

1. **판별**: `KeyTranslator`가 레이아웃 캐시를 채울 때마다 우리가 합성하는 문자 키코드 4종(`kVK_ANSI_Z/X/C/V`)을 현재 ASCII-capable 레이아웃으로 번역해 기대 문자(`z/x/c/v`)와 일치하는지 검사하고, 결과를 잠금 상자(`hasQwertyCommandKeys`)에 캐시한다. **레이아웃 ID 화이트리스트가 아니라 행동 검사다** — QWERTY 변형(ABC·US·British·Canadian 등)을 목록으로 다 셀 수 없고, 위험의 실체가 "그 위치에 다른 문자가 있다"이므로 검사도 그것이어야 한다.
2. **게이트**: `KeyboardAdapter`가 ANSI 문자 키코드를 합성하는 액션(`.edit`=Cmd-X/C, `.paste`=Cmd-V, `.undo`/`.redo`=Cmd-Z)을 비-QWERTY에서 보류한다(`Mapping.layoutBlocked`). 화살표·Return만 쓰는 액션(모션·스크롤·openLine·선택)은 레이아웃 무관이라 통과한다. 게이트 위치는 걸러내기 게이트와 같은 자리(어댑터 `mapping` 최상단, 부수효과 앞)다.
3. **로그**: 미지원 스킵과 **별도 요약**(`비-QWERTY 레이아웃 스킵 ×N`)으로 집계한다 — 섞이면 게이트 심사가 구현된 어휘를 미구현으로 읽는다(스킵 2종 분리와 같은 규칙).

## 배경·근거 (왜)

[Cmd-Z 위험 등급 확대](20260730_cmd-z-ansi-layout-escalation.md)가 단계 4 게이트 판정으로 승격해 둔 항목의 이행이다. 매퍼는 ANSI 키코드를 고정 게시하고 대상 앱이 활성 레이아웃으로 재해석하므로, AZERTY에서 `u`는 `Cmd-Z`가 아니라 **`Cmd-W`(창/탭 닫기)** 로 나가 저장 안 된 작업의 데이터 손실이 가능하다. 입력 번역의 ASCII-capable 방어([CGEvent→Key 번역](20260716_cgevent-key-translation-ascii-layout.md))는 출력을 덮지 못한다.

게이트 심사(2026-08-01, 사용자 결정)에서 "수용 + 문서화" 대신 **가드 구현**을 택했다: 릴리스 게이트가 해제되면 비-QWERTY 사용자가 실제로 생길 수 있고, 그 최악 실패가 "되돌리기로 신뢰하는 키가 창을 닫는" 데이터 손실이라 문서화로 덮을 등급이 아니다. 가드의 실패 방향은 안전하다 — 오판으로 보류하면 편집이 안 되는 불편(로그로 관측 가능)이고, 통과시키면 데이터 손실이다.

보류 범위를 `.edit` 전체로 잡은 이유: Cmd-X/C는 AZERTY에서는 같은 자리라 순하지만([기존 등급](20260727_operator-key-ansi-layout-assumption.md)), Dvorak 등 재배열 레이아웃에서는 엉뚱한 `Cmd-` 단축키가 나간다. "이 레이아웃에서 이 키코드가 무슨 문자인가"를 안 뒤에 키별로 선별하는 것은 역조회 주입과 같은 비용이라, v1은 문자 명령 키 합성 액션을 통째로 보류한다 — 비-QWERTY에서 VimAction은 "이동·스크롤·Visual 선택만 되는 레이어"로 정직하게 퇴행한다.

스냅샷 시점: 계열(family)과 달리 레이아웃은 실행 중 거의 바뀌지 않으므로 키 입력 시점 스냅샷으로 sink에 싣지 않고, 어댑터가 게시 큐에서 잠금 상자를 직접 읽는다. 값 갱신은 translate 경로(메인)뿐이고 액션은 항상 translate를 거친 키에서만 나오므로, 어댑터가 읽는 시점에는 그 키 기준 최신이다.

한계 (수용): 개발자가 QWERTY 사용자라 **실 AZERTY 하드웨어 실증은 없다** — 판별 함수는 유닛 테스트(주입)로, 행동 검사는 QWERTY에서 true가 나오는 것까지만 실기기 확인된다. 비-QWERTY 실사용 보고가 오면 이 가드가 첫 방어선이고, 정식 해소(문자→키코드 역조회 주입)는 M5 이후 카드로 남는다.

## 검토한 대안

- **수용 + 문서화만**: 위 게이트 심사에서 기각 — 데이터 손실 축은 문서화로 덮을 등급이 아니다.
- **역조회 주입**(활성 레이아웃에서 `z/x/c/v`의 실제 키코드를 찾아 게시): 비-QWERTY에서도 전 어휘가 동작하는 정식 해소지만, 매퍼 순수성을 깨고 주입 계층이 필요하다는 기존 판단 그대로다([ANSI 고정 결정](20260727_operator-key-ansi-layout-assumption.md)). 실증 경로(비-QWERTY 실기기) 없이 만드는 것도 위험하다. 이연.
- **`Cmd-Z`만 보류**(AZERTY 실측 위험만): 가장 좁지만 Dvorak류에서 X/C/V도 어긋난다는 것을 알면서 통과시키는 셈이다. 기각.
- **레이아웃 ID 화이트리스트**: 테스트의 `QwertyLayoutCondition`과 같은 방식 — 변형 누락이 곧 오탐(정상 레이아웃에서 어휘 절반이 죽음)이다. 행동 검사가 위험의 실체를 직접 잰다. 기각.

## 영향 범위

- 코드: `VimAction/KeyTranslator.swift`(`hasQwertyCommandKeys` 잠금 상자 + 행동 검사 + 재진입 가드), `VimAction/KeyboardAdapter.swift`(`Mapping.layoutBlocked`·게이트·별도 요약 로그·주입 seam)
- 테스트: `KeyboardAdapterTests.swift` — `KeyboardAdapterLayoutGateTests` 4건(보류 대상/비대상, 부수효과 선행, 실행 중 재판정)
- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- 관련: [Cmd-Z 위험 등급 확대](20260730_cmd-z-ansi-layout-escalation.md)(이 문서가 그 판정 항목의 이행), [게이트 해제 심사 ①](20260801_release-block-gate-lifted.md)

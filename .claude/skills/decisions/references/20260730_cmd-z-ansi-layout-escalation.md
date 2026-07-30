# Cmd-Z의 ANSI 가정은 위험 등급이 다르다 — 단계 4 게이트 항목

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-30

## 결정

`u`=`Cmd-Z`·`Ctrl-r`=`Shift-Cmd-Z`를 ANSI 키코드(`kVK_ANSI_Z`)로 그대로 출하한다 — [오퍼레이터 키 ANSI 고정](20260727_operator-key-ansi-layout-assumption.md)과 같은 처리다. 단, **그 결정이 수용한 위험 등급과 다르다는 것을 명시**하고 **단계 4 릴리스 게이트의 판정 항목으로 승격**한다.

이 문서는 기존 결정을 뒤집지 않는다(supersede 아님) — 같은 가정의 **위험 재평가**다.

## 배경·근거 (왜)

`Cmd-X`/`Cmd-C`가 ANSI 고정일 때의 위험은 순했다: `kVK_ANSI_X`(0x07)·`kVK_ANSI_C`(0x08)는 AZERTY에서도 **같은 위치가 `x`·`c`** 라, 프랑스 레이아웃 사용자에게도 잘라내기·복사가 그대로 동작한다. 실제로 어긋나는 건 Dvorak 같은 재배열 레이아웃이고, 거기서도 최악이 "엉뚱한 `Cmd-` 단축키가 나간다"였다.

`kVK_ANSI_Z`(0x06)는 다르다. **AZERTY는 이 물리 위치에 `w`를 배치한다.** 따라서 프랑스 레이아웃에서 `u`를 누르면 `Cmd-Z`(실행 취소)가 아니라 **`Cmd-W`(창/탭 닫기)** 가 나간다. 실행 취소를 기대한 키가 저장 안 된 작업을 닫아 **데이터 손실**로 이어질 수 있고, 하필 사용자가 "되돌리기"로 신뢰하는 키다.

이 앱은 한글 입력 소스에서도 동작하도록 ASCII-capable 레이아웃으로 **입력**을 번역하지만([CGEvent→Key 번역](20260716_cgevent-key-translation-ascii-layout.md)), **출력**은 물리 키코드를 그대로 게시하므로 대상 앱이 활성 레이아웃으로 재해석한다 — 입력 쪽 방어가 출력 쪽을 덮지 못한다.

지금 코드로 막지 않는 이유는 기존 결정과 같다: 문자→키코드 역조회는 매퍼의 순수성을 깨고 주입 계층을 요구한다. 그리고 **개발자 본인이 QWERTY 사용자라 실증 경로가 없다.** 대신 게이트 판정에 올려 "비-QWERTY에서 파괴적 오동작"이 릴리스 조건으로 다뤄지게 한다 — 후보 안전판은 (a) 활성 레이아웃이 ANSI 계열이 아니면 명령 키 액션을 스킵, (b) 역조회 주입. 저장소에는 이미 활용할 레이아웃 기반이 있다(`KeyTranslator`의 레이아웃 캐시, 테스트의 `QwertyLayoutCondition`).

`Cmd-V`(`kVK_ANSI_V`, 0x09)도 같은 계열이다 — AZERTY에서 이 위치는 `v` 그대로라 `Cmd-X`/`Cmd-C`와 같은 순한 등급이다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `VimAction/CommandKeyMapper.swift`의 `undoKey`·`redoKey`·`pasteKey` 상수 주석
- **단계 4 게이트 판정 항목**: 기존의 "비-QWERTY 오퍼레이터 키" 항목에 이 등급 차이를 반영해 함께 판단한다
- 관련: [오퍼레이터 키 ANSI 고정](20260727_operator-key-ansi-layout-assumption.md), [undo 단위 실측](20260726_undo-unit-cmdz-policy.md), [릴리스 게이트 M3 이동](20260726_release-block-gate-moves-to-m3.md)

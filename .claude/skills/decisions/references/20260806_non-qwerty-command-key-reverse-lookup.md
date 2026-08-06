# 비-QWERTY 정식 해소 — 문자→키코드 역조회 + 어댑터 게시 경로 치환

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-06

## 결정

비-QWERTY 레이아웃에서 문자 명령 키 액션(`.edit`·`.paste`·`.undo`·`.redo`)을 통째 보류하던 가드를 **역조회 치환**으로 해소한다.

1. **역조회 소유자 = `KeyTranslator`**: `refreshQwertyCommandKeys`가 도는 바로 그 자리에서 키코드 0~50을 순회해 현재 ASCII-capable 레이아웃에서 `z/x/c/v`를 내는 키코드를 찾고, `hasQwertyCommandKeys`와 같은 잠금 상자 패턴으로 `[Character: CGKeyCode]`(최대 4칸 — 못 찾은 문자는 항목 없음)에 캐시한다. 갱신 타이밍·무효화는 기존 레이아웃 캐시 생명주기를 그대로 공유한다(같은 함수, 같은 재진입 가드). **shifted 문자는 찾지 않는다** — redo(`Shift-Cmd-Z`)는 "z의 키코드 + Shift 플래그"로 충분하다.
2. **소비 지점 = 어댑터 게시 경로의 재작성(rewrite)**: 매퍼는 지금처럼 ANSI 상수(`kVK_ANSI_Z/X/C/V` = 6/7/8/9)를 **논리 키코드**로 낸다 — 매퍼·골든 테스트 무변경. 어댑터가 시퀀스 확정(`.groups`) 후 게시 직전에 6/7/8/9를 역조회 키코드로 치환하는 단일 변환 단계를 둔다. 근거: 우리가 합성하는 다른 키는 화살표(123~126)·Return(36)·기능 키뿐이고 프로파일 스트로크 어휘(`ConfigKey` v1 11종)도 문자 키를 제외하므로, 6/7/8/9가 명령 키 외의 의미로 시퀀스에 등장할 길이 없다 — 이 사실을 주석·테스트로 고정한다.
3. **QWERTY 경로 = 조건부**: `hasQwertyCommandKeys == true`면 치환을 생략한다(현행 바이트 동일 증명). 역조회 치환은 비-QWERTY에서만 활성이다.
4. **역조회 실패 폴백 = 기존 `layoutBlocked` 유지**: 비-QWERTY인데 그 액션이 필요로 하는 문자(`.edit`는 op가 yank면 `c` 아니면 `x`, `.paste`는 `v`, `.undo`/`.redo`는 `z`)를 못 찾으면 해당 액션은 지금처럼 보류한다. 가드는 삭제가 아니라 "역조회까지 실패했을 때"의 최후 방어선으로 좁혀지며, 별도 요약 로그(`비-QWERTY 레이아웃 스킵 ×N`)의 의미도 유지된다.

## 배경·근거 (왜)

[레이아웃 가드 결정](20260801_non-qwerty-command-key-layout-guard.md)이 이연해 둔 정식 해소 항목의 이행이다(M5 PR-C2 ③). 통째 보류는 비-QWERTY 사용자에게 VimAction을 "이동·스크롤·Visual 선택만 되는 레이어"로 퇴행시켰다 — 역조회가 성공하는 레이아웃(French/AZERTY, Dvorak 등 모든 일반 레이아웃)에서는 전 어휘가 동작하게 된다.

**역조회를 KeyTranslator에 둔 이유**: 레이아웃 데이터 캐시·무효화(분산 노티)·`UCKeyTranslate` 배관·재진입 가드가 전부 이미 거기 있고, `hasQwertyCommandKeys` 갱신과 같은 트리거(레이아웃 캐시 적재)에서 함께 갱신하면 두 값이 어긋날 창이 없다. 매퍼에 주입하면 [ANSI 고정 결정](20260727_operator-key-ansi-layout-assumption.md)이 우려했던 대로 매퍼 순수성이 깨지고 골든이 레이아웃 조건부가 된다 — 어댑터 게시 경로의 치환은 매퍼를 논리 키코드 산출자로 유지해 그 비용을 치르지 않는다.

**게이트-치환 TOCTOU 봉쇄**: 액션마다 레이아웃 상태(qwerty 여부 + 테이블)를 한 번만 읽어 게이트와 치환이 같은 값을 쓴다. 게이트가 필요 문자의 존재를 확정한 뒤에는 치환이 실패할 수 없는 total 변환이므로, 부수효과(`recordEdit`·클립보드 읽기)보다 게이트가 앞이라는 기존 계약이 그대로 성립한다.

**검증 전략 (사용자 결정 — 실기기 검증 범위 축소)**:
- 주입 유닛 테스트: 가짜 역조회 테이블(AZERTY형·Dvorak형·부분 테이블)로 치환·폴백·QWERTY 생략을 검증.
- 실 레이아웃 데이터 테스트: `TISCreateInputSourceList(includeAllInstalled: true)`로 French·Dvorak 레이아웃 데이터를 **입력 소스 전환 없이** 가져와 역조회 함수를 실데이터로 단언. 헤드리스 동작은 세션 초입 프로브로 확인 완료(2026-08-06, 251개 레이아웃 반환): French `z→13, x→7, c→8, v→9`(AZERTY — z만 W 자리), Dvorak `z→44, x→11, c→34, v→47`(전부 재배열).
- 수동 테스트는 에이전트가 입력 소스 전환 포함으로 수행하고, 사용자 실기기 확인은 **QWERTY 회귀 없음(`hasQwertyCommandKeys == true` 경로) 하나만** 요청한다.

## 검토한 대안

- **매퍼에 역조회 테이블 주입**: 매퍼 순수성이 깨지고 골든 테스트가 레이아웃 조건부가 된다(20260727의 기각 사유 그대로). 어댑터 치환이 같은 결과를 매퍼 무변경으로 얻는다. 기각.
- **가드 삭제(역조회 전면 신뢰)**: 4문자 전부를 못 찾는 병적 레이아웃(비라틴 전용 등)에서 ANSI 코드가 그대로 나가 `Cmd-W` 류 데이터 손실 축이 부활한다. 가드를 최후 방어선으로 유지. 기각.
- **shifted 문자까지 역조회**: redo는 z 키코드에 Shift 플래그를 얹으면 되고, macOS 단축키 매칭도 base 문자 기준이다. 확장할 이유 없음. 기각.

## 영향 범위

- 코드: `VimAction/KeyTranslator.swift`(역조회 + `commandKeyCodes` 잠금 상자, `character`의 layoutData seam), `VimAction/KeyboardAdapter.swift`(주입 seam·게이트 좁히기·치환 단계)
- 테스트: `KeyboardAdapterTests.swift`(레이아웃 게이트 확장 + 매퍼 사실 고정), `KeyTranslatorTests.swift`(실 레이아웃 데이터 역조회)
- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)

## Supersedes

- [20260727_operator-key-ansi-layout-assumption.md](20260727_operator-key-ansi-layout-assumption.md) — 부분: "역조회하지 않는다"(이연)가 이 결정으로 해소됐다. 매퍼가 ANSI 상수를 논리 키코드로 내는 것 자체는 유지된다.
- [20260801_non-qwerty-command-key-layout-guard.md](20260801_non-qwerty-command-key-layout-guard.md) — 부분: "통째 보류"가 "역조회 실패 시 최후 방어선"으로 좁아졌다. 판별(행동 검사)·게이트 위치·별도 요약 로그는 유지된다.

# append 전용 모션은 base 모션 재정의를 자동으로 따라간다

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

append 전용 모션 케이스(`charRightForAppend`/`lineEndForAppend` — a/A)는 **설정 어휘에 노출하지 않는다**. 프로파일의 `motions:`에서 `char_right`/`line_end`를 재정의·disable하면 append 케이스도 **자동으로 같은 값을 따라간다**. `char_right_for_append` 같은 이름은 미지 모션명(warn+무시)이다.

## 배경·근거 (왜)

- 두 케이스가 갈라져 있는 이유는 M5 AX 어댑터의 줄 끝 시맨틱 구분을 위한 **엔진 계약의 예약**이지([append 전용 케이스 결정](20260712_append-dedicated-motion-cases.md)), 사용자 조절축이 아니다. 현 키보드 전략에서는 base 모션과 완전히 같은 시퀀스로 수렴한다.
- 별도 노출하면 "`line_end`를 고쳤는데 `A`는 그대로"라는 함정이 생긴다 — 사용자 관점에서 `$`와 `A`의 줄 끝은 같은 개념이다.
- a/A만 다르게 재정의할 표현은 사라지지만, v1에서 그럴 실익이 실증된 바 없다. 필요해지면 이름을 additive로 여는 확장이라 이 결정과 충돌하지 않는다.

## 검토한 대안

- **별도 이름 노출** (`char_right_for_append`·`line_end_for_append`): 전 케이스 개별 제어가 가능해 명시적이지만, 위 함정이 기본 경험을 해쳐 기각 (사용자 결정).

## 영향 범위

- `VimActionConfig`의 모션 이름 파생에서 append 케이스 2종은 어휘 제외, 재정의 조회에서 base 모션의 값을 상속.
- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md) — 미결 질문 해소.

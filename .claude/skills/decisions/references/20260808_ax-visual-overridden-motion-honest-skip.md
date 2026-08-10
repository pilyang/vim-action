# AX 고정 Visual 세션에서 프로파일 재정의 모션은 정직한 스킵

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 PR-D1b 세션 0)

## 결정

AX로 고정된 Visual 세션에서 프로파일 `motions:`에 항목이 있는 모션(strokes 재정의든 `disabled`든)의 `extendSelection`은 **정직한 스킵**이다 — AX 범위 쓰기도, 재정의 시퀀스 게시도 하지 않는다. disable은 기존 분류(`.disabledByProfile`)로, strokes 재정의는 스킵으로 집계한다.

두 기존 결정의 교차점을 닫는 결정이다: [프로파일 모션 재정의가 AX보다 우선](20260808_profile-motion-override-outranks-ax.md)(재정의 모션 = keyboard 경로)과 [AX Visual 세션 경로 고정](20260808_ax-visual-session-path-pinning.md)(세션 중간의 무상태 keyboard 시퀀스 금지)이 이 자리에서 서로를 배제한다 — 어느 쪽도 이 교차를 다루지 않았다.

## 배경·근거 (왜)

- **무상태 폴백 금지의 뿌리가 그대로 적용된다.** AX가 `AXSelectedTextRange`를 써 넣은 뒤에는 앱이 어느 끝을 포커스로 보는지 미정의라, 재정의 시퀀스(Shift+키)가 앵커 반대쪽으로 자랄 수 있고 뒤따르는 `d`가 엉뚱한 텍스트를 지운다 — 파괴 방향 동전 던지기. 재정의 시퀀스도 무상태 시퀀스다.
- **스킵은 사용자 지시 위반이 아니다.** 재정의를 적는 실제 동기는 "이 앱에서 이 키를 쓰지 마라"(Notion `Shift-Cmd-↑` 충돌 회피가 원형)이고, 스킵은 그 키를 정확히 쓰지 않는다. "적었는데 조용히 다른 키가 나간다"(c안)와 달리 반증 가능하다 — 스킵 집계가 로그에 남는다.
- **피해 범위가 최소다.** 그 모션 하나만 죽고 세션·다른 모션은 AX 정확 경로 그대로다. `strategy: accessibility` + 모션 재정의 + Visual의 3중 교집합은 실사용에서 드물다.

## 검토한 대안

- **세션 통째 keyboard 고정**(재정의 모션이 하나라도 있는 프로파일은 Visual 진입 시 keyboard로 pin): 일관성은 최고지만 재정의 하나가 Visual AX 전체(재앵커 곡예 소멸·정확 상태)를 잃게 한다 — 과잉.
- **재정의 시퀀스 게시 + 상태를 미상으로 좁힘**: 금지 결정의 근거를 정면 위반 — 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (Visual 세션 경로 고정 문단)
- PR-D1b Visual 배선: AX 세션의 `extendSelection` 분기에서 `profile.motionOverrides[motion] != nil` 판정 추가.
- 도그푸딩 판독 주의: 재정의 앱의 AX Visual 세션에서 그 모션이 무동작인 것은 의도된 동작이다(스킵 로그가 증거).

# `unproven` 편집 위임은 AX 창(4096)을 keyboard 정확화에 그대로 전달 — 재읽기 없음

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 PR-D1b 세션 0)

## 결정

AX 실행 계획이 편집의 오프셋 증명에 실패해(`unproven`) keyboard로 위임할 때, keyboard 정확화(`classifyEdit`의 `text:`)에는 **이미 읽은 AX 창(`AXWindowSnapshot`, 반경 4096)의 `FocusedText`를 그대로 전달**한다 — `FocusedTextSnapshot`(반경 256)을 다시 읽지 않는다.

스냅샷 계약 문언을 함께 정밀화한다: "keyboard 경로의 `FocusedTextSnapshot`과 소비자가 겹치지 않는다"의 실체는 **"한 액션은 창을 한 번만 읽는다"** 이다 — 실행 계획이 AX를 골랐으면 그 읽기 하나가 위임 낙하 후의 정확화까지 먹인다.

## 배경·근거 (왜)

- **왕복이 1회로 유지된다.** unproven 위임에서 256 창을 재읽기하면 액션당 AX 왕복이 2배가 된다(Notion `selectedRange` ~7ms — 액션 수만큼 곱해지는 자리). 이 계약("실행 계획이 정해 준 쪽만 묻는다")을 지키는 유일한 방법이 전달이다.
- **의미가 동일하다.** `FocusedText`는 같은 타입이고 keyboard 정확화의 술어는 전부 창 상대(`windowRange` 기준)라, 4096 창은 256 창의 초집합으로서 같은 술어에 같은 답을 낸다 — 오히려 증명이 서는 범위가 넓다. 읽기 출처(요소 핸들 경유)의 차이는 술어 의미에 관여하지 않는다.
- 정확화를 포기하는 대안(b)은 4096 창이 절단될 정도의 자리(초장문 논리 줄)에서 편집 정확화까지 잃는다 — unproven은 AX가 포기한 것이지 keyboard 정확화가 포기할 이유가 아니다.

## 검토한 대안

- **`text: nil`로 위임**(정확화 포기): 이중 읽기는 없지만 AX 앱의 unproven 엣지에서 정확화 손실 — 공짜가 아니다.
- **256 창 재읽기**: 계약 위반 + Notion 7ms×2. 두 창의 시점이 어긋나 정확화가 계획과 다른 문서 상태를 볼 수도 있다.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (AX 어댑터 문단)
- PR-D1b: `mapping`의 `.edit` 분기 — AX 계획 unproven 낙하 시 `axText.value()`를 `classifyEdit`에 전달. `AXWindowSnapshot` doc 주석의 "소비자 비겹침" 문언 정밀화.
- 모션의 unproven 위임은 해당 없음(모션 keyboard 경로는 읽기를 묻지 않는다 — 현행 그대로).

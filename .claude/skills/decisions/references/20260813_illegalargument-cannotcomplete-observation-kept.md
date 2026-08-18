# `.illegalArgument` 관측 전용 유지 · `.cannotComplete` 경합 스킵 유지 — 재심사 종결

- **결정일**: 2026-08-13

## 결정

D1이 D2로 예약한 재심사 2건을 종결한다: **`.illegalArgument`는 실보고로 승격하지 않고 관측 전용(`.info` 요약)을 유지**하고, **`.cannotComplete`는 경합 스킵 분류를 유지**한다. 관측 로그는 계속 남긴다 — 비-0 표본이 다시 나타나면 그 데이터로 재심사한다.

## 배경·근거 (왜)

- **`.illegalArgument`**: 세션 0 착수 실측(2026-08-11~13)이 유일한 비-0 표본(D1b 세션 5: TextEdit 캐럿 18, `[18,21)` 범위 쓰기 3/3 거부)의 재현 조건을 정조준해 전수 조합을 돌렸으나 **재현 불가** — TextEdit 범위 쓰기 ~460회 + 캐럿 90회(전 오프셋 × plain/RTF × 배경/최전면 × 캐럿 선행 × ASCII·개행 걸침·탭·빈 줄·CJK·ZWJ·무종결 꼬리) + Notion 121회 전부 0건. 프로덕션 도그푸딩도 캐럿·범위·삽입·Visual 쓰기로 표본이 넓어진 전 기간 0건. 세션 5의 3/3은 일시 상태로 판정한다. 재현 불가 이벤트를 `.failure` 실보고로 올리면 소음 + `FailureBurstCounter` 오발동 축만 생긴다.
- **`.cannotComplete`**: 세션 0 ~580회 쓰기에서 0건(프로브에 5ms×3 재시도 로깅을 심었으나 발동 0). "경합 스킵" 분류를 뒤집을 표본 자체가 없다.
- 관측 인프라(상시 `.info`, [로그 레벨 결정](20260808_ax-illegal-argument-observation-log-level.md))는 유지한다 — auto 기본화로 쓰기 대상 앱이 넓어지면 표본 성격이 바뀔 수 있고, 그때의 판정 데이터가 이 로그다.

## 검토한 대안

- **`.failure` 승격**: 재현 불가 + 도그푸딩 0건에 실보고는 이득 없이 킬스위치 오발동 축. 기각.
- **재분류(`.cannotComplete`)**: 표본 0. 기각.

## 영향 범위

- 코드 무변경 (현행 분류·로그 유지가 결정). [20260808_ax-write-failure-whitelist-no-fallback.md](20260808_ax-write-failure-whitelist-no-fallback.md)의 "D1 종료 시 승격 재심사" 예약이 이 문서로 소화됐다 — supersede 아님.

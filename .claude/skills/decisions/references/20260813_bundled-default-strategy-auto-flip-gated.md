# 번들 기본 전략의 auto 전환 — D2 마지막 단계, 도그푸딩 게이트

- **결정일**: 2026-08-13

## 결정

번들 기본 전략(프로파일이 없거나 `strategy` 미지정인 앱)을 `keyboard` → `auto`로 전환하되, **D2 안에서 마지막 단계**로 한다: 프로브 구현 → opt-in 프로파일 도그푸딩 → 통과 시 **별도 커밋**으로 기본값 전환 + 전앱 도그푸딩. 문제 발견 시 전환 커밋만 철회한다(프로브 코드는 남긴다 — 세션 5 철회 전례). 구현상 기본값은 `defaultStrategy` **단일 상수**를 파서 기본값과 "프로파일 파일 없음" 경로가 함께 소비하게 하고, `ResolvedProfile.empty`는 `keyboard`로 남긴다.

## 배경·근거 (왜)

- **auto의 최종 자리는 기본값이다** — 앱 단위 opt-in으로서의 auto는 사용자 가치가 얇다("이 앱은 AX가 된다"고 믿으면 `accessibility`를 직접 쓰는 것이 직관적이고, "모르니 알아서"가 필요한 자리가 곧 기본값이다 — 사용자 확인). keyboard 기본 + auto opt-in은 항구 상태가 아니라 검증 기간의 과도기다.
- 전환을 게이트 뒤에 두는 이유: auto는 앱 단위 사전 판정이라 프로브 오판의 실패가 "그 앱에서 키 무동작"이고, 기본값이 되는 순간 폭발 반경이 전 앱이다. opt-in 도그푸딩이 그 반경을 좁힌 채 프로브를 검증한다.
- 게이트의 판정 데이터는 관측 결정([20260813_auto-trusted-runtime-demotion-and-observability.md](20260813_auto-trusted-runtime-demotion-and-observability.md))의 `.info` 3종(판정 전이·auto발 `.axUnavailable`·강등)과 되읽어 검증 버킷이다.
- `defaultStrategy` 단일 상수인 이유: 기본값이 실제로는 **두 곳**이다 — 파서 기본값(파일은 있는데 필드 없음)과 `ResolvedProfile` 부재 경로(파일 자체 없음). 한쪽만 바꾸면 두 경우의 동작이 갈린다. `.empty`를 건드리지 않는 이유: 그 값은 어댑터의 **builtIn 재조회 센티널**로도 쓰여 "재정의 없음"의 의미가 실려 있고, 매퍼는 strategy를 안 보므로 keyboard로 남겨도 동작 차이가 없다 (독립 검토 실이슈).
- **수용 한계**: 전환 후 사용자 측 전역 off 수단은 앱별 프로파일 명시와 마스터 토글뿐이다 — config.yaml 전역 전략 키는 PR-E 스키마에서 재검토.

## 검토한 대안

- **D2 착수 시점에 즉시 기본 전환**: 미검증 프로브가 전 앱에 걸린다. 기각.
- **PR-E로 이연**: D2 산출물이 과도기 상태로 한 PR 더 남고, PR-E가 자체 도그푸딩을 또 돈다. 기각 (사용자 확인).
- **장기 keyboard 기본 유지**: auto의 존재 이유(기본값) 상실. 선택지에서 제외 (사용자 확인).

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- `AppProfile` 파서 기본값, `ResolvedProfile` 부재 경로, D2 도그푸딩 절차. [20260725_keyboard-first-mvp-build-order.md](20260725_keyboard-first-mvp-build-order.md)가 예고한 과도기(keyboard 고정)의 계획된 종료라 supersede가 아니다.

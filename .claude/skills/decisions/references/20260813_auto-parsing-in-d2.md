# `strategy: auto` 정식 파싱은 PR-D2에서

- **결정일**: 2026-08-13

## 결정

`strategy` 필드 어휘에 `auto`를 **PR-D2에서** 정식 추가한다 (파서 `.auto` 케이스 + `ResolvedProfile` 패스스루). D1 결정이 PR-E로 배정했던 것을 앞당긴다.

## 배경·근거 (왜)

- auto 프로브의 유일한 소비자가 D2 산출물인데 파싱이 없으면 `strategy: auto`를 실기기에서 켤 수 없어 **opt-in 도그푸딩이 불가**하다. 기본값 전환([20260813_bundled-default-strategy-auto-flip-gated.md](20260813_bundled-default-strategy-auto-flip-gated.md))의 게이트가 그 도그푸딩이라 파싱은 D2의 전제다.
- D1 결정([20260808_strategy-field-minimal-parsing-d1.md](20260808_strategy-field-minimal-parsing-d1.md))이 "임시 배선 기각 — 정식 소비자와 함께 추가"를 이미 원칙으로 세웠고, 그 정식 소비자가 D2다. 배정만 바뀌는 것이고 원칙은 그대로다.
- 기존 파서 테스트 중 `auto`를 `invalidValue`로 고정한 것은 그 결정이 "계획된 변경"으로 예고해 둔 항목이라 교체가 회귀가 아니다.

## 검토한 대안

- **PR-E 유지**: D2가 프로브를 도달 불가 상태로만 배선하게 되어 도그푸딩이 유닛 테스트 수준으로 약해진다. 기각 (사용자 확인).
- **임시 스위치(UserDefaults 등)로 프로브만 켜기**: D1이 기각한 임시 배선의 재판. 기각.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md), [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- `AppProfileParser`의 strategy 어휘, `ResolvedProfile`, `auto`를 invalidValue로 단언하던 파서 테스트. PR-E에는 `per_element`·사용자 문서화가 남는다.

## Supersedes

- [20260808_strategy-field-minimal-parsing-d1.md](20260808_strategy-field-minimal-parsing-d1.md) — 부분: "`auto`는 PR-E에서 추가" 배정만. 최소 파싱 형태·어휘 밖 값 warn+무시 규칙은 유효.

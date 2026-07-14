# 멀티키 커맨드 빌더 (오퍼레이터·카운트·텍스트 오브젝트)

- **생성일**: 2026-07-14
- **갱신일**: 2026-07-14

## 목표

엔진이 `diw`, `dd`, `3w`, `d2w` 같은 오퍼레이터·카운트·텍스트 오브젝트 커맨드를 처리할 수 있도록, `pending`을 문법 기반 누적 빌더(부분 파스 상태)로, `resolve`를 extend/complete/cancel 스텝 함수로 재설계한다. 설계 모델은 결정 문서에 확정되어 있음 (관련 링크 참조).

## 완료된 것

- [x] 설계 모델 결정·기록 — 문법 기반 누적 빌더 채택, 대안(케이스 열거·트라이·raw 버퍼) 기각 ([결정 문서](../../decisions/references/20260714_multikey-command-grammar-builder.md))

## 남은 것

- [ ] `PendingCommand` 부분 파스 상태 도입 + `resolve`를 extend/complete/cancel 스텝 함수로 전환 — 기존 `gg`/무효 연속/pending 픽스처가 전부 그대로 통과해야 함 (회귀 핀)
- [ ] 취소 규칙을 명시적 최우선 분기로: 어느 깊이서든 Esc → 폐기+swallow+Normal 유지, 탈출 modifier 콤보 → 폐기+passthrough+Insert. 깊이별(`d` 후, `di` 후, 카운트 입력 중) 픽스처 추가
- [ ] `VimAction` 출력 확장 — 오퍼레이터+범위 합성(`.edit(op:, over: motion | textObject)` 계열) 타입 설계 (형태 확정 시 decisions에 기록)
- [ ] 1차 편집 키셋 구현: 카운트(`3w`), `x`, `dd`, `d`+모션(`dw`, `d$` 등), `diw`/`daw`
- [ ] architecture `mode-engine.md` 최종 상태 갱신 (구조 반영 완료 시)

## 진행 중 컨텍스트

- MVP 2차 플랜(엔진↔탭 연결)이 진행 중이므로 **이 플랜은 그 이후 착수** 예정. 착수 전 신선도 확인할 것.
- 현재 코드의 `d[Esc]` 류 취소는 `handleNormal` 진입부 무조건 pending 클리어의 부수효과 — 빌더 모델에서는 pending이 여러 키에 걸쳐 살아남으므로 이 공짜 효과가 사라진다. 취소를 명시 분기로 옮기는 항목이 이것 때문에 있음 (결정 문서에 상세).
- 어댑터(AX/keyboard)의 오퍼레이터 실행은 이 플랜 범위 밖 — 여기서는 엔진의 `VimAction` 출력까지만.

## 관련 링크

- decisions: [20260714_multikey-command-grammar-builder.md](../../decisions/references/20260714_multikey-command-grammar-builder.md)
- decisions: [20260712_pending-invalid-sequence-noop.md](../../decisions/references/20260712_pending-invalid-sequence-noop.md) (유지·일반화되는 기존 규칙)
- architecture: [mode-engine.md](../../architecture/references/mode-engine.md)

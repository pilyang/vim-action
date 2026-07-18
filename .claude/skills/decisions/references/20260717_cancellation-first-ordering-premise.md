# 취소 최우선 순서의 전제 — 탈출 콤보 선행은 modifier 매핑 부재 위에서만 동치

- **결정일**: 2026-07-17

## 결정

`handleNormal`은 어떤 매핑보다 먼저 취소를 판정한다: ① Esc **정확 매치**(수식자 없음) → pending 폐기 + swallow + Normal 유지, ② 탈출 modifier 콤보(`isEscapeCombo`) → pending 폐기 + passthrough + Insert 전이. 그 다음에야 `step`(문법 진행)에 들어간다.

이 순서에는 명시적 전제가 있다: **탈출 콤보 판정을 모든 매핑보다 선행시키는 것은 "현재 매핑 테이블에 modifier 콤보 키가 하나도 없다"는 사실 위에서만 기존 동작과 동치다.** 향후 `Ctrl-d`(half-page down) 같은 modifier 매핑을 추가할 때는 이 순서를 재검토해야 한다 — 사용자가 Ctrl을 탈출 modifier로 설정하면 취소 분기가 매핑을 가로채 `Ctrl-d`가 영원히 동작하지 않는 충돌이 생기며, 그때는 "매핑 조회 → 미스일 때만 탈출 판정" 또는 매핑·탈출 셋의 교집합 금지 같은 해소 규칙이 필요하다.

## 배경·근거 (왜)

빌더 모델 이전에는 `d[Esc]` 류 취소가 `handleNormal` 진입부의 무조건 pending 클리어의 부수효과였다. 빌더에서는 pending이 여러 키에 걸쳐 살아남으므로 취소를 명시적 최우선 분기로 승격했다 ([20260714_multikey-command-grammar-builder.md](20260714_multikey-command-grammar-builder.md)). 승격 과정에서 두 가지가 코드 순서에 박제됐다:

- **Esc는 정확 매치**: 수식자 붙은 Esc(Cmd+Esc 등)는 Esc 취소가 아니라 탈출 콤보 판정을 탄다. base 매치로 구현하면 Cmd+Esc가 swallow+Normal로 뒤집히는데, 이를 잡는 회귀 핀(`EscapeModifierFixtures`의 Cmd+Esc 픽스처)을 함께 추가했다.
- **탈출 콤보 선행의 전제**: 위 결정 본문. 전제가 코드에서 역추적되지 않는 종류의 사실("매핑에 modifier 콤보가 없어서 성립")이라 여기 기록한다.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift`의 `handleNormal`
- 향후 modifier 매핑(half-page 스크롤 등) 추가 작업은 착수 전에 이 문서를 확인해야 한다

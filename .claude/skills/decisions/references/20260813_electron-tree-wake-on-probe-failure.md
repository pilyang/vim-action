# Electron AX 트리 기상 — 프로브의 요소 실증 실패 시 1회

- **결정일**: 2026-08-13

## 결정

auto 프로브는 **요소 실증(계층 2) 실패 시 그 앱에 `AXManualAccessibility=true`를 1회 쓰고 유계 재시도**(콜드 재시도와 같은 자리, ~200ms×1–2회)한다. 앱(pid)당 1회이며, 프로브 대상(실효 전략 auto) 앱에서만 — 트리거가 "첫 vim 키 디스패치"라 개입 범위가 **사용자가 실제로 VimAction을 쓰는 앱**으로 한정된다. 비-Electron 앱에는 이 속성 쓰기가 무해한 에러다.

## 배경·근거 (왜)

- 초안은 "기상 안 함"이었고 근거가 "수혜자(AX가 정당한 Electron 앱) 실측 0"이었는데, 독립 검토가 **순환**을 지적했다: Slack·VS Code의 "포커스 요소 미노출" 실측은 전부 **깨우지 않은 상태**에서 잰 값이라 "AX 미지원"과 "트리 수면"을 구분하지 못한다.
- **검증 측정이 전제를 뒤집었다** (2026-08-13, 프로브 CLI): 기상 상태의 Slack(com.tinyspeck.slackmacgap)은 ⓐ 포커스 요소 `AXTextArea` 노출, `characterCount`·`selectedTextRange`·`visibleCharacterRange` 전부 success ⓑ **선택 범위 쓰기 왕복 10/10** — 쓰기 p50 0.19ms, 수렴 p50 10.57ms/max 12.52ms (Notion형 ~10ms 비동기 적용, 되읽어 검증 40ms 캡 안에서 안정 수렴) ⓒ Notion처럼 **최전면일 때만 포커스 요소를 보고**한다. 즉 **"Slack은 원리적으로 도달 불가" 전제는 수면 상태 측정의 산물이었고, 깨어난 Slack은 AX 프리미티브가 정상**이다 — auto의 실 수혜 후보 1호로 D2 도그푸딩 대상에 넣는다.
- 기상 주체의 귀속(명시 속성 쓰기 vs VimAction 상주의 암묵 기상)은 이번에도 모호하다 — 그래서 **명시 쓰기를 채택**한다: 암묵 기상에 맡기면 같은 앱이 세션마다 다른 판정을 받는 비결정성("어제는 되던 앱")이 남고, 명시 쓰기는 판정을 결정적으로 만든다.
- 개입 비용(대상 앱의 a11y 트리 구성 부담)은 실재하지만, 트리거 지연([20260813_auto-probe-async-cached-verdict-pid-lifetime.md](20260813_auto-probe-async-cached-verdict-pid-lifetime.md)) 덕에 "사용자가 그 앱에서 텍스트 편집 서비스를 요청한" 앱에만 발생해 비례성이 성립한다.

## 검토한 대안

- **기상 안 함 (초안)**: 근거였던 "수혜자 0"이 순환으로 반증됐고, 실측된 수혜자(Slack)가 생겼다. 암묵 기상 의존은 비결정적. 기각.
- **앱 활성화마다 전 앱 기상**: vim 키를 안 쓰는 앱까지 a11y 비용 강제. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- 프로브 계층 2의 실패 분기, 플랜의 "Slack·VS Code 원리적 도달 불가" 실측 메모 정정(수면 상태 한정으로 재문언 — keyboard 혼용 정확화도 기상 후엔 살아날 수 있어 PR-E 이후 재검토 후보).

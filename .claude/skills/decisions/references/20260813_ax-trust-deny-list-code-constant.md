# AX 신뢰 거부 목록 — 코드 상수, 초기값 notion.id, 명시 전략이 이긴다

- **결정일**: 2026-08-13

## 결정

auto 프로브의 계층 1로 **번들 ID 거부 목록**을 코드 상수로 둔다. 초기값은 `{notion.id}` 하나. 등재 기준은 "**프로브 신호(요소·읽기·settable 실증)가 잡지 못함이 실측된 거짓말 앱**"이다. 목록은 auto 판정에만 적용된다 — 프로파일에 `strategy: accessibility`를 명시한 앱은 목록과 무관하게 AX로 가며(사용자 지시 우선), 그 override 발생 시 `.info` 1회 로그를 남긴다. 목록 앱은 AX 접촉 없이 즉시 untrusted이고 재시도가 없다(목록은 정적). YAML 노출은 하지 않는다 — PR-E 스키마에서 additive 재검토.

## 배경·근거 (왜)

- Notion은 프로브의 전 계층을 통과하는 실측된 거짓말 앱이다: 읽기·쓰기 프리미티브는 정상(세션 0 왕복 15/15)인데 visible 오보(C2)·**블록 넘는 선택 미보고**(세션 5)·AX Visual 부적합([20260810 결정](20260810_notion-unfit-for-ax-visual-session-5-withdrawn.md))이 실측돼 있다. 거짓말이 신호 사각(선택 보고 진실성 축)에 있어 목록이 프로브와 중복이 아니라 빈틈을 메운다 (독립 검토 확인). `strategy`가 앱 단위 단일 값이라 "편집·모션만 AX"를 표현할 수 없는 것이 목록 등재의 직접 원인이고, per-카테고리 세분화가 생기는 PR-E에서 재개방을 검토한다 (사용자 확인).
- **명시 전략이 이기는 이유**: 명시 `accessibility`는 D1부터 전권이었고 거부 목록은 auto 판정에만 개입하는 새 축이라 기존 권한을 축소하지 않을 뿐이다 — 프로파일 모션 재정의 우선·스크롤 사다리와 같은 우선순위 축. override의 최악은 파괴가 아니라 UX 저하다(Visual 자가 검증·되읽어 검증·`.axUnavailable` 스킵이 경로 무관으로 걸린다 — 독립 검토 확인). 단 **"거부 목록 앱 + 명시 override" 조합의 도그푸딩 실사례는 없다** — 유일한 근접 사례(세션 5의 Notion `strategy: accessibility`)는 반대 방향으로 되돌려졌다. override 로그가 그 조합의 첫 관측 데이터가 된다.
- 코드 상수인 이유: 등재 기준이 "실측"이라 사용자 편집 대상이 아니고, 사용자에게는 더 강한 수단(프로파일 명시 전략)이 이미 있다.
- Slack·VS Code는 등재하지 않는다 — 목록은 신호 사각 전용이고, 그 둘은 신호로 판정되는(트리 상태에 따라 통과하거나 탈락하는) 앱이다. Slack은 오히려 기상 후 프리미티브 정상이 실측됐다([20260813_electron-tree-wake-on-probe-failure.md](20260813_electron-tree-wake-on-probe-failure.md)).

## 검토한 대안

- **YAML 노출**: 등재 기준이 실측이라 사용자 편집 축이 아니다. 기각 (PR-E additive 재검토 열어 둠).
- **Notion 목록 제외 (프로브 통과 시 AX)**: 세션 5가 기각한 Visual 회귀 상태로 복귀. 기각 (사용자 확인).

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- 프로브 계층 1, override `.info` 로그. 번들 Notion 프로파일(12/24 스크롤)은 무관하게 유지된다.

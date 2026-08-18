# force-text — 자동 폴백 없음 유지, `keyboard_family` 스키마, 치환은 keyboard 쪽만

- **결정일**: 2026-08-13

## 결정

셋을 확정한다: ① **`key-mapping` → `force-text` 자동 폴백은 만들지 않는다** — 원 결정([20260712](20260712_ax-keyboard-strategy-dispatch.md) "자동 감지로는 절대 선택하지 않는다") 유지 확인으로 미결 질문을 닫는다. ② 스키마는 프로파일 필드 **`keyboard_family`**, 값 어휘는 `key_mapping`(기본 — 미지정과 동일)·`force_text` 둘이며(snake_case — 스키마 표기 관례), 어휘 밖 값은 항목 warn+무시. ③ 구현은 실효 family를 `.textArea`로 치환하되 **keyboard 실행 쪽에만** 적용한다 — 걸러내기 게이트·매퍼 호출·매퍼 내부 `.nonText` 봉쇄·하이브리드 위임분 진입점(`openLineDelegatedStrokes`/`pasteDelegatedGroups`)이 전부 **같은 치환값**을 보고, `usesAXWrite`와 AX 분기의 계열 판정(`.nonText`/`.unresolved` 강등)은 **원본 family**를 유지한다.

## 배경·근거 (왜)

- 자동 폴백 없음: force-text는 요소 걸러내기(비텍스트 UI에서 편집 봉쇄 — Finder에서 `dd`가 파일을 지우는 것을 막는 층)를 버리는 수단이라, 자동 선택은 리졸버 오보 1건을 파괴적 시퀀스로 승격시킨다. D1a·D1b 도그푸딩 전 기간에 force-text가 필요했을 실패는 0건이라 반증 데이터도 없다 (독립 검토 확인).
- **치환 분리가 이 결정의 핵심 수정이다** (독립 검토 2건이 같은 함정을 양쪽에서): 코드의 `mapping(for:family:)`은 한 `family` 파라미터를 걸러내기 게이트와 `usesAXWrite` 양쪽에 먹인다. 문언 그대로 "최상단 치환"을 한 변수로 구현하면 `strategy: accessibility|auto` + `force_text` 앱에서 **비텍스트 요소에 AX 범위 쓰기가 나가고** 앱 전환 직후 `.unresolved` 창(위험 어휘 보류)도 뚫린다. force-text가 사용자에게 약속한 것은 "keyboard 실행 = 항상 TextArea 시퀀스"이지 AX 위임 표의 강등 행을 지우는 것이 아니다. 반대로 치환이 keyboard 쪽 전체에 닿지 않으면(게이트만 치환) `EditKeyMapper`의 자체 `.nonText → nil` 봉쇄가 force-text를 정확히 그것이 필요한 자리에서 무력화한다.
- **구현 선행 조건**: family 소비처 전수 조사(걸러내기 게이트 / 매퍼 내부 봉쇄 / `unproven` 위임의 재진입 경로 / AX `.nonText`·`.unresolved` 강등의 keyboard 낙하 경로)와, 강등·위임 두 경로 각각에서 force_text 적용을 단언하는 회귀 테스트.
- AX 전략과의 조합(`strategy: accessibility` + `force_text`)은 금지하지 않는다 — AX 강등·`unproven` 위임이 낳는 keyboard 실행에도 치환이 적용된다. force-text는 "이 앱의 role 보고를 믿지 말라"는 사용자 지시라 keyboard 실행이 어느 경로로 오든 일관 적용이 맞다.
- snake_case: 스키마의 enum 값은 전부 밑줄(`open_line`, `document_end`)이고 하이픈은 키스트로크 토큰(`cmd-down`)의 별개 문법 축이다. prose·Swift 케이스 이름(`force-text`, `.forceText`)은 그대로다.

## 검토한 대안

- **자동 폴백 도입**: 원 결정 근거 불변 + 반증 0. 기각.
- **`strategy` 값으로 `force-text`**: 전략(AX vs keyboard)과 keyboard 계열(요소 인식 vs 우회)은 별개 축 — 원 결정의 두 필드 구도 유지.
- **하이픈 토큰 `force-text`**: 스키마 첫 하이픈 enum이 되어 관례를 깬다. 기각.
- **한 변수 치환 (초안 문언)**: AX까지 새면 위 파괴 경로. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- `AppProfileParser`(`keyboard_family`), `ResolvedProfile`, `KeyboardAdapter`의 실효 family 산출 자리(두 값 분리), 회귀 테스트 2계.

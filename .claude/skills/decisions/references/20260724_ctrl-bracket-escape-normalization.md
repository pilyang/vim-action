# Ctrl-[ Esc 별칭 — 엔진 진입부 정규화

- **결정일**: 2026-07-24

## 결정

`Ctrl-[`는 Esc의 완전한 별칭이다 (Vim 동일). 구현은 **엔진 `handle(_:)` 진입부에서 `Key.char("[", [.control])`을 `.escape`로 치환**하는 정규화 — 모드 분기 이전이라 세 모드 전부에서 Esc와 자동으로 동일 경로를 탄다 (Insert의 Esc→Normal 전이 포함). 판정은 **정확 매치만**이다: `Cmd+Ctrl+[` 등 추가 modifier가 붙으면 별칭이 아니라 탈출 콤보 판정으로 간다 (Cmd+Esc가 Esc 취소 분기가 아닌 것과 동일 기준).

우선순위 함의: 정규화가 탈출 콤보 판정보다 먼저 일어나므로, 사용자가 Ctrl을 탈출 modifier로 설정해도 `Ctrl-[`는 Insert 탈출이 아니라 Esc 취소로 동작한다 — 별칭이 설정에 잠식되지 않는다.

## 배경·근거 (왜)

Ctrl-[를 각 모드 핸들러에서 개별 처리하면 같은 별칭 로직이 세 곳(Insert/Normal/Visual)에 중복되고 새 모드 추가 시 누락 위험이 생긴다. 진입부 정규화는 한 곳에서 "이 키는 Esc다"를 선언하고 이후 전 경로가 기존 Esc 규칙(정확 매치, pending 폐기, Visual clearSelection)을 그대로 상속한다.

앱 계층(KeyTranslator) 정규화가 아닌 엔진 정규화인 이유: 엔진 픽스처로 전 모드 동작을 커버할 수 있고(앱 계층이면 불가), 이번 작업의 순수 엔진 범위에 머문다. KeyTranslator는 base 문자 유도에 ctrl을 반영하지 않으므로 물리 Ctrl-[가 `.char("[", [.control])`로 번역됨을 확인했다 — 앱 계층 수정 불필요.

## 검토한 대안

- **각 모드 핸들러의 Esc 분기에 별칭 조건 추가**: 치환 없이 명시적이지만 3곳 중복 + 새 모드 누락 위험. 기각.
- **KeyTranslator(앱 계층)에서 Esc로 정규화**: 엔진 무변경이지만 엔진 픽스처로 커버 불가, 순수 엔진 범위 밖. 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- 코드: `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift`의 `handle(_:)`·`normalized(_:)`
- 픽스처: `CtrlComboFixtures.swift` (세 모드 별칭 + 탈출 설정 선행 핀)
- 부수 효과(의도됨): Insert 모드에서 Ctrl-[가 이전의 passthrough 대신 swallow+Normal 전이가 된다 — 시스템 전역에서 Ctrl-[를 쓰는 앱과는 충돌하지만 Vim 별칭의 핵심 용도(Insert 탈출)라 수용

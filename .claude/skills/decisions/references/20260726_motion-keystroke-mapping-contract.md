# 모션 키스트로크 매핑 계약 — 시퀀스 반환 + 근사 3건

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

Keyboard 어댑터의 모션 매핑은 순수 매퍼 `Motion → [KeyStroke]`로 둔다. `KeyStroke`는 `(keyCode, flags)`만 담는 값 타입이고, **반환이 배열인 것이 계약이다** — 모션 1개가 키스트로크 N개의 조합으로 실행될 수 있다(예: 나중에 `w`를 `[Opt-→, Opt-→, Opt-←]` 3타로 개선). CGEvent 변환(keyDown+keyUp 쌍 생성)은 매퍼 밖, 게시 직렬 큐 위에서 한다.

M2 첫 매핑은 전부 단일 키스트로크이며, macOS 텍스트 시스템에 대응 개념이 없는 3곳은 근사한다:

| Motion | 합성 키 | 성격 |
|---|---|---|
| charLeft/charRight, lineUp/lineDown | ←/→, ↑/↓ | 정확 |
| wordBackward | Opt-← | 정확 |
| wordEndForward | Opt-→ | 정확 (macOS Opt-→ = 단어 끝) |
| **wordForward** | **Opt-→** | **근사 — e와 동일 취급** ("다음 단어 시작"이 macOS에 없음) |
| lineStart / lineEnd | Cmd-← / Cmd-→ | 정확 |
| **lineFirstNonBlank** | **Cmd-←** | **근사 — 0과 동일 취급** (첫 비공백 개념이 macOS에 없음) |
| documentStart / documentEnd | Cmd-↑ / Cmd-↓ | 정확 |
| charRightForAppend / lineEndForAppend | → / Cmd-→ | 캐럿 모델에서 l·$와의 구분이 자연 소멸 |

## 배경·근거 (왜)

Vim의 w/e 구분과 `^`는 커서가 "문자 위"에 있는 Vim 모델의 개념이라, 캐럿(문자 사이) 모델을 쓰는 Keyboard 전략에서는 원리적으로 정확 재현이 불가하다 — 정확한 의미는 M5 AX 어댑터(문자 오프셋 직접 조작)의 몫이고, M2는 "가능성 높은 근사로 시작해 도그푸딩으로 검증 후 개선" 방침이다. 매퍼 반환을 처음부터 배열로 두는 것은 그 개선(멀티 스트로크 조합)이 매핑 테이블의 원소 교체만으로 되게 하기 위해서다 — 어댑터·실행기·테스트가 안 바뀐다.

매퍼를 CGEvent에서 분리한 이유: 매핑 로직을 CGEvent 생성 없이 골든 테스트(위 표가 곧 테스트 픽스처)할 수 있고, CGEvent는 비-Sendable이라 게시 큐 위에서 만들어야 한다는 기존 계약([20260726_action-executor-nonisolated-sendable.md](20260726_action-executor-nonisolated-sendable.md))과도 맞물린다. 화살표·수정키 조합은 키코드(123~126 등)가 키보드 레이아웃 무관 고정값이라 레이아웃 이슈가 없다.

`charRightForAppend`/`lineEndForAppend` 전용 케이스([20260712_append-dedicated-motion-cases.md](20260712_append-dedicated-motion-cases.md))는 Keyboard 전략에서는 l·$와 같은 키로 수렴하지만 케이스는 유지한다 — 구분이 의미를 갖는 것은 M5 AX 어댑터부터다.

## 검토한 대안

- **매퍼가 단일 KeyStroke 반환**: 멀티 스트로크 개선 시 시그니처 변경이 전파된다. 기각.
- **w를 처음부터 3타 조합(`Opt-→ Opt-→ Opt-←`)으로**: 커서가 단어 끝에 있을 때 한 단어를 건너뛰는 등 나름의 엣지가 있어 단일 키 근사보다 낫다는 보장이 없다 — 도그푸딩 후 판단. 첫 구현은 단일 키로. 보류.
- **매퍼를 VimActionCore로 이동**: CGKeyCode/CGEventFlags 재발명(자체 타입 + 변환 계층)이 필요해 과잉. 앱 타깃에 둔다. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (Keyboard 어댑터 절)
- 신규 매퍼·어댑터 파일 (M2 구현 예정), 앱 유닛 테스트(골든 테이블)
- M5에서 w/e·^의 정확 의미가 AX로 구현되면 "왜 Keyboard에서는 같이 움직이나"의 답이 이 문서다

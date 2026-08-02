# 전략 디스패치

- **Last updated**: 2026-08-02 (M5 PR-A 구현 반영 — 디스패치 경로 AX 읽기 기반 구축, 소비자는 PR-B부터)

## 현재 구조

엔진에서 온 각 `VimAction`은 전략 디스패처가 앱별 프로파일과 AX 자동 감지(하드 타임아웃 3ms)를 통해 **Accessibility 어댑터** 또는 **Keyboard 어댑터** 중 하나로 라우팅한다. Keyboard 어댑터는 `key-mapping`(요소 인식, 선호 폴백)과 `force-text`(요소 감지 우회, 최후 수단) 두 계열을 가진다.

**과도기 상태 (MVP 구간)**: 실행 계층은 **Keyboard 어댑터부터** 구축한다 — MVP 1단계 동안 번들 기본 전략은 `keyboard`(key-mapping) 고정이며, Accessibility 어댑터·`auto` 프로브·force-text는 MVP 이후 1차 확장에서 들어온다. 아래 선택 플로우는 그 확장까지 완성된 최종 상태다 ([20260725_keyboard-first-mvp-build-order.md](../../decisions/references/20260725_keyboard-first-mvp-build-order.md)). 포커스/컨텍스트 리졸버도 같은 순서로 분해 구축된다: 앱 수준(bundleID) → 요소 수준(AXObserver+focusedRole) → AX 프로브.

M2의 최소 디스패처에서 앱 수준 게이트는 **탭 콜백의 엔진 진입 전**에 판정한다: 최전면 앱이 disable 목록(하드코딩, 초기값 `com.mitchellh.ghostty` — M4에서 `config.yaml`의 앱별 on/off 목록이 교체, [20260801_app-enable-config-yaml-only.md](../../decisions/references/20260801_app-enable-config-yaml-only.md))이면 번역·엔진 없이 원본 키를 통과시키고, 엔진 모드 상태는 동결한다(리셋 없음). 판정 위치는 마커 가드·마스터 토글 가드 뒤, 번역 앞. 최전면 bundleID는 `@MainActor` 캐시가 `NSWorkspace` 앱 활성화 알림으로 갱신하고 콜백은 캐시만 읽는다 — 디스패치 시점 게이트는 삼킨 뒤 실행만 막아 "죽은 키"가 되므로 기각됐다 ([20260726_m2-app-gate-pre-engine-passthrough.md](../../decisions/references/20260726_m2-app-gate-pre-engine-passthrough.md)).

### 선택 플로우 (VimAction마다 실행)

```mermaid
flowchart TD
    VA[VimAction 수신] --> P{"설정 조회<br/>(앱별 on/off는 config.yaml,<br/>전략은 프로파일)"}
    P -->|"앱 off"| Pass[통과 후 중단]
    P -->|"strategy: accessibility"| AX[Accessibility 어댑터]
    P -->|"strategy: keyboard"| KB[Keyboard 어댑터]
    P -->|"strategy: auto"| Probe{"AX 탐지<br/>(형태는 D2에서 결정 —<br/>동기+소캡은 실측 기각)"}
    Probe -->|정상 값| AX
    Probe -->|실패/타임아웃| KM["Keyboard 어댑터<br/>family = key-mapping"]
    AX --> Override{요소별 재정의?}
    KB --> Override
    KM --> Override
    Override -->|"per_element 매칭"| Re[재정의된 전략으로 교체]
    Override -->|없음| Exec[ActionExecutor로 실행]
    Re --> Exec
```

### Accessibility 어댑터

`VimAction` → AX 호출 변환. 예: `move(.charLeft)` → `kAXSelectedTextRangeAttribute`를 `(location-1, 0)`으로 설정, `delete(.line)` → 줄 범위 얻어 `kAXSelectedText`를 `""`로 설정, `yank(.selection)` → `kAXSelectedText` 읽어 `NSPasteboard`에 쓰기.

### Keyboard 어댑터 — 요소 계열(element family)

`ElementFamily`는 `.textArea` / `.textField` / `.nonText` / `.unresolved` 넷이며 리졸버가 보고한다. 앞의 셋이 판정 결과이고 `.unresolved`는 **앱 전환 직후 첫 읽기가 아직 착지하지 않은 상태**다 — 폴백(`.textArea`)과 구분되는 별개 값이며, 걸러내기에서는 `.nonText`와 같은 편에 선다. **계열은 시퀀스를 다변화하지 않는다 — 걸러낼지만 정한다.** `.textField`는 편집·Visual·붙여넣기·undo에서 `.textArea`와 **같은 시퀀스**를 쓴다: 단일행 필드에서 TextArea 시퀀스가 자연 수렴하고(주소창에서 `Shift-↓`는 끝까지 선택된다), 전용 분기는 role 오보고 시 여러 줄 검색창의 `dd` 1줄 삭제를 전체 삭제로 개악한다 — 실패 방향이 비대칭이다 ([20260801_textfield-edit-sequences-scrapped.md](../../decisions/references/20260801_textfield-edit-sequences-scrapped.md)).

- **key-mapping 계열**: 리졸버를 참조해 요소 인식 시퀀스 선택. AX 불가 시 자동 감지가 사용하는 기본 폴백.
- **force-text 계열**: 항상 TextArea 시퀀스 사용. 프로파일 명시 선택 전용, 자동 감지 금지.

**걸러내기 표** — 계열이 실제로 가르는 전부다:

| 액션 | `.textArea` | `.textField` | `.nonText` | `.unresolved` |
|---|---|---|---|---|
| `.move` · `.scroll` | 게시 | 게시 | **게시** | **게시** |
| `.edit` · Visual 4종 · `.paste` · `.undo` · `.redo` | 게시 | 게시 | `nil` 스킵 | `nil` 스킵 |
| `.openLine` (`o`/`O`) | 게시 | **`nil` 스킵** | `nil` 스킵 | `nil` 스킵 |

`.nonText`에서 모션·스크롤이 살아남는 것은 위험 등급을 가르는 축이 "비텍스트인가"가 아니라 **"앱이 이미 아는 명령인가"** 이기 때문이다. Finder에서 `p`는 파일을 붙여넣고 `u`는 파일 조작을 되돌리는 반면, 화살표는 무해하게 흘러가며 리스트 이동·페이지 스크롤로 유용하다 — 엔진이 이미 키를 삼킨 뒤라 스킵은 네이티브 동작으로의 복귀가 아니라 **완전 무동작**이다. `.scroll`이 명령 매퍼 소속인데도 여기 속하는 것은 그 매퍼에서 유일하게 네이티브 명령에 위임하지 않는 액션(화살표 반복)이기 때문이다 ([20260801_non-text-filter-keeps-motion-and-scroll.md](../../decisions/references/20260801_non-text-filter-keeps-motion-and-scroll.md)). 이것이 [20260730_native-command-non-text-ui-hazard.md](../../decisions/references/20260730_native-command-non-text-ui-hazard.md)가 단계 3에 위임한 구조적 해소다.

`.unresolved`가 `.nonText`와 같은 열인 것은 **모르는 동안은 위험 어휘를 보류한다**는 규칙이다. 실측에서 앱 전환 후 ~15~20ms에 도착한 첫 키는 이전 앱 계열로 판정돼 게이트를 그대로 통과했고, TextEdit→Finder 직후의 `u`가 그 창을 타고 `Cmd-Z`로 Finder에 도달했다. 모션·스크롤까지 막지 않는 이유는 이 창이 앱을 옮길 때마다 열려서다 — 화살표를 막으면 "앱을 바꾸면 첫 `j`가 사라진다"가 된다 ([20260801_unresolved-window-after-app-switch.md](../../decisions/references/20260801_unresolved-window-after-app-switch.md)).

**걸러내기 게이트는 `KeyboardAdapter.mapping(for:family:)` 최상단 한 곳**이며 매퍼가 아니다. 같은 자리에 두 번째 축인 **비-QWERTY 레이아웃 가드**가 나란히 선다: `KeyTranslator`가 레이아웃 캐시를 채울 때마다 합성 키코드 4종(`kVK_ANSI_Z/X/C/V`)을 현재 ASCII-capable 레이아웃으로 번역해 기대 문자와 일치하는지 **행동 검사**하고(레이아웃 ID 화이트리스트 아님) 잠금 상자 `hasQwertyCommandKeys`에 캐시하며, 어댑터는 문자 명령 키를 합성하는 액션(`.edit`·`.paste`·`.undo`·`.redo`)을 비-QWERTY에서 보류한다(`Mapping.layoutBlocked`) — AZERTY에서 `u`의 `Cmd-Z`가 `Cmd-W`(창 닫기)로 나가는 데이터 손실 축이다. 화살표·Return만 쓰는 액션(모션·스크롤·openLine·선택)은 레이아웃 무관이라 통과한다 ([20260801_non-qwerty-command-key-layout-guard.md](../../decisions/references/20260801_non-qwerty-command-key-layout-guard.md)). 매퍼에 두면 세 부수효과를 앞설 수 없기 때문이다: `.move`에는 애초에 family가 없고(모션은 계열 무관이 계약), `.edit`은 매퍼 호출 전에 `recordLinewiseEdit()`을 불러 게시하지도 않을 편집을 기억하며, `.paste`는 매퍼 호출 전에 클립보드를 읽어 걸러내기가 "텍스트 없음"(`.skipped`)으로 잘못 집계된다. 매퍼 쪽에는 `.nonText → nil` 봉쇄만 남아 있다(`EditKeyMapper`에서 `.selection` 조기 반환이 계열 분기보다 앞에 있던 함정의 방어선). 걸러내기 스킵은 **미지원(`.unsupported`) 경로로 집계**되고, 요약 로그에 결정된 계열이 함께 실려 단계 4 심사자가 "미구현"과 "의도적 걸러내기"를 구분한다.

키 시퀀스 생성은 **네 순수 매퍼**(`MotionKeyMapper` / `EditKeyMapper` / `VisualKeyMapper` / `CommandKeyMapper`)가 담당하고, 어댑터는 액션을 넷 중 하나로 보내 나온 `[KeyStroke]`를 CGEvent 쌍으로 바꿔 게시한다. 매퍼가 `nil`을 내면 그 액션은 **미지원**이며 스킵+요약 DEBUG 로그로 간다. **네 매퍼 어디도 빈 배열을 반환하지 않는다** — "지원 ⟹ 빈 시퀀스 아님"이 공통 불변식이라, 게시할 것이 없는 경우는 `nil`(정직한 스킵)로 표현한다. 무로그 삼킴 금지가 릴리스 게이트 규칙이기 때문이다. CGEvent 변환은 **액션 단위 all-or-nothing**이다 — 스트로크 하나라도 생성에 실패하면 그 액션 전체를 버리고 error 로그를 남긴다(부분 시퀀스는 편집에서 "선택은 어긋난 채 `Cmd-X`만 나가는" 파괴적 실행이 된다).

어댑터의 스킵은 **세 종류로 갈린다**: 매퍼 `nil` = 미지원(요약 로그에 집계), 지원하지만 이번 입력에는 게시할 것이 없는 경우(사유를 아는 자리에서 자체 로그 — 유일한 사례가 텍스트 없는 클립보드의 `p`), 그리고 비-QWERTY 레이아웃 보류(`layoutBlocked` — 미지원과 **별도 요약** `비-QWERTY 레이아웃 스킵 ×N`). 구분이 필요한 이유는 같다: 섞이면 심사자가 구현된 어휘를 미구현으로 읽는다.

**편집 매퍼** `EditKeyMapper`는 `(Operator, TextRange, ElementFamily) → [KeyStroke]?`이며, 모든 편집이 한 형태다: **범위를 Shift+모션으로 선택한 뒤 오퍼레이터 1타**(delete·change = `Cmd-X`, yank = `Cmd-C` + `←` collapse). change는 엔진이 이미 Insert로 전이해 뒤에 붙일 키가 없다. 선택 스트로크는 모션 매핑 결과의 각 스트로크에 `.maskShift`를 얹어 만들므로, `w`·`^`의 3타 조합도 앵커 고정·엔드포인트 이동으로 그대로 성립한다 — 편집 시퀀스의 모션별 특례는 `cw`→`ce` 하나뿐이다. linewise 반올림은 오퍼레이터별로 갈리고(delete/yank는 개행 포함, change는 줄 유지) 문서 끝에서는 빈 줄 1개가 남는다(`dgg`만 정확 — 감지가 원리적으로 불가). `iw`는 모션과 같은 "끝을 지나친 뒤 시작 복귀" 3타로 앵커를 잡는다(`Opt-→,Opt-←` 후 `Shift-Opt-→` — 캐럿이 단어 시작이어도 그 단어를 잡는다). 오퍼레이터 키만 ANSI 키코드라 QWERTY 계열을 가정한다. `Shift-Cmd-↑/↓`를 블록 이동에 쓰는 앱(Notion)에서는 `d/c/y`+`G`·`gg` 6조합이 파괴적으로 오동작한다 — 회피가 앱 축을 요구해 M4 프로파일까지 수용된 한계다. 문서 경계에서 선택이 접히거나 포화하는 **수용 엣지 5종**(줄 끝 `x` 줄 병합, 첫 줄 `dk` 아래 줄 삭제, 마지막 단어 `dw` 반전, 마지막 줄 `dgg` 누락, 빈 선택+오퍼레이터)과 소프트 랩 문단의 **시각 줄 단위** linewise(랩 문단에서 `dd`가 화면 행만 삭제)는 무상태 전제상 감지 불가로 수용됐다 — 정확화는 M5 AX 읽기 혼용의 몫. `ElementFamily`는 리졸버가 채우지만 이 매퍼에서 시퀀스를 가르지는 않는다 — `.textArea`와 `.textField`가 같은 분기이고 `.nonText`는 `nil` 봉쇄다(위 걸러내기 표). 모션 매퍼에는 family가 없다(화살표 이동은 계열 무관). [20260727_edit-keystroke-mapping-contract.md](../../decisions/references/20260727_edit-keystroke-mapping-contract.md), [20260727_linewise-newline-rounding.md](../../decisions/references/20260727_linewise-newline-rounding.md), [20260727_yank-collapse-to-range-start.md](../../decisions/references/20260727_yank-collapse-to-range-start.md), [20260727_operator-key-ansi-layout-assumption.md](../../decisions/references/20260727_operator-key-ansi-layout-assumption.md), [20260727_inner-word-anchor-via-word-end.md](../../decisions/references/20260727_inner-word-anchor-via-word-end.md), [20260727_notion-cmd-shift-vertical-conflict.md](../../decisions/references/20260727_notion-cmd-shift-vertical-conflict.md), [20260728_edit-boundary-saturation-accepted-edges.md](../../decisions/references/20260728_edit-boundary-saturation-accepted-edges.md), [20260728_linewise-visual-line-wrap-accepted-edge.md](../../decisions/references/20260728_linewise-visual-line-wrap-accepted-edge.md).

**Visual 매퍼** `VisualKeyMapper`는 `(VimAction, ElementFamily) → [KeyStroke]?`로 선택 **세션**(진입·확장·wise 전환·이탈)만 담당한다 — 선택에 오퍼레이터를 적용하는 `.edit(op, .selection)`은 `EditKeyMapper`의 몫이다(선택 시퀀스 없이 `Cmd-X`/`Cmd-C` 1타, 계열 분기 밖). **어댑터는 wise 상태를 들지 않는다**: `extendSelection(Motion)`은 `MotionKeyMapper.selectionStrokes(for:)`(모션 스트로크마다 Shift union)의 순수한 재사용이고 linewise 줄 반올림은 적용하지 않는다 — 편집의 범위 선택과 같은 함수를 쓰므로 **모션 매핑이 개선되면 편집과 Visual이 동시에 따라온다**. 시퀀스: `v`=`Shift-→`(Vim의 inclusive 시맨틱 — 무게시면 `vd`/`vy`가 무동작이고 이탈 `←`가 캐럿을 표류시킨다), `V`=`Cmd-←, Shift-↓`(`dd` 접두와 동일), `v`→`V`=`Shift-↓, Shift-Cmd-←`(포커스 줄만 반올림 — 앵커는 앱에 박혀 손댈 수 없다), `V`→`v`=`nil`(반올림에 역연산 없음), `clearSelection`=`←`(collapse 전담 — 그래서 `.selection` yank는 `Cmd-C`만 낸다). 이는 엔진이 문서화한 "앵커·범위는 어댑터 상태" 계약으로부터의 **의도적 이탈**이며, `V` 세션에서 Vim과 충실히 일치하는 것은 `j`·`0`·`G`와 오퍼레이터뿐이다(후진 확장은 앵커가 점이라 원리적으로 불가). **후진 확장은 charwise에서도 어긋난다** — 진입의 `Shift-→`가 모션의 출발점을 앵커 P가 아니라 P+1로 밀어, 단어 경계 모션의 착지가 한 단어 어긋난다(`vb`·`vh`는 빈 선택). 앵커를 옮겨도 포커스 출발점은 그대로라 상태로 넘을 수 없고, 실패 모드가 "선택이 안 생긴다"로 눈에 보여 수용됐다. [20260728_visual-charwise-entry-inclusive-selection.md](../../decisions/references/20260728_visual-charwise-entry-inclusive-selection.md), [20260728_visual-extend-stateless-no-linewise-rounding.md](../../decisions/references/20260728_visual-extend-stateless-no-linewise-rounding.md), [20260728_visual-switch-wise-focus-end-rounding.md](../../decisions/references/20260728_visual-switch-wise-focus-end-rounding.md), [20260728_visual-clear-selection-collapse-left.md](../../decisions/references/20260728_visual-clear-selection-collapse-left.md), [20260728_visual-charwise-backward-origin-shift.md](../../decisions/references/20260728_visual-charwise-backward-origin-shift.md).

**명령 매퍼** `CommandKeyMapper`는 **네이티브 명령 위임 계열**(`o`/`O`·`p`/`P`·`u`/`Ctrl-r`·스크롤)을 담당한다 — 모션의 캐럿 이동이나 편집의 "선택 후 오퍼레이터"와 달리 앱이 이미 아는 명령 키 하나에 위임하고, 우리가 조립하는 것은 위치를 잡는 접두뿐이다(접두는 전부 `MotionKeyMapper` 재사용이라 모션 매핑 개선이 함께 전파된다). 진입점이 2개인 것은 붙여넣기만 wise라는 추가 입력이 필요하기 때문이다: `keyStrokes(for:family:)`(openLine·undo·redo·scroll)와 `pasteStrokes(before:count:wise:family:)`. 시퀀스: `o`=`Cmd-→, Return`, `O`=`Cmd-←, Return, ↑`(개행이 현재 줄을 아래로 밀고 새 빈 줄로 복귀 — `↑, Cmd-→, Return`은 첫 줄에서 `↑`가 no-op이라 조용히 `o`로 퇴행해 기각), `u`=`Cmd-Z`, `Ctrl-r`=`Shift-Cmd-Z`, 스크롤만은 **위임할 네이티브 명령이 없어** 이 매퍼에서 유일하게 명령 키를 쓰지 않는다 — `↓`/`↑` 반복(half 15줄·full 30줄)이다. macOS에는 캐럿을 한 뷰포트만큼 옮기는 키 프리미티브가 없고(`Opt-Page*` 무동작, `Shift-PageDown`은 1줄 확장, 휠은 마우스 포인터 아래 창으로 배달), `PageUp`/`PageDown`은 뷰만 옮겨 **다음 모션 한 번에 스크롤이 원위치한다** — Vim 레이어는 모든 키가 모션이라 사실상 죽은 기능이었다. 줄 수는 뷰포트 높이를 모르는 상태의 근사값이며 M4 프로파일의 조절값, M5에서 AX `AXVisibleCharacterRange`로 정확해진다, 붙여넣기는 위치 접두 1회 + `Cmd-V`×count(charwise `p`=`→`·`P`=접두 없음, linewise `p`=`Cmd-→, →, Cmd-←`·`P`=`Cmd-←`). linewise `p`의 꼬리 `Cmd-←`는 멱등 보정자다 — 마지막 줄에서 `→`가 포화하면 그것 없이는 붙여넣기가 마지막 줄에 이어붙어 텍스트를 훼손한다. **붙여넣기 단위(wise)는 `PasteWiseResolver`가 정한다** — 어댑터가 주입받는 유일한 상태 보유 협력자이며 게시 직렬 큐가 단독 소유한다. 우선순위는 "우리가 아는 것 먼저"다: 어댑터가 줄 단위 편집(`op != .change` && `.line`/`.linewiseMotion`)을 게시할 때 그 시점의 `NSPasteboard.changeCount`와 함께 linewise를 기억해 두고, 붙여넣기 시점에 카운트가 **정확히 1 늘었으면** 그 기억을 쓴다. 그 외에는 순수 함수 `PasteWise(clipboardText:)`의 **끝 개행 휴리스틱으로 폴백**한다 — 이 휴리스틱은 이제 외부에서 복사된 내용 전담이다. 앱이 줄을 복사해도 끝 개행을 붙이지 않는 경우(Notion)가 실측돼, 우리 `dd`/`yy` 뒤의 `p`가 charwise로 오판되던 것이 이 우선순위로 해소된다. 패스트보드 접근은 전부 `Clipboard`(주입 기본값)가 맡아 매퍼 순수성이 유지되고 골든이 개발자 클립보드에 의존하지 않는다. 텍스트가 아예 없으면 기억 여부와 무관하게 정직한 스킵이다. 수용 편차: charwise `p`는 줄 끝에서 다음 줄 시작에 붙여넣고, charwise `P`는 접두가 없어 살아 있는 선택을 덮어쓰며, `3p`는 undo 3단위이고, 소프트 랩 문단에서 `O`는 빈 줄을 아예 만들지 못한다. `Return`이 전송인 앱(Slack류 컴포저)은 M4 프로파일 몫이고, 비-QWERTY의 `Cmd-Z`(AZERTY에서 `Cmd-W` = 창 닫기)는 어댑터의 레이아웃 가드가 보류한다(위 걸러내기 게이트 문단). [20260730_command-key-mapper-scope.md](../../decisions/references/20260730_command-key-mapper-scope.md), [20260730_openline-return-sequence.md](../../decisions/references/20260730_openline-return-sequence.md), [20260730_paste-wise-trailing-newline-heuristic.md](../../decisions/references/20260730_paste-wise-trailing-newline-heuristic.md), [20260730_paste-wise-from-our-own-edit.md](../../decisions/references/20260730_paste-wise-from-our-own-edit.md), [20260730_scroll-arrow-repetition.md](../../decisions/references/20260730_scroll-arrow-repetition.md), [20260730_cmd-z-ansi-layout-escalation.md](../../decisions/references/20260730_cmd-z-ansi-layout-escalation.md).

**모션 매핑**은 순수 매퍼 `Motion → [KeyStroke]`(`(keyCode, flags)` 값 타입)가 담당한다 — **배열 반환이 계약**이라 모션 1개를 키스트로크 N개 조합으로 실행하는 확장이 매핑 테이블 원소 교체만으로 된다. CGEvent 변환(keyDown+keyUp 쌍)은 매퍼 밖, 게시 직렬 큐 위에서 한다. Keyboard 전략은 캐럿(문자 사이) 모델이라 macOS에 프리미티브가 없는 곳은 조합·수렴으로 처리한다: `wordForward`(w)는 `Opt-→,Opt-→,Opt-←` 3타, `lineFirstNonBlank`(^·I)는 `Cmd-←,Opt-→,Opt-←` 3타(단어 끝을 지나친 뒤 시작으로 복귀 — 수용 엣지는 결정 문서 참조, 탭 들여쓰기의 ^·I는 Chromium 계열에서 0으로 퇴행), `charRightForAppend`/`lineEndForAppend`는 l·$와 자연 수렴(케이스는 M5 AX용으로 유지) — [20260726_motion-keystroke-mapping-contract.md](../../decisions/references/20260726_motion-keystroke-mapping-contract.md), [20260726_word-forward-first-nonblank-multi-stroke.md](../../decisions/references/20260726_word-forward-first-nonblank-multi-stroke.md), [20260726_tab-indent-first-nonblank-chromium-edge.md](../../decisions/references/20260726_tab-indent-first-nonblank-chromium-edge.md). 합성 이벤트는 keyDown·keyUp 모두 flags를 **명시 대입**한다(빈 flags 포함) — 소스 nil 이벤트의 flags 기본값은 실행 시점의 물리 modifier 상태라, 대입이 없으면 사용자가 누르고 있던 Shift가 새어 들어간다 ([20260726_shift-leak-event-flags-sufficient.md](../../decisions/references/20260726_shift-leak-event-flags-sufficient.md)).

### 포커스/컨텍스트 리졸버

`FocusedElementResolver`(`@MainActor`)가 포커스 요소의 계열을 캐싱해 키 입력마다 AX를 재탐지하지 않는다. **탭 콜백은 캐시만 읽고**(앱 게이트와 같은 형태), 계열은 `.replace` 시점에 콜백이 읽어 디스패치 페이로드로 실린다 — 게시 큐가 나중에 읽으면 버스트 도중 옮겨간 포커스를 기준으로 걸러진다.

갱신 트리거는 둘이며 **둘 다 실기기에서 살아 있음이 확인됐다**: `NSWorkspace` 앱 활성화 알림(옵저버를 새 앱으로 갈아탄다)과 `AXObserver`의 `kAXFocusedUIElementChangedNotification`(런루프 소스는 메인). 후자는 앱을 바꾸지 않는 **앱 내부** 포커스 이동도 잡는다 — Chrome 옴니박스→페이지 본문 클릭, Finder 리스트→`Cmd-F` 검색창이 각각 전이로 관측됐다. 그래서 콜백은 캐시만 읽어도 충분하며, 라이브 AX 읽기가 필요한 케이스는 도그푸딩 8항목 어디에서도 나오지 않았다 ([20260801_cache-only-callback-confirmed-sufficient.md](../../decisions/references/20260801_cache-only-callback-confirmed-sufficient.md)). **AX 호출은 전용 직렬 큐 위에서만** 하고 메인 스레드는 AX를 아예 호출하지 않는다 — 콜백 경량 불변식보다 강한 보장이며, 그래서 타임아웃 값이 탭 안정성과 무관하다. 타임아웃은 **50ms**다: 실측상 앱 최초 접촉의 focusedRole 읽기는 ~20ms가 걸리고 **3ms 캡에서는 앱 6종 전부 실패**해, 3ms를 지키면 앱 전환 직후 첫 판정이 반드시 폴백이 된다(리졸버가 겨냥한 순간이 정확히 거기다). 큐로 넘기는 값은 `pid_t` 하나뿐이라 비-`Sendable` `AXUIElement`가 격리를 건너지 않는다. 앱 전환 순간 캐시는 **즉시 리셋**되고(이전 앱 계열을 들고 있으면 편집기 진입 직후 편집이 통째로 죽는다) 늦게 착지한 읽기는 토큰 비교로 폐기된다 ([20260801_focused-role-cache-shape.md](../../decisions/references/20260801_focused-role-cache-shape.md)). 리셋이 채우는 값은 폴백이 아니라 `.unresolved`이며, 읽을 앱이 없을 때(pid `nil`)만 폴백이 곧 최종 판정이다 — 착지할 읽기가 애초에 없기 때문이다.

**계열 판정은 role이 아니라 `AXSelectedTextRange` 노출 여부**다 — `AXUIElementCopyAttributeNames` 목록에 있는가로 보며, 값 조회는 판별자가 되지 못한다(Finder도 `.success`를 돌려준다). role은 텍스트로 판정된 뒤 TextArea/TextField를 가르는 데만 쓴다. role 화이트리스트가 기각된 이유는 실측이다: **Finder는 리스트에 포커스가 있어도 `AXGroup`을 보고**하는데 그 role은 Chromium·Electron이 편집 가능한 영역에도 붙여, 텍스트로 두면 Finder를 못 막고 비텍스트로 두면 웹 앱이 죽는다. 어느 단계에서 실패하든(포커스 요소 없음·속성 조회 실패·미지 role) **폴백은 `.textArea`** 이며, 걸러내기는 확실한 보고에만 발동한다 — AX가 트리를 열지 않는 VS Code가 그 경로의 실증이다 ([20260801_element-family-classification-table.md](../../decisions/references/20260801_element-family-classification-table.md), [20260801_resolver-fallback-defaults-to-text-area.md](../../decisions/references/20260801_resolver-fallback-defaults-to-text-area.md)). `selectedRange`는 캐싱하지 않는다 — 키마다 변해 캐시가 원리적으로 불가하며, 아래 디스패치 경로 읽기가 담당한다.

### 디스패치 경로 AX 읽기 (M5 혼용의 읽기 기반)

**과도기 상태 (소비자 미배선)**: 읽기 기반은 구축됐고 **아직 아무 매퍼도 결과를 읽지 않는다** — 소비는 PR-B·C가 붙인다. 그래서 AX 호출은 현재 런타임에 0건이고, 그 사실을 어댑터 테스트가 계약으로 고정한다(소비가 붙으면 그 테스트가 뒤집혀 짚어 준다).

정확 오프셋이 필요한 시퀀스(단어 경계, 경계 포화, Visual 앵커 등)를 위해 **게시 직렬 큐 위에서** 동기 AX 읽기를 한다. 콜백·메인 스레드는 계속 AX 무접촉이다 ([20260802_dispatch-read-on-posting-queue.md](../../decisions/references/20260802_dispatch-read-on-posting-queue.md), [20260802_focused-text-read-api-shape.md](../../decisions/references/20260802_focused-text-read-api-shape.md)).

- **lazy 읽기**: `KeyboardAdapter.execute`가 **액션마다** `FocusedTextSnapshot`을 새로 만들고, 처음 물을 때 읽어 그 액션 동안 기억한다 — 같은 버스트의 앞 액션이 캐럿을 옮기므로 실행 직전 값만 정확하고(계열 스냅샷과 시점 요구가 정반대), 한 액션 안의 여러 소비자가 왕복을 곱하지 않는다. **실패도 기억한다** — 그러지 않으면 타임아웃 나는 앱에서 물음 수만큼 캡(50ms)을 문다.
- **pid는 키 입력 시점 스냅샷** — `DispatchContext.processID`에 실려 오고 출처는 `FocusedElementResolver.observedProcessID`다(게이트가 아니다 — 같은 곳에서 나온 `family`와 짝이라 둘이 다른 앱을 가리킬 수 없다). `AXUIElement`는 큐 위에서 생성한다 (격리를 건너는 비-`Sendable` 값 없음).
- **프리미티브는 `AXSelectedTextRange` + `AXNumberOfCharacters` + `AXStringForRange`(캐럿 ±256, 문서 경계 clamp; 선택이 범위면 양 끝 바깥으로)**. `AXValue` 전체 읽기는 키당 경로 금지 — 비용이 문서 크기에 비례한다 (실측 100만자 3.5~5.3ms vs 창 읽기 크기 무관 ~0.2ms). 반환 타입 `FocusedText`는 `selection`·`characterCount`·`window`에 **`windowRange`** 를 더한 넷이다 — 마지막이 없으면 절대↔상대 오프셋 변환이 안 된다.
- **실패·타임아웃은 현행 무상태 시퀀스로 폴백** — 정확화만 포기하고 실행은 한다. 스킵도, 실행 실패 보고도 아니다. 실패는 단계·에러코드를 가리지 않는 **단일 `nil`** 이며(pid 없음도 같다), 소비자의 폴백이 하나뿐이라 갈라 봐야 쓸 데가 없다. Slack·VS Code처럼 포커스 요소를 노출하지 않는 앱은 이 폴백이 상시 경로다.

읽기 비용 실측(웜 p50): TextEdit ~0.03ms, Notion `selectedRange` **7.1ms(max 16)** — 후자가 콜백 배치를 기각시킨 수치다. 리더(`FocusedTextReader`)는 어댑터에 주입한다 (골든 테스트가 실기기 AX 없이 읽기 결과를 주입하는 seam — `ActionExecutor.postEvent`·`PasteWiseResolver`와 같은 형태). 타임아웃과 포커스 요소 조회는 **`AXRead`가 단독 소유**해 리졸버 경로와 디스패치 경로가 같은 상수를 쓰는 것이 코드로 강제된다.

## 불변식·계약

- **AX 호출은 콜백·메인 스레드에 들어오지 않는다** — 리졸버는 전용 큐, 디스패치 경로 읽기는 게시 큐. 탭 생존을 지키는 것은 타임아웃 값이 아니라 이 배치다. 메시징 타임아웃은 **경로 불문 50ms 단일 상수**이며 병적 정지가 큐를 잡아두는 것을 자르는 차단기다 — 실패 반환은 캡+2ms로 바운드됨이 실측됐고, 유일한 예외는 프로세스 생애 최초 AX 호출 1회(~23ms, 리졸버가 앱 시작 직후 흡수) ([20260802_ax-read-timeout-50ms-supersedes-3ms.md](../../decisions/references/20260802_ax-read-timeout-50ms-supersedes-3ms.md)).
- `AXValue` 전체 읽기는 키당 경로에 넣지 않는다 — 비용이 문서 크기에 비례한다.
- `force-text`는 프로파일에서 명시적으로만 선택하며, 자동 감지가 선택하는 일은 없다.

## 근거 요약

올바른 AX 앱에서는 AX가 정밀하지만 너무 많은 앱이 AX 지원을 거짓말하므로, 자동 감지 + Keyboard 폴백의 이중 전략이 필요하다.

- 관련 결정: [20260712_ax-keyboard-strategy-dispatch.md](../../decisions/references/20260712_ax-keyboard-strategy-dispatch.md)

## 미결 질문 (결정 시 decisions에 기록 후 이 파일 갱신)

- 일회성 Accessibility → Keyboard 다운그레이드 수정 키 (kindaVim의 `fn` 방식) — 채택 여부와 키 선택.
- "AX 거짓말" 감지 휴리스틱 (왕복 테스트, 번들 거부 목록) — `strategy: auto` 신뢰 전 결정.
- `key-mapping` → `force-text` 자동 폴백 휴리스틱 존재 여부.
- `strategy: auto` 프로브의 구체 형태 — 동기+소캡은 실측 기각됐고, 비동기 캐시형(리졸버 선례)이 유력. D2 착수 시 결정.

## 관련

- 선택 알고리즘 요구사항: 워크스페이스 `docs/prd.md` §9
- 프로파일 스키마: [profiles-and-config.md](profiles-and-config.md)
- 실행/재진입: [reentrancy-and-safety.md](reentrancy-and-safety.md)
- 테스트: 기록된 `AXUIElement` 픽스처로 회귀 테스트, 어댑터는 골든 출력 테스트 (워크스페이스 `docs/architecture.md` §7)

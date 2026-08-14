# 메뉴바 disabled 앱 인디케이터 (minus.square)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-14

## 결정

앱 게이트가 켜진 앱(= `config.yaml` `apps:`에서 `false`)이 앞에 있을 때를 **메뉴바 글리프 `minus.square`** 로 표시한다. 세 가지가 한 결정이다:

1. **글리프는 `minus.square`** — 미채움(비-fill) SF Symbol. `menuBarAccessibilityLabel`에 대응 문구를, `menuBarShowsVisualLineGlyph`에 같은 우선순위 조건을 함께 넣는다.
2. **표시 판정 축은 `FrontmostAppGate.lastNonSelfBundleID`** (비자신 캐시)다 — **게이트 판정 축은 계속 `frontmostBundleID`**. 판정/표시 축 분리이며, 메뉴바 편의 기능([20260802_menubar-frontmost-app-conveniences.md](20260802_menubar-frontmost-app-conveniences.md), [20260802_frontmost-gate-non-self-cache-observable.md](20260802_frontmost-gate-non-self-cache-observable.md))과 같은 편이다.
3. **글리프 우선순위**: 탭 고장(`square.dashed`) > 마스터 토글 off(`square.slash`) > **앱별 disabled(`minus.square`)** > Secure Input(`lock.square`) > 모드 글리프.

## 배경·근거 (왜)

disabled 앱이 최전면일 때 게이트는 번역·엔진 진입 전에 키를 통과시키고 **모드 상태를 동결한다** ([20260726_m2-app-gate-pre-engine-passthrough.md](20260726_m2-app-gate-pre-engine-passthrough.md)). 그래서 메뉴바에는 그 앱에 들어가기 직전의 모드 글리프가 그대로 얼어붙어 남는다 — 화면은 "Normal 모드로 가로채는 중"이라고 말하는데 실제로는 아무것도 가로채지 않는다. 지금 disable 여부를 확인하는 유일한 방법이 메뉴를 열어 'Disable for This App' 체크마크를 보는 것인데, 그건 이미 의심이 든 사람만 하는 행동이다. 가로채기가 꺼진 다른 두 상태(토글 off·탭 고장)는 전부 글리프가 있으므로, 앱별 off만 글리프가 없는 것이 오히려 예외다.

**`minus.square`를 고른 이유** (이 머신에서 `NSImage(systemSymbolName:)` 존재 확인 완료):

- **미채움이 기존 축과 부합한다.** fill은 "키 차단 여부" 축이다(Normal/Visual은 fill, 통과 모드 Insert는 미채움). disabled는 키가 그대로 통과하는 상태이므로 미채움이 맞다.
- **글자=모드 어휘와 충돌하지 않는다.** `n`/`i`/`v`/`Vl`은 모드가 살아 있을 때의 어휘고, `minus`는 글자가 아니라 기호라 "모드가 없다"를 말한다.
- **다른 비-모드 글리프와 눈으로 구분된다** — `square.dashed`(고장)·`square.slash`(마스터 off)·`lock.square`(Secure Input) 어느 것과도 형태가 겹치지 않는다.

**표시 축이 `lastNonSelfBundleID`인 이유**: 메뉴바를 클릭하면 VimAction 자신이 최전면이 되어 `frontmostBundleID`가 자기 자신으로 바뀐다. 표시를 그 축에 걸면 사용자가 아이콘을 누르는 순간 인디케이터가 사라져 "눌렀더니 상태가 바뀌었다"로 읽히고, 바로 아래 메뉴의 'Disable for This App' 체크마크(비자신 캐시 기반)와도 어긋난다. 두 축이 갈리는 것은 각 축이 답하는 질문이 다르기 때문이다 — 게이트는 "**지금 이 키를 삼켜도 되는가**"(반드시 실제 최전면), 표시는 "**사용자가 방금까지 쓰던 앱은 무엇인가**"(비자신 캐시). `lastNonSelfBundleID`로 게이트를 판정하면 다른 앱으로 갔는데 disable이 따라오는 오동작이 된다.

**disabled를 Secure Input보다 위에 두는 이유**: Secure Input은 일시적 억제라 `lock.square`가 "풀리면 곧 재개된다"를 함의한다. 그런데 이 앱에서는 SEI가 풀려도 가로채지 않는다 — 사용자가 그렇게 설정했기 때문이다. 사용자 의도(영구)가 OS의 일시 상태보다 앞서야 한다는 점에서, 토글 off가 Secure Input보다 앞서는 것과 **같은 논거**다 ([20260719_secure-input-status.md](20260719_secure-input-status.md)). 반대로 disabled가 토글 off·탭 고장보다 아래인 것도 같은 사다리다: 그 둘은 앱과 무관하게 전역으로 가로채기가 없는 상태라 더 넓다.

**`menuBarShowsVisualLineGlyph`도 같은 조건을 받아야 한다**: 이 파생은 모드 글리프가 실제로 표시되는 조건에서만 참이어야 한다는 계약이다(SF Symbol이 아닌 커스텀 "Vl" 이미지로 렌더 경로가 갈리기 때문). 빠뜨리면 Visual-line 상태로 disabled 앱에 들어갔을 때 동결된 "Vl"이 그대로 남아 이 기능이 그 한 케이스에서만 조용히 무력해진다.

## 검토한 대안

- **`square.slash`로 마스터 off와 같은 글리프 재사용**: 기각 — "전역으로 껐다"와 "이 앱에서만 껐다"는 사용자가 취할 행동이 다르다(전자는 메뉴바 토글, 후자는 `config.yaml`/'Disable for This App'). 같은 글리프면 그 구분이 사라진다.
- **fill 계열(`minus.square.fill`)**: 기각 — fill 축이 "키를 차단한다"를 뜻하므로 통과 상태에 fill을 쓰면 축이 뒤집힌다.
- **표시 축을 `frontmostBundleID`(게이트와 동일)로 통일**: 기각 — 메뉴바 클릭 시 인디케이터가 흔들리고 메뉴 체크마크와 어긋난다. 축을 하나로 합치는 단순함보다 "둘이 항상 일치한다"가 크다.
- **disabled를 Secure Input 아래에 두기**: 기각 — 위 근거대로 `lock.square`가 오해를 준다. (탭 고장·토글 off 위로 올리는 것도 기각 — 더 넓은 상태가 이겨야 한다.)

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (완화책 ⑤ 표시 우선순위), [profiles-and-config.md](../../architecture/references/profiles-and-config.md) (비자신 캐시의 두 번째 소비자)
- 코드: `VimAction/AppState.swift` (`menuBarGlyph`·`menuBarShowsVisualLineGlyph`·`menuBarAccessibilityLabel`)
- 재렌더 배선은 추가 코드가 없다 — `FrontmostAppGate`가 이미 `@Observable`이고 라벨이 `AppState` 경유로 읽으므로 관찰이 따라온다.
- [20260719_secure-input-status.md](20260719_secure-input-status.md)의 우선순위 3단(고장 > 토글 off > SEI)은 **뒤집히지 않는다** — 그 셋의 상대 순서는 그대로고 사이에 한 단이 삽입될 뿐이다. supersede가 아니다.

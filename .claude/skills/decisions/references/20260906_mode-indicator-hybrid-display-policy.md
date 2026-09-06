# 온스크린 모드 인디케이터 표시 정책 — 전환 시 순간 표시 + 비-Insert 상시 배지

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-09-06

## 결정

PRD §7.7·로드맵 Stage 4의 "선택적 온스크린 HUD 모드 인디케이터"를 **두 겹의 오버레이 라벨**로 구현한다.

1. **순간 표시(transient)**: 모드가 바뀔 때마다(Insert 진입 포함) 라벨 알약("NORMAL"·"INSERT"·"VISUAL"·"V-LINE")을 캐럿 근처에 약 1초 띄우고 페이드아웃한다. 상시 배지보다 한 단계 크고 진하다.
2. **상시 배지(persistent)**: **Insert가 아닌 모드**(Normal·Visual·Visual Line) 동안 작은 라벨 알약이 포커스 요소 모서리에 계속 붙어 있다. **Insert는 아무것도 표시하지 않는다.**
3. **표시 조건은 메뉴바 사다리를 재사용**한다 — `MenuBarIndicator.resolve`가 `.mode`일 때만 보이고, 탭 고장·마스터 off·앱별 disabled·Secure Input에서는 둘 다 숨긴다.
4. **색만으로 구분하지 않는다** — 라벨 텍스트가 항상 동반된다(PRD 접근성 NFR).
5. **화면 테두리**(화상회의 공유 표시 같은 프레임)는 기본이 아니라 **설정에서 고르는 대체 스타일**로 두고, 3단계에서 추가한다.

앵커를 어디에 두는가·언제 갱신하는가는 별도 결정 [20260906_mode-indicator-anchor-ladder-event-driven.md](20260906_mode-indicator-anchor-ladder-event-driven.md)이다.

## 배경·근거 (왜)

메뉴바 글리프는 시야 밖이라 "지금 어느 모드인가"를 사실상 알려주지 못한다. 사용자가 겪는 문제는 두 갈래이고 하나의 표시로는 둘 다 풀리지 않는다.

- **전환 확인** ("방금 Esc가 먹었나?"): 전환 직후 한 번 보이면 충분하다. macOS가 입력 소스 전환 때 캐럿 아래에 잠깐 띄우는 인디케이터와 같은 방식이다. Insert 진입도 뜨게 해야 `i`·`a`·`Esc` 전부가 확인된다.
- **사후 인지** ("딴 데 갔다 와서 지금 Normal이었나?"): 순간 표시는 이미 사라진 뒤라 소용없다. 이때 무심코 `x`·`dd`가 나가 글이 지워지는 사고가 난다. 모드는 전역이라 앱을 옮겨도 Normal이 유지되므로 이 사고는 앱 전환 뒤에 특히 잦다. Vim이 커서 모양으로 상태를 상시 노출하는 것, macOS가 Caps Lock이 켜진 동안 표시를 남기는 것과 같은 논리로 **위험한 모드에 있는 동안만** 상시 표시한다.
- **Insert 무표시**: Insert는 기본 상태이자 "그냥 타이핑하면 되는" 상태라 표시가 있으면 소음이다. 상시 배지가 "지금 위험한 모드다"를 뜻하려면 기본 상태에는 없어야 한다.
- **메뉴바 사다리 재사용**: 사다리 위 상태(disabled 앱·Secure Input 등)에서 모드 라벨을 띄우면 [20260814_menubar-disabled-app-indicator.md](20260814_menubar-disabled-app-indicator.md)가 메뉴바에서 없앤 "가로채지 않는데 Normal이라고 말하는" 거짓말을 화면 한가운데서 되풀이하게 된다.

## 검토한 대안

- **순간 표시만**: 사후 인지 문제를 못 푼다 — 이 기능의 핵심 사고(Normal인 줄 모르고 타이핑)가 그대로 남는다.
- **상시 표시만(Insert 포함 전 모드)**: 전환 순간의 피드백이 약하고, Insert까지 항상 떠 있으면 배지가 배경 소음이 되어 정작 Normal일 때 눈에 안 띈다.
- **화면 테두리를 기본으로**: 구현은 가장 쉽지만 계속 켜진 색 프레임은 피로가 크고, 색만으로 구분하면 접근성 NFR을 어긴다. 선택 스타일로만 둔다.
- **kindaVim식 "Viming 중인 창 하이라이트"**: 창 단위 표시는 어느 입력칸인지·어느 모드인지를 말하지 못한다. 앵커 사다리의 창 폴백으로만 흡수한다.

## 영향 범위

- 갱신한 architecture reference: 없음 — 오버레이 컴포넌트는 아직 코드에 없다. **PR 1 머지 시 신규 reference(오버레이 컴포넌트·표시 사다리·앵커 갱신 트리거)를 추가**한다 (플랜 [20260906_onscreen-mode-indicator.md](../../plans/references/20260906_onscreen-mode-indicator.md)에 항목 있음).
- 코드: 신규 오버레이 컴포넌트(앱 셸), `AppState`/`MenuBarIndicator`의 두 번째 소비자, `EventTapController.mode` 관찰.
- PRD §7.7의 "커서 근처의 작은 HUD"는 이 결정으로 구체화된다. 설정 소유권은 [20260906_mode-indicator-settings-in-userdefaults.md](20260906_mode-indicator-settings-in-userdefaults.md).

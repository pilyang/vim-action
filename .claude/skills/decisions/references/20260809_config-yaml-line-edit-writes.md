# UI 쓰기는 라인 편집으로 허용 (재직렬화는 계속 금지)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-09

## 결정

"설정 UI는 YAML을 쓰지 않는다"를 **폐기가 아니라 범위 축소**한다.

- **계속 금지**: 사용자 파일의 **재직렬화**(파싱 → 수정 → Yams dump). 주석·키 순서·서식이 통째로 날아간다.
- **새로 허용**: **라인 단위 텍스트 편집** — 값 토큰 교체 / 한 줄 삽입 / 파일 끝 블록 추가. 첫 적용 대상은 메뉴바 'Disable for This App' 토글(`config.yaml`의 `apps:` 항목 하나).
- Settings 창 자체는 여전히 읽기 전용이다(표시 + 파일 열기). 쓰기 진입점은 메뉴바 토글 **하나**뿐이다.

쓰기 경로는 **안전 계약 3종**을 함께 갖는다. 이 셋은 편의 기능이 아니라 결정의 일부다 — 셋 중 하나라도 빠지면 위 범위 축소를 승인할 근거가 사라진다.

1. **에러 상태에서는 쓰지 않는다.** 마지막 로드에 `ConfigError`가 있으면(= 직전 유효 설정으로 돌고 있으면) 파일을 건드리지 않고 거부한다. 사용자가 고치려던 원본과 우리 편집이 섞이면 안 된다. 메뉴 토글은 이 상태에서 `.disabled`라 클릭 전에 보인다.
2. **애매하면 `nil` — 손대지 않는다.** 순수 함수 `settingAppEnabled(in:bundleID:enabled:)`는 실패가 아니라 "안전하게 손대지 않음"으로 `nil`을 돌린다: 최상위 `apps:`가 둘 이상, 항목이 둘 이상, `apps: {}` 같은 flow 형태, 인용이 필요한 bundle id, 원본이 이미 파싱 불가. **그리고 반환 직전에 결과를 `GlobalConfigParser`로 실제 파싱해, 에러가 없고 apps 맵이 정확히 "원본 + 이 항목"인지 증명한 뒤에만 돌려준다.**
3. **실패는 파일 열기로 폴백한다.** 쓰기가 어느 단계에서 막히든 알림 + `config.yaml` 열기로 이어진다. 토글 클릭이 조용한 무동작이 되면 사용자는 앱이 고장 났다고 읽는다.

## 배경·근거 (왜)

**주력 플로우가 7단계였다.** 메뉴바에서 최전면 앱의 bundle id를 보고 복사할 수는 있었지만, 실사용에서 가장 자주 하는 "이 앱에서 Vim 끄기"는 Copy Bundle ID → Preferences… → Open config.yaml → 에디터에서 `apps:` 찾아 붙여넣고 `: false` → 저장 → Reload Config로, 표면 3개(메뉴바→설정창→에디터→메뉴바)를 왕복했다. 반면 **부차적** 플로우인 프로파일 생성은 메뉴에서 원클릭이었다 — 주력과 부차가 뒤집혀 있었다.

원래 결정([20260801_settings-ui-read-only-yaml](20260801_settings-ui-read-only-yaml.md))의 진짜 근거는 "UI가 파일을 쓰면 안 된다"가 아니라 **"Yams가 주석을 보존하지 못한다"**였고, 그 문서 자신이 재개 조건을 명시해 뒀다: *"GUI 쓰기 요구가 실증되면 '주석 보존 부분 편집'(전체 재직렬화가 아닌 라인 단위 패치) 같은 접근으로 재개할 수 있다 — additive라 이 결정과 충돌하지 않는다."* 이번 작업이 정확히 그 조건이다. 원래 결정이 걱정한 실패 모드(주석·서식 파괴)는 라인 편집에서 구조적으로 발생하지 않는다.

또 하나의 원래 근거였던 "재진입 처리 소거"(UI 쓰기를 파일 감시가 다시 리로드하는 루프)는 [파일 감시 폐기](20260802_config-reload-manual-menubar-trigger.md)로 이미 소멸했다 — 리로드는 명시적 호출뿐이다.

**왜 이렇게까지 방어적인가**: 이 편집이 중복 키를 만들면 Yams `compose`가 던져 `config.yaml`이 **통째로 무효**가 되고, 그 순간 사용자가 off 해둔 앱이 **전부 켜진다**(터미널·에디터에서 Vim이 이중 해석되기 시작한다). 이 작업에서 가장 심각한 실패 모드이고, 편의 기능 하나가 만들 수 있는 피해로는 과하다. 그래서 애매하면 무조건 안 쓰는 쪽으로 기울였다.

**자가검증을 순수 함수 안에 둔 이유**: 안전망을 앱 레벨 롤백(쓰기 → 리로드 → 새 에러가 생기면 원본 텍스트로 재-write)으로 둘 수도 있었다. 자가검증이 나은 이유는 셋이다 — (a) 파일에 손대기 **전에** 막는다(롤백은 이미 쓴 뒤이고, 롤백 쓰기 자체가 또 실패할 수 있다), (b) `VimActionConfig`가 이미 Yams와 파서를 갖고 있어 Foundation 없이 순수하게 끝나고 headless 테스트로 결정적으로 커버된다, (c) 검증 실패가 곧 계약상의 `nil`이라 폴백 경로가 하나로 합쳐진다. 비용은 토글 클릭당 `compose` 한 번 추가인데 파일이 작고 클릭이 드물어 무시할 수 있다.

**재활성화는 줄 삭제가 아니라 값 교체다** (`false` → `true`). `true`가 기본값이라 줄을 지우는 것도 의미상 동등하지만, 사용자가 그 줄에 적어 둔 후행 주석이 함께 사라진다. 사용자 파일을 덜 건드리는 쪽을 택했다.

**체크마크는 끄는 쪽이 켜진다** — 항목 제목이 'Disable for This App'이다. 기본이 on이고 사용자가 하는 일은 쓰지 않을 앱을 골라 끄는 것이라, 체크마크가 "이 앱은 내가 손대 둔 앱"을 뜻해야 읽힌다. `config.yaml`의 `apps:`(적힌 앱 = 예외)와도 같은 방향이다.

## 검토한 대안

- **앱 레벨 롤백 안전망**: 위 근거 참고. 쓴 뒤에 되돌리는 것보다 쓰기 전에 증명하는 쪽이 실패 모드가 적다. 순수 함수의 왕복 테스트로 이미 결정적으로 커버되는 영역이기도 하다.
- **`ConfigSeeder.seed()` 재사용**: 시더는 `fileExists`면 내용을 보지 않고 `.skippedExisting`을 돌려주는 "기존 파일 절대 무수정" 경로라 목적이 정반대다. 쓰기 seam(`ConfigSeeder.FileSystem.writeFile`)만 공유하고 `seed()`는 거치지 않는다.
- **"인용이 필요한 문자"를 정밀 판별**: YAML 인용 규칙을 그대로 구현하는 대신 `[A-Za-z0-9._-]` 화이트리스트로 막았다. 실제 bundle id는 전부 통과하고, 애매한 입력은 전부 `nil`로 떨어진다 — 이 결정의 "애매하면 안 쓴다" 기조와 같다.
- **`NSRegularExpression` 기반 파싱**: `VimActionConfig`는 Foundation을 import하지 않는다(플랫폼 프레임워크 미import는 이 타깃의 불변식이고 테스트가 지킨다). 평범한 String/Substring 라인 파싱으로 구현했다.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- 신규: `Packages/VimActionCore/Sources/VimActionConfig/AppEnableEditor.swift`(순수 함수), 같은 이름의 테스트.
- `ConfigStore.setAppEnabled(_:enabled:)` — 읽기는 `ConfigLoader.FileSystem.readFile`, 쓰기는 `ConfigSeeder.FileSystem.writeFile` seam. `AppState.setAppEnabled`가 성공 시 기존 `reloadConfig()`로 게이트 푸시까지 잇고, 실패 시 알림 + `openConfigFile()`.
- 메뉴바: 'Disable for This App' 토글 + 'Open config.yaml'. Settings의 "Open config.yaml" 버튼도 같은 `openConfigFile()`(Finder 폴백 공유)을 쓴다.
- 시딩 경로는 **그대로다** — "기존 파일을 절대 덮어쓰지 않는다"는 시더의 계약으로 계속 유효하고, 새 쓰기 경로가 시더를 타지 않기 때문에 두 진술이 충돌하지 않는다.

## Supersedes

- [20260801_settings-ui-read-only-yaml.md](20260801_settings-ui-read-only-yaml.md) — **부분**. "UI는 YAML을 쓰지 않는다"가 "UI는 YAML을 **재직렬화하지 않는다**"로 좁혀졌다. 주석 보존 근거, Settings 화면의 읽기 전용 성격, "설정 파일 열기" 버튼은 그대로 유효하다.

# 메뉴바 최전면 앱 편의 기능 2종

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

메뉴바 메뉴에 **최전면(직전 포커스) 앱 대상 편의 기능 2종**을 추가한다 (M4 세션 B 범위):

1. **Bundle ID 확인·복사** — 현재 앱의 bundle id를 메뉴에 표시하고 클릭 시 클립보드에 복사.
2. **프로파일 열기·scaffold 생성** — 그 앱의 `profiles/<bundle-id>.yaml`이 있으면 열고, 없으면 주석 처리된 스키마 예시(scaffold)를 생성한 뒤 연다. **기존 파일은 절대 수정하지 않는다** — 없는 파일 생성만.

## 배경·근거 (왜)

- 설정의 모든 진입점이 bundle id다 (`config.yaml`의 `apps` 맵 키, `profiles/` 파일명). 그런데 bundle id는 일반 사용자가 조회하기 어렵다 (`osascript`나 `mdls`를 알아야 함) — 이 마찰이 "앱 끄기"라는 가장 기본적인 설정 행위를 막는다.
- scaffold는 프로파일 작성 시의 실물 예시 문서 역할을 한다 — 번들 기본 프로파일(Slack·Notion)이 같은 역할을 하지만, scaffold는 "지금 이 앱, 올바른 파일명으로" 시작점을 만들어 준다.
- 두 기능 모두 "지금 포커스된 앱"에 대한 동작이라 **메뉴바가 유일하게 맞는 위치**다 — 대상 앱을 쓰다가 앱 전환 없이 바로 접근한다.
- **scaffold 생성은 [UI 읽기 전용 결정](20260801_settings-ui-read-only-yaml.md)과 충돌하지 않는다**: 그 결정의 근거는 Yams가 주석을 보존하지 못해 기존 파일 쓰기가 사용자의 주석·서식을 파괴한다는 것이다. scaffold는 없는 파일의 신규 생성만 하므로(시딩과 동일 성격) 파괴할 내용이 없다.

## 구현 전제 (세션 B에서 확인)

- 메뉴바 클릭 시 VimAction 자신이 활성화되면 `FrontmostAppGate`의 `frontmostBundleID` 캐시가 자기 자신으로 바뀌어 대상 앱 정보가 사라질 수 있다 → **"마지막 비자신(non-self) 앱" 캐시**가 필요하다. LSUIElement 앱의 MenuBarExtra 클릭이 실제로 활성화 알림을 유발하는지는 실기기 확인 항목.

## 검토한 대안

- **Settings 창에 배치**: 기각 — Settings 창을 여는 순간 포커스가 대상 앱에서 떠나고, 창을 띄우는 왕복 자체가 이 기능이 없애려는 마찰이다.
- **scaffold 없이 파일 열기만**: 기각 — 파일이 없으면 "열기"가 할 일이 없고, 사용자가 빈 파일에서 스키마를 기억해 작성해야 한다. scaffold 생성 비용은 템플릿 문자열 하나다.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- M4 세션 B 구현 범위: 메뉴 항목 2개 + non-self 앱 캐시 + scaffold 템플릿. 파일 쓰기는 `ConfigSeeder`의 쓰기 seam(fileExists/writeFile) 재사용.

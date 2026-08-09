# 설정 UI는 YAML 읽기 전용

> Superseded (부분) by [20260802_bundled-defaults-seeded-not-merged.md](20260802_bundled-defaults-seeded-not-merged.md) — 표시 대상이 "3계층 병합 결과 + 그 값을 정한 계층"에서 파싱 결과 자체로 바뀜(계층 개념 소멸) / 읽기 전용·"설정 파일 열기" 버튼·쓰기 금지 근거는 유효.
> Superseded (부분) by [20260809_config-yaml-line-edit-writes.md](20260809_config-yaml-line-edit-writes.md) — "UI는 YAML을 쓰지 않는다"가 "재직렬화하지 않는다"로 좁혀짐(메뉴바 앱별 토글이 라인 편집으로 씀) / 주석 보존 근거·Settings 화면의 읽기 전용 성격은 유효.

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

설정 UI의 앱별 목록은 **읽기 전용**이다: 3계층 병합 결과(앱별 on/off)와 그 값을 정한 계층(번들 기본값 / config.yaml)을 표시하고, **"설정 파일 열기" 버튼**만 제공한다. UI는 YAML을 쓰지 않는다 — 쓰기는 항상 사용자가 파일로 한다.

## 배경·근거 (왜)

- **Yams는 주석을 보존하지 못한다**: UI가 config.yaml을 파싱→수정→재직렬화하면 사용자가 적은 주석·키 순서·서식이 전부 날아간다. "개발자가 파일을 직접 편집·관리한다"는 [설정 루트 결정](20260801_config-root-dot-config.md)의 전제와 정면 충돌하는 실패 모드라, 쓰기 자체를 없애 원천 차단한다.
- **재진입 처리 소거**: UI가 파일을 쓰면 파일 감시가 자기 변경을 다시 리로드하는 루프의 구분 처리가 필요해진다 — 읽기 전용이면 이 문제가 존재하지 않는다.
- M4 범위 축소: 표시·버튼만이라 설정 UI 작업이 작아진다.

## 검토한 대안

- **UI가 YAML을 직접 쓰기**: 편의는 높지만 주석 파괴 + 재진입 처리 비용으로 기각. GUI 쓰기 요구가 실증되면 "주석 보존 부분 편집"(전체 재직렬화가 아닌 라인 단위 패치) 같은 접근으로 재개할 수 있다 — additive라 이 결정과 충돌하지 않는다.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- M4 설정 UI 카드의 범위 정의. 기존 Settings의 UserDefaults 기반 토글(마스터 토글·탈출 옵션)은 이 결정과 무관하게 쓰기 가능하게 유지된다 ([소유권 경계 결정](20260801_userdefaults-yaml-ownership.md)).

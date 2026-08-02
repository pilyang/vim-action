# ConfigError 가시화 형태와 스냅샷 적용 의미론

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

`ConfigError`(파일 통째 무효) 사용자 가시화의 구현 형태(M4 세션 B, 사용자 확정):

1. **메뉴바 메뉴에 설정 상태 라인 상시 표시** — `configStatusText` 순수 함수로 "Config: N profiles" / "Config error — config.yaml" / "Config errors — N files"를 파생해 비활성 항목으로 렌더한다. 시작 시 로드 에러도 여기서 보인다.
2. **NSAlert는 'Reload Config' 클릭 실패 시에만** — 파일 basename + Yams 메시지 + "직전 유효 설정 유지 중" 안내. MenuBarExtra는 항목 클릭 시 메뉴가 닫히므로 "클릭한 자리에서 가시화"는 알림이 맡는다. LSUIElement라 `NSApp.activate(ignoringOtherApps:)`를 선행한다(최전면 캐시 일시 오염은 수용 — 다음 앱 전환에 자가 치유, non-self 캐시는 세션 B 후반 확인 항목).
3. **시작 시 에러는 팝업 없음** — 상태 라인 + Settings 읽기 전용 섹션(에러 목록 red·경고 수)이 커버한다.
4. **스냅샷 적용 의미론**: 경고·에러는 로드마다 항상 최신으로 노출하되, 스냅샷 적용은 에러가 없거나 **최초 로드**일 때만이다. 최초 로드는 에러가 있어도 부분 스냅샷을 적용한다 — 깨진 파일은 로더가 이미 부재 처리했고 유지할 직전 유효 설정이 없다. 이후 리로드 실패는 직전 유효 스냅샷 유지(스키마 v1 규칙 그대로).

## 배경·근거 (왜)

- 리로드 수동 트리거 결정([20260802](20260802_config-reload-manual-menubar-trigger.md))이 "클릭 자리 가시화"를 요구하지만 구현 형태는 열어 뒀다 — 상태 라인+실패 알림 조합을 사용자가 확정했다.
- 시작 시 알림 팝업은 침습적이고(앱을 켰을 뿐인데 모달), 상태 라인은 상시 노출이라 다음 메뉴 열기에서 반드시 보인다.
- 최초 로드 부분 적용이 없으면 "config.yaml 하나 깨짐 = 성한 프로파일까지 전부 무시"가 된다 — 파일 단위 독립성(로더가 파일별로 부재 처리)을 앱 적용 계층이 다시 깨지 않는다.

## 검토한 대안

- **시작 시에도 알림**: 기각 — 침습적이고, off 앱이 켜지는 위험은 상태 라인·Settings로 이미 인지 가능하다.
- **알림 없이 상태 라인만**: 기각 — 리로드 직후 메뉴가 닫혀 있어 "방금 클릭한 결과"를 보려면 메뉴를 다시 열어야 한다. 결정 요구에 미달.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- [20260801_config-yaml-schema-v1.md](20260801_config-yaml-schema-v1.md)의 "리로드 실패 시 직전 유지"를 구현 계층에서 구체화한다 (최초 로드 예외 추가 — supersede 아님).

# M2 앱 게이트는 엔진 진입 전 통과 + 모드 동결

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-26

## 결정

M2 최소 디스패처의 앱 수준 게이트(하드코딩 disable 목록)는 **탭 콜백에서 엔진 진입 전에** 판정한다: 최전면 앱이 disable 목록이면 번역·엔진 해석 없이 원본 키를 그대로 통과시킨다. 그동안 엔진 모드 상태는 **동결**한다 — 리셋하지 않고, disable 앱에 있는 동안 키를 보지 않았으므로 이전 상태 그대로 남는다. 판정 위치는 마커 가드·마스터 토글 가드 **뒤**, 번역 앞이다(마커 최우선 불변식 유지). disable 목록 초기값은 `com.mitchellh.ghostty` 하나(하드코딩, M4 프로파일이 교체).

최전면 bundleID는 키마다 NSWorkspace를 조회하지 않는다 — `@MainActor` 캐시가 앱 활성화 알림(`NSWorkspace.didActivateApplicationNotification`)으로 갱신되고 콜백은 캐시만 읽는다(콜백 경량 불변식).

## 배경·근거 (왜)

게이트를 실행(디스패치) 시점에 두면 엔진은 평소처럼 동작해 disable 앱에서도 Normal 모드 키를 삼키는데 실행만 막혀 "죽은 키"가 된다 — 끈 것이 아니라 고장낸 것이다. 엔진 전 통과는 disable 앱 안에서 VimAction이 존재하지 않는 것과 동일한 경험을 주고, 최종 전략 디스패치 플로우의 "enabled: false → 통과 후 중단" 의미와도 일치한다.

모드 동결은 추가 코드 0줄이면서 관찰 가능한 동작도 자연스럽다: Normal 모드인 채 disable 앱에 다녀오면 여전히 Normal이다. 앱별 모드 기억은 프로파일 이후(M4+)의 주제라 여기서 선점하지 않는다.

## 검토한 대안

- **디스패치 시점 게이트**: 위의 죽은 키 문제. 기각.
- **disable 앱 진입 시 엔진 Insert 리셋**: 앱 전환 감지에 반응하는 추가 경로가 생기고, 돌아왔을 때 모드가 사라지는 동작이 오히려 놀랍다. 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (과도기 상태 문단)
- `EventTapController.handleKeyDown` 가드 체인, 신규 최전면 앱 캐시 컴포넌트 (M2 구현 예정)
- M4에서 하드코딩 목록이 프로파일 `enabled:` 필드로 교체될 때 이 게이트 위치가 그대로 프로파일 판정 위치가 된다

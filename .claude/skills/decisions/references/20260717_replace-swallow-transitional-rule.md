# replace 미실행 과도기 규칙 — 삼키고 로그만

- **결정일**: 2026-07-17

## 결정

엔진이 `.replace`(동작 실행이 필요한 결정)를 내면, 배선 마일스톤에서는 **실행하지 않고 삼킨 뒤(콜백에서 `nil` 반환) 요약 1건만 DEBUG 로그**한다. 실제 실행(커서 이동 등)은 ActionExecutor·어댑터가 들어오는 디스패처 마일스톤의 몫이다. 이 과도기 규칙에는 수용 조건이 붙는다: **디스패처 마일스톤 전에는 릴리스 빌드를 배포하지 않는다.**

## 배경·근거 (왜)

배선 마일스톤의 범위는 "엔진 결정을 이벤트에 적용(통과/삼킴)하되 실행은 로그로만 확인"이다. `.replace`를 통과시키면 원본 키가 앱에 그대로 입력돼 Normal 모드 커맨드가 텍스트로 새고, 실행하려면 아직 없는 ActionExecutor가 필요하다. 그래서 **삼킴**이 이 마일스톤에서 올바른 과도기 동작이다.

- **릴리스 무배포 조건** (silent-failure 리뷰 advisory): DEBUG 로그는 릴리스 빌드에서 컴파일되지 않는다. 릴리스에서 `.replace` 키는 **아무 관측 흔적 없이 삼켜져** 사용자에겐 "죽은 키"로 보인다. 실행이 붙기 전 배포하면 이 무로그 삼킴이 그대로 나가므로, 디스패처 마일스톤 완료를 배포 게이트로 못 박는다.
- **로그는 요약 1건**(`String(describing: output.actions.first)` + 개수)이지 `actions` 순회가 아니다: 카운트 도입으로 `actions`가 최대 9,999개까지 나올 수 있어(`2d3w` 곱·`9999G` 등), 콜백 안에서 수천 건 `os_log`는 탭 콜백 타임아웃을 유발해 워치독 실기기 검증까지 오염시킨다.
- **DEBUG 전용**: passthrough(Insert 타이핑)까지 로그하면 키로거가 된다. swallow/replace만, 그것도 DEBUG에서만 남긴다.
- **`switch`에 `default` 없이 `String(describing:)`**: 병렬 worktree에서 `VimAction`에 편집 케이스가 추가되던 중이라, exhaustive switch는 머지 시 충돌 마커 없이 빌드만 깨뜨린다 (소비자 non-exhaustive 계약).

## 검토한 대안

- **`.replace`를 통과**: Normal 커맨드가 앱에 텍스트로 샌다. 기각.
- **과도기 실행을 임시 구현**: 디스패처 마일스톤이 통째로 재작성할 코드라 낭비 + 재진입 마커 없는 실행은 무한 루프 위험. 기각.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)
- 앱: `EventTapController.handleKeyDown`의 `.replace` 분기. 디스패처 마일스톤에서 실행 배선으로 교체 예정.
- 배포 게이트: 디스패처 마일스톤 완료 전 릴리스 배포 금지.

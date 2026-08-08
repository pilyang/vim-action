# `strategy` 필드 최소 파싱을 PR-D1a로 선행 — `auto`는 미지값 warn+무시

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 D1-설계 세션, 결정 ⑤)

## 결정

AX 어댑터 도그푸딩 경로로 **프로파일 `strategy` 필드의 최소 파싱을 PR-D1a에 앞당긴다**:

- 값은 `accessibility`/`keyboard` 둘만 파싱한다. `auto` 포함 그 외 값은 **항목 단위 `invalidValue` warn+무시**(파일 생존 — 미리 `strategy: auto`를 써 둔 파일이 D1a 배포 순간 통째로 깨지지 않게). `auto`의 정식 파싱은 PR-E에서 추가한다.
- 파싱 위치는 `AppProfileParser`(top-level scalar — 전략은 앱별 프로파일 필드), `AppProfile`→`ResolvedProfile` 변환에 필드 추가. `per_element`는 계속 미지 키(PR-E 몫 보존).
- **기본값(미지정)은 keyboard** — 어떤 프로파일도 이 필드를 안 쓰면 기존과 동작 diff 0("keyboard-first" 관례 유지).
- 노출 수위는 **미문서 상태로 열어 둔다** — 도그푸딩 이용자는 개발자 본인이고, 사용자 문서화는 PR-E 스키마 확정 시.

## 배경·근거 (왜)

- **코드가 이미 이 방향을 예고하고 있다** — 파서 테스트에 "미지 최상위 키는 그 항목만 무시 — **M5 필드 선기입 전방 호환**"이라는 이름의 `strategy`/`per_element` fixture가 존재한다. 새 방향이 아니라 깔린 레일이다.
- `strategy` 값 어휘(accessibility/keyboard/auto)는 [20260712_ax-keyboard-strategy-dispatch.md](20260712_ax-keyboard-strategy-dispatch.md)에서 이미 결정된 것 — 새 스키마 설계가 아니라 합의된 어휘의 부분 구현이라 설계 리스크가 낮다.
- 도그푸딩이 **실배포 경로 그대로**를 검증하고 버릴 코드가 0이다. 필드 구조(top-level scalar)·변환 경로 통합은 PR-E에서 어차피 해야 하는 일이라, 지금 하면 D1 도그푸딩이 그 통합을 실사용으로 밟는다.
- `auto`를 파일 통째 실패로 처리하지 않는 것은 기존 강건성 규칙(scroll 범위 밖 값 등 "그 항목만 무시, 형제 생존") 그대로다.

## 검토한 대안

- **임시 배선**(하드코딩 bundleID 목록·debug 플래그, D1 후 제거): 스키마 약속이 없다는 것이 유일한 이득. 실경로 미검증·버릴 배선·제거 누락 시 미감사 debug 경로 잔존(무로그 삼킴 금지 기조와 충돌) — 배선을 두 번 만드는 셈이라 기각.
- **UserDefaults 플래그**: 전략은 "사용자가 파일로 관리하고 싶은 설정"이지 "앱이 스스로 쓰는 상태"가 아니다 — UserDefaults↔YAML 경계 원칙상 프로파일 YAML이 정답 위치.
- **별도 debug 파일 + 파일 감시**: 리로드는 수동 트리거 전용이 기결정([20260802_config-reload-manual-menubar-trigger.md](20260802_config-reload-manual-menubar-trigger.md)) — 이를 위해 감시 인프라를 얹는 것은 A/B보다 무거운 스코프 확장.

수용한 대가: PR-E의 실질 신규 작업이 `auto`+`per_element`로 줄어든다(플랜 문서 갱신). `auto`를 `invalidValue`로 고정한 테스트는 PR-E에서 정식 파싱으로 바뀔 **계획된 변경**이다 — 파서 주석에 "auto는 PR-E에서 추가 예정"을 명시해 혼란을 막는다.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- PR-D1a: `AppProfileParser`·`AppProfile`·`ResolvedProfile` 필드 추가 + 정상 파싱 fixture. 디스패치 소비는 [단일 드라이버](20260808_ax-delegation-table-single-driver.md)의 실행 계획 분기.

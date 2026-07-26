# M2 — Keyboard 어댑터 ① 모션 (비파괴)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-07-26
- **갱신일**: 2026-07-26

## 목표

Normal 모드의 이동 계열 `VimAction`이 실제 앱에서 합성 CGEvent로 실행된다: `.replace`가 더 이상 무실행 삼킴이 아니고, disable 앱(Ghostty)에서는 VimAction이 존재하지 않는 것처럼 동작하며, 어디서든 읽기 전용 도그푸딩이 가능한 상태. ([MVP 마일스톤 플랜](20260725_mvp-milestones.md)의 M2 항목 상세 플랜)

## 완료된 것

- [x] **설계 확정** (2026-07-26, 결정 3건 기록): 미지원 액션 = 실패 아님(스킵+DEBUG 로그), 앱 게이트 = 엔진 전 통과 + 모드 동결(disable 초기값 `com.mitchellh.ghostty` 하드코딩), 매핑 계약 = 순수 매퍼 `Motion → [KeyStroke]`(배열 반환이 계약, 근사 3건: w≈e, ^≈0, a/A 자연 수렴). 카운트는 엔진 클램프(9,999) 그대로 — 상한·합치기는 실측 후 판단.

## 남은 것

<!-- 다음에 할 것이 맨 위. 인계 단위(세션/마일스톤 수준)로 — 함수 단위 세부 todo는 세션 내 TodoList의 몫. -->

- [ ] **매퍼 + 어댑터**: `MotionKeyMapper`(순수, 골든 테이블 테스트 — 결정 문서의 매핑표가 픽스처) + `KeyboardAdapter`(직렬 큐 위에서 KeyStroke → keyDown+keyUp CGEvent 쌍 생성 → `ActionExecutor.post`, 미지원 액션 스킵+DEBUG 로그, 실패 보고는 키 입력당 1회 접기). 파일은 앱 타깃.
- [ ] **게이트 + 배선**: 최전면 bundleID 캐시(`@MainActor`, `NSWorkspace` 활성화 알림 구독) → `handleKeyDown` 가드 체인에 게이트 삽입(마커·토글 뒤, 번역 앞) → `.replace` 분기에서 actions를 직렬 큐로 전달. 기존 DEBUG 요약 로그 유지 여부는 구현 시 판단.
- [ ] **실기기 도그푸딩 확인**: 주력 앱에서 h/j/k/l·w/b/e·0/$/gg/G 동작, Ghostty에서 완전 통과(Esc 포함), 근사 3건 체감 평가, `100j` 등 카운트 폭탄 실측. 문제 발견 시 매핑표만 조정.
- [ ] **마무리**: 릴리스 배포 금지 규칙 해제 여부 판단(모션은 실행되지만 편집은 여전히 죽은 키 — M3까지 유지가 유력), 플랜 갱신·MVP 마일스톤 플랜에 M2 완료 반영.

## 진행 중 컨텍스트

- 인계 계약 4종(MVP 플랜에서 승계): ① 게시는 반드시 `ActionExecutor.post` ② CGEvent는 post 호출 직렬 큐 위에서 생성 ③ 실패 보고는 `reportExecutionFailure`만 ④ 보고는 원인 키 입력당 최대 1회.
- 매핑표 전체(키코드·근사 표시 포함)는 [매핑 계약 결정 문서](../../decisions/references/20260726_motion-keystroke-mapping-contract.md)에 있다 — 골든 테스트는 이 표를 그대로 옮긴다.
- 테스트는 M1 방식 재사용: `ActionExecutor(postEvent:)` 수집기 주입으로 키코드·플래그·마커 검증. CGEvent **생성**은 TCC 불요라 headless 가능.
- 빌드 경고 기준선 0건, `defaults.bool` 단언 함정(미설정 키도 false) 주의 — MVP 플랜 컨텍스트 참조.

## 관련 링크

- 상위 플랜: [20260725_mvp-milestones.md](20260725_mvp-milestones.md)
- decisions: [미지원≠실패](../../decisions/references/20260726_unsupported-action-not-failure.md), [앱 게이트 엔진 전 통과](../../decisions/references/20260726_m2-app-gate-pre-engine-passthrough.md), [매핑 계약](../../decisions/references/20260726_motion-keystroke-mapping-contract.md), [실패 보고 단위](../../decisions/references/20260726_execution-failure-report-granularity.md)
- architecture: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)

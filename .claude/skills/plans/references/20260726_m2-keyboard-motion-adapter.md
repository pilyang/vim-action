# M2 — Keyboard 어댑터 ① 모션 (비파괴)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 플랜 생성일. 이 문서는 살아있는 문서입니다: 진행에 따라 계속 갱신하고, 완료·폐기되면 삭제합니다 (decisions와 정반대). -->

- **생성일**: 2026-07-26
- **갱신일**: 2026-07-26 (세션 B 구현·도그푸딩 완료 — PR #21 병합 대기)

## 목표

Normal 모드의 이동 계열 `VimAction`이 실제 앱에서 합성 CGEvent로 실행된다: `.replace`가 더 이상 무실행 삼킴이 아니고, disable 앱(Ghostty)에서는 VimAction이 존재하지 않는 것처럼 동작하며, 어디서든 읽기 전용 도그푸딩이 가능한 상태. ([MVP 마일스톤 플랜](20260725_mvp-milestones.md)의 M2 항목 상세 플랜)

## 완료된 것

- [x] **설계 확정** (2026-07-26, 결정 3건 기록): 미지원 액션 = 실패 아님(스킵+DEBUG 로그), 앱 게이트 = 엔진 전 통과 + 모드 동결(disable 초기값 `com.mitchellh.ghostty` 하드코딩), 매핑 계약 = 순수 매퍼 `Motion → [KeyStroke]`(배열 반환이 계약, 근사 3건: w≈e, ^≈0, a/A 자연 수렴). 카운트는 엔진 클램프(9,999) 그대로 — 상한·합치기는 실측 후 판단.
- [x] **세션 A — 매퍼 + 어댑터** (2026-07-26, TDD): `MotionKeyMapper`(순수, 골든 테이블 14케이스 전수) + `KeyboardAdapter`(`.move`만 실행, 직렬 큐 위 keyDown+keyUp 생성 → `ActionExecutor.post`, 미지원 스킵+DEBUG 요약 1건). `execute`는 값을 돌려주지 않는다 — 리뷰 반영으로 `Bool` 반환 제거(아래 컨텍스트 참조). `EventTapController` 무변경(런타임 동작 변화 0). 부수: 테스트 타깃의 동명 로컬 픽스처 구조체를 제거하고 프로덕션 `KeyStroke` 재사용, `Motion`에 `CaseIterable`(골든 표 완전성 단언용).
- [x] **세션 B — 게이트 + 배선 + 도그푸딩** (2026-07-26, PR #21 — **병합만 남음**): `FrontmostAppGate`(최전면 bundleID 캐시, 옵저버 등록이 시드보다 먼저인 것이 계약) + `handleKeyDown` 가드 체인 삽입(마커·토글 뒤, 번역 앞 → 엔진 전이라 모드 자연 동결) + `.replace`가 주입된 sink로 actions 전달(sink가 게시 직렬 큐 + `KeyboardAdapter`를 캡처). 테스트 9건 추가, 앱 유닛 테스트·엔진 테스트 GREEN, 빌드 경고 0건 유지, CI 2잡 GREEN. 마이크로 결정 4건 확정 → [실행 배선 형태 결정](../../decisions/references/20260726_m2-execution-wiring-shape.md).

## 남은 것

<!-- 다음에 할 것이 맨 위. 인계 단위(세션/마일스톤 수준)로 — 함수 단위 세부 todo는 세션 내 TodoList의 몫. -->

- [ ] **세션 B 병합** — PR #21(CI GREEN, 도그푸딩 통과) 병합 대기. 병합되면 아래 마무리를 이어서.
- [ ] **마무리** (병합 직후): ① 릴리스 배포 금지 규칙 판단 — 모션은 실행되지만 편집은 여전히 무로그 스킵이라 **M3까지 유지**가 결론이고, 게이트를 "디스패처 마일스톤"에서 "M3(편집 실행)"으로 옮기는 것을 decisions에 형식화한다. 그때 [20260717 과도기 규칙](../../decisions/references/20260717_replace-swallow-transitional-rule.md)의 supersede 처리(인덱스 유지/제거)는 **사용자 확인이 필요하다** — 본문에 아직 유효한 컨텍스트(로그 형태·DEBUG 전용 근거)가 섞여 있다. ② MVP 마일스톤 플랜에 M2 완료 반영(다음 착수 M3).
- [ ] **M2 후속 PR — 모션 매핑 정확도** (도그푸딩發, 별도 PR로 분리 확정): ① 근사 3건 개선(w≈e, ^≈0, a/A) — 매핑 계약의 "배열 반환" 을 처음 활용하는 변경이라 테이블 원소 교체로 끝난다. ② **Shift 새어 들어감** — `$`(Shift+4)·`G`(Shift+g)·`^`·`A`는 사용자가 Shift를 누른 상태에서 Cmd/Opt 조합을 게시하므로, 전역 modifier 상태를 별도로 읽는 앱에서 이동이 아니라 **선택**이 될 수 있다. 이건 매퍼가 아니라 **어댑터 레벨**(게시 전 modifier 정리)이라 "매퍼 밖·큐 위 변환" 경계가 바뀐다 → decisions 먼저. 착수 전 **어긋난 항목의 구체 목록을 먼저 확보할 것**(아래 컨텍스트).

## 진행 중 컨텍스트

- 인계 계약 4종(MVP 플랜에서 승계): ① 게시는 반드시 `ActionExecutor.post` ② CGEvent는 post 호출 직렬 큐 위에서 생성 ③ 실패 보고는 `reportExecutionFailure`만 ④ 보고는 원인 키 입력당 최대 1회. ①②는 세션 B에서 이행됐고, ③④는 여전히 **호출자가 없다**(아래).
- **도그푸딩에서 실제로 확인한 것**(2026-07-26, `notion.id ↔ com.mitchellh.ghostty`, DEBUG 로그 스트림): 게이트 앱 전이 정확·Ghostty 구간 `replace` 0건(완전 통과, Esc 포함), 모션 디스패치(`10w` 카운트 포함)와 캐럿 이동, 미지원 스킵(`scroll(halfPage)`·`openLine`) 및 실패 보고 0건, 탭 비활성화 통지·`fault` 0건.
- **아직 확인하지 않은 것** (다음 세션이 착각하지 않도록): ① `100j`/`9999j` 카운트 폭탄 실측(배수 시간, 버스트 직후 타이핑의 순서 역전, 킬스위치가 in-flight 큐를 멈추지 못하는 정도 — 배수 시간이 ≈1초 이상이면 **실행 중단 래치를 M3 범위로** 올린다) ② 실행 배선 후 킬스위치 회귀 ③ **어긋난 모션의 구체 목록** — "일부 예상과 다르다, 다만 테이블 버그는 아니다"까지만 확인됐고 어느 모션이 어떻게 어긋났는지는 기록되지 않았다. 후속 PR은 이 목록 확보부터 시작한다.
- `.debug` 로그는 로그 저장소에 남지 않는다 — `log show`로는 판정 불가다. 도그푸딩 관측은 `/usr/bin/log stream --level debug --predicate 'subsystem == "dev.pilyang.VimAction"'`(zsh에서 `log`가 가려져 절대 경로 필요).
- **실패 보고 배선은 세션 B에도 없다.** 계약 ④(키 입력당 1회)는 유효하지만, Keyboard 게시 경로(`ActionExecutor.post` → `CGEvent.post`)는 오류를 돌려주지 않아 **접을 실패 자체가 없다** — [실패 보고 단위 결정](../../decisions/references/20260726_execution-failure-report-granularity.md)의 "첫 호출자에서의 도달 범위 주의"가 이미 짚은 내용이다. 세션 A는 도달 불가능한 `CGEvent` 생성 실패만 담은 `Bool`을 반환했는데, 리뷰에서 제거했다(항상 통과하는 단언 3건이 딸려 있었다). 실패 신호는 `AXError`를 돌려주는 **M5 AX 어댑터**가 들어온 뒤 실제 실패 형태에 맞춰 만든다.
- 매핑표 전체(키코드·근사 표시 포함)는 [매핑 계약 결정 문서](../../decisions/references/20260726_motion-keystroke-mapping-contract.md)에 있다 — 골든 테스트는 이 표를 그대로 옮긴다.
- 테스트는 M1 방식 재사용: `ActionExecutor(postEvent:)` 수집기 주입으로 키코드·플래그·마커 검증. CGEvent **생성**은 TCC 불요라 headless 가능. 세션 B에서 같은 seam이 두 곳 더 생겼다 — 실행 sink와 앱 게이트의 기본값은 **XCTest 하위에서 무해한 것으로 바꿔치기**된다(그냥 두면 테스트가 실제 화살표 키를 머신에 주입하거나, Ghostty에서 테스트를 돌릴 때 게이트가 켜져 결정 테스트가 통째로 뒤집힌다). 동작을 검증하는 테스트는 init으로 자기 것을 주입한다.
- 빌드 경고 기준선 0건, `defaults.bool` 단언 함정(미설정 키도 false) 주의 — MVP 플랜 컨텍스트 참조.

## 관련 링크

- 상위 플랜: [20260725_mvp-milestones.md](20260725_mvp-milestones.md)
- decisions: [미지원≠실패](../../decisions/references/20260726_unsupported-action-not-failure.md), [앱 게이트 엔진 전 통과](../../decisions/references/20260726_m2-app-gate-pre-engine-passthrough.md), [매핑 계약](../../decisions/references/20260726_motion-keystroke-mapping-contract.md), [실패 보고 단위](../../decisions/references/20260726_execution-failure-report-granularity.md), [실행 배선 형태](../../decisions/references/20260726_m2-execution-wiring-shape.md)
- PR: [#20 세션 A](https://github.com/pilyang/vim-action/pull/20)(병합), [#21 세션 B](https://github.com/pilyang/vim-action/pull/21)(병합 대기)
- architecture: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md), [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md)

# AX 위임 표는 "명령 매퍼 계열 = 위임" + 배선은 단일 실행 드라이버

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 D1-설계 세션, 결정 ②)

## 결정

strategy=accessibility인 앱에서 액션별 실행 수단을 다음 표로 확정한다. 골격 규칙: **명령 매퍼(`CommandKeyMapper`) 계열 = 위임, 모션·편집·Visual 매퍼 계열 = AX(범위/캐럿 쓰기)** — 명령 매퍼의 정의("앱이 이미 아는 네이티브 명령에 위임")가 곧 "AX에 그 프리미티브가 없음"과 동치라, 어휘가 늘어도 판정이 자동으로 선다.

| 액션 | 실행 | 근거 |
|---|---|---|
| `.move` (j/k 제외 12−2+append 2) | AX 캐럿 쓰기 | 오프셋 대입이 정확 프리미티브 — `w`/`^` 3타 근사·Chromium 탭 들여쓰기 퇴행 소멸 |
| `.move(.lineUp/.lineDown)` (j/k) | **위임** | 오프셋 대입은 **희망 열(desired column)을 잃는다** — 짧은 줄을 지나면 열이 영구히 깎이는 현행보다 나쁜 회귀. 희망 열 상태 협력자 신설은 기각(마우스로 조용히 무효화되는 상태 추가) |
| `.edit` 전 범위 | **하이브리드** — AX 범위 선택 + `Cmd-X`/`Cmd-C` 1타 위임 | [20260808_ax-edit-select-then-operator-delegate.md](20260808_ax-edit-select-then-operator-delegate.md) |
| Visual 4종 | AX 범위 쓰기 (세션 경로 고정은 [20260808_ax-visual-session-path-pinning.md](20260808_ax-visual-session-path-pinning.md)) | 재앵커·크로싱·V↔v 조건부의 keyboard 곡예가 불필요 |
| `.clearSelection` | AX 캐럿 쓰기 (collapse) | 현행 패리티(왼쪽 끝) 고정 — Vim 방향 정확화는 별도 결정으로 이연 |
| `.openLine` | **하이브리드** — AX 위치 접두 + `Return` 위임 | 자동 들여쓰기·리스트 연속·블록 생성은 `Return`만 태운다. 접두가 AX라 소프트 랩 `O` 실패·`Cmd-→` 시각 줄 문제 해소. `.textField` 게이트(Return=submit) 유지 |
| `.paste` | **하이브리드** — AX 위치 접두 + `Cmd-V`×count 위임 | 리치 텍스트·앱 paste 훅 보존. 줄 끝 접두 생략·linewise 멱등 보정자 같은 화살표 포화 우회 장치 불필요. 빈 클립보드 정직 스킵은 접두 계산보다 앞(현행 순서) |
| `.undo`/`.redo` | 위임 (강제) | AX에 undo API 없음 |
| `.scroll` | 위임 | 뷰포트만큼 캐럿을 옮기는 AX 쓰기 프리미티브 없음, 뷰포트 수학은 keyboard 완성 |
| quote/pair 오브젝트 | 양쪽 미지원 유지 | 패리티만 — 범위 확장 아님 |
| 계열 `.nonText`/`.unresolved` | **전 액션 keyboard 강등** | AX 대입은 텍스트 요소 전제 — Finder 리스트에서 무동작이라, "모션·스크롤은 게시" 걸러내기 결정([20260801](20260801_non-text-filter-keeps-motion-and-scroll.md))이 조용히 죽는다 |

추가 규칙 셋:

- **위임·혼합은 액션 단위 all-or-nothing** — 하이브리드 액션의 순서는 항상 "동기 AX 쓰기 → 게시"이며(대상 앱 메인 런루프가 직렬화 — 이 방향은 레이스 없음), **접두 AX 실패 시 그 액션을 통째로 keyboard 경로로 낙하**시킨다. 맨 `Cmd-V`/`Return`만 내보내는 것은 "엉뚱한 자리 붙여넣기"라 금지.
- **오프셋 증명 실패(`unproven`)도 keyboard 위임** — 쓰기 시도 **전**이라 이중 실행이 원리적으로 불가하며, 쓰기 시도 **후** 실패의 폴백 금지([20260808_ax-write-failure-whitelist-no-fallback.md](20260808_ax-write-failure-whitelist-no-fallback.md))와는 별개 축이다. 이 구분을 흐리면 다음 작업자가 "폴백 금지"를 여기까지 확장한다.
- **비-QWERTY 게이트·치환은 위임 행에만** — AX 행은 문자 명령 키를 합성하지 않으므로 `requiredCommandCharacters`가 실행 계획을 인지해야 한다(AX 편집도 오퍼레이터 1타가 위임이라 `x`/`c`는 유지된다).

**배선은 단일 실행 드라이버다**: execute 루프(중단 래치·청크·스냅샷·요약 로그)와 게이트 3종(`actions:` disable·걸러내기·레이아웃)·부수효과(`recordEdit`/`noteSelectionWise`/`forgetSelectionWise`)를 공유하고, 액션별 분기 안쪽만 갈린다 — `Mapping`에 `.groups`(위임)·`.ax`(쓰기 계획)·`.hybrid`(접두 쓰기 + 그룹) 형제 케이스를 얹는다. AX 접두는 합성 이벤트가 아니라 드롭 모드가 없으므로 페이싱 대상이 아니다(`paced:`는 위임 전용 속성으로 남는다).

## 배경·근거 (왜)

- 위임 집합이 매퍼 소속과 일치한다는 관찰이 표를 액션별 임의 판단에서 규칙으로 바꾼다. 하이브리드 둘(openLine·paste)·편집도 "위치·범위는 AX, 명령 키는 위임"이라는 한 문장으로 정리된다 — M5 전체의 축("읽기는 AX·실행은 keyboard")의 쓰기판 연장.
- 배선 후보 둘은 모두 기각됐다. "AX 어댑터가 keyboard 어댑터를 부른다"는 keyboard 계약 스택(게이트·부수효과·청크 회계)에 감사되지 않는 둘째 진입점을 만들고 execute당 계약(뷰포트 스냅샷·`holdsNextAction` 등)을 중첩시킨다. "디스패처가 액션 단위로 어댑터를 가른다"는 execute당 계약을 쪼개고 상태 협력자 인스턴스 공유가 조용히 깨질 수 있으며, 무엇보다 **하이브리드를 표현할 수 없다**. 하이브리드가 존재하는 순간 단일 드라이버가 유일하게 성립하는 모양이고, [프리미티브당 단일 통로](20260808_ax-writer-per-primitive-channel.md)와도 구조가 일치한다.
- j/k 위임은 검토 ②·④가 독립적으로 수렴한 결론이다. 부수 이득: Notion 블록 간 이동 같은 앱 고유 `↓` 동작이 공짜로 유지된다.
- 비텍스트 강등: `.unresolved`는 이 프로젝트가 이미 "모르는 동안은 보수적으로"를 택한 창이다 — AX 쓰기는 더 위험한 방향(모르는 요소에 대입)이라 같은 규칙이 더 강하게 적용된다.

## 검토한 대안

- **좁은 위임**(undo/redo·scroll만, openLine·paste·편집 오퍼레이터까지 순수 AX): 오프셋 계층이 커지고, openLine의 자동 들여쓰기 상실·paste의 플레인 강등·undo 미등록이라는 사용자 가시 퇴행 셋을 산다. 순수 AX 표본(D2 관측)이 늘어나는 것이 유일한 이득인데 범위 쓰기 표본으로 충분하다.
- **j/k 희망 열 상태 협력자 신설**: 셋째 협력자가 되고 마우스 클릭·앱 자체 이동으로 조용히 무효화된다. 필요가 실증되면 별도 PR로.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- PR-D1a: `Mapping` 케이스 확장 + `.move`(j/k 제외) AX 배선. PR-D1b: 편집·Visual·하이브리드·강등 마감. 프로파일 문서: `newLineStrokes`·`pasteStrokes`·`undoStrokes`·`redoStrokes` 훅은 위임 행에 그대로 살아 있다(AX 행은 문자 키를 안 쓰므로 해당 없음).

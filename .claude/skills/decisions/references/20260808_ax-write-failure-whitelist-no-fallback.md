# AX 쓰기 실패 보고는 화이트리스트·keyboard 폴백 없음 — `.illegalArgument`는 D1 관측 전용

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 D1-설계 세션, 결정 ③·쟁점 1)

## 결정

**(a) `AXError` 분류는 default-deny 화이트리스트다.** 순수 AX 경로에서 "보고"와 "스킵"은 사용자 가시 결과가 동일(무동작)하므로, 유일한 판단 기준은 "이 코드가 **우리 실행 코드의 고장**을 가리키는가"다.

| AXError | 분류 |
|---|---|
| `.failure` (시스템 오류 — 정상 사용 도달 불가) | **실패 보고** (`reportExecutionFailure` 첫 실호출자) |
| `.illegalArgument` (사전 경계 검증 통과 후 앱이 거부 = 오프셋 공간 불일치 신호) | **D1 구간은 관측 전용** — 앱 번들 ID를 실은 별도 요약 로그만. **D1 종료 시 보고 승격 재심사 예약** |
| `.attributeUnsupported` `.notImplemented` `.parameterizedAttributeUnsupported` `.noValue` | 미지원 스킵 (앱의 정적 성질 — "미지원 ≠ 실패" 연장) |
| `.invalidUIElement` (요소가 사이에 사라짐) `.cannotComplete` (타임아웃·앱 busy) | 경합 스킵 |
| `.apiDisabled` (TCC 회수) | 보고 아님 — `AccessibilityPermissionMonitor`(1초 폴링) 전담 + error 로그 |
| 미지 코드 (`@unknown default`) | 미보고 스킵 + error 로그 — 새 코드가 조용히 보고로 흘러들지 않게 |

사전 경계 검증(`0 ≤ location && upperBound ≤ characterCount`, 앱이 준 `characterCount` 기준)을 쓰기 전에 우리 쪽에서 수행하고, **검증 실패는 보고가 아니라 스킵**이다(감지 가능한 우리 버그를 AX에 보내지 않는다). AX 스킵은 기존 분류와 섞지 않는 **전용 요약 버킷**(`AX 미지원 스킵 ×N` / `AX 경합 스킵 ×N`)으로 집계한다.

**(b) 쓰기 시도 후 실패의 keyboard 폴백은 하지 않는다** — 실패 = (a)에 따른 처리 + 그 액션 무동작. 읽기 단계 실패(포커스 요소 없음·오프셋 계산용 읽기 타임아웃)는 실행 시도 **전**이므로 보고도 폴백도 아닌 스킵이다(단, 오프셋 증명 실패의 keyboard **위임**은 별개 축 — [20260808_ax-delegation-table-single-driver.md](20260808_ax-delegation-table-single-driver.md)).

구조 규칙 셋: ① **첫 미지원·첫 실패에서 그 execute의 잔여 액션을 통째로 스킵하고 반환** — "키 입력당 보고 1회"가 코드 구조로 보장되고, `100j`의 동기 왕복(최대 100×50ms 큐 점유)이 1×50ms로 접힌다. ② **실패 시각은 게시 큐에서 캡처해 `reportExecutionFailure(at:)`로 넘긴다** — 메인 홉 착지 시각으로 세면 메인 스톨 후 뭉쳐 착지한 보고들이 1초 창에 몰려 거짓 트립한다(어댑터→메인 홉 자체는 카운터 MainActor 계약대로 유지 — [20260725_failure-burst-autodisable-shape.md](20260725_failure-burst-autodisable-shape.md) 4항). ③ 중단 래치 질의는 액션 사이 + 파괴적 게시 직전(AX 경로에는 청크가 없다 — keyboard 8타 청크보다 촘촘한 개선).

## 배경·근거 (왜)

- **`.cannotComplete` 제외가 오탐 차단의 핵심이다.** 헤더가 "This does not necessarily mean that the function has failed"를 명시 — 성공했는데 응답만 유실된 경우와 구분 불가하다. 자동저장으로 잠깐 바쁜 앱 + `j` 오토리핏이면 1초 5건이 자연스럽게 나오는데, 올바른 대응은 가로채기 전체 off가 아니라 그 앱 강등(D2 몫)이다. 방어는 50ms 캡 + 첫 실패 execute 중단 + 중단 래치로 충분하다.
- **폴백 금지의 근거 둘이 독립적으로 같은 결론이다**: ⓐ `.cannotComplete`가 "이미 수행 + 응답 유실"일 수 있어 keyboard 재실행은 **이중 삭제**가 된다. ⓑ keyboard 시퀀스는 캐럿/선택 **상대** 기준인데 AX 실패는 그 기준을 미상으로 만든다 — 어긋난 상태 위의 상대 시퀀스는 파괴적 실행이다. 추가로 조용한 폴백은 `strategy: accessibility` 설정을 반증 불가능하게 만들어 D2가 관측할 데이터를 가리고, 기본 전략이 keyboard라 피해 범위는 명시 설정자로 한정된다.
- **`.illegalArgument`를 D1에서 관측 전용으로 두는 이유**: 이것이 실질적 안전망 전부인데, 가장 현실적인 오탐(앱이 `characterCount`를 UTF-16이 아닌 단위로 보고 → 이모지·한글 문서에서 연속 거부 → 오토리핏 자동 off)의 실제 빈도가 미실측이다. 자동 트립은 UserDefaults에 영속되어 재시작 후에도 꺼진 채라 오탐 1회의 대가가 크다. 실측 없이 상수를 정하지 않는 프로젝트 태도대로, 도그푸딩 로그(번들 ID 포함)로 빈도를 본 뒤 승격한다. D1 도그푸딩 사용자는 개발자 본인뿐이라 실사용자 노출 전에 승격 판단이 끝난다.
- `.invalidUIElement`가 경합인 이유: 우리 요소 ref는 액션마다 새로 만들어 나이가 수 ms다 — 그 사이 무효가 됐다면 원인은 실제 요소 소멸(앱 전환·시트 닫힘·Electron DOM 재생성)이고, 발생 빈도는 우리 정확도가 아니라 대상 앱의 뷰 수명에 비례해 세어도 우리 버그를 가리키지 못한다. 죽은 요소 쓰기는 부수효과가 없어 실패 방향도 무해하다.

## 검토한 대안

- **넓은 분류(`.success` 외 전부 보고)**: AX 반쪽 지원 앱에 accessibility 설정 + 오토리핏 = 가로채기 전체 자동 off 오탐 축이 그대로 열린다.
- **`.illegalArgument` 즉시 보고**: 안전망 조기 가동이 이득이나 위 오탐 리스크가 미실측. 관측 전용안과 "동등하게 방어된다"(독립 검토)여서 보수 쪽을 택했다.
- **액션 한정 폴백(`.move`만)**: 가장 안전한 폴백 케이스인 것은 맞으나, 규칙이 액션별로 갈리고 D2가 봐야 할 가장 깨끗한 표본(모션)이 사라진다.

## 영향 범위

- 갱신한 architecture reference: [reentrancy-and-safety.md](../../architecture/references/reentrancy-and-safety.md) (완화책 #2·실패 보고 문단), [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)
- PR-D1a: 분류 순수 함수 + 16개 케이스 전수 스윕 테스트(`LogicalCommandKeyCodeExclusivityTests` 선례) + `reportExecutionFailure` 배선(시각 캡처 포함 — [20260726_m2-execution-wiring-shape.md](20260726_m2-execution-wiring-shape.md)가 열어 둔 항목이 닫힌다). 예약 항목: `.illegalArgument` 승격 재심사(D1 종료 시), `.cannotComplete` 재분류 재심사(D2 착수 시 — 도그푸딩 요약 로그가 판정 데이터), 자동 트립 영속의 오탐 대가 재검토.

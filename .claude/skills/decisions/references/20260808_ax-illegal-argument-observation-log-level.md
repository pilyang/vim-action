# `.illegalArgument` 관측 로그는 항상 컴파일 + `.info` — 요약 버킷 관례에서 이탈

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 PR-D1a 세션1 Part D)

## 결정

AX 쓰기 결과의 요약 로그는 클래스마다 레벨이 갈리며, **`.illegalArgument`만 `#if DEBUG` 밖에서 `Logger.eventTap.info`로 나간다.**

| 클래스 | 레벨 | 컴파일 |
|---|---|---|
| `.failure` | `.error` | 항상 |
| `.illegalArgument` | **`.info`** | **항상** |
| `.unsupportedSkip` / `.contentionSkip` | `.debug` | `#if DEBUG` (기존 요약 버킷 관례) |
| `.apiDisabled` / `.unexpected` | `.error` | 항상 |
| `.success` | 로그 없음 | — |

집계(카운트·첫 액션)는 조건부 컴파일 밖에서 항상 한다 — 값 타입의 저장 프로퍼티라 `#if DEBUG`로 가르면 지저분하고, 비용이 Int 증가 1회다. 갈리는 것은 **emit뿐**이다.

## 배경·근거 (왜)

기존 요약 버킷(미지원 스킵·비-QWERTY 스킵·프로파일 disable)은 전부 `#if DEBUG` + `.debug`다. `.illegalArgument`를 그 관례에 맞추지 않는 이유는 **읽히는 시점이 다르기 때문**이다.

- 이 로그는 [화이트리스트 결정](20260808_ax-write-failure-whitelist-no-fallback.md)이 **D1 종료 시 보고 승격 재심사의 판정 데이터**로 예약해 둔 것이다. 판정은 도그푸딩이 끝난 뒤에 이뤄지는데, `.debug`는 그 순간 `log stream`을 켜 두고 있던 사람만 볼 수 있다 — 승격 심사 시점에는 남아 있는 것이 없다. `.info`는 메모리 버퍼에 들어가 `log show --info`로 **사후 회수**된다.
- 관측 대상이 "앱이 우리 범위를 거부한 빈도 + 그 앱"이라, 표본을 뒤늦게 모을 수 있는지가 이 로그의 존재 이유 자체다. 켜 두는 것을 잊으면 소실되는 데이터로는 결정을 되돌릴 수도 밀고 나갈 수도 없다.
- 스킵 2종을 `.debug`로 남겨 두는 것은 반대 이유다 — 그쪽은 도그푸딩 중 화면과 대조하며 읽는 관측이고(앱 강등 후보 발견), 사후 회수가 요구되지 않는다. 릴리스 빌드에서 조용한 것이 맞다.
- 로그가 발생마다가 아니라 **execute당 요약 1줄**이라 `.info`의 상시 컴파일 비용도 키 입력 1건당 최대 1줄로 바운드된다(`100j`가 액션 100건으로 전개되는 구조에서 per-occurrence 로그는 애초에 불가능하다).

## 검토한 대안

- **`#if DEBUG` + `.debug` (관례 그대로)**: 새 결정이 필요 없고 일관되지만, 승격 재심사가 볼 데이터가 남지 않는다 — 관례를 지키느라 그 관례를 도입한 목적(관측)을 잃는다.
- **`.error`로 올리기**: 회수는 더 확실하지만 `.illegalArgument`는 **정상적으로 일어날 수 있는 일**(앱의 오프셋 공간 불일치)이라 error는 거짓 경보다. 관측 전용이라는 분류와도 모순된다.
- **전용 파일·별도 카테고리 로거 신설**: 회수 편의는 같은데 `Logger` 카테고리 3종(eventTap/permission/config) 체계를 D1 한 구간 때문에 늘리게 된다.

## 영향 범위

- 코드: `VimAction/AXWriteEffects.swift`(`summaryRows` 표)
- 관측 명령: `log show --last 1h --info --predicate 'subsystem == "dev.pilyang.VimAction"'` (스트리밍은 종전대로 `log stream --level debug`)
- 예약: D1 종료 시 `.illegalArgument` 보고 승격 재심사 — 승격되면 이 로그는 보고 경로로 바뀌므로 이 결정도 함께 재검토된다.
- 관련 결정: [20260808_ax-write-failure-whitelist-no-fallback.md](20260808_ax-write-failure-whitelist-no-fallback.md)(관측 전용 분류의 출처), [20260726_execution-failure-report-granularity.md](20260726_execution-failure-report-granularity.md)(요약 1줄이 강제되는 이유)

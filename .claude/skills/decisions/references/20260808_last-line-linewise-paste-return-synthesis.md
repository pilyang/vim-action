# 마지막 줄 linewise `p`는 `Return` 합성 — naive 문서 끝 캐럿은 병합 훼손 (실측)

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-08 (M5 PR-D1b 세션 0 — 실측 후 결정)

## 결정

하이브리드 linewise `p`(after)의 접두는 줄 위치에 따라 갈린다:

- **내부 줄**: AX 캐럿 쓰기로 다음 줄 시작 오프셋 — 화살표 포화 우회 장치(`→` 접두·멱등 보정자) 없이 정확하다.
- **마지막 줄(뒤 개행 없음)**: AX 캐럿 쓰기로 **문서 끝** + 게시 그룹 `[Return, Cmd-V]`(한 원자 그룹). 문서 끝에 개행 1개가 남는 편차를 명시 수용한다 — linewise 반올림이 이미 문서 끝에서 수용한 것과 같은 축의 편차다.

이로써 [20260808_last-line-linewise-paste-degrades-to-P.md](20260808_last-line-linewise-paste-degrades-to-P.md)의 `P` 퇴행이 실제로 해소된다(그 결정의 "하이브리드가 포화 자체를 없앤다"는 근거 문장은 마지막 줄에 대해서는 부정확했다 — 본질은 포화가 아니라 **구분 개행의 부재**이고, 캐럿 쓰기만으로는 개행을 만들 수 없어 `Return` 합성이 필요하다).

## 배경·근거 (왜)

- **실측 (세션 0, TextEdit — 문서 `alpha\nbravo`, 클립보드 `PASTE\n`)**:

  | 접두 | 결과 | 판정 |
  |---|---|---|
  | 다음 줄 시작 캐럿 + `Cmd-V` (내부 줄) | `alpha\nPASTE\nbravo` | **정확** — 하이브리드 정상 경로 성립 |
  | 문서 끝 캐럿 + `Cmd-V` | `alpha\nbravoPASTE\n` | **병합 훼손** — 현행 `P` 퇴행(위치 오차·구조 온전)보다 나쁘다 |
  | 문서 끝 캐럿 + `Return` + `Cmd-V` | `alpha\nbravo\nPASTE\n` | **위치 정확 + 끝 개행 1개** |

- keyboard 경로가 이 자리를 못 고친 이유("마지막 줄에 개행을 만들어 붙이는 조립은 새 편차를 만든다")는 그대로인데, 그 편차(문서 끝 개행 1개)는 `dgg`류 linewise 반올림이 이미 수용한 편차와 동일한 축이라 새 종류의 수용이 아니다. keyboard에서 기각된 실제 이유는 "D1b가 곧 통째로 걷어낸다 — 두 번 만드는 배선"이었고, 여기가 그 한 번이다.
- `[Return, Cmd-V]`가 한 원자 그룹인 것은 원자 그룹 규칙 ③(`접두 + 첫 Cmd-V`)의 연장이다 — `Return`만 나가고 끊기면 빈 줄만 만든다. 하이브리드 접두(AX 쓰기)와 첫 그룹의 원자성은 [20260808_hybrid-prefix-atomic-with-first-group.md](20260808_hybrid-prefix-atomic-with-first-group.md).
- 마지막 줄 판정은 오프셋 계층이 창에서 증명한다(`FocusedTextOffsets` — 캐럿 뒤 개행 부재 + 문서 끝 도달). 증명 못 하면(`unproven`) 통상 규칙대로 keyboard 위임이다.

## 검토한 대안

- **naive 문서 끝 캐럿 + `Cmd-V`**: 실측 기각 — 병합 훼손. 실패 방향이 현행보다 나쁘다.
- **`P` 패리티(줄 시작 캐럿 + `Cmd-V`)**: 퇴행을 AX로 재현하는 것 — 도그푸딩이 잡은 엣지(`ddp`)를 그대로 두고, 해소 예정 결정과 충돌한다.
- **마지막 줄만 keyboard 낙하**: keyboard도 같은 퇴행이라 이득 0.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) (paste 하이브리드 행)
- PR-D1b: `FocusedTextOffsets`의 paste 삽입점 산출에 "마지막 줄" 3상태 분기 추가, 매퍼의 하이브리드 paste 그룹 조립.
- Notion 주의: 이 실측은 TextEdit이다. Notion의 블록 모델에서 `Return`은 블록 분리라 결과가 다를 수 있다 — **D1b 도그푸딩 관측 포인트**로 남기고, 어긋나면 그 자리에서 조정한다(블록 앱의 linewise는 논리 줄 = 블록이라 마지막 "줄" 개념 자체가 다르게 성립할 수 있다).

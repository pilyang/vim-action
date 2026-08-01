# 프로파일 스키마 v1 필드 구성과 키 표기법

> Superseded (부분) by [20260802_profile-disable-via-mapping-keyword.md](20260802_profile-disable-via-mapping-keyword.md) · [20260802_config-keyword-notation-lowercase.md](20260802_config-keyword-notation-lowercase.md) — `disabled_actions` 필드 폐기(→ 매핑 값 `disabled` + `actions` 섹션), 키 표기 대문자→소문자·v1 키 목록 확정 / name·scroll·motions 구성, 문자 키 v1 제외, chunk 비노출, M4 전부 구현은 유효.

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

`profiles/<bundle-id>.yaml` v1 필드는 넷이다 (`enabled` 없음 — [기존 결정](20260801_app-enable-config-yaml-only.md)):

```yaml
name: Notion                      # 선택 — 표시용
scroll:
  half_page_lines: 20             # 기본 15
  full_page_lines: 40             # 기본 30
disabled_actions:                 # 통제된 어휘 목록
  - open_line                     #   o/O 억제 (Return=전송 앱)
  - edit_to_document_edge         #   d/c/y+G·gg 억제 (Shift-Cmd-↑/↓ 충돌 앱)
motions:                          # 모션 단위 시퀀스 재정의 (단위 근거는 별도 결정)
  document_end: [Cmd-Down]
```

- **모션 이름**: 엔진 `Motion` 케이스의 snake_case.
- **키 스트로크 표기**: `[Modifier-]KeyName` — modifier는 `Cmd`/`Opt`/`Ctrl`/`Shift`(순서 무관), 키는 **이름 있는 키만**(`Left`/`Right`/`Up`/`Down`/`Return`/`Escape`/`Tab` 등). **문자 키(`Cmd-Z` 류)는 v1 제외** — 키코드가 레이아웃 의존이라 비-QWERTY 레이아웃 가드와 얽히고, ANSI 가정 확대는 [Cmd-Z 위험 등급 확대](20260730_cmd-z-ansi-layout-escalation.md)가 경고한 축이다.
- **미지 모션명·키명·disabled_actions 어휘**: 해당 항목만 warn + 무시 (config.yaml과 같은 강건성 규칙).
- `scroll`·`motions`·`disabled_actions`는 **프로파일 전용**(v1) — config.yaml 전역 재정의는 실익이 실증되면 additive로 연다.
- `chunkStrokes`/`chunkInterval`은 **YAML 비노출** — 실행 중단 래치의 안전장치 파라미터라 사용자 조절 대상이 아니다. 튜닝은 코드 상수로 한다.
- M4에서 네 필드 전부 **파싱 + 실행 배선까지 구현**한다 (스키마만 예약하는 필드 없음).

## 배경·근거 (왜)

- `scroll`: 줄 수 15/30은 뷰포트를 모르는 근사값이고 앱마다 뷰포트가 달라, 앱별 재정의가 [스크롤 화살표 반복 결정](20260730_scroll-arrow-repetition.md)이 M4로 위임한 조절값이다.
- `disabled_actions`: Slack류 Return=전송([openLine 결정](20260730_openline-return-sequence.md))·Notion 블록 이동 충돌([결정](20260727_notion-cmd-shift-vertical-conflict.md))처럼 "그 앱에서 그 어휘가 위험"한 케이스의 차단 자리. 자유 문자열이 아닌 통제된 어휘인 것은 오타가 조용히 무시되는 것을 warn으로 잡기 위해서다.
- M4 전부 구현인 이유: 프로파일 기능이 실제로 동작해야 Slack·Notion 위험이 해소되고 도그푸딩으로 검증된다 — 스키마 예약만 하면 위험이 M4 이후로 밀린다.

## 검토한 대안

- **motions를 스키마 예약만 하고 구현은 M4.5로 분리**: MVP 도달은 빨라지지만 Slack·Notion 해소가 밀려 기각 (사용자 결정).

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- 재정의 단위 근거: [20260801_profile-motion-override-unit.md](20260801_profile-motion-override-unit.md)
- Notion·Slack·Chromium `^` 등 M3 수용 엣지 중 앱 축 해소 대상이 이 스키마로 들어온다.

# 설정 키워드는 전부 소문자 — 키 이름 v1 목록 확정

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

설정 YAML의 키워드는 **전부 소문자 snake_case**로 통일한다 — 모션·액션 이름(기존과 동일), modifier, 키 이름 전부.

- 키 스트로크 토큰: `[modifier-]key`. modifier는 `cmd`/`opt`/`ctrl`/`shift`(순서 무관). 예: `shift-cmd-down`.
- 키 이름 v1 **11종**: `left` `right` `up` `down` `return` `escape` `tab` `home` `end` `page_up` `page_down`.
- 대소문자 관용 없음: `Cmd-Down` 같은 비소문자 토큰은 미지 키워드와 같은 warn+무시.
- 문자 키(`cmd-z` 류) v1 제외는 [기존 결정](20260801_profile-schema-v1-fields.md) 그대로다.

## 배경·근거 (왜)

- **한 파일 한 표기 체계**: 모션·액션 이름이 이미 소문자 snake_case라, 키 토큰만 대문자면 같은 파일 안에서 두 표기가 섞인다 (사용자 결정).
- 손편집 시 Shift 없이 타이핑된다 — 파일이 SSOT·사용자가 편집자라는 [설정 루트 결정](20260801_config-root-dot-config.md)의 전제와 맞는다.
- **관용을 두지 않는 이유**: 두 표기가 모두 유효하면 dotfiles·예시 간 표기가 갈린다. 로더 강건성 규칙(warn+무시)이 오타를 이미 가시화하므로 관용 없이도 실패가 조용하지 않다.

## 검토한 대안

- **`[Modifier-]KeyName` 대문자 표기 (기존 결정)**: 사람이 읽는 단축키 관례(⌘↓ 표기류)에는 가깝지만 위의 통일성에서 밀려 기각.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- `VimActionConfig`의 토큰 파서·키 어휘 enum이 이 표기 기준으로 구현된다.

## Supersedes

- [20260801_profile-schema-v1-fields.md](20260801_profile-schema-v1-fields.md) — **부분 supersede**: 키 스트로크 표기(`[Modifier-]KeyName` 대문자)만. "이름 있는 키만, 문자 키 v1 제외" 원칙은 유효.

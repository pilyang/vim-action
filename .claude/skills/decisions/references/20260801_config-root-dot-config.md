# 설정 루트를 `~/.config/vim-action/`으로 이동

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

설정 파일의 디스크 루트를 `~/Library/Application Support/VimAction/`에서 **`~/.config/vim-action/`**으로 변경한다. 사용자 설정은 `~/.config/vim-action/config.yaml`, 앱별 프로파일은 `~/.config/vim-action/profiles/<bundle-id>.yaml`. 포맷(YAML)·파서(Yams 단일)·번들 기본값 계층·핫 리로드는 기존 결정 그대로다.

## 배경·근거 (왜)

- **개발자 친화**: VimAction의 주 사용자층은 개발자이고, 설정을 GUI가 아니라 파일로 직접 편집·관리(dotfiles 저장소, 버전 관리, 머신 간 동기화)하는 워크플로우가 기본이다. `~/.config`는 이 워크플로우의 표준 위치(XDG 계열 관례)이며, `~/Library/Application Support`는 Finder 기본 숨김 + 경로 타이핑이 길어 직접 편집 대상 파일을 두기에 불리하다.
- M4 프로파일 배관 착수 전 시점이라 마이그레이션 비용이 0이다 — 코드도 파일도 아직 없다.

## 검토한 대안

- **`~/Library/Application Support/VimAction/` 유지 (기존 결정)**: macOS 네이티브 관례이지만, "사용자가 직접 편집하는 설정 파일"이라는 이 파일들의 성격과 맞지 않는다. 직접 편집 대상이 아닌 내부 상태 저장에는 여전히 적절하며, 그런 데이터가 생기면 그때 별도 판단한다.
- **`$XDG_CONFIG_HOME` 환경변수 존중**: 지금은 고정 경로 `~/.config/vim-action/`만 지원. macOS에서 XDG 변수를 설정하는 사용자는 소수이고, 로더 구현이 단순해진다. 요구가 실증되면 그때 추가한다 (이 결정과 충돌하지 않는 additive 확장).

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- M4 프로파일 로더가 이 경로를 기준으로 구현된다. 기존 경로에는 아무것도 배포된 적이 없어 마이그레이션 불필요.

## Supersedes

- [20260712_yaml-three-layer-config.md](20260712_yaml-three-layer-config.md) — **부분 supersede**: 디스크 루트 위치만. YAML·Yams·3계층·핫 리로드 결정은 유효하게 유지 (옛 문서는 인덱스에 잔존).

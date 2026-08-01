# 프로파일과 설정

- **Last updated**: 2026-08-01 (설정 루트 `~/.config/vim-action/` 이동, 앱별 on/off config.yaml 단일 소유 반영)

## 현재 구조

설정은 전부 YAML이며 **Yams**로 파싱한다. 디스크 루트는 **`~/.config/vim-action/`** — 개발자가 dotfiles로 관리·직접 편집하는 대상이라 `~/Library/Application Support`가 아니다. 3계층 재정의 구조를 가지며, 파일 변경 시(`DispatchSource.makeFileSystemObjectSource`) 자동 리로드한다.

계층 (아래가 위를 재정의):

1. 번들 기본값 — 앱 내부 읽기 전용 리소스.
2. 사용자 설정 — `~/.config/vim-action/config.yaml`.
3. 앱별 프로파일 — `~/.config/vim-action/profiles/<bundle-id>.yaml`.

역할 분담이 핵심이다:

- **`config.yaml`이 앱별 활성화/비활성화(on/off)를 단일 소유한다.** 프로파일에는 `enabled` 필드가 없다 — 있으면 앱을 끌 때마다 `profiles/`에 그 앱 전용 파일이 증식한다.
- **`profiles/<bundle-id>.yaml`은 일부 특수한 앱의 동작 고도화 전용**이다 (예: Slack의 Return=전송, Notion의 블록 이동 충돌 같은 앱별 재정의). 대부분의 앱은 프로파일 파일이 필요 없어야 정상이다.

## 스키마

**정식 스키마는 아직 없다 — M4 프로파일 배관에서 재설계한다.** 기존 스케치(PRD §7.4 유래의 `strategy`/`keyboard_family`/`keymap_overrides`/`per_element`/`disable_in_elements`)는 구현 시작 전 초기 계획 문서에서 온 것으로 신뢰도가 낮아 스키마 SSOT가 아니다. 방향 참고까지만 유효하다. M4 재설계 시 이 파일이 정식 스키마의 최종 상태를 담는다.

재설계 시 반영해야 할 확정 사항:

- 프로파일에 `enabled` 없음 (config.yaml 단일 소유).
- MVP 구간(M2~M4) 번들 기본 전략은 `keyboard` 고정 — `strategy`/`per_element` 류 필드는 M5(AX·auto) 전까지 죽은 필드라, M4 로더가 어디까지 파싱할지는 M4에서 결정.
- M3가 M4 프로파일로 위임한 조절값 후보: 스크롤 half/full 줄 수(15/30 근사), chunkInterval 튜닝, Notion `Shift-Cmd-↑/↓` 충돌 회피, Slack류 Return=전송 컴포저의 `o`/`O` 억제.

## 불변식·계약

- 설정 파서는 Yams 단일 의존 — 다른 포맷/파서를 섞지 않는다.
- 하위 계층은 상위 계층이 정의한 키만 재정의하며, 계층 간 침범이 없다.
- 앱별 on/off는 config.yaml에만 존재한다 — 같은 값이 두 계층에 살지 않는다.

## 근거 요약

번들 기본값으로 바로 동작하되 사용자/앱별 미세 조정을 얹을 수 있어야 하고, YAML을 직접 편집하는 사용자가 앱을 재시작하지 않아도 되도록 파일 감시 리로드를 둔다. 루트가 `~/.config`인 것은 주 사용자층(개발자)의 파일 기반 설정 관리 워크플로우 때문이다.

- 관련 결정: [20260712_yaml-three-layer-config.md](../../decisions/references/20260712_yaml-three-layer-config.md), [20260801_config-root-dot-config.md](../../decisions/references/20260801_config-root-dot-config.md), [20260801_app-enable-config-yaml-only.md](../../decisions/references/20260801_app-enable-config-yaml-only.md)

## 미결 질문 (결정 시 decisions에 기록 후 이 파일 갱신)

- 정식 프로파일·config.yaml 스키마 (M4에서 재설계).
- UserDefaults(마스터 토글·킬스위치 off 영속 등 앱 내부 상태)와 YAML(사용자 편집 설정)의 소유권 경계 세부 — 설정 UI의 앱별 목록이 YAML을 읽고 쓰는 방식 포함, M4 구현 시 확정.
- `keymap_overrides`(예: Insert 탈출 `jk` 시퀀스)는 엔진 v1 어휘에 없다 — 스키마에 남길지, 남기면 로더가 미지원 필드를 어떻게 다룰지.

## 관련

- 소비자: [strategy-dispatch.md](strategy-dispatch.md) (앱별 on/off·프로파일이 전략 선택 1단계)
- 요구사항 방향 참고: 워크스페이스 `docs/prd.md` §7.4 (초기 계획 문서 — 신뢰도 낮음, SSOT 아님)

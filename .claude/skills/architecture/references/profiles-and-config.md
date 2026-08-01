# 프로파일과 설정

- **Last updated**: 2026-08-01 (스키마 v1 확정 — apps 맵, 프로파일 4필드, UI 읽기 전용, UserDefaults 경계)

## 현재 구조

설정은 전부 YAML이며 **Yams**로 파싱한다. 디스크 루트는 **`~/.config/vim-action/`** — 개발자가 dotfiles로 관리·직접 편집하는 대상이라 `~/Library/Application Support`가 아니다. 3계층 재정의 구조를 가지며, 파일 변경 시(`DispatchSource.makeFileSystemObjectSource`) 자동 리로드한다.

계층 (아래가 위를 재정의, **병합은 키 단위** — 같은 키만 이긴다):

1. 번들 기본값 — 앱 내부 읽기 전용 리소스 (주력 앱 + VS Code류 off 목록 포함).
2. 사용자 설정 — `~/.config/vim-action/config.yaml`.
3. 앱별 프로파일 — `~/.config/vim-action/profiles/<bundle-id>.yaml`.

역할 분담:

- **`config.yaml`이 앱별 on/off를 단일 소유한다.** 프로파일에는 `enabled` 필드가 없다.
- **`profiles/`는 특수 앱의 동작 고도화 전용** — 대부분의 앱은 프로파일 파일이 필요 없어야 정상이다.

## 스키마 v1 (M4에서 전부 파싱·실행 배선까지 구현)

**config.yaml**:

```yaml
apps:                              # bundle-id → bool 맵. 맵인 이유: 키 단위 병합이라
  com.mitchellh.ghostty: false     # 번들 기본값이 끈 앱을 사용자가 true로 되켤 수 있다
  com.exafunction.windsurf: true
```

**profiles/\<bundle-id\>.yaml** — 필드 넷, `enabled` 없음:

```yaml
name: Notion                      # 선택 — 표시용
scroll:
  half_page_lines: 20             # 기본 15 — 앱 뷰포트에 맞춘 근사값 재정의
  full_page_lines: 40             # 기본 30
disabled_actions:                 # 통제된 어휘 목록 (자유 문자열 아님)
  - open_line                     #   o/O 억제 — Return=전송 앱 (Slack류)
  - edit_to_document_edge         #   d/c/y+G·gg 억제 — Shift-Cmd-↑/↓ 충돌 앱 (Notion)
motions:                          # 모션 단위 시퀀스 재정의
  document_end: [Cmd-Down]
```

**모션 재정의는 모션 단위이며 자동 전파된다**: 편집(Shift+모션 선택)·Visual(`selectionStrokes`)이 모션 매핑을 재사용하는 구조라, 재정의 조회를 `MotionKeyMapper` 조회의 단일 지점에 얹으면 `G`를 고칠 때 `dG`·`vG`가 함께 따라온다. 액션 단위 재정의는 없다.

**키 스트로크 표기**: `[Modifier-]KeyName` — modifier는 `Cmd`/`Opt`/`Ctrl`/`Shift`(순서 무관), 키는 이름 있는 키만(`Left`/`Right`/`Up`/`Down`/`Return`/`Escape`/`Tab` 등). 문자 키(`Cmd-Z` 류)는 레이아웃 의존이라 v1 제외.

**로더 강건성 규칙**: 미지 키·미지 모션명·미지 어휘는 해당 항목만 warn+무시(전방 호환 — `strategy`·`per_element` 등 M5 필드는 M4에서 미지 키), 핫 리로드 파싱 실패는 직전 유효 설정 유지 + error 로그.

**YAML 비노출**: `chunkStrokes`/`chunkInterval`(실행 중단 래치의 안전장치 파라미터 — 튜닝은 코드 상수로), 마스터 토글·Normal 탈출 옵션(아래 경계).

## 소비 지점

- 앱별 on/off → `FrontmostAppGate`의 하드코딩 목록을 교체 (M4).
- `scroll`·`motions`·`disabled_actions` → Keyboard 어댑터·매퍼 경로 (M4 배선).
- 설정 UI는 **읽기 전용**: 병합 결과와 결정 계층을 표시하고 "설정 파일 열기" 버튼만 — UI는 YAML을 쓰지 않는다 (Yams가 주석을 보존하지 못해, UI 쓰기는 사용자의 주석·서식을 파괴한다).

## UserDefaults↔YAML 경계

**"사용자가 파일로 관리하고 싶은 설정"은 YAML, "앱이 스스로 쓰는 상태"는 UserDefaults.**

- UserDefaults 잔류: `interceptionEnabled`(마스터 토글 — 킬스위치가 전용 스레드에서 직접 영속하는 안전 경로라 파일 IO에 의존시키지 않는다), `normalModeEscapeEnabled`(기존 Settings UI 토글 유지).
- YAML: 앱별 on/off, 프로파일 전부.

## 불변식·계약

- 설정 파서는 Yams 단일 의존 — 다른 포맷/파서를 섞지 않는다.
- 병합은 키 단위이며, 하위 계층은 같은 키만 재정의한다.
- 앱별 on/off는 config.yaml에만 존재한다 — 같은 값이 두 계층에 살지 않는다.
- 설정 오류는 절대 Vim 레이어를 통째로 죽이지 않는다 — 항목 단위 무시 또는 직전 유효 설정 유지.

## 근거 요약

번들 기본값으로 바로 동작하되 사용자/앱별 미세 조정을 얹을 수 있어야 하고, 파일을 직접 편집하는 사용자가 재시작 없이 반영을 봐야 한다. 루트가 `~/.config`인 것과 UI가 읽기 전용인 것은 같은 전제(파일이 SSOT, 사용자가 편집자)에서 나온다.

- 관련 결정: [3계층·Yams·핫 리로드](../../decisions/references/20260712_yaml-three-layer-config.md), [설정 루트](../../decisions/references/20260801_config-root-dot-config.md), [on/off 단일 소유](../../decisions/references/20260801_app-enable-config-yaml-only.md), [config.yaml 스키마 v1](../../decisions/references/20260801_config-yaml-schema-v1.md), [모션 단위 재정의](../../decisions/references/20260801_profile-motion-override-unit.md), [프로파일 v1 필드](../../decisions/references/20260801_profile-schema-v1-fields.md), [UI 읽기 전용](../../decisions/references/20260801_settings-ui-read-only-yaml.md), [UserDefaults 경계](../../decisions/references/20260801_userdefaults-yaml-ownership.md)

## 미결 질문 (결정 시 decisions에 기록 후 이 파일 갱신)

- 설정 계층 코드의 위치 — 순수 파서·병합을 `VimActionCore` 새 타깃으로 둘지(Yams 의존을 그 타깃에만), 앱 타깃에 둘지. M4 구현 착수 시 결정.
- `strategy`/`per_element`/`keymap_overrides` 등 M5 필드의 정식 스키마 — M5 착수 시 additive로 확장.
- GUI에서 설정을 편집하려는 요구가 실증되면: 주석 보존 부분 편집 방식 검토 (UI 읽기 전용 결정의 재개 조건).

## 관련

- 소비자: [strategy-dispatch.md](strategy-dispatch.md) (앱별 on/off·프로파일이 전략 선택 1단계)
- 요구사항 방향 참고: 워크스페이스 `docs/prd.md` §7.4 (초기 계획 문서 — 신뢰도 낮음, SSOT 아님)

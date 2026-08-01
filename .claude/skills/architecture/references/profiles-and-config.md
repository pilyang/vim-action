# 프로파일과 설정

- **Last updated**: 2026-08-02 (번들 기본값이 병합 계층에서 **파일 단위 시딩**으로 — 읽기는 사용자 파일 1계층, 병합·계층 출처 소멸)

## 현재 구조

설정은 전부 YAML이며 **Yams**로 파싱한다. 순수 설정 계층(스키마 타입·파서·로더·시딩 정책)은 `Packages/VimActionCore`의 **`VimActionConfig` 타깃**이다 — 의존은 `VimEngine` + Yams뿐이고 **Yams는 이 타깃에만** 붙는다. 앱 타깃은 파싱 결과 스냅샷을 소비하며, 설정 키 표현→`CGKeyCode` 변환·파일 감시(핫 리로드)·번들 리소스 읽기·파일시스템 접근은 앱 몫이다(주입 seam).

디스크 루트는 **`~/.config/vim-action/`** — 개발자가 dotfiles로 관리·직접 편집하는 대상이라 `~/Library/Application Support`가 아니다. 파일 변경 시(`DispatchSource.makeFileSystemObjectSource`) 자동 리로드한다.

**번들 기본값은 계층이 아니라 초기값이다.** 앱은 실행 시 번들 리소스를 `~/.config/vim-action/`에 **파일 단위로 시딩**한다 — 없는 파일만 복사하고, **이미 있으면 내용을 보지 않고 그대로 둔다**. 동봉 대상은 config.yaml(주력 앱 + VS Code류 off 목록)과 기본 프로파일(Slack·Notion)이며, 후자는 설치 즉시 위험 해소 + 사용자가 프로파일을 작성할 때의 실물 예시(문서 역할)를 겸한다.

따라서 **읽기는 사용자 파일 1계층이고 병합이 없다**:

- `~/.config/vim-action/config.yaml` — 파싱 결과가 곧 최종값.
- `~/.config/vim-action/profiles/<bundle-id>.yaml` — 앱 하나당 파일 하나, 그것이 곧 최종값.
- "기본값"은 값의 **부재**로 표현된다 — 파일·항목이 없으면 코드 상수(scroll 15/30, 매퍼 키 테이블)가 그대로 쓰인다. 값의 출처 계층이라는 개념은 없다.

수용한 대가: 이후 버전이 **기존 파일 안의 항목을 갱신하지 못한다**(새로 추가되는 프로파일 *파일*은 시딩으로 들어온다). 사용자가 지운 프로파일 파일은 다음 실행에 부활하므로, 프로파일을 안 쓰려면 파일 삭제가 아니라 내용을 비우거나 `config.yaml`에서 그 앱을 off한다.

역할 분담:

- **`config.yaml`이 앱별 on/off를 단일 소유한다.** 프로파일에는 `enabled` 필드가 없다.
- **`profiles/`는 특수 앱의 동작 고도화 전용** — 대부분의 앱은 프로파일 파일이 필요 없어야 정상이다.

## 스키마 v1 (M4에서 전부 파싱·실행 배선까지 구현)

**config.yaml**:

```yaml
apps:                              # bundle-id → bool 맵 (목록이 아니라 맵 —
  com.mitchellh.ghostty: false     # 앱별로 on·off를 같은 자리에서 지정한다)
  com.exafunction.windsurf: true   # 여기 없는 앱은 없는 것 — 기본값 판단은 앱 게이트 몫
```

**profiles/\<bundle-id\>.yaml** — 필드 넷(`name`·`scroll`·`motions`·`actions`), `enabled` 없음:

```yaml
name: Notion                      # 선택 — 표시용
scroll:
  half_page_lines: 20             # 기본 15 — 앱 뷰포트에 맞춘 근사값 재정의 (유효 1...200)
  full_page_lines: 40             # 기본 30 (유효 1...200)
motions:                          # 모션 단위: 시퀀스 재정의 또는 disabled
  document_end: [cmd-down]
  document_start: disabled        # 이 모션을 쓰는 어휘 전부(gg·dgg·vgg)가 정직한 스킵
actions:                          # 명령 계열 disable — v1 값은 disabled만 (시퀀스 재정의 없음)
  open_line: disabled             #   o/O 억제 — Return=전송 앱 (Slack류)
```

**disable은 별도 목록이 아니라 매핑 값 `disabled`다**: "그 앱에서 이 항목은 아무 동작도 하지 않는다"를 재정의와 같은 자리·같은 강건성 규칙으로 표현한다. 실행 의미는 매퍼 `nil`(미지원 스킵)과 동일 — 무로그 삼킴은 생기지 않는다. **빈 배열 `[]`은 disable이 아니라 warn+무시**(오타 가드, "지원 ⟹ 빈 시퀀스 아님" 매퍼 불변식 보호). `actions` v1 어휘는 `VimAction` 케이스 파생 5종 — `open_line`·`paste`·`undo`·`redo`·`scroll`.

**모션 재정의·disable은 모션 단위이며 자동 전파된다**: 편집(Shift+모션 선택)·Visual(`selectionStrokes`)이 모션 매핑을 재사용하는 구조라, 재정의 조회를 `MotionKeyMapper` 조회의 단일 지점에 얹으면 `G`를 고칠 때(또는 끌 때) `dG`·`vG`가 함께 따라온다. 액션 단위 시퀀스 재정의는 없다. **append 전용 모션(`charRightForAppend`/`lineEndForAppend` — a/A)은 어휘에 노출하지 않는다** — `char_right`/`line_end` 재정의·disable을 자동으로 상속한다(사용자 관점에서 `$`와 `A`의 줄 끝은 같은 개념).

**키워드 표기**: 전부 소문자 snake_case. 키 스트로크 토큰은 `[modifier-]key` — modifier는 `cmd`/`opt`/`ctrl`/`shift`(순서 무관), 키 이름 v1 11종: `left` `right` `up` `down` `return` `escape` `tab` `home` `end` `page_up` `page_down`. 문자 키(`cmd-z` 류)는 레이아웃 의존이라 v1 제외. 비소문자 토큰(`Cmd-Down`)은 미지 키워드와 같은 warn+무시(대소문자 관용 없음).

**로더 강건성 규칙**: 미지 키·미지 모션명·미지 액션명·미지 키 토큰은 해당 항목만 warn+무시(전방 호환 — `strategy`·`per_element` 등 M5 필드는 M4에서 미지 키), scroll 값은 1...200 정수만 유효(벗어나면 항목 warn+무시), 파일 통째 파싱 실패는 그 파일만 부재 취급 + error 반환(핫 리로드에선 직전 유효 설정 유지 + error 로그). 시퀀스 안의 토큰 하나가 깨지면 그 모션 항목 전체를 버린다 — 반쯤 맞는 시퀀스를 만들지 않는다.

**한 매핑 안의 키 중복은 항목 단위로 접히지 않고 파일 통째 실패다** — Yams `compose`가 관용 옵션 없이 던지기 때문이고, 우회하려면 이벤트 단위 파싱을 직접 짜야 해서 v1에서는 수용한다. 손편집에서 흔한 실수인데 그 파일이 통째로 없는 것이 되므로(예: `config.yaml`이 날아가면 off로 지정한 앱들이 전부 켜진 상태가 된다), **앱은 이 error를 로그에만 남기지 말고 사용자에게 보이게 해야 한다**.

`VimActionConfig`는 os.log도 파일시스템도 모른다: **경고·에러는 로그가 아니라 값으로 반환**하고(`ConfigWarning`/`ConfigError`), 읽기·쓰기는 주입된 클로저 seam으로만 한다. 로깅과 실제 IO는 앱 몫이다.

**YAML 비노출**: `chunkStrokes`/`chunkInterval`(실행 중단 래치의 안전장치 파라미터 — 튜닝은 코드 상수로), 마스터 토글·Normal 탈출 옵션(아래 경계).

## 소비 지점

- 앱별 on/off → `FrontmostAppGate`의 하드코딩 목록을 교체 (M4).
- `scroll` 재정의·`motions`/`actions`의 재정의·disable → Keyboard 어댑터·매퍼 경로 (M4 배선, disable은 기존 스킵 경로 재사용).
- 설정 UI는 **읽기 전용**: 파싱 결과를 표시하고 "설정 파일 열기" 버튼만 — UI는 YAML을 쓰지 않는다 (Yams가 주석을 보존하지 못해, UI 쓰기는 사용자의 주석·서식을 파괴한다).

## UserDefaults↔YAML 경계

**"사용자가 파일로 관리하고 싶은 설정"은 YAML, "앱이 스스로 쓰는 상태"는 UserDefaults.**

- UserDefaults 잔류: `interceptionEnabled`(마스터 토글 — 킬스위치가 전용 스레드에서 직접 영속하는 안전 경로라 파일 IO에 의존시키지 않는다), `normalModeEscapeEnabled`(기존 Settings UI 토글 유지).
- YAML: 앱별 on/off, 프로파일 전부.

## 불변식·계약

- 설정 파서는 Yams 단일 의존 — 다른 포맷/파서를 섞지 않으며, Yams 의존은 `VimActionConfig` 타깃 밖으로 나가지 않는다.
- 병합은 없다 — 사용자 파일이 곧 최종값이고, 번들 기본값은 시딩된 초기 내용일 뿐 런타임에 얹히지 않는다.
- 시딩은 파일 단위이며 **기존 파일을 절대 덮어쓰지 않는다**.
- 앱별 on/off는 config.yaml에만 존재한다 — 같은 값이 두 곳에 살지 않는다.
- 설정 오류는 절대 Vim 레이어를 통째로 죽이지 않는다 — 항목 단위 무시 또는 직전 유효 설정 유지.
- 설정이 만드는 "동작 없음"은 항상 정직한 스킵(매퍼 `nil` 경로)이다 — 무로그 삼킴을 만들지 않는다.

## 근거 요약

번들 기본값으로 바로 동작하되 사용자가 그것을 온전히 소유해야 하고(지우는 것까지), 파일을 직접 편집하는 사용자가 재시작 없이 반영을 봐야 한다. 루트가 `~/.config`인 것도, UI가 읽기 전용인 것도, 번들 기본값이 병합이 아니라 시딩인 것도 같은 전제(파일이 SSOT, 사용자가 편집자)에서 나온다 — 사용자가 여는 파일에 실제로 적용 중인 값이 전부 적혀 있다.

- 관련 결정: [번들 기본값 시딩](../../decisions/references/20260802_bundled-defaults-seeded-not-merged.md), [Yams·핫 리로드](../../decisions/references/20260712_yaml-three-layer-config.md), [설정 루트](../../decisions/references/20260801_config-root-dot-config.md), [on/off 단일 소유](../../decisions/references/20260801_app-enable-config-yaml-only.md), [config.yaml 스키마 v1](../../decisions/references/20260801_config-yaml-schema-v1.md), [모션 단위 재정의](../../decisions/references/20260801_profile-motion-override-unit.md), [프로파일 v1 필드](../../decisions/references/20260801_profile-schema-v1-fields.md), [UI 읽기 전용](../../decisions/references/20260801_settings-ui-read-only-yaml.md), [UserDefaults 경계](../../decisions/references/20260801_userdefaults-yaml-ownership.md), [코드 위치 VimActionConfig](../../decisions/references/20260802_config-layer-vimactionconfig-target.md), [disable은 매핑 값](../../decisions/references/20260802_profile-disable-via-mapping-keyword.md), [키워드 소문자](../../decisions/references/20260802_config-keyword-notation-lowercase.md), [번들 프로파일 동봉](../../decisions/references/20260802_bundled-default-profiles-slack-notion.md), [scroll 상한](../../decisions/references/20260802_scroll-override-bounds.md), [append 모션 base 상속](../../decisions/references/20260802_append-motions-follow-base-override.md), [Package.resolved 커밋](../../decisions/references/20260802_package-resolved-committed.md)

## 미결 질문 (결정 시 decisions에 기록 후 이 파일 갱신)

- `strategy`/`per_element`/`keymap_overrides` 등 M5 필드의 정식 스키마 — M5 착수 시 additive로 확장.
- 시딩이 기존 파일 안의 항목을 갱신하지 못하는 것(수용한 대가)이 실제로 문제가 되면: "새 기본값이 생겼다" 알림이나 마이그레이션을 additive로 검토.
- GUI에서 설정을 편집하려는 요구가 실증되면: 주석 보존 부분 편집 방식 검토 (UI 읽기 전용 결정의 재개 조건).

## 관련

- 소비자: [strategy-dispatch.md](strategy-dispatch.md) (앱별 on/off·프로파일이 전략 선택 1단계)
- 요구사항 방향 참고: 워크스페이스 `docs/prd.md` §7.4 (초기 계획 문서 — 신뢰도 낮음, SSOT 아님)

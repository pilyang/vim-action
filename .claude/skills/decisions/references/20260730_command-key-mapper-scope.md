# 명령 매퍼 신설 — 네이티브 명령 위임 계열

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-30

## 결정

`o`/`O`·`p`/`P`·`u`/`Ctrl-r`·스크롤을 **4번째 순수 매퍼 `CommandKeyMapper`** 가 담당한다 — 기존 세 매퍼에 나눠 끼우지 않는다. 진입점은 2개다: `keyStrokes(for action: VimAction, family:)`(openLine·undo·redo·scroll)와 `pasteStrokes(before:count:wise:family:)`. 붙여넣기 단위 판정은 순수 함수 `PasteWise(clipboardText:)`가 하고, `NSPasteboard` 읽기는 어댑터의 주입 seam(`readPasteWise`)이 담당한다.

함께 확정: 어댑터 내부의 스킵을 **두 종류로 가른다**(`Mapping.unsupported` / `.skipped`).

## 배경·근거 (왜)

다섯 액션의 공통점은 **앱의 네이티브 명령·키에 그대로 위임한다**는 것이다. 모션은 캐럿을 옮기고 편집은 "범위를 선택한 뒤 오퍼레이터 1타"로 의미를 조립하는데, 이쪽은 우리가 조립하는 것이 위치를 잡는 접두뿐이고 끝은 항상 앱이 이미 아는 명령 키 하나(`Return`·`Cmd-V`·`Cmd-Z`·`PageUp`/`PageDown`)다. 이 축이 기존 세 매퍼의 분할선과 같은 종류의 축이라 4번째 파일이 맞다 — `EditKeyMapper`에 밀어넣으면 `(op, range, family)` 시그니처와 "오퍼레이터 키로 끝난다" 불변식이 둘 다 깨지고, `VisualKeyMapper`는 선택 세션 전용이다.

**진입점 2개인 이유**: 붙여넣기만 wise라는 추가 입력이 필요하다. 단일 진입점(`pasteWise: PasteWise?` 파라미터 추가)이면 계약 지점이 하나로 모이는 대신 다섯 중 넷에 항상 `nil`인 인수가 붙고, 무엇보다 **어댑터가 undo·스크롤에도 클립보드를 읽어야** 한다(값 파라미터는 지연 평가가 안 된다). 클립보드 읽기는 IPC 왕복이라 `p` 입력에만 지불해야 한다. `MotionKeyMapper`의 `keyStrokes`/`selectionStrokes`가 이미 진입점 2개 선례다.

**판정과 읽기를 분리한 이유**: 매퍼가 패스트보드를 직접 읽으면 순수성이 깨져 골든 테스트가 개발자의 클립보드에 의존한다. wise를 파라미터로 받으면 4 시퀀스 × count 변형이 테이블로 고정되고, 휴리스틱 자체는 `PasteWise(clipboardText:)`가 AppKit 없이 테이블 테스트된다. 읽기 클로저 주입은 `ActionExecutor(postEvent:)`·`EventTapController`의 주입 3종과 같은 seam이다.

**스킵 2종 구분이 필요한 이유**: 어댑터의 미지원 스킵 로그는 요약 1건("미지원 액션 스킵 ×N: <첫 액션>")이고, **단계 4의 릴리스 금지 게이트 해제 판정이 바로 그 로그의 전수 확인**이다. 텍스트 없는 클립보드로 건너뛴 `p`가 여기 집계되면 심사자가 paste를 미구현으로 읽는다. 사유를 아는 자리(어댑터의 클립보드 가드)에서 자체 로그를 남기고 요약 카운터는 건드리지 않는 것이 그 오독을 막는다.

## 검토한 대안

- **paste 전용 5번째 매퍼 분리**: `Cmd-V`와 `Cmd-Z`를 다른 파일에 두게 되는데 그 경계를 정당화하는 불변식이 없다. 붙여넣기도 "위치 접두 + 명령 키 반복"이라는 같은 형태다 — 기각.
- **단일 진입점 + `pasteWise: PasteWise?`**: 위 "진입점 2개인 이유" 참조 — 클립보드 읽기가 다섯 액션 전부로 번진다. 대신 **골든 픽스처는 하나의 배열로 합쳤다**(따로 두면 paste 행이 공통 불변식 테스트를 조용히 빠져나간다).
- **스킵 2종을 로그 문구만으로 구분**: 요약 로그가 개수와 첫 액션만 담아(버스트 대비) 두 종류가 섞이면 분리가 불가능하다 — 기각.

## 영향 범위

- 갱신한 architecture reference: [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md) — 매퍼가 셋에서 넷으로
- 신규: `VimAction/CommandKeyMapper.swift`, `VimAction/Clipboard.swift`, `VimActionTests/CommandKeyMapperTests.swift`
- `KeyboardAdapter`: `readPasteWise` 주입 추가, `keyStrokes(for:)` → `mapping(for:)` 인스턴스 메서드(주입 사용), `Mapping` 3케이스
- `Clipboard`는 `nonisolated`여야 한다 — 프로젝트 기본 격리가 `MainActor`라 그냥 두면 기본 인수 식(nonisolated 컨텍스트에서 평가)에 놓을 수 없다
- 관련: [편집 매핑 계약](20260727_edit-keystroke-mapping-contract.md), [모션 매핑 계약](20260726_motion-keystroke-mapping-contract.md), [미지원 액션은 실패 아님](20260726_unsupported-action-not-failure.md), [릴리스 게이트 M3 이동](20260726_release-block-gate-moves-to-m3.md)

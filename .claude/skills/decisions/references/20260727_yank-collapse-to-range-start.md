# yank collapse는 항상 왼쪽 — 범위 시작으로

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-07-27

## 결정

`yank`는 `Cmd-C` 뒤에 **`←` 한 타**를 붙여 선택을 왼쪽 끝으로 collapse한다. 전진 모션(`yw`)·후진 모션(`yb`)·linewise(`yy`) 구분 없이 단일 규칙이다.

## 배경·근거 (왜)

`delete`/`change`는 선택을 소비해 캐럿이 자연스럽게 한 점으로 남지만, `yank`는 범위를 파괴하지 않아 **선택이 화면에 그대로 남는다**. 남겨 두면 다음 키 입력이 선택을 지우며 이동하는데, 그 착지점은 앱마다 다르고(선택 시작에서 출발하는 앱, 끝에서 출발하는 앱) 시각적으로도 "뭔가 선택된 상태"가 잔류한다. 그래서 collapse는 생략 대상이 아니다 — 엔진도 Visual `y`에 `clearSelection`을 동반시켜 같은 문제를 명시적으로 다룬다 ([20260723_visual-yank-clear-selection.md](20260723_visual-yank-clear-selection.md)).

방향이 `←`인 것은 Vim이 yank 후 커서를 **범위 시작**에 두기 때문이다. macOS 표준 텍스트 시스템에서 선택이 있는 상태의 `←`는 한 칸 더 이동하지 않고 **선택 시작으로 붙는다**. 그리고 선택을 어느 방향으로 만들었든 "선택 시작"은 항상 왼쪽 끝이다 — `yb`처럼 뒤로 선택한 경우에도 왼쪽 끝이 곧 캐럿이 도달한 지점이자 Vim이 말하는 범위 시작이다. 그래서 모션 방향별 분기가 필요 없다.

## 검토한 대안

- **`→`로 범위 끝에 collapse**: 복사 후 이어서 타이핑하는 흐름에는 편하지만 Vim과 다르고, `yy` 후 캐럿이 다음 줄로 넘어가 `p`의 착지점이 어긋난다. 기각.
- **collapse 없이 선택 유지**: 다음 입력의 착지점이 앱마다 갈리고 잔류 선택이 남는다. 기각.
- **모션 방향별 분기**: 왼쪽 끝이 항상 범위 시작이라 분기해도 결과가 같다. 불필요.

## 영향 범위

- `VimAction/EditKeyMapper.swift`의 `apply(_:)` — yank만 `[Cmd-C] + move(.charLeft)`
- 골든 픽스처의 yank 전 행(접미 `Cmd-C`, `←`), 불변식 테스트 "시퀀스는 오퍼레이터 키로 끝난다"
- 단계 2의 Visual `y` collapse 목적지도 같은 규칙을 쓴다 — 엔진이 `clearSelection`으로 신호만 주고 목적지는 어댑터 몫이다.
- 상위 계약: [20260727_edit-keystroke-mapping-contract.md](20260727_edit-keystroke-mapping-contract.md)

# 프로파일 시퀀스 재정의는 모션 단위

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

앱 프로파일의 키 시퀀스 재정의 단위는 **모션**이다. `motions:` 맵이 그 앱에서 모션 매핑 테이블 원소를 교체하며, 이동·편집·Visual이 각각 별도 재정의를 갖지 않는다:

```yaml
motions:
  document_end: [Cmd-Down]
# 자동 전파: G(이동)→Cmd-Down / dG(편집)→Shift-Cmd-Down,Cmd-X / vG(Visual)→Shift-Cmd-Down
```

구현 seam은 **모션 매핑 조회의 단일 지점 래핑** — `EditKeyMapper`(Shift+모션 선택)와 `VisualKeyMapper`(`selectionStrokes` 재사용)가 이미 `MotionKeyMapper`를 경유하므로, 그 조회 하나만 앱별 재정의를 먼저 보게 하면 전파는 기존 구조가 공짜로 해 준다.

## 배경·근거 (왜)

- **전파가 구조에 내장돼 있다**: 편집·Visual이 모션 매핑을 재사용하는 것은 M3 확정 구조다([편집 매핑 계약](20260727_edit-keystroke-mapping-contract.md)). 재정의를 모션 단위로 두면 "모션 하나 고치면 그 모션을 쓰는 모든 어휘가 함께 고쳐진다"는 기존 강점이 프로파일에도 그대로 적용된다.
- **일관성 강제**: 같은 모션이 이동에서는 A 시퀀스, 편집에서는 B 시퀀스로 갈리는 상태를 표현할 수 없게 만든다 — 그 비일관성은 버그이지 기능이 아니다.
- **M3 수용 엣지의 해소 통로**: Notion `Shift-Cmd-↑/↓` 충돌(문서 끝 모션 교체), Chromium 탭 들여쓰기 `^` 퇴행, 소프트 랩 문단 바인딩(백로그 이연 사유가 "앱 커버리지 미검증"이었는데 앱 단위 opt-in이면 그 사유가 소멸) 전부가 이 메커니즘의 적용 대상이다.

## 검토한 대안

- **액션 단위 재정의** (dG·vG·G 각각): 표면이 모션×오퍼레이터 조합으로 폭발하고, 같은 모션의 앱 내 비일관 동작을 허용하게 돼 기각.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md), [strategy-dispatch.md](../../architecture/references/strategy-dispatch.md)의 매퍼 구조에 재정의 조회 지점이 추가된다 (M4 구현 시).
- 필드 구성·키 표기법: [20260801_profile-schema-v1-fields.md](20260801_profile-schema-v1-fields.md)

# 액션 자신의 키도 재정의 대상 — `actions:` 값에 시퀀스 허용

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

`actions:` 값이 `disabled` 외에 **키 시퀀스**도 받는다. 의미론은 **"그 액션 자신의 키를 교체한다"** — 위치를 잡는 모션 접두는 그대로 `motions` 재정의를 따른다:

```yaml
actions:
  open_line: [shift-return]   # o = Cmd-→ + Shift-Return / O = Cmd-← + Shift-Return + ↑
```

- 대상은 자기 키를 가진 넷: `open_line`(Return)·`paste`(Cmd-V)·`undo`(Cmd-Z)·`redo`(Shift-Cmd-Z).
- **`scroll`은 `disabled`만 받는다** — 자기 키가 없고 게시하는 스트로크가 곧 `line_down`/`line_up` 모션이라, 시퀀스 재정의는 모션 재정의와 의미가 겹치고 "줄 수만큼 반복"이라는 카운트 단위와도 충돌한다. 시퀀스 값은 warn+무시.
- 타입은 `motions`와 공유한다 (`MotionOverride` → `ConfigOverride`) — 두 섹션의 값 문법·강건성 규칙이 같으므로 파싱 경로도 하나다.

## 배경·근거 (왜)

- **disable은 위험만 없애고 기능도 함께 잃는다** (사용자 요구, 도그푸딩 실측). Slack에서 `Return`은 메시지 전송이지만 `Shift-Return`은 줄바꿈이다 — `open_line: disabled`는 오발송을 막는 대신 그 앱에서 `o`/`O`를 통째로 죽인다. 앱마다 "줄바꿈 키"가 다르다는 것은 프로파일이 표현해야 할 사실이지, 포기해야 할 기능이 아니다.
- **[모션 단위 재정의 결정](20260801_profile-motion-override-unit.md)의 기각 대상과 다른 축이다.** 그때 기각한 것은 같은 모션을 이동·편집·Visual에서 **각각** 재정의하는 것(`G`·`dG`·`vG` 별도)이고, 기각 사유는 조합 폭발과 앱 내 비일관 동작이었다. 여기서 여는 것은 액션 **자신의 키** 하나이며, 모션 접두는 여전히 `MotionKeyMapper` 단일 조회 지점을 타므로 전파 구조와 일관성 강제가 그대로 유지된다.
- **액션 전체 시퀀스를 교체하지 않는 이유**: `open_line` 하나가 `o`와 `O`를 함께 덮는다. 통째 교체를 허용하면 두 동작이 같은 시퀀스로 붕괴한다(`O`가 `o`로 퇴행 — 첫 줄에서 특히 치명적). 자기 키만 교체하면 `o = 줄 끝 + 줄바꿈`, `O = 줄 시작 + 줄바꿈 + 위`라는 구성이 보존된다.

## 파급 (수용)

**비-QWERTY 레이아웃 가드는 재정의를 보지 않는다** — 재정의된 `undo`·`redo`·`paste`도 여전히 `layoutBlocked`로 보류된다. 설정 어휘에 문자 키가 없어([키워드 소문자](20260802_config-keyword-notation-lowercase.md)) 재정의 시퀀스는 항상 레이아웃 무관이므로 이 보류는 과보수적이지만, 가드를 프로파일 인지로 만드는 복잡도 대비 이득이 없다(비-QWERTY 사용자가 액션 키까지 재정의한 교집합). 실증되면 그때 가드를 프로파일 인지로 바꾼다.

## 검토한 대안

- **`open_line`만 시퀀스 허용**: 필요한 범위는 최소지만 네 액션이 같은 파스 경로를 타므로 특례를 두는 쪽이 오히려 비싸고, 나머지 셋에 같은 요구가 오면 다시 열어야 해서 기각.
- **Slack 전용 하드코딩**: 앱별 특수 동작을 코드에서 빼내는 것이 프로파일의 존재 이유라 기각.
- **`scroll`도 시퀀스 허용** (예: `[page_down]`): 페이지 키 스크롤이 표현되지만, 게시가 "줄 수만큼 반복"이라 `page_down`을 15회 반복하는 오동작이 된다. 반복 단위를 함께 재정의하는 스키마는 v1 범위 밖이라 기각.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md) — `actions` 값 문법과 자기 키 교체 의미론, `scroll` 예외.
- 번들 Slack 프로파일이 `open_line: disabled` → `open_line: [shift-return]`으로 바뀐다 ([동봉 결정](20260802_bundled-default-profiles-slack-notion.md)의 내용 확정).
- 매퍼가 설정 어휘를 모른다는 경계는 유지된다 — `ResolvedProfile`이 자기 키 재정의를 이름 붙인 프로퍼티로 노출하고 `CommandKeyMapper`는 `ConfigAction`을 보지 않는다.

## Supersedes

- [20260802_profile-disable-via-mapping-keyword.md](20260802_profile-disable-via-mapping-keyword.md) — **부분 supersede**: "`actions:`의 v1 값은 `disabled`뿐"이라는 부분만. disable을 매핑 값 `disabled`로 통일한 것, `disabled_actions` 필드 폐기, 빈 배열 `[]`은 warn+무시, 미지 이름 warn+무시는 전부 유효하다.

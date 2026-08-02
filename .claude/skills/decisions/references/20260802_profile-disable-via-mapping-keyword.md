# 프로파일 disable은 매핑 값 `disabled`로 통일 — disabled_actions 폐기

> Superseded (부분) by [20260802_action-own-key-override.md](20260802_action-own-key-override.md) — `actions:` v1 값이 `disabled`뿐이라는 부분이 뒤집힘(자기 키 시퀀스 재정의 허용, `scroll`만 disabled 전용) / disable을 매핑 값으로 통일한 것·`disabled_actions` 폐기·빈 배열 warn+무시는 유효.

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-02

## 결정

프로파일 스키마에서 `disabled_actions` 필드(통제된 그룹 어휘 목록)를 **제거**하고, disable을 **매핑 값 `disabled` 키워드**로 통일한다:

```yaml
motions:
  document_end: [cmd-down]     # 시퀀스 재정의
  document_start: disabled     # 이 모션을 쓰는 어휘 전부(gg·dgg·vgg)가 정직한 스킵
actions:                       # 명령 계열 — v1은 disabled만 (시퀀스 재정의 없음)
  open_line: disabled          # o/O 억제 (Return=전송 앱)
```

- `motions:` 값은 **시퀀스 배열 또는 `disabled`**. 새 섹션 `actions:`의 v1 값은 `disabled`뿐이다.
- `actions:` v1 어휘는 `VimAction` 케이스 파생 snake_case **5종**: `open_line`·`paste`·`undo`·`redo`·`scroll`.
- disable의 실행 의미는 **기존 미지원 스킵과 동일**(매퍼 `nil` 경로 재사용) — 무로그 삼킴은 생기지 않는다.
- **빈 배열 `[]`은 disable이 아니라 warn+무시**다. 오타 가드이자 "지원 ⟹ 빈 시퀀스 아님" 매퍼 불변식의 보호 — 끄려는 의도는 `disabled`로 명시해야 한다.

## 배경·근거 (왜)

- **별도 통제 어휘의 관리 소거** (사용자 제안): `disabled_actions`는 `edit_to_document_edge`(d/c/y×G·gg 6조합) 같은 그룹 이름을 매핑 어휘와 **따로** 정의·관리해야 했다. 매핑 값으로 통일하면 "무엇을 끌 수 있는가" = "무엇이 매핑되어 있는가"로 어휘가 하나가 된다.
- **표현의 일관성**: "그 앱에서 이 항목은 아무 동작도 하지 않는다"가 시퀀스 재정의와 같은 자리·같은 강건성 규칙(미지 이름 warn+무시)으로 표현된다.
- 모션 disable이 편집·Visual로 자동 전파되는 것은 [모션 단위 재정의 결정](20260801_profile-motion-override-unit.md)의 단일 조회 지점을 그대로 타기 때문 — 재정의와 disable이 같은 메커니즘이다.

## 파급 (수용)

disable 단위가 curated 그룹에서 모션·액션 단위로 바뀐다. 기존 `edit_to_document_edge`는 **편집 조합만** 끄고 G·gg 이동은 살렸지만, 새 방식으로 Notion 충돌을 막으려면 `document_start`/`document_end` 모션 자체를 꺼야 해서 **G·gg 이동까지 함께 꺼진다**. 모션 단위 자동 전파의 대칭적 귀결로 수용한다 — "같은 모션이 이동에서는 살고 편집에서는 죽는" 부분 차단이 필요해지면 M5 AX 읽기 혼용(편집을 AX 오프셋으로 정확화)이 그 축을 다룬다.

## 검토한 대안

- **`disabled_actions` 유지 (기존 결정)**: 그룹 단위라 차단 범위는 정밀하지만(이동 생존), 그룹 어휘를 스키마 밖에서 별도로 관리해야 하고 확장마다 새 그룹 이름 정의가 필요해 기각 (사용자 결정).

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md) — 프로파일 필드가 `name`·`scroll`·`motions`·`actions` 넷으로 재구성.
- 번들 기본 프로파일(Slack·Notion)의 내용이 이 표현을 쓴다 ([동봉 결정](20260802_bundled-default-profiles-slack-notion.md)).

## Supersedes

- [20260801_profile-schema-v1-fields.md](20260801_profile-schema-v1-fields.md) — **부분 supersede**: `disabled_actions` 필드만. name·scroll·motions 구성, 문자 키 v1 제외, chunk 비노출, M4 전부 구현은 유효.

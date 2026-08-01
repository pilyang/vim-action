# config.yaml 스키마 v1 — apps 맵과 병합·강건성 규칙

> Superseded (부분) by [20260802_bundled-defaults-seeded-not-merged.md](20260802_bundled-defaults-seeded-not-merged.md) — 공통 규칙 1(3계층 키 단위 병합)이 뒤집힘, `apps` 맵의 근거도 "하위 계층 되켜기"가 아니라 "사용자가 자기 파일에서 앱별 값 지정" / `apps` bool 맵 형태와 규칙 2·3은 유효.

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

`config.yaml`의 앱별 on/off는 **bundle-id를 키로 하는 bool 맵**이다:

```yaml
apps:
  com.mitchellh.ghostty: false
  com.microsoft.VSCode: false
  com.exafunction.windsurf: true   # 번들 기본값이 끈 앱을 되켜기
```

공통 로더 규칙 3종을 함께 확정한다:

1. **3계층 병합은 키 단위** — 번들 기본값 → config.yaml → 프로파일, 뒤 계층이 같은 키만 이긴다.
2. **미지 키·미지 어휘는 warn 로그 + 해당 항목만 무시** — 파일 전체를 실패시키지 않는다 (전방 호환: M5 필드가 미리 적혀 있어도 M4 로더가 안 깨진다). `strategy`·`per_element` 등 전략 필드는 M4에서 파싱하지 않는 미지 키다.
3. **핫 리로드 파싱 실패 시 직전 유효 설정 유지 + error 로그** — 설정 오타가 Vim 레이어를 통째로 죽이면 안 된다.

## 배경·근거 (왜)

- **맵인 이유**: 병합이 키 단위라, 번들 기본값이 끈 앱(VS Code류)을 사용자가 `true`로 되켜는 재정의가 자연스럽게 성립한다. disabled 리스트는 union만 가능해 "하위 계층에서 되켜기"의 표현이 없다 — 리스트를 쓰면 별도 `enabled:` 리스트나 특수 병합 규칙이 필요해진다.
- 미지 키 관용·직전 유지는 "사용자가 파일을 직접 편집한다"는 [설정 루트 결정](20260801_config-root-dot-config.md)의 전제에서 따라온다 — 손편집은 오타·미래 필드 선기입이 일상이다.

## 검토한 대안

- **disabled 리스트** (`apps: {disabled: [...]}`): 더 읽기 쉽지만 위의 되켜기 표현 부재로 기각.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- 선행 결정: [앱별 on/off config.yaml 단일 소유](20260801_app-enable-config-yaml-only.md) — 이 문서는 그 형태의 확정.

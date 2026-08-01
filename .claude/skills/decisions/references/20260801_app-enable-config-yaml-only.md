# 앱별 on/off는 config.yaml 단일 소유

<!-- 파일명 규칙: yyyymmdd_<kebab-case-title>.md — 날짜는 결정일. 이 문서는 결정의 불변 스냅샷이며, 기록 후 수정하지 않습니다 (Superseded 마킹 1줄 제외). -->

- **결정일**: 2026-08-01

## 결정

앱별 활성화/비활성화(on/off)는 **`config.yaml`에서만** 관리한다. 앱별 프로파일(`profiles/<bundle-id>.yaml`)의 스키마에서 `enabled` 필드를 **제거**한다 — 프로파일의 역할은 일부 특수한 앱에 대한 키맵핑 등 동작 고도화 전용이며, on/off 게이트가 아니다.

함께 확정된 것: 앱별 토글 상태의 저장소는 UserDefaults가 아니라 YAML(config.yaml)이다 — 사용자가 파일로 직접 관리·수정하는 대상이기 때문이다.

## 배경·근거 (왜)

- **중복 관리 제거**: `enabled`가 프로파일에도 있으면 앱 하나를 끌 때마다 `profiles/`에 그 앱 전용 파일이 하나씩 생긴다. disable 목록은 시간이 지날수록 늘어나는 성격이라, 프로파일 디렉토리가 "끈 앱 파일 무덤"이 된다. on/off는 목록 성격의 데이터이므로 메인 설정 파일 한 곳의 목록으로 두는 것이 관리 단위와 맞는다.
- **프로파일의 목적 재확인**: `profiles/`는 Slack의 Return=전송, Notion의 블록 이동 충돌처럼 **그 앱에서만 필요한 동작 재정의**를 담는 곳이다. 대부분의 앱은 프로파일 파일이 필요 없어야 정상이다.
- **YAML 소유인 이유**: 앱별 on/off는 사용자가 직접 편집하는 설정이다 ([설정 루트 이동 결정](20260801_config-root-dot-config.md)과 같은 근거). 마스터 토글·킬스위치 off 영속 등 앱 내부 상태의 UserDefaults 소유([20260718 설정 소유 모델](20260718_interception-toggle-semantics.md))는 이 결정의 범위 밖이며 그대로다 — 경계의 세부(설정 UI의 앱별 목록이 YAML을 읽고 쓰는 방식 등)는 M4 구현 시 확정한다.

## 검토한 대안

- **프로파일별 `enabled` (기존 스케치, PRD §7.4 유래)**: 위의 파일 증식 문제. 또한 같은 값이 두 계층에 존재하면 재정의 규칙(어느 쪽이 이기는가)을 정의·문서화·테스트해야 하는 비용이 생기는데, 그 비용이 사는 가치가 없다.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md) — 스키마 스케치에서 `enabled` 제거, config.yaml 역할 명시.
- M2 하드코딩 disable 목록(ghostty)의 M4 교체 대상이 "프로파일"에서 "**config.yaml의 앱별 on/off 목록**"으로 구체화된다.
- 프로파일 스키마 스케치(PRD §7.4 유래)는 신뢰도가 낮아 **M4에서 재설계**한다 — PRD는 구현 시작 전 초기 계획 문서로 이후 관리되지 않았고, 방향 참고용이지 스키마 SSOT가 아니다.

## Supersedes

- 없음 (스키마는 스케치 단계였고 확정 결정이 아니었다 — [20260712_yaml-three-layer-config.md](20260712_yaml-three-layer-config.md)의 3계층 구조 자체는 불변).

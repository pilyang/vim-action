# 프로파일과 설정

- **Last updated**: 2026-07-12

## 현재 구조

설정은 전부 YAML이며 **Yams**로 파싱한다. 디스크 루트는 `~/Library/Application Support/VimAction/`. 3계층 재정의 구조를 가지며, 파일 변경 시(`DispatchSource.makeFileSystemObjectSource`) 자동 리로드한다.

계층 (아래가 위를 재정의):

1. 번들 기본값 — 앱 내부 읽기 전용 리소스.
2. 사용자 설정 — `~/Library/Application Support/VimAction/config.yaml`.
3. 앱별 프로파일 — `~/Library/Application Support/VimAction/profiles/<bundle-id>.yaml`.

각 계층이 재정의할 수 있는 것: 키맵, 전역 Escape 매핑, 활성화된 앱, 전략 선택.

앱별 프로파일 스키마 (스케치 — 정식 버전은 워크스페이스 `docs/prd.md` §7.4):

```yaml
bundle_id: com.tinyspeck.slackmacgap
name: Slack
enabled: true
strategy: keyboard            # accessibility | keyboard | auto
keyboard_family: key-mapping  # key-mapping | force-text  (strategy=keyboard일 때만)
keymap_overrides:
  insert_to_normal: ["Escape", "jk"]
per_element:
  - axrole: AXWebArea
    strategy: keyboard
    keyboard_family: force-text
disable_in_elements:
  - axrole: AXScrollArea
```

## 불변식·계약

- 설정 파서는 Yams 단일 의존 — 다른 포맷/파서를 섞지 않는다.
- 하위 계층은 상위 계층이 정의한 키만 재정의하며, 계층 간 침범이 없다.

## 근거 요약

번들 기본값으로 바로 동작하되 사용자/앱별 미세 조정을 얹을 수 있어야 하고, YAML을 직접 편집하는 사용자가 앱을 재시작하지 않아도 되도록 파일 감시 리로드를 둔다.

- 관련 결정: [20260712_yaml-three-layer-config.md](../../decisions/references/20260712_yaml-three-layer-config.md)

## 관련

- 소비자: [strategy-dispatch.md](strategy-dispatch.md) (프로파일이 전략 선택 1단계)
- 요구사항: 워크스페이스 `docs/prd.md` §7.4

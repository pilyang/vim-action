# 프로파일과 설정

- **Status**: accepted
- **Date**: 2026-07-12

## 결정

설정은 전부 YAML이며 **Yams**로 파싱한다. 디스크 루트는 `~/Library/Application Support/VimAction/`. 3계층 재정의 구조를 가지며, 파일 변경 시 자동 리로드한다.

## 근거 (왜)

- 파일 변경 감시(`DispatchSource.makeFileSystemObjectSource`)로 자동 리로드하는 이유: YAML을 직접 편집하는 사용자/컨트리뷰터가 앱을 재시작할 필요가 없어야 한다.
- 계층 구조인 이유: 번들 기본값으로 바로 동작하되, 사용자 전역 설정과 앱별 미세 조정을 서로 침범 없이 얹을 수 있어야 한다.

## 상세

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

## 관련

- 소비자: [strategy-dispatch.md](strategy-dispatch.md) (프로파일이 전략 선택 1단계)
- 요구사항: 워크스페이스 `docs/prd.md` §7.4

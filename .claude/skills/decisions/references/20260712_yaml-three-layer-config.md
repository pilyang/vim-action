# YAML 3계층 설정

- **결정일**: 2026-07-12

## 결정

설정은 전부 YAML이며 **Yams**로 파싱한다. 디스크 루트는 `~/Library/Application Support/VimAction/`. 번들 기본값 → 사용자 설정(`config.yaml`) → 앱별 프로파일(`profiles/<bundle-id>.yaml`)의 3계층 재정의 구조를 가지며, 파일 변경 시(`DispatchSource.makeFileSystemObjectSource`) 자동 리로드한다.

## 배경·근거 (왜)

- 파일 변경 감시로 자동 리로드하는 이유: YAML을 직접 편집하는 사용자/컨트리뷰터가 앱을 재시작할 필요가 없어야 한다.
- 계층 구조인 이유: 번들 기본값으로 바로 동작하되, 사용자 전역 설정과 앱별 미세 조정을 서로 침범 없이 얹을 수 있어야 한다.

## 영향 범위

- 갱신한 architecture reference: [profiles-and-config.md](../../architecture/references/profiles-and-config.md)
- 프로파일이 전략 선택의 1단계: [20260712_ax-keyboard-strategy-dispatch.md](20260712_ax-keyboard-strategy-dispatch.md)

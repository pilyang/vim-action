# Normal 모드의 매핑 없는 modifier 조합은 passthrough

- **결정일**: 2026-07-12

## 결정

Normal 모드에서 매핑되지 않은 키 중 **modifier(Ctrl/Option/Command)가 붙은 조합은 앱으로 통과**시키고, modifier 없는 미매핑 키만 삼킨다.

## 배경·근거 (왜)

Vim에는 Cmd 키가 없어 참고할 원본 동작이 없고, macOS 사용자는 Normal 모드 중에도 Cmd+C(복사), Cmd+S(저장) 같은 시스템·앱 단축키가 동작하길 기대한다. "매핑 안 된 키는 전부 swallow"를 유지하면 Normal 모드에서 이 단축키들이 전부 죽는다. 반대로 modifier 없는 미매핑 키(예: 아직 지원 안 하는 `x`)는 삼켜야 Normal 모드의 키가 앱에 새서 텍스트를 오염시키지 않는다. 이후 Ctrl-d 스크롤 등을 매핑하면 그 키만 매핑 테이블에 추가해 가로채면 되므로 확장과도 충돌하지 않는다. 사용자 확인을 거친 결정 (2026-07-12).

## 검토한 대안

- **전부 swallow (현행 유지)**: 가장 Vim-pure하지만 Normal 모드 중 복사/저장/찾기가 안 되는 실사용 비용이 커서 기각.
- **Cmd 조합만 passthrough**: Vim이 Ctrl을 많이 쓰므로 미리 예약하는 의미가 있지만, 매핑 전인 Ctrl 키까지 죽이는 비용이 있고 매핑 시점에 가로채면 충분해서 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift`의 `handleNormal` 폴백 규칙, `Tests/VimEngineTests/MotionFixtures.swift`의 modifier 가드 픽스처.

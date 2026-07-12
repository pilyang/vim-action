# 멀티키 pending의 무효 연속 키는 no-op

- **결정일**: 2026-07-12

## 결정

Normal 모드에서 멀티키 시퀀스의 첫 키(`g` 등)로 pending 상태가 된 뒤 무효한 연속 키가 오면, pending과 그 키를 **함께 버리고 둘 다 삼킨다** (no-op). Esc는 pending 취소로만 소비된다. 엔진은 pending 해소에 타임아웃을 두지 않는다 — 오직 다음 키로만 해소된다.

## 배경·근거 (왜)

`gg`가 1차 키셋의 유일한 멀티키 시퀀스라 pending 처리 규칙이 처음 필요해졌다. Vim의 실제 동작(무효 커맨드는 아무 일도 안 함)과 일치하고, 규칙이 결정론적이라 픽스처 테스트로 검증하기 쉽다. 타임아웃을 엔진에 두지 않는 것은 순수 엔진의 결정론(같은 키 시퀀스 → 같은 출력)을 지키기 위함이다. 사용자 확인을 거친 결정 (2026-07-12).

주의: `gi`는 실제 Vim 커맨드(마지막 삽입 위치로 insert 진입)라서 `g`→`i`가 no-op인 현재 동작은 미지원 커맨드의 no-op일 뿐이다. 이후 `gi`를 지원하면 유효 연속으로 바뀌며, 이 결정(무효 연속의 no-op 규칙)과 충돌하지 않는다.

## 검토한 대안

- **pending을 버리고 두 번째 키를 새 입력으로 재처리** (`g`→`h`면 h 모션 실행): 오타 시 이동이 씹히지 않는 장점이 있지만 Vim 동작과 다르고, "키가 두 번 해석되는" 경로가 생겨 규칙이 복잡해져 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- `Packages/VimActionCore/Sources/VimEngine/VimEngine.swift`의 `Pending` 상태와 `resolve(_:then:)`, `Tests/VimEngineTests/MotionFixtures.swift`의 pending 경계 픽스처.

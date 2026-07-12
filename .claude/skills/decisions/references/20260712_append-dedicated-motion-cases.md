# append 계열(a/A)은 전용 Motion 케이스

- **결정일**: 2026-07-12

## 결정

`a`/`A`의 진입 이동은 기존 모션 케이스(`charRight`/`lineEnd`)를 재사용하지 않고 전용 케이스 `Motion.charRightForAppend`/`Motion.lineEndForAppend`로 둔다. `I`는 목표 위치가 `^`와 동일하므로 `lineFirstNonBlank`를 재사용한다.

## 배경·근거 (왜)

Vim에서 `l`은 줄 끝 문자 **위**에서 멈추고 `$`도 마지막 문자 **위**로 가지만, `a`/`A`는 마지막 문자 **뒤**(insert 지점)까지 간다. 케이스를 공유하면 어댑터(전략 디스패처 단계)가 "l의 오른쪽 이동"과 "a의 오른쪽 이동"을 구분할 수 없어, 줄 끝에서 `a`가 다음 줄로 새는 등의 미세 동작을 교정할 여지가 사라진다. macOS caret 모델(문자 사이)과 Vim 블록 커서 모델(문자 위)의 차이를 흡수하는 것은 어댑터의 몫이므로, 엔진은 의도가 다른 이동을 다른 케이스로 전달해야 한다. 케이스 두 개 추가가 비용의 전부다. 사용자 확인을 거친 결정 (2026-07-12).

## 검토한 대안

- **`charRight`/`lineEnd` 재사용**: 단순하지만 어댑터가 append 의도를 잃어 줄 끝 시맨틱을 맞출 수 없어 기각.
- **MVP에서 `a` ≡ `i` 단순화**: 가장 단순하지만 Vim 사용자 기대(커서 뒤 삽입)와 달라 기각.

## 영향 범위

- 갱신한 architecture reference: [mode-engine.md](../../architecture/references/mode-engine.md)
- `Packages/VimActionCore/Sources/VimEngine/VimAction.swift`의 `Motion` 케이스, `VimEngine.swift`의 a/I/A 처리. 어댑터 구현 시(다음 플랜) 이 두 케이스의 줄 끝 동작을 별도 구현해야 한다.

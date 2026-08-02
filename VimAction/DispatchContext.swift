//
//  DispatchContext.swift
//  VimAction
//

import Foundation

/// 실행 sink에 실리는 **키 입력 시점의 컨텍스트 스냅샷** — 요소 계열, 대상 앱 pid,
/// 최전면 앱 프로파일.
///
/// 콜백(메인)이 캐시에서 읽어 값으로 넘긴다: 게시 큐가 나중에 캐시를 읽으면 그 사이
/// 포커스·최전면 앱이 옮겨간 뒤일 수 있다 (`KeyboardAdapter.execute`의 family 계약과
/// 같은 규칙). 필드가 늘어도 sink 시그니처(2인자)가 유지되는 것도 요점이다 — 기존
/// 테스트 클로저가 깨지지 않는다.
nonisolated struct DispatchContext: Equatable, Sendable {
    var family: ElementFamily = .textArea
    /// 디스패치 경로 AX 읽기의 대상 앱. **pid만 싣는 것이 규칙이다** — 게시 큐가 이 값으로
    /// `AXUIElement`를 큐 위에서 만들므로 비-`Sendable` 값이 격리를 건너지 않는다
    /// (`20260802_dispatch-read-on-posting-queue.md` ②).
    ///
    /// 출처가 `FocusedElementResolver`인 것도 계약이다: 리더가 겨냥하는 대상(포커스 요소)의
    /// 소유자와 같아야 `family`와 pid가 서로 다른 앱을 가리키는 일이 없다.
    var processID: pid_t?
    var profile: ResolvedProfile = .empty
}

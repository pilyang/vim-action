//
//  DispatchContext.swift
//  VimAction
//

/// 실행 sink에 실리는 **키 입력 시점의 컨텍스트 스냅샷** — 요소 계열과 최전면 앱 프로파일.
///
/// 콜백(메인)이 캐시에서 읽어 값으로 넘긴다: 게시 큐가 나중에 캐시를 읽으면 그 사이
/// 포커스·최전면 앱이 옮겨간 뒤일 수 있다 (`KeyboardAdapter.execute`의 family 계약과
/// 같은 규칙). 필드가 늘어도 sink 시그니처(2인자)가 유지되는 것도 요점이다 — 기존
/// 테스트 클로저가 깨지지 않는다.
nonisolated struct DispatchContext: Equatable, Sendable {
    var family: ElementFamily = .textArea
    var profile: ResolvedProfile = .empty
}

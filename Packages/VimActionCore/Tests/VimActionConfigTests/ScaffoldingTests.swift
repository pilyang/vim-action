import Testing
import Yams

@testable import VimActionConfig

/// 타깃·의존이 실제로 링크되는지 확인하는 스모크 테스트.
/// (Yams가 이 저장소의 첫 외부 의존이라, 해석·링크 자체가 한 번은 검증돼야 한다.)
@Test
func yamsDependencyLinks() throws {
    let node = try #require(try Yams.compose(yaml: "apps:\n  com.foo: true\n"))
    #expect(node.mapping?["apps"]?.mapping?["com.foo"]?.bool == true)
}

import Testing

@testable import VimEngine

/// 선행 카운트(`3w`) 픽스처.
///
/// 규칙: digit 1–9는 항상 카운트 누적을 시작/연장하고, `0`은 카운트 슬롯이
/// 비어 있으면 모션(lineStart), 누적 중이면 자리값이다 (`1`→`0` = 10).
/// 카운트 붙은 모션은 `.move` 반복으로 출력한다 — `.move`에 count 슬롯을
/// 추가하지 않아 기존 단일 모션 픽스처가 전부 count 1로 회귀 통과한다.

let countMotionFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "3w → wordForward ×3 반복",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("w"), .replace([.move(.wordForward), .move(.wordForward), .move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "10j → 0이 자리값으로 붙어 lineDown ×10",
        startMode: .normal,
        steps: [
            step(.char("1"), .swallow),
            step(.char("0"), .swallow),
            step(.char("j"), .replace(Array(repeating: VimAction.move(.lineDown), count: 10))),
        ],
        finalMode: .normal
    ),
    // 절대 목표 모션의 count는 Vim 의미(3G=3번째 줄)와 다르지만 멱등 반복이라
    // 무해함을 인지한 채 수용한다 — line-target count는 이후 확장. 여기 핀은
    // "현재는 반복 출력"이라는 계약의 고정이다.
    KeySequenceFixture(
        "3G → documentEnd ×3 반복 수용 (절대 모션 핀)",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("G"), .replace([.move(.documentEnd), .move(.documentEnd), .move(.documentEnd)])),
        ],
        finalMode: .normal
    ),
    // mode-change 키의 count 무시와 같은 원칙 — g 접두 complete 시 count를 버린다.
    KeySequenceFixture(
        "3gg → count 무시하고 documentStart 단일 출력",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("g"), .swallow),
            step(.char("g"), .replace([.move(.documentStart)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: countMotionFixtures)
func countMotions(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 카운트 누적은 9,999에서 클램프한다 — 초과 자리 digit은 무시하고 누적 상태를
// 유지한다. 무제한이면 Int 오버플로 트랩(시스템 전역 훅 크래시)과 반복 출력
// 배열 폭주(탭 콜백 타임아웃) 리스크가 있다.
let countClampFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "99999j → 9,999로 클램프된 lineDown 반복",
        startMode: .normal,
        steps: [
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("9"), .swallow),
            step(.char("j"), .replace(Array(repeating: VimAction.move(.lineDown), count: 9_999))),
        ],
        finalMode: .normal
    )
]

@Test(arguments: countClampFixtures)
func countClamp(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

let countEdgeFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "카운트 후 무효 키(q)는 둘 다 버리는 no-op — 이후 j는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("q"), .swallow),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "카운트 입력 중 Esc는 카운트 취소 — 이후 j는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.escape, .swallow),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
    // 3i 류 반복 삽입은 범위 밖 — 선행 count가 있어도 i는 그냥 Insert 진입.
    KeySequenceFixture(
        "3i → count 무시하고 Insert 진입",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("i"), .swallow),
        ],
        finalMode: .insert
    ),
    // digit도 modifier가 붙으면 카운트가 아니다 — 미매핑 콤보로 통과.
    KeySequenceFixture(
        "Ctrl+3은 카운트 아님 — 미매핑 콤보로 통과",
        startMode: .normal,
        steps: [step(.char("3", [.control]), .passthrough)],
        finalMode: .normal
    ),
]

@Test(arguments: countEdgeFixtures)
func countEdges(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

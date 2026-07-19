import Testing

@testable import VimEngine

/// linewise TextRange 픽스처 — 오퍼레이터 뒤 줄 단위 모션(`dj`/`dk`/`dG`/`dgg`)의
/// 커버. 상대 모션(j/k)만 카운트가 적용되고, 절대 모션(G/gg)은 카운트가
/// 하나라도 있으면 invalid다 (Vim의 d3G는 "3번 줄까지"라는 절대 의미인데
/// 표현할 수 없고, 파괴적 편집이라 오해석 대신 이연).

// 기본 완결 — 상대(j/k)와 절대(G/gg) 전수, delete 기준.
let linewiseBasicFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "dj → delete linewise lineDown",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("j"), .replace([.edit(.delete, .linewiseMotion(.lineDown, count: 1))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "dk → delete linewise lineUp",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("k"), .replace([.edit(.delete, .linewiseMotion(.lineUp, count: 1))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "dG → delete linewise documentEnd",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("G"), .replace([.edit(.delete, .linewiseMotion(.documentEnd, count: 1))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "dgg → delete linewise documentStart (g는 op-pending에서 extend)",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("g"), .swallow),
            step(.char("g"), .replace([.edit(.delete, .linewiseMotion(.documentStart, count: 1))])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: linewiseBasicFixtures)
func linewiseBasics(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 오퍼레이터별 모드 전이 — change는 Insert, yank는 Normal 유지.
let linewiseModeTransitionFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "cj → change linewise, Insert 전이 — 이후 키는 통과",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("j"), .replace([.edit(.change, .linewiseMotion(.lineDown, count: 1))])),
            step(.char("w"), .passthrough),
        ],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "cgg → change linewise documentStart, Insert 전이",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("g"), .swallow),
            step(.char("g"), .replace([.edit(.change, .linewiseMotion(.documentStart, count: 1))])),
        ],
        finalMode: .insert
    ),
    KeySequenceFixture(
        "yk → yank linewise, Normal 유지 — 이후 j는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("y"), .swallow),
            step(.char("k"), .replace([.edit(.yank, .linewiseMotion(.lineUp, count: 1))])),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "ygg → yank linewise documentStart, Normal 유지",
        startMode: .normal,
        steps: [
            step(.char("y"), .swallow),
            step(.char("g"), .swallow),
            step(.char("g"), .replace([.edit(.yank, .linewiseMotion(.documentStart, count: 1))])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: linewiseModeTransitionFixtures)
func linewiseModeTransitions(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 상대 모션 카운트 — 기존 곱 규칙 그대로 (선행 × op 뒤).
let linewiseCountFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "d2j → linewise lineDown count 2 (opCount)",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("2"), .swallow),
            step(.char("j"), .replace([.edit(.delete, .linewiseMotion(.lineDown, count: 2))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "2dj → linewise lineDown count 2 (선행 카운트)",
        startMode: .normal,
        steps: [
            step(.char("2"), .swallow),
            step(.char("d"), .swallow),
            step(.char("j"), .replace([.edit(.delete, .linewiseMotion(.lineDown, count: 2))])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "2d3j → 카운트 곱 6",
        startMode: .normal,
        steps: [
            step(.char("2"), .swallow),
            step(.char("d"), .swallow),
            step(.char("3"), .swallow),
            step(.char("j"), .replace([.edit(.delete, .linewiseMotion(.lineDown, count: 6))])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: linewiseCountFixtures)
func linewiseCounts(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// 절대 모션 + 카운트는 invalid — 선행·op 뒤 어느 쪽이든. change가 무효로
// 끝나면 Insert 전이도 없다.
let linewiseAbsoluteCountFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "d3G → no-op — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("3"), .swallow),
            step(.char("G"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "3dG → no-op — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("d"), .swallow),
            step(.char("G"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "d3gg → no-op (완결 시점 판정) — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("3"), .swallow),
            step(.char("g"), .swallow),
            step(.char("g"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "3dgg → no-op — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("d"), .swallow),
            step(.char("g"), .swallow),
            step(.char("g"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "c3gg → no-op — Insert 진입 없음",
        startMode: .normal,
        steps: [
            step(.char("c"), .swallow),
            step(.char("3"), .swallow),
            step(.char("g"), .swallow),
            step(.char("g"), .swallow),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: linewiseAbsoluteCountFixtures)
func linewiseAbsoluteCounts(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

// op-pending g 접두의 무효 완결 — g 뒤 유효 연속은 g뿐이고, 무효 키는
// pending과 함께 버려진다 (dg 후 첫 키는 삼켜지고 그다음 키부터 정상).
let linewiseGPrefixInvalidFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "dg 후 무효 키(w)는 폐기 — 그다음 w부터 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("g"), .swallow),
            step(.char("w"), .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "dg 후 Esc는 취소 — 이후 w는 단일 모션",
        startMode: .normal,
        steps: [
            step(.char("d"), .swallow),
            step(.char("g"), .swallow),
            step(.escape, .swallow),
            step(.char("w"), .replace([.move(.wordForward)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: linewiseGPrefixInvalidFixtures)
func linewiseGPrefixInvalids(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

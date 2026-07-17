import Testing

@testable import VimEngine

/// 편집 커맨드(`.edit` 출력) 픽스처 — `x`, `d`+모션, `dd`, 텍스트 오브젝트.

// `x`는 전용 케이스가 아니라 delete-over-motion의 재사용이다 —
// `.edit(.delete, .motion(.charRight, count:))`. 줄 끝 문자 삭제 같은 경계는
// 어댑터 몫 (charRight/charRightForAppend 분리와 동일 원칙).
let deleteCharFixtures: [KeySequenceFixture] = [
    KeySequenceFixture(
        "x → delete over charRight ×1",
        startMode: .normal,
        steps: [step(.char("x"), .replace([.edit(.delete, .motion(.charRight, count: 1))]))],
        finalMode: .normal
    ),
    KeySequenceFixture(
        "3x → delete over charRight ×3 (한 편집 단위)",
        startMode: .normal,
        steps: [
            step(.char("3"), .swallow),
            step(.char("x"), .replace([.edit(.delete, .motion(.charRight, count: 3))])),
        ],
        finalMode: .normal
    ),
    // 편집 후에도 Normal 유지 — 후속 키가 정상 동작하는지 겸사 확인.
    KeySequenceFixture(
        "x 후 j는 단일 모션 — 편집이 pending을 남기지 않는다",
        startMode: .normal,
        steps: [
            step(.char("x"), .replace([.edit(.delete, .motion(.charRight, count: 1))])),
            step(.char("j"), .replace([.move(.lineDown)])),
        ],
        finalMode: .normal
    ),
]

@Test(arguments: deleteCharFixtures)
func deleteChar(_ fixture: KeySequenceFixture) {
    expectFixture(fixture)
}

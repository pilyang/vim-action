//
//  KeyboardAdapter.swift
//  VimAction
//

import CoreGraphics
import Foundation
import os
import VimActionConfig
import VimEngine

/// Keyboard 전략의 실행 어댑터 — 엔진이 낸 `VimAction`을 합성 `CGEvent`로 바꿔
/// `ActionExecutor`로 내보낸다.
///
/// **호출은 게시 직렬 큐 위에서** 한다: `CGEvent`는 비-`Sendable`이라 만든 컨텍스트에서
/// 게시까지 끝내야 하고(격리를 건너는 값이 애초에 없게), 탭 콜백은 경량 불변식에 묶여 있다.
/// 그래서 타입 단위 `nonisolated`다 — 메인 격리를 가정하지 않는다.
///
/// 실행 범위는 v1 어휘 전체다 — 이동(`.move`), 편집(`.edit`), Visual 선택 세션, 그리고
/// 네이티브 명령 위임(`.openLine`·`.paste`·`.undo`·`.redo`·`.scroll`). 아직 구현하지 않은
/// 액션은 **실패가 아니다** — 조용히 스킵하고 DEBUG 로그만 남긴다
/// (`20260726_unsupported-action-not-failure.md`).
nonisolated struct KeyboardAdapter: Sendable {
    private let executor: ActionExecutor

    /// 붙여넣기 단위 판정. 우리가 게시한 편집의 wise를 기억하므로 **상태를 가진 참조 타입**이며,
    /// 게시 직렬 큐가 단독 소유한다. 주입하는 이유는 `ActionExecutor.postEvent`와 같다 —
    /// 실제 패스트보드를 읽으면 테스트가 **개발자의 클립보드**에 따라 갈려 비결정적이 된다.
    private let pasteWise: PasteWiseResolver

    /// 합성 명령 키(`Cmd-Z/X/C/V`)의 물리 위치가 QWERTY와 일치하는가. 주입하는 이유는
    /// `pasteWise`와 같다 — 실제 값(`KeyTranslator.hasQwertyCommandKeys`)을 읽으면 테스트가
    /// 개발자 머신의 레이아웃에 따라 갈린다. 클로저인 이유: 값은 레이아웃 전환으로 실행 중
    /// 바뀌므로 액션마다 다시 물어야 한다.
    private let hasQwertyCommandKeys: @Sendable () -> Bool

    /// 캐럿 주변 텍스트 리더 — 무상태 시퀀스를 정확화하는 입력이다. 주입하는 이유는
    /// `pasteWise`와 같다: 실제 AX를 읽으면 골든 테스트가 실기기 권한과 개발자 머신의
    /// 포커스 상태에 따라 갈린다.
    ///
    /// 소비자는 `mapping`의 `.edit` 분기와 Visual 세션 분기 **두 곳**이다. 편집은 범위가
    /// 캐럿 주변을 묻는 경우(`EditKeyMapper.consultsFocusedText`)에만 읽는 **범위 술어**,
    /// Visual은 앵커 상태의 수립·검증 때문에 읽는 **세션 술어**다 — 모션·paste·undo는
    /// 묻지 않으므로 AX 왕복이 0건이다. 읽기가 실패하면 정확화만 포기하고 실행은 한다.
    private let reader: FocusedTextReader

    /// Visual 세션의 앵커 상태 — `pasteWise`와 같은 형태의 상태 보유 협력자이며 게시 직렬
    /// 큐가 단독 소유한다. 주입하는 이유도 같다: 골든 테스트가 세션 중간 상태를 실기기
    /// 없이 만든다 (`20260804_visual-anchor-state-collaborator.md`).
    private let visualAnchor: VisualAnchorTracker

    init(
        executor: ActionExecutor = ActionExecutor(),
        pasteWise: PasteWiseResolver = PasteWiseResolver(),
        hasQwertyCommandKeys: @escaping @Sendable () -> Bool = {
            KeyTranslator.hasQwertyCommandKeys
        },
        reader: FocusedTextReader = FocusedTextReader(),
        visualAnchor: VisualAnchorTracker = VisualAnchorTracker()
    ) {
        self.executor = executor
        self.pasteWise = pasteWise
        self.hasQwertyCommandKeys = hasQwertyCommandKeys
        self.reader = reader
        self.visualAnchor = visualAnchor
    }

    /// 키 입력 1건이 만든 액션 시퀀스를 실행한다.
    ///
    /// **통짜로 게시하지 않고 청크로 나눠 게시하며, 청크 사이마다 `isCurrent`에 묻는다.**
    /// `1000j`·`1000p`급 버스트를 킬스위치·새 입력·토글 off가 도중에 끊을 수 있게 하는 것이
    /// 목적이고(`ExecutionAbortLatch`), 생성도 청크 단위로 미뤄져 게시 전에 이벤트 2,000개를
    /// 통째로 만들지 않는다. `isCurrent`가 false를 내는 순간 **잔여는 게시되지 않는다.**
    ///
    /// 기본값 `{ true }`는 "중단 없음" — 중단이 관심사가 아닌 호출자(대부분의 테스트)를 위한
    /// 것이고, 프로덕션 경로는 `EventTapController.keyboardActionSink`가 항상 주입한다.
    ///
    /// `family`는 **키 입력 시점의 스냅샷**이다 — 컨트롤러가 콜백에서 캐시를 읽어 넘긴다.
    /// 게시 큐 위에서 뒤늦게 읽으면 그 사이 포커스가 옮겨간 뒤일 수 있고, 그러면 이미 결정된
    /// 시퀀스가 다른 요소를 기준으로 걸러지거나 통과한다. 기본값 `.textArea`는 계열이 관심사가
    /// 아닌 호출자(대부분의 테스트)를 위한 것이며 폴백 기본값과 같은 값이다.
    ///
    /// `profile`도 같은 이유의 스냅샷이다 — 최전면 앱의 프로파일을 컨트롤러가 콜백에서
    /// 캐시로 읽어 넘긴다. 기본값 `.empty`는 프로파일이 관심사가 아닌 호출자를 위한 것이다.
    ///
    /// `processID`만은 **스냅샷이되 값이 아니라 대상**이다 — 이 pid로 아래에서 액션마다
    /// 캐럿 주변을 다시 읽는다(lazy). 계열·프로파일과 시점 요구가 정반대이기 때문이다:
    /// 같은 버스트의 앞 액션이 캐럿을 옮기므로 선택 범위는 실행 직전 값만 정확하다.
    /// 기본값 `nil`은 읽기가 관심사가 아닌 호출자(대부분의 테스트)를 위한 것이며,
    /// 그때 리더는 아예 불리지 않는다.
    func execute(
        _ actions: [VimAction], family: ElementFamily = .textArea,
        profile: ResolvedProfile = .empty, processID: pid_t? = nil,
        isCurrent: () -> Bool = { true }
    ) {
        // dispatch 직후 곧바로 다음 키에 밀려난 경우 — 한 이벤트도 내보내지 않는다.
        guard isCurrent() else { return }

        #if DEBUG
        var skippedCount = 0
        var firstSkipped: VimAction?
        var layoutBlockedCount = 0
        var firstLayoutBlocked: VimAction?
        var disabledCount = 0
        var firstDisabled: VimAction?
        #endif
        /// 아직 청크 크기에 못 미쳐 게시를 미뤄 둔 이벤트.
        var pending: [CGEvent] = []
        var pendingStrokes = 0
        var postedChunks = 0

        /// 미뤄 둔 이벤트를 게시한다. 두 번째 청크부터는 앞에 간격을 둔다.
        ///
        /// 최신 여부 재확인은 **페이싱 뒤, 게시 직전**이다 — 간격에 잠들어 있는 동안 무효화가
        /// 오면 이 청크째 폐기된다. 체크가 sleep보다 앞이면 무효화 **뒤에도** 청크 하나가 더
        /// 나가고, 그 화살표들이 새 사용자 키와 인터리브돼 문서를 오염시킨다 (실기기 실증 —
        /// 도그푸딩에서 3ms 창이 정확히 1청크 폭의 순서 역전으로 나타났다).
        /// 반환 false = 이 실행이 밀려남 — 호출자는 즉시 그만둔다.
        @discardableResult
        func flush() -> Bool {
            guard !pending.isEmpty else { return true }
            if postedChunks > 0 { Thread.sleep(forTimeInterval: Self.chunkInterval) }
            guard isCurrent() else {
                #if DEBUG
                Logger.eventTap.debug("실행 중단 — 잔여 폐기 (게시 청크 \(postedChunks, privacy: .public))")
                #endif
                return false
            }
            executor.post(pending)
            pending.removeAll(keepingCapacity: true)
            pendingStrokes = 0
            postedChunks += 1
            return true
        }

        /// 페이싱 다타 그룹(Visual 정확화·paste 접두)을 **스트로크(다운·업 쌍) 사이 고정
        /// 간격**으로 게시한다 —
        /// Notion 실측에서 0간격 버스트는 재앵커의 Shift 확장을 소화하지 못했다(이벤트당
        /// 5ms 프로브는 완전 정상 — 간격 문제로 확정). 그룹은 원자라 내부 중단 확인은 없다
        /// (최대 수 타 × 5ms라 무해). 최신 여부 확인·중단 계약은 `flush`와 같다.
        /// 반환 false = 이 실행이 밀려남 — 호출자는 즉시 그만둔다.
        func postPaced(_ events: [CGEvent]) -> Bool {
            if postedChunks > 0 { Thread.sleep(forTimeInterval: Self.chunkInterval) }
            guard isCurrent() else {
                #if DEBUG
                Logger.eventTap.debug(
                    "실행 중단 — 페이싱 그룹 폐기 (게시 청크 \(postedChunks, privacy: .public))")
                #endif
                return false
            }
            for index in stride(from: 0, to: events.count, by: 2) {
                if index > 0 { Thread.sleep(forTimeInterval: Self.pacedStrokeInterval) }
                executor.post(Array(events[index..<min(index + 2, events.count)]))
            }
            postedChunks += 1
            return true
        }

        for action in actions {
            // 액션마다 새 스냅샷 — 앞 액션이 캐럿을 옮겼으므로 이전 액션의 읽기를 물려받으면
            // 낡은 오프셋으로 계산한다. 만드는 것만으로는 AX를 부르지 않는다 (lazy).
            let text = FocusedTextSnapshot(processID: processID, reader: reader)
            let groups: [[KeyStroke]]
            let paced: Bool
            switch mapping(for: action, family: family, profile: profile, text: text) {
            case .groups(let mapped, let pacedGroups):
                groups = mapped
                paced = pacedGroups
            case .unsupported:
                #if DEBUG
                skippedCount += 1
                if firstSkipped == nil { firstSkipped = action }
                #endif
                continue
            case .skipped:
                continue
            case .layoutBlocked:
                #if DEBUG
                layoutBlockedCount += 1
                if firstLayoutBlocked == nil { firstLayoutBlocked = action }
                #endif
                continue
            case .disabledByProfile:
                #if DEBUG
                disabledCount += 1
                if firstDisabled == nil { firstDisabled = action }
                #endif
                continue
            }

            // Visual `y`는 `[.edit(.yank, .selection), .clearSelection]`을 함께 낸다. 그 사이가
            // 끊기면 **살아 있는 선택이 Normal로 넘어오고**, Normal `x`(`Shift-→, Cmd-X`)가
            // 그것을 통째로 잘라낸다. 그래서 이 액션을 처리하는 동안에는 flush하지 않고,
            // 잠금은 **다음 액션의 첫 경계**까지만 이어진다 (판정은 액션 진입 시점이어야
            // 한다 — 액션을 다 처리한 뒤 세우면 이미 그 안에서 끊긴 뒤다).
            let holdsNextAction = Self.isSelectionEdit(action)

            for group in groups {
                // 그룹 단위 all-or-nothing — 스트로크 하나라도 CGEvent 생성에 실패하면 그룹
                // 전체를 버린다. 부분 시퀀스는 편집에서 "선택은 어긋난 채 Cmd-X만 나가는"
                // 파괴적 실행이 된다 (이동만 실행하던 시절의 스킵-계속은 한 타 누락으로
                // 무해했다). `.paste`를 뺀 모든 액션은 그룹이 곧 액션 전체라 의미가 같다.
                guard let groupEvents = Self.events(for: group) else {
                    // 미지원 스킵(DEBUG)과 달리 실제 이상 상황이라 항상 남긴다.
                    Logger.eventTap.error(
                        "CGEvent 생성 실패 — 액션 폐기: \(String(describing: action), privacy: .public)")
                    // 게시되지 않은 액션의 Visual 상태가 남으면 화면과 어긋난 채 검증을
                    // 거짓 통과할 수 있다 — 재앵커 `.set`이 그 자리다(진입형 선택이 새
                    // `pinnedEnd`와 우연히 일치한다). 폐기 = 무상태 강등이라 안전 방향이다.
                    visualAnchor.apply(.discard)
                    continue
                }
                // 페이싱 그룹은 pending과 섞지 않고 단독으로, 스트로크 사이 간격을 두고
                // 게시한다 — 순서 보존을 위해 미뤄 둔 것을 먼저 비운다. 1타 그룹은 간격
                // 자체가 없으므로 일반 경로 그대로다.
                if paced, group.count >= 2 {
                    guard flush(), postPaced(groupEvents) else {
                        // 아래 flush 실패와 같은 이유 — 폐기된 게시에 실린 Visual 액션의
                        // 상태가 남으면 안 된다.
                        visualAnchor.apply(.discard)
                        return
                    }
                    continue
                }
                pending.append(contentsOf: groupEvents)
                pendingStrokes += group.count
                // 원자 그룹은 절대 가르지 않는다 — 경계는 그룹 **사이**에만 온다.
                guard pendingStrokes >= Self.chunkStrokes, !holdsNextAction else { continue }
                guard flush() else {
                    // 위 CGEvent 실패와 같은 이유 — 폐기된 청크에 실린 Visual 액션의 상태가
                    // 남으면 안 된다.
                    visualAnchor.apply(.discard)
                    return
                }
            }
        }

        // 마지막 청크가 중단으로 버려지면 그 안의 Visual 액션 상태도 함께 버린다 (위와 동일).
        if !flush() { visualAnchor.apply(.discard) }

        #if DEBUG
        // 카운트 반복(`1000u`, Visual `1000j` 등)으로 액션이 수백~천 개일 수 있어 요약 1건으로
        // 접는다. 요약에 쓰는 건 개수와 첫 1개뿐이라 액션 자체를 쌓아 두지 않는다.
        if let first = firstSkipped {
            // 계열을 함께 남기는 것이 요점이다 — 단계 4의 게이트 판정은 이 로그의 전수 확인인데,
            // 걸러내기 스킵(계열이 `.nonText`/`.textField`)과 진짜 미구현이 섞이면 심사자가
            // 구현된 어휘를 미구현으로 읽는다.
            Logger.eventTap.debug(
                "미지원 액션 스킵 ×\(skippedCount, privacy: .public) [\(String(describing: family), privacy: .public)]: \(String(describing: first), privacy: .public)"
            )
        }
        if let first = firstLayoutBlocked {
            // 미지원과 별도 요약인 이유는 Mapping.layoutBlocked 주석 참고.
            Logger.eventTap.debug(
                "비-QWERTY 레이아웃 스킵 ×\(layoutBlockedCount, privacy: .public): \(String(describing: first), privacy: .public)"
            )
        }
        if let first = firstDisabled {
            // 미지원·레이아웃과 별도 집계인 이유는 Mapping.disabledByProfile 주석 참고 —
            // 사용자 설정이 만든 스킵이 미구현으로 읽히면 안 된다.
            Logger.eventTap.debug(
                "프로파일 disable 스킵 ×\(disabledCount, privacy: .public) [\(profile.name ?? "프로파일", privacy: .public)]: \(String(describing: first), privacy: .public)"
            )
        }
        #endif
    }

    /// 한 청크에 담는 키스트로크 수 (스트로크 = keyDown+keyUp 쌍이라 이벤트로는 두 배).
    ///
    /// 이 값과 `chunkInterval`은 **도그푸딩 조절값**이다 — 작을수록 중단이 빠르고, 클수록
    /// 버스트 총 소요가 짧다.
    private static let chunkStrokes = 8

    /// 두 번째 청크부터 청크 앞에 두는 간격.
    ///
    /// 지연이 **중단을 가능하게 하는 장치**다: `CGEvent.post`는 배달만 걸어 두고 즉시 돌아오는
    /// 반면 소비하는 쪽은 대상 앱이라, 간격이 없으면 수천 개를 수십 ms에 다 넘겨버려 끊을
    /// 잔여가 남지 않는다(단계 0 실측: 킬스위치 발동은 즉시지만 이미 게시된 이벤트는 끝까지
    /// 소진됐다). 첫 청크는 지연 없이 나가므로 일상 입력(1~3 스트로크)의 반응성은 그대로다.
    /// 게시 직렬 큐를 막는 것이 곧 스로틀이며, 새 키는 탭 콜백에서 래치만 세우고 그 뒤에 쌓인다.
    private static let chunkInterval: TimeInterval = 0.002

    /// 페이싱 다타 그룹(Visual 정확화·paste 접두)의 스트로크 간 간격 — 도그푸딩
    /// 조절값이다 (Notion 실측: 5ms 충분 확인, 최솟값 미탐). `chunkInterval`과 달리 중단
    /// 장치가 아니라 **대상 앱이 각 스트로크의 의미(collapse·이동 → Shift 확장·Cmd-V)를
    /// 소화할 시간**이다.
    private static let pacedStrokeInterval: TimeInterval = 0.005

    /// 원자 그룹 하나의 CGEvent. 하나라도 생성에 실패하면 `nil` — 부분 시퀀스를 내지 않는다.
    private static func events(for strokes: [KeyStroke]) -> [CGEvent]? {
        var events: [CGEvent] = []
        events.reserveCapacity(strokes.count * 2)
        for stroke in strokes {
            guard
                let down = CGEvent(
                    keyboardEventSource: nil, virtualKey: stroke.keyCode, keyDown: true),
                let up = CGEvent(
                    keyboardEventSource: nil, virtualKey: stroke.keyCode, keyDown: false)
            else {
                return nil
            }
            // 소스가 nil인 이벤트는 flags 기본값이 **실행 시점의 실제 modifier 상태**라,
            // 대입은 선택이 아니라 필수다 — 사용자가 누르고 있던 키가 새어 들어간다.
            down.flags = stroke.flags
            up.flags = stroke.flags
            events.append(down)
            events.append(up)
        }
        return events
    }

    /// 화면에 이미 있는 선택에 대한 편집인가 — 뒤따르는 `clearSelection`과 갈라지면 안 된다.
    /// `VimAction`에 exhaustive switch를 걸지 않는 것은 매퍼와 같은 계약이다.
    private static func isSelectionEdit(_ action: VimAction) -> Bool {
        guard case .edit(_, .selection) = action else { return false }
        return true
    }

    /// 액션 1건의 매핑 결과. 스킵을 **두 종류로 가르는 것이 요점**이다 — 단계 4의 릴리스
    /// 게이트 판정이 "미지원 스킵 로그 전수 확인"이라, 지원하는데 이번 입력에는 할 일이 없는
    /// 경우가 미지원으로 집계되면 심사자가 그 어휘를 미구현으로 읽는다.
    private enum Mapping {
        /// **원자 그룹**의 목록. 청크 경계는 그룹 사이에만 올 수 있다 — 대부분의 액션은
        /// 그룹 1개(액션 전체)이고, `.paste`만 카운트만큼 갈라져 온다.
        ///
        /// `paced`는 **Visual 정확화 그룹과 `.paste`** 만 참이다 — 다타 그룹의 스트로크
        /// 사이에 고정 간격을 둔다 (Notion 실측: 0간격 버스트는 재앵커의 Shift 확장도,
        /// 붙여넣기 접두의 화살표도 소화하지 못했고, 이벤트당 5ms에서는 완전 정상 — 간격
        /// 문제로 확정). 범위를 이 둘로 한정해야 스크롤(15~30타 단일 그룹)·폴백 카운트
        /// 반복(`500x`)·카운트 버스트가 타이밍까지 현행 그대로다.
        case groups([[KeyStroke]], paced: Bool)
        /// 매퍼가 `nil` — 이 어휘가 아직 구현되지 않았다. 요약 로그에 집계된다.
        case unsupported
        /// 지원하지만 이번엔 게시할 것이 없다. 사유를 아는 자리에서 **자체 로그를 이미 남겼다**.
        case skipped
        /// 지원하지만 현재 레이아웃이 비-QWERTY라 보류했다. 미지원과 별도로 집계된다 —
        /// 섞이면 게이트 심사자가 구현된 어휘를 미구현으로 읽는다 (스킵 2종 분리와 같은 규칙).
        case layoutBlocked
        /// 지원하지만 이 앱의 프로파일이 껐다 (모션 disable 또는 `actions:` disable).
        /// 미지원과 별도로 집계된다 — 사용자 설정이 만든 "동작 없음"이 미구현으로 읽히면
        /// 설정 오타 진단도, 게이트 심사도 함께 틀린다.
        case disabledByProfile
    }

    /// 액션 → 합성할 키스트로크.
    ///
    /// `VimAction`에 exhaustive switch를 걸지 않는 것이 계약이다 — 엔진에 케이스가 늘어도
    /// 폴백이 흡수해 어댑터가 컴파일 에러로 무너지지 않는다.
    ///
    /// 폴백이 맨 `default:`가 아니라 `@unknown default:`인 이유: v1 어휘 11종이 전부 채워진
    /// 지금 맨 `default:`는 도달 불가라 컴파일러가 "실행되지 않는다"고 경고하고, 그 경고는
    /// 계약을 몰라 지우라고 부추긴다. `@unknown default:`는 런타임 흡수를 그대로 두면서
    /// 그 경고를 없애고, 케이스가 늘면 **에러가 아니라 경고로** 여기를 짚어 준다 —
    /// "무너지지 않되 조용하지도 않다"는 이 계약이 원래 원하던 것이다.
    ///
    /// `static`이 아닌 이유는 `.paste`가 주입된 클립보드 읽기를 쓰기 때문이다.
    ///
    /// `text`를 읽는 것은 아래 `.edit` 분기와 Visual 세션 분기 **두 곳**이다 — 묻지 않으면
    /// AX 왕복도 없다(lazy).
    private func mapping(
        for action: VimAction, family: ElementFamily, profile: ResolvedProfile,
        text: FocusedTextSnapshot
    ) -> Mapping {
        // 새 Visual 세션의 시작은 옛 세션 wise를 **게이트보다 앞에서** 잊는다 — note는
        // 게시 확정에 게이팅되므로, 걸러진 begin(`.nonText`·`.unresolved`) 뒤의
        // `.selection` 편집이 이전 세션의 wise로 기록되는 구멍을 여기서 막는다. 망각은
        // 기록이 아니라서 "게이트가 부수효과보다 앞" 계약을 깨지 않는다(보수 방향 —
        // 틀려봐야 휴리스틱 폴백이다).
        if case .beginSelection = action { pasteWise.forgetSelectionWise() }
        // `actions:` disable 판정은 **모든 게이트·부수효과보다 앞**이다 — 사용자가 끈
        // 액션은 `recordEdit`·클립보드 읽기 같은 부수효과도 남기면 안 되고
        // (걸러내기 게이트가 부수효과보다 앞인 것과 같은 규칙), 분류도 미지원이 아니라
        // `.disabledByProfile`이어야 한다.
        if let configAction = Self.configAction(for: action),
            profile.actionOverrides[configAction] == .disabled {
            return .disabledByProfile
        }
        // 비텍스트 걸러내기는 **여기 한 곳**이다 — 매퍼가 아니라 어댑터인 이유가 셋 있고,
        // 셋 다 "게이트가 부수효과보다 앞이어야 한다"로 모인다
        // (`20260801_non-text-filter-keeps-motion-and-scroll.md`):
        //   ① `.move`에는 family가 없다 (모션은 계열 무관이 계약).
        //   ② 아래 `.edit`은 게시 확정 시 `recordEdit`으로 wise를 기억한다 — 게시하지도
        //      않을 편집을 기억하면 뒤따르는 `p`의 wise가 오염된다.
        //   ③ 아래 `.paste`는 매퍼 호출 전에 클립보드를 읽는다 — 순서가 반대면 걸러내기가
        //      "클립보드에 텍스트 없음"(`.skipped`)으로 잘못 집계돼 스킵 2종 구분이 무너진다.
        guard Self.survivesFilterGate(action, family: family) else { return .unsupported }
        // 비-QWERTY 레이아웃 게이트 — ANSI **문자** 키코드를 합성하는 액션만 보류한다.
        // 매퍼는 키코드를 고정 게시하고 대상 앱이 활성 레이아웃으로 재해석하므로, AZERTY에서
        // `u`의 `Cmd-Z`는 `Cmd-W`(창 닫기 — 데이터 손실)가 된다. 화살표·Return만 쓰는
        // 액션(모션·스크롤·openLine·선택)은 레이아웃 무관이라 통과한다. 걸러내기 게이트와
        // 같은 이유로 부수효과(`recordEdit`·클립보드 읽기)보다 앞이다.
        guard hasQwertyCommandKeys() || !Self.synthesizesAnsiLetterCommand(action) else {
            return .layoutBlocked
        }

        switch action {
        case .move(let motion):
            return Self.classify(MotionKeyMapper.keyStrokes(for: motion, profile: profile)) {
                MotionKeyMapper.keyStrokes(for: motion, profile: .empty)
            }

        case .edit(let op, let range):
            // **읽기의 첫 소비 지점**이다 (M5 PR-B — 둘째는 Visual 세션 분기).
            // 게이트 뒤·부수효과 앞이라
            // `recordEdit`·클립보드 오염 없이 빠져나가고, 범위가 묻지 않으면
            // AX 왕복도 없다(읽기는 lazy이므로 `value()`를 부르지 않으면 호출 0건이다).
            //
            // 읽기 실패·타임아웃·pid 없음은 전부 `nil`이라 매퍼가 무상태 시퀀스를 낸다 —
            // 정확화만 포기하고 실행은 한다. 스킵도, 실행 실패 보고도 아니다.
            let focused = EditKeyMapper.consultsFocusedText(range) ? text.value() : nil
            let result = Self.classifyEdit(
                op: op, range: range, family: family, profile: profile, text: focused)
            if case .skipped = result {
                // 미지원이 아니라 "지원하지만 이번 입력에는 게시할 것이 없다"이므로 `.skipped`다
                // (`p`의 빈 클립보드와 같은 편) — `op`·`range`·액션을 다 아는 이 자리에서
                // 자체 로그를 남긴다. `classifyEdit`은 사유를 알지만 액션을 모른다.
                #if DEBUG
                Logger.eventTap.debug(
                    "편집 스킵 — 읽기가 Vim 무효를 증명했다: \(String(describing: action), privacy: .public)"
                )
                #endif
            }
            // 편집은 전부 클립보드를 쓴다(delete·change는 `Cmd-X`, yank는 `Cmd-C`) — 뒤따르는
            // `p`가 끝 개행 휴리스틱(앱마다 틀린다)에 기대지 않게 내용의 wise를 기억해 둔다.
            // **게시가 확정된 뒤에만** 기억한다 — 프로파일 disable로 스킵된 편집이 기억을
            // 남기면, 다음 외부 복사 한 번 뒤의 `p`가 그 wise로 오판된다 (게이트 2종과 같은
            // 규칙이되, 모션 disable은 매퍼 안에서야 드러나므로 판정이 앞설 수 없어 기억을
            // 뒤로 미룬다).
            if case .groups = result {
                if case .selection = range {
                    // 내용 wise는 범위가 아니라 세션이 정한다 — change도 선택을 그대로
                    // 자르므로(cc의 줄 유지 반올림이 없다) 세션 wise가 곧 내용이다.
                    pasteWise.recordSelectionEdit()
                } else if let wise = Self.contentWise(op, range) {
                    pasteWise.recordEdit(wise)
                }
            }
            return result

        case .beginSelection, .extendSelection, .switchSelectionWise, .clearSelection:
            // **읽기의 두 번째 소비 지점**이다 (M5 PR-C1). 편집의 범위 술어와 달리 Visual은
            // **세션 술어**다 — 앵커 상태의 수립(진입)과 자가 검증(세션 중)이 읽기의
            // 소비자라, 어떤 액션이 읽는지는 범위가 아니라 세션 상태가 정한다.
            let context = anchorContext(for: action, text: text)
            let (result, update) = Self.classifyVisual(
                action: action, family: family, profile: profile, anchor: context)
            if case .skipped = result {
                // 미지원이 아니라 "지원하지만 게시할 것이 없다" — 편집의 읽기 증명 무효와
                // 같은 편이다. 세션 1에서는 도달하지 않는다: 첫 소비자는 `V` 세션의 범위
                // 무변화 charwise 모션이다 (`20260804_visual-linewise-motion-range-noop.md`).
                #if DEBUG
                Logger.eventTap.debug(
                    "Visual 스킵 — 범위 무변화가 정확 동작이다: \(String(describing: action), privacy: .public)"
                )
                #endif
            }
            // 게시가 확정된 뒤에만 상태를 남긴다 — `recordEdit`과 같은 규칙이다.
            // 걸러진 액션이 side를 뒤집으면 다음 액션이 있지도 않은 재앵커를 전제로 계산한다.
            if case .groups = result {
                visualAnchor.apply(update)
                // 게시가 확정된 진입·전환의 wise를 세션 wise로 note한다 — `.selection`
                // 편집의 내용 wise는 세션이 정하는데, 스킵된 전환(`V`→`v` 폴백 `nil`)은
                // 화면 선택이 그대로라 **확정 스트림만** 따라가야 기억이 내용과 일치한다.
                switch action {
                case .beginSelection(let linewise), .switchSelectionWise(let linewise):
                    pasteWise.noteSelectionWise(linewise ? .linewise : .charwise)
                default:
                    break
                }
                #if DEBUG
                // 상태 전이 관측 — 도그푸딩에서 각 액션이 어느 경로(수립·재앵커·폐기·무상태)를
                // 탔는지 화면과 대조하는 유일한 수단이다.
                switch update {
                case .set(let state):
                    Logger.eventTap.debug(
                        "Visual 앵커 갱신 [\(String(describing: state.side), privacy: .public), pinned \(state.pinnedEnd, privacy: .public)]: \(String(describing: action), privacy: .public)"
                    )
                case .discard:
                    Logger.eventTap.debug(
                        "Visual 앵커 폐기 (게시 경로): \(String(describing: action), privacy: .public)"
                    )
                case .unchanged:
                    break
                }
                #endif
            }
            return result

        case .openLine, .undo, .redo, .scroll:
            return Self.classify(
                CommandKeyMapper.keyStrokes(for: action, family: family, profile: profile)
            ) {
                CommandKeyMapper.keyStrokes(for: action, family: family, profile: .empty)
            }

        case .paste(let before, let count):
            // 텍스트가 없는 클립보드(이미지만 있는 등)는 미지원이 아니라 "붙여넣을 것이 없음"이다.
            // 접두만 게시하면 붙여넣기 없이 캐럿만 움직이는 조용한 오동작이 된다.
            guard let wise = pasteWise.resolve() else {
                Logger.eventTap.debug("paste 스킵 — 클립보드에 텍스트가 없다")
                return .skipped
            }
            // **읽기의 세 번째 소비 지점** — charwise `p`만 줄 끝 증명을 위해 묻는다
            // (`P`·linewise는 왕복 0건 유지). 읽기 실패·pid 없음은 `nil`이라 현행 접두
            // 그대로다. 정확화가 접두를 비울 뿐 `nil`을 새로 만들지 않으므로 편집·Visual과
            // 달리 프로브는 그대로 둘이다.
            let focused = CommandKeyMapper.pasteConsultsFocusedText(before: before, wise: wise)
                ? text.value() : nil
            // 유일하게 그룹이 여럿인 액션 — 액션 1개 안에서 카운트가 곱해지므로 래치가
            // 파고들 틈을 매퍼가 직접 낸다. 분류 규칙은 `classify`와 같고 그룹 모양만 다르다.
            // `paced`인 것은 접두 다타 그룹(linewise 4타 등)이 Notion 0간격 버스트에서
            // 화살표를 소화하지 못해 `Cmd-V`가 낡은 캐럿에서 터지기 때문이다 (도그푸딩 실측 —
            // Visual 정확화 그룹과 같은 약점·같은 대응). 후속 `Cmd-V` 그룹은 1타라 자연히
            // 일반 경로다.
            if let groups = CommandKeyMapper.pasteStrokeGroups(
                before: before, count: count, wise: wise, family: family, profile: profile,
                text: focused) {
                return .groups(groups, paced: true)
            }
            return CommandKeyMapper.pasteStrokeGroups(
                before: before, count: count, wise: wise, family: family, profile: .empty) != nil
                ? .disabledByProfile : .unsupported

        @unknown default:
            return .unsupported
        }
    }

    /// 매퍼의 `nil`을 두 스킵으로 가른다 — 프로파일 없이 다시 물어 값이 나오면 프로파일이
    /// 만든 disable이고, 그래도 `nil`이면 진짜 미지원이다. 재조회는 `nil` 경로(드묾)에서만
    /// 일어나고, 분류 규칙이 이 한 곳에 있어 집계가 어긋날 자리가 없다.
    private static func classify(
        _ strokes: [KeyStroke]?, builtIn: () -> [KeyStroke]?
    ) -> Mapping {
        if let strokes { return .groups([strokes], paced: false) }
        return builtIn() != nil ? .disabledByProfile : .unsupported
    }

    /// 편집 전용 분류 — 매퍼의 `nil`을 **세 스킵**으로 가른다. 읽기가 정확화의 입력이 되면서
    /// `nil`이 "미지원"과 "읽기가 증명한 무효" 두 뜻을 갖게 됐고, 그래서 프로브가 하나 늘었다.
    ///
    /// **프로브 순서가 계약이고, 그 계약을 이 함수의 존재가 강제한다.** 위 `classify`처럼
    /// 클로저로 열어 두면 호출부가 `text`를 어느 프로브에 넘기든 컴파일이 통과하는데,
    /// 순서가 하나만 어긋나도 정확화 결과가 `.unsupported`로 집계돼 릴리스 게이트 심사자가
    /// **구현된 어휘를 미구현으로 읽는다**. 인접한 두 줄에 같은 인자를 넘기지 않는 것에
    /// 의존하는 계약은 감사할 수 없으므로, `text`를 받는 자리를 여기 한 곳으로 닫는다.
    private static func classifyEdit(
        op: VimAction.Operator, range: VimAction.TextRange, family: ElementFamily,
        profile: ResolvedProfile, text: FocusedText?
    ) -> Mapping {
        if let strokes = EditKeyMapper.keyStrokes(
            for: op, range: range, family: family, profile: profile, text: text) {
            return .groups([strokes], paced: false)
        }
        // ① 텍스트 프로브 — **`builtIn`보다 앞**이다. 읽기 없이 답이 있었다면 `nil`을 만든 것은
        //    미지원도 프로파일도 아니라 정확화다.
        if text != nil,
            EditKeyMapper.keyStrokes(for: op, range: range, family: family, profile: profile)
                != nil {
            return .skipped
        }
        // ② builtIn 프로브 — **`text`를 받지 않는다.** 여기에 `text`가 새면 정확화 결과가
        //    프로파일 disable로 둔갑한다.
        return EditKeyMapper.keyStrokes(for: op, range: range, family: family, profile: .empty)
            != nil ? .disabledByProfile : .unsupported
    }

    /// Visual 액션 1건의 정확화 입력 — 세션 술어의 본체다.
    ///
    /// 읽기 실패·pid 없음·상태 부재는 전부 `.none`으로 접힌다: 매퍼가 무상태 시퀀스를 내고
    /// 실행은 한다 (Slack·VS Code 상시 경로). **검증 실패만 상태를 폐기하며**(`validated`가
    /// 즉시 지운다) 읽기 실패는 폐기 트리거가 아니다 — Notion 타임아웃 1회로 세션을 잃으면
    /// 남은 세션 전체가 폴백으로 강등된다. 그 사이 폴백이 화면을 바꿔도 다음 성공 읽기의
    /// 자가 검증이 잡는다 (`20260804_visual-anchor-read-self-validation.md`).
    private func anchorContext(
        for action: VimAction, text: FocusedTextSnapshot
    ) -> VisualAnchorContext {
        switch action {
        case .beginSelection:
            // 수립 재료 — 진입 시퀀스가 게시되면 원래 캐럿은 파괴되므로 이 읽기가 유일한
            // 시점이다. `mapping`은 게시보다 앞이라 "게시 직전"이 구조로 성립한다.
            guard let processID = text.processID, let read = text.value() else { return .none }
            return .establishing(read, processID)
        case .extendSelection, .switchSelectionWise:
            // 상태가 없으면 검증할 것도 없다 — AX 왕복 자체를 생략한다 (lazy 규칙 그대로).
            guard visualAnchor.hasState else { return .none }
            guard let read = text.value() else {
                // 읽기 실패는 폐기가 아니다 — 다만 이어서 게시될 무상태 시퀀스가 포커스를
                // 옮기므로, linewise의 포커스 줄 거리만은 미상으로 좁힌다. 알던 값을 두면
                // 다음 검증(앵커 쪽만 본다)이 낡은 거리를 못 잡는다.
                visualAnchor.unknowFocusLineDistance()
                #if DEBUG
                Logger.eventTap.debug("Visual 읽기 실패 — 무상태 폴백 (상태 유지)")
                #endif
                return .none
            }
            guard let state = visualAnchor.validated(against: read, processID: text.processID)
            else {
                #if DEBUG
                // 어긋난 읽기의 실값을 남긴다 — 낡은 읽기 레이스와 앱 시맨틱 차이를
                // 도그푸딩에서 가르는 근거가 이 줄이다.
                Logger.eventTap.debug(
                    "Visual 앵커 폐기 — 검증 불일치: 읽은 선택 [\(read.selection.location, privacy: .public), \(read.selection.upperBound, privacy: .public))"
                )
                #endif
                return .none
            }
            return .session(state, read)
        default:
            // `clearSelection` — 폐기는 증거가 필요 없다 (읽지 않는다).
            return .none
        }
    }

    /// Visual 전용 분류 — 매퍼의 `nil`을 **세 스킵**으로 가른다. 앵커 상태가 정확화의 입력이
    /// 되면서 `nil`이 "미지원"과 "정확화가 증명한 무게시" 두 뜻을 갖게 됐고, 그래서
    /// `classifyEdit`과 같은 3-프로브다.
    ///
    /// 프로브 순서가 계약이고 그 계약을 이 함수의 존재가 강제한다 — `anchor`를 받는 자리를
    /// 여기 한 곳으로 닫아, 정확화 결과가 `.unsupported`나 `.disabledByProfile`로 집계돼
    /// 게이트 심사자가 구현된 어휘를 미구현으로 읽을 자리를 없앤다.
    private static func classifyVisual(
        action: VimAction, family: ElementFamily, profile: ResolvedProfile,
        anchor: VisualAnchorContext
    ) -> (mapping: Mapping, update: VisualAnchorUpdate) {
        if let mapped = VisualKeyMapper.keyStrokes(
            for: action, family: family, profile: profile, anchor: anchor) {
            return (.groups([mapped.strokes], paced: mapped.paced), mapped.anchor)
        }
        // ① 상태 프로브 — **builtIn보다 앞**이다. 상태 없이 답이 있었다면 `nil`을 만든 것은
        //    미지원도 프로파일도 아니라 정확화다.
        if anchor.isRefining,
            VisualKeyMapper.keyStrokes(for: action, family: family, profile: profile) != nil {
            return (.skipped, .unchanged)
        }
        // ② builtIn 프로브 — **`anchor`를 받지 않는다.** 여기에 상태가 새면 정확화 결과가
        //    프로파일 disable로 둔갑한다.
        return (
            VisualKeyMapper.keyStrokes(for: action, family: family, profile: .empty) != nil
                ? .disabledByProfile : .unsupported,
            .unchanged
        )
    }

    /// 이 계열에서 이 액션을 게시하는가 — 걸러내기 게이트 본체다.
    ///
    /// `.unresolved`가 `.nonText`와 같은 편에 서는 것이 요점이다. 앱 전환 직후 첫 읽기가
    /// 착지하기 전(콜드 ~20ms)에는 요소를 **모르는** 상태이고, 그때 폴백으로 판정하면 실측된
    /// 방향으로 틀린다 — TextEdit→Finder 전환 직후의 `u`가 그 창을 타고 `Cmd-Z`로 Finder에
    /// 도달했다. 모르는 동안은 위험 어휘를 보류하고, 모션·스크롤만 흘려보낸다
    /// (`20260801_unresolved-window-after-app-switch.md`).
    ///
    /// `ElementFamily`에는 exhaustive switch를 건다 — 계열이 늘면 "어느 편인가"를 반드시
    /// 결정해야 하고, 조용한 기본값은 곧 무언의 통과다.
    private static func survivesFilterGate(_ action: VimAction, family: ElementFamily) -> Bool {
        switch family {
        case .textArea, .textField:
            return true
        case .nonText, .unresolved:
            return survivesNonTextGate(action)
        }
    }

    /// 비텍스트 요소에서도 게시되는 액션인가.
    ///
    /// 위험 등급을 가르는 축은 "비텍스트인가"가 아니라 **"앱이 이미 아는 명령인가"** 다.
    /// 화살표는 텍스트가 아닌 곳에서도 무해하게 흘러가고(리스트 선택 이동, 페이지 스크롤)
    /// 전부 막으면 M2부터 살아 있던 그 동작이 죽는다 — 엔진이 이미 키를 삼킨 뒤라 스킵은
    /// 네이티브 동작으로의 복귀가 아니라 **완전 무동작**이기 때문이다.
    ///
    /// `.scroll`이 여기 속하는 것은 `CommandKeyMapper` 소속이지만 그 매퍼에서 **유일하게
    /// 네이티브 명령에 위임하지 않는** 액션이기 때문이다 — 실체가 화살표 반복이라 위험 축에서는
    /// 모션 편이다 (`20260730_scroll-arrow-repetition.md`).
    ///
    /// `VimAction`에 exhaustive switch를 걸지 않는 것은 매퍼와 같은 계약이다.
    private static func survivesNonTextGate(_ action: VimAction) -> Bool {
        switch action {
        case .move, .scroll:
            return true
        default:
            return false
        }
    }

    /// ANSI 문자 키코드의 `Cmd-` 조합을 합성하는 액션인가 — 비-QWERTY 레이아웃 게이트 대상.
    /// `.edit`은 오퍼레이터 스트로크(`Cmd-X`/`Cmd-C`), `.paste`는 `Cmd-V`,
    /// `.undo`/`.redo`는 `Cmd-Z`다. `VimAction`에 exhaustive switch를 걸지 않는 것은
    /// 매퍼와 같은 계약이다.
    private static func synthesizesAnsiLetterCommand(_ action: VimAction) -> Bool {
        switch action {
        case .edit, .paste, .undo, .redo:
            return true
        default:
            return false
        }
    }

    /// 이 편집이 클립보드에 남기는 내용의 wise. `nil` = 미지의 범위라 기록하지 않는다
    /// (휴리스틱 폴백 — 보수 방향). `.selection`은 여기 오지 않는다 — 내용 wise를 범위가
    /// 아니라 세션이 정하므로 `recordSelectionEdit()`이 따로 맡는다.
    ///
    /// 줄 범위에서 `change`만 charwise인 것은 내용 진실이다 — `cc`는 마지막 확장을 줄 끝으로
    /// 바꿔 개행을 남기지 않으므로 내용이 실제로 charwise이고, 그렇게 붙여넣는 것이 맞다.
    /// `TextRange`에 exhaustive switch를 걸지 않는 것은 매퍼와 같은 계약이다.
    private static func contentWise(
        _ op: VimAction.Operator, _ range: VimAction.TextRange
    ) -> PasteWise? {
        switch range {
        case .line, .linewiseMotion:
            return op == .change ? .charwise : .linewise
        case .motion, .textObject:
            return .charwise
        default:
            return nil
        }
    }

    /// `actions:` 어휘 대응 — `VimAction` → `ConfigAction`. 대응이 없는 액션(모션·편집·
    /// Visual 세션)은 `actions:`의 대상이 아니다 (모션 단위 disable이 따로 있다).
    /// `VimAction`에 exhaustive switch를 걸지 않는 것은 매퍼와 같은 계약이다.
    private static func configAction(for action: VimAction) -> ConfigAction? {
        switch action {
        case .openLine: return .openLine
        case .paste: return .paste
        case .undo: return .undo
        case .redo: return .redo
        case .scroll: return .scroll
        default: return nil
        }
    }
}

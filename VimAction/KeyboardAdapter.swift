//
//  KeyboardAdapter.swift
//  VimAction
//

import CoreGraphics
import Foundation
import os
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

    /// 붙여넣기 단위 판정. 우리가 게시한 줄 단위 편집을 기억하므로 **상태를 가진 참조 타입**이며,
    /// 게시 직렬 큐가 단독 소유한다. 주입하는 이유는 `ActionExecutor.postEvent`와 같다 —
    /// 실제 패스트보드를 읽으면 테스트가 **개발자의 클립보드**에 따라 갈려 비결정적이 된다.
    private let pasteWise: PasteWiseResolver

    init(
        executor: ActionExecutor = ActionExecutor(),
        pasteWise: PasteWiseResolver = PasteWiseResolver()
    ) {
        self.executor = executor
        self.pasteWise = pasteWise
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
    func execute(
        _ actions: [VimAction], family: ElementFamily = .textArea, isCurrent: () -> Bool = { true }
    ) {
        // dispatch 직후 곧바로 다음 키에 밀려난 경우 — 한 이벤트도 내보내지 않는다.
        guard isCurrent() else { return }

        #if DEBUG
        var skippedCount = 0
        var firstSkipped: VimAction?
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

        for action in actions {
            let groups: [[KeyStroke]]
            switch mapping(for: action, family: family) {
            case .groups(let mapped):
                groups = mapped
            case .unsupported:
                #if DEBUG
                skippedCount += 1
                if firstSkipped == nil { firstSkipped = action }
                #endif
                continue
            case .skipped:
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
                    continue
                }
                pending.append(contentsOf: groupEvents)
                pendingStrokes += group.count
                // 원자 그룹은 절대 가르지 않는다 — 경계는 그룹 **사이**에만 온다.
                guard pendingStrokes >= Self.chunkStrokes, !holdsNextAction else { continue }
                guard flush() else { return }
            }
        }

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
        #endif

        flush()
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
        case groups([[KeyStroke]])
        /// 매퍼가 `nil` — 이 어휘가 아직 구현되지 않았다. 요약 로그에 집계된다.
        case unsupported
        /// 지원하지만 이번엔 게시할 것이 없다. 사유를 아는 자리에서 **자체 로그를 이미 남겼다**.
        case skipped
    }

    /// 액션 → 합성할 키스트로크.
    ///
    /// `VimAction`에 exhaustive switch를 걸지 않는 것이 계약이다 — 엔진에 케이스가 늘어도
    /// `default:`가 흡수해 어댑터가 컴파일 에러로 무너지지 않는다.
    ///
    /// `static`이 아닌 이유는 `.paste`가 주입된 클립보드 읽기를 쓰기 때문이다.
    private func mapping(for action: VimAction, family: ElementFamily) -> Mapping {
        // 비텍스트 걸러내기는 **여기 한 곳**이다 — 매퍼가 아니라 어댑터인 이유가 셋 있고,
        // 셋 다 "게이트가 부수효과보다 앞이어야 한다"로 모인다
        // (`20260801_non-text-filter-keeps-motion-and-scroll.md`):
        //   ① `.move`에는 family가 없다 (모션은 계열 무관이 계약).
        //   ② 아래 `.edit`은 매퍼 호출 **전에** `recordLinewiseEdit()`을 부른다 — 게시하지도
        //      않을 편집을 기억하면 뒤따르는 `p`의 wise가 오염된다.
        //   ③ 아래 `.paste`는 매퍼 호출 전에 클립보드를 읽는다 — 순서가 반대면 걸러내기가
        //      "클립보드에 텍스트 없음"(`.skipped`)으로 잘못 집계돼 스킵 2종 구분이 무너진다.
        guard Self.survivesFilterGate(action, family: family) else { return .unsupported }

        switch action {
        case .move(let motion):
            return Self.mapping(MotionKeyMapper.keyStrokes(for: motion))

        case .edit(let op, let range):
            // 줄 단위 편집은 클립보드에 줄 단위 내용을 남긴다 — 뒤따르는 `p`가 끝 개행
            // 휴리스틱(앱마다 틀린다)에 기대지 않게 그 사실을 기억해 둔다.
            if Self.isLinewise(op, range) { pasteWise.recordLinewiseEdit() }
            return Self.mapping(EditKeyMapper.keyStrokes(for: op, range: range, family: family))

        case .beginSelection, .extendSelection, .switchSelectionWise, .clearSelection:
            return Self.mapping(VisualKeyMapper.keyStrokes(for: action, family: family))

        case .openLine, .undo, .redo, .scroll:
            return Self.mapping(CommandKeyMapper.keyStrokes(for: action, family: family))

        case .paste(let before, let count):
            // 텍스트가 없는 클립보드(이미지만 있는 등)는 미지원이 아니라 "붙여넣을 것이 없음"이다.
            // 접두만 게시하면 붙여넣기 없이 캐럿만 움직이는 조용한 오동작이 된다.
            guard let wise = pasteWise.resolve() else {
                Logger.eventTap.debug("paste 스킵 — 클립보드에 텍스트가 없다")
                return .skipped
            }
            // 유일하게 그룹이 여럿인 액션 — 액션 1개 안에서 카운트가 곱해지므로 래치가
            // 파고들 틈을 매퍼가 직접 낸다.
            return CommandKeyMapper.pasteStrokeGroups(
                before: before, count: count, wise: wise, family: family)
                .map(Mapping.groups) ?? .unsupported

        default:
            return .unsupported
        }
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

    /// 이 편집이 클립보드에 **줄 단위** 내용을 남기는가.
    ///
    /// `change`는 제외한다 — `cc`는 마지막 확장을 줄 끝으로 바꿔 개행을 남기지 않으므로
    /// 내용이 실제로 charwise이고, 그렇게 붙여넣는 것이 맞다.
    /// `TextRange`에 exhaustive switch를 걸지 않는 것은 매퍼와 같은 계약이다.
    private static func isLinewise(_ op: VimAction.Operator, _ range: VimAction.TextRange) -> Bool {
        guard op != .change else { return false }
        switch range {
        case .line, .linewiseMotion:
            return true
        default:
            return false
        }
    }

    /// 매퍼의 `[KeyStroke]?` 계약을 `Mapping`으로 옮긴다 — `nil`은 미지원이고, 평평한
    /// 시퀀스는 **가를 수 없는 그룹 하나**다 (액션 중간에서 끊으면 "선택은 어긋난 채
    /// `Cmd-X`만 나가는" 파괴적 실행이 된다).
    private static func mapping(_ strokes: [KeyStroke]?) -> Mapping {
        strokes.map { Mapping.groups([$0]) } ?? .unsupported
    }
}

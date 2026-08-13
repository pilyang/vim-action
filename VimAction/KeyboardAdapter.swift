//
//  KeyboardAdapter.swift
//  VimAction
//

import Carbon.HIToolbox
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

    /// 현재 레이아웃에서 `z/x/c/v`를 내는 키코드의 역조회 표 — 비-QWERTY에서 게시 직전
    /// 논리 ANSI 키코드(6/7/8/9)를 치환하는 입력이다. 주입 이유·클로저인 이유는
    /// `hasQwertyCommandKeys`와 같다 (`20260806_non-qwerty-command-key-reverse-lookup.md`).
    private let commandKeyCodes: @Sendable () -> [Character: CGKeyCode]

    /// 캐럿 주변 텍스트 리더 — 무상태 시퀀스를 정확화하는 입력이다. 주입하는 이유는
    /// `pasteWise`와 같다: 실제 AX를 읽으면 골든 테스트가 실기기 권한과 개발자 머신의
    /// 포커스 상태에 따라 갈린다.
    ///
    /// 소비자는 `mapping`의 `.edit` 분기·Visual 세션 분기·`.paste` 분기 **세 곳**이다.
    /// 편집은 범위가 캐럿 주변을 묻는 경우(`EditKeyMapper.consultsFocusedText`)에만 읽는
    /// **범위 술어**, Visual은 앵커 상태의 수립·검증 때문에 읽는 **세션 술어**, 붙여넣기는
    /// charwise `p`의 줄 끝 증명(`pasteConsultsFocusedText`)만 읽는다 — 모션·undo는 묻지
    /// 않으므로 AX 왕복이 0건이다. 읽기가 실패하면 정확화만 포기하고 실행은 한다.
    private let reader: FocusedTextReader

    /// Visual 세션의 앵커 상태 — `pasteWise`와 같은 형태의 상태 보유 협력자이며 게시 직렬
    /// 큐가 단독 소유한다. 주입하는 이유도 같다: 골든 테스트가 세션 중간 상태를 실기기
    /// 없이 만든다 (`20260804_visual-anchor-state-collaborator.md`).
    private let visualAnchor: VisualAnchorTracker

    /// 뷰포트 표시 줄 수 리더 — 스크롤 근사(15/30)를 정확화하는 입력이며 `reader`(캐럿 주변
    /// 창)와 **별개의 프리미티브**다. 주입 이유는 `reader`와 같다. 소비자는 `mapping`의
    /// `.scroll` 분기 한 곳이고, 그 extent의 프로파일 명시값이 있으면 묻지 않는다
    /// (`CommandKeyMapper.scrollConsultsViewport`).
    private let viewportReader: ViewportReader

    /// **AX 쓰기 경로 전용 창 읽기 seam** — 같은 프리미티브(`FocusedText`)를 읽지만 둘이 다르다:
    /// pid가 아니라 **요소**를 받고(쓰기와 같은 핸들 — `AXWindowSnapshot` doc), 반경이 4096이다.
    ///
    /// 소비자는 `mapping`의 AX 실행 계획 분기 한 곳이고, 전략이 accessibility가 아니면 아예
    /// 묻지 않는다 — keyboard 전략 앱은 이 경로로 인한 AX 왕복이 0건이다.
    private let axWindow: @Sendable (AXUIElement) -> FocusedText?

    /// **되읽어 검증 전용 재읽기 seam** — 선택 범위만 읽는다. `axWindow`와 갈린 이유가
    /// 검증의 존재 이유 그 자체다: 창 스냅샷은 액션당 1회 memo라 **쓰기 전** 값이고, 그것과
    /// 비교하면 검증이 자기 자신을 확인하는 장식이 된다. 그래서 이쪽은 memo가 없고 폴링
    /// 간격마다 새로 부른다 (`20260808_ax-readback-verify-convergence-poll.md` 1항).
    private let axSelection: @Sendable (AXUIElement) -> NSRange?

    /// AX 쓰기 단일 통로. 주입 이유는 리더들과 같고 하나 더 있다 — 실제로 쓰면 테스트가
    /// **개발자의 실제 문서를 편집한다** (`AXWriter` doc).
    private let writer: AXWriter

    /// 쓰기 대상 요소 획득 seam. 실구현은 `AXRead.focusedElement`이며 그것이 50ms 메시징
    /// 타임아웃이 쓰기 경로에 상속되는 고리다. 주입은 테스트가 실기기 AX 없이 요소를
    /// 만들어 내기 위한 것이다 (`AXElementSnapshot` doc).
    private let axElement: @Sendable (pid_t) -> AXUIElement?

    /// 실행 실패 보고 seam — 게시 직렬 큐에서 `EventTapController.reportExecutionFailure(at:)`
    /// 로 가는 경로다. **시각을 인자로 싣는 것이 계약이다**: 카운터는 MainActor 격리 안에서만
    /// 돌아 보고가 메인 홉을 타는데, 홉 착지 시각으로 세면 메인 스톨 뒤 뭉쳐 착지한 보고들이
    /// 1초 창에 몰려 거짓 트립한다 (`AXWriteEffects.apply` 주석).
    ///
    /// 기본값 no-op은 다른 주입들과 같은 XCTest 무해화다 — 유일한 실배선은 컨트롤러의
    /// `keyboardActionSink`이고, 그것만이 컨트롤러에 닿을 수 있다.
    private let reportExecutionFailure: @Sendable (TimeInterval) -> Void

    /// 실패 시각 캡처 seam. 주입 이유는 `pasteWise`와 같다 — 실시계를 읽으면 폭주 창(1초)
    /// 판정을 테스트가 실제로 기다려야 한다.
    private let now: @Sendable () -> TimeInterval

    init(
        executor: ActionExecutor = ActionExecutor(),
        pasteWise: PasteWiseResolver = PasteWiseResolver(),
        hasQwertyCommandKeys: @escaping @Sendable () -> Bool = {
            KeyTranslator.hasQwertyCommandKeys
        },
        commandKeyCodes: @escaping @Sendable () -> [Character: CGKeyCode] = {
            KeyTranslator.commandKeyCodes
        },
        reader: FocusedTextReader = FocusedTextReader(),
        visualAnchor: VisualAnchorTracker = VisualAnchorTracker(),
        viewportReader: ViewportReader = ViewportReader(),
        axWindow: @escaping @Sendable (AXUIElement) -> FocusedText? = {
            FocusedTextReader.read($0, radius: FocusedTextReader.axWindowRadius)
        },
        axSelection: @escaping @Sendable (AXUIElement) -> NSRange? = {
            FocusedTextReader.readSelection($0)
        },
        writer: AXWriter = AXWriter(),
        axElement: @escaping @Sendable (pid_t) -> AXUIElement? = AXRead.focusedElement(ofProcess:),
        reportExecutionFailure: @escaping @Sendable (TimeInterval) -> Void = { _ in },
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.executor = executor
        self.pasteWise = pasteWise
        self.hasQwertyCommandKeys = hasQwertyCommandKeys
        self.commandKeyCodes = commandKeyCodes
        self.reader = reader
        self.visualAnchor = visualAnchor
        self.viewportReader = viewportReader
        self.axWindow = axWindow
        self.axSelection = axSelection
        self.writer = writer
        self.axElement = axElement
        self.reportExecutionFailure = reportExecutionFailure
        self.now = now
    }

    /// AX 쓰기 결과의 효과 실행 지점 — **execute 1회당 하나** 만들어 쓰기마다 `apply`하고
    /// 끝에서 `logSummary()`한다 (보고 접기·요약 버킷의 수명이 곧 execute다).
    ///
    /// 어댑터가 seam 둘을 들고 여기서 묶는 것이 요점이다: 효과 타입은 순수하게 유지되고
    /// (주입만 받는다), 배선을 아는 자리는 여전히 어댑터 하나다.
    func axWriteEffects(bundleID: String?) -> AXWriteEffects {
        AXWriteEffects(bundleID: bundleID, report: reportExecutionFailure, now: now)
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
    /// `effectiveStrategy`는 그 프로파일의 전략을 프로브 판정과 함께 **접은 값**이며, 접기가
    /// 콜백 1회인 것도 같은 이유다(버스트 도중 라우팅이 갈리지 않는다).
    ///
    /// `processID`만은 **스냅샷이되 값이 아니라 대상**이다 — 이 pid로 아래에서 액션마다
    /// 캐럿 주변을 다시 읽는다(lazy). 계열·프로파일과 시점 요구가 정반대이기 때문이다:
    /// 같은 버스트의 앞 액션이 캐럿을 옮기므로 선택 범위는 실행 직전 값만 정확하다.
    /// 기본값 `nil`은 읽기가 관심사가 아닌 호출자(대부분의 테스트)를 위한 것이며,
    /// 그때 리더는 아예 불리지 않는다.
    /// `bundleID`는 **값도 대상도 아닌 라벨**이다 — AX 쓰기 요약 로그가 앱을 특정하는 데만
    /// 쓴다. 출처가 `FrontmostAppGate`라 `processID`(포커스 요소 소유자)와 다르지만, 로그
    /// 라벨이라 그 차이가 계약을 깨지 않는다 (`DispatchContext.bundleID`).
    func execute(
        _ actions: [VimAction], family: ElementFamily = .textArea,
        profile: ResolvedProfile = .empty, effectiveStrategy: ProfileStrategy? = nil,
        processID: pid_t? = nil, bundleID: String? = nil,
        isCurrent: () -> Bool = { true }
    ) {
        // dispatch 직후 곧바로 다음 키에 밀려난 경우 — 한 이벤트도 내보내지 않는다.
        guard isCurrent() else { return }

        // AX 실행 계획이 보는 유일한 전략. `nil`은 전략이 관심사가 아닌 호출자(대부분의
        // 테스트)를 위한 기본값이고, `.auto`가 아닌 프로파일에서는 접기와 결과가 같다
        // (`effectiveStrategy(_:verdict:)`가 명시 전략을 그대로 돌려주기 때문).
        let strategy = effectiveStrategy ?? profile.strategy

        // AX 쓰기 효과(보고 1회 접기·요약 버킷)의 수명은 **execute 1회**다. `defer`인 이유는
        // 아래 중단 경로의 이른 `return`들이 요약을 건너뛰면 안 되기 때문이고, 쓰기가 한 건도
        // 없으면 버킷이 비어 아무것도 남기지 않으므로 keyboard 경로에는 공짜다.
        var effects = axWriteEffects(bundleID: bundleID)
        defer { effects.logSummary() }

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

        /// 한 그룹을 **스트로크(다운·업 쌍) 사이 고정 간격**으로 게시한다 — 래치 질의도 청크
        /// 간격도 없는 순수 게시다. Notion 실측에서 0간격 버스트는 재앵커의 Shift 확장도
        /// 붙여넣기 접두의 화살표도 소화하지 못했다(이벤트당 5ms 프로브는 완전 정상 — 간격
        /// 문제로 확정). 그룹은 원자라 내부 중단 확인이 없다(최대 수 타 × 5ms라 무해).
        ///
        /// 하이브리드의 첫 그룹은 이것을 **직접** 부른다 — 원자 그룹 ④는 그 앞에 래치 질의를
        /// 두지 못하기 때문이다. 간격 규칙이 두 경로에서 갈리지 않도록 함수를 공유한다.
        func postSpaced(_ events: [CGEvent]) {
            for index in stride(from: 0, to: events.count, by: 2) {
                if index > 0 { Thread.sleep(forTimeInterval: Self.pacedStrokeInterval) }
                executor.post(Array(events[index..<min(index + 2, events.count)]))
            }
        }

        /// 페이싱 그룹을 청크 경계 규칙 아래 게시한다 — 최신 여부 확인·중단 계약은 `flush`와
        /// 같다. 반환 false = 이 실행이 밀려남 — 호출자는 즉시 그만둔다.
        func postPaced(_ events: [CGEvent]) -> Bool {
            if postedChunks > 0 { Thread.sleep(forTimeInterval: Self.chunkInterval) }
            guard isCurrent() else {
                #if DEBUG
                Logger.eventTap.debug(
                    "실행 중단 — 페이싱 그룹 폐기 (게시 청크 \(postedChunks, privacy: .public))")
                #endif
                return false
            }
            postSpaced(events)
            postedChunks += 1
            return true
        }

        /// AX 쓰기 앞의 **순서 봉인** — 같은 execute에 아직 게시되지 않은 keyboard 이벤트를
        /// 먼저 비운다. 게시는 배달만 걸고 돌아오고 AX 쓰기는 대상 앱 런루프까지 동기라,
        /// 두고 쓰면 화면 순서가 액션 순서와 그대로 뒤집힌다 — "동기 AX 쓰기 → 게시"만
        /// 레이스가 없다는 계약의 코드 측 대응이다.
        /// 반환 false = 이 실행이 밀려남 — 호출자는 즉시 그만둔다.
        func sealOrder(before action: VimAction) -> Bool {
            guard flush() else {
                visualAnchor.apply(.discard)
                return false
            }
            #if DEBUG
            // `flush`는 **미게시분**만 해결한다 — 이미 게시된 이벤트를 대상 앱이 소비하는
            // 순서 대 동기 AX 쓰기는 미확정 방향이다(계약이 보증하는 것은 "AX 쓰기 → 게시"
            // 하나뿐). 한 execute가 전부 AX이거나 전부 위임이라 도달 불가여야 하므로, 뜨면
            // 그 전제가 깨진 것이다.
            if postedChunks > 0 {
                Logger.eventTap.debug(
                    "AX 쓰기가 위임 게시 뒤에 온다 — 소비 순서 미보장: \(String(describing: action), privacy: .public)"
                )
            }
            #endif
            return true
        }

        // 뷰포트 스냅샷은 **execute당 1회**다 — 액션별 재생성 계약(`FocusedTextSnapshot`)의
        // 사유는 앞 액션이 캐럿을 옮긴다는 것인데, 뷰포트 높이는 버스트 중 불변이라 액션별
        // 재읽기는 이득 0에 비용만 곱한다(`3Ctrl-f`는 엔진이 액션 3건으로 복제한다).
        // 만드는 것만으로는 AX를 부르지 않는다 (lazy).
        let viewport = ViewportSnapshot(processID: processID, reader: viewportReader)

        for action in actions {
            // 액션마다 새 스냅샷 — 앞 액션이 캐럿을 옮겼으므로 이전 액션의 읽기를 물려받으면
            // 낡은 오프셋으로 계산한다. 만드는 것만으로는 AX를 부르지 않는다 (lazy).
            let text = FocusedTextSnapshot(processID: processID, reader: reader)
            // AX 경로의 요소·읽기도 액션당 1회 lazy·memo다. 요소는 반드시
            // `AXRead.focusedElement` 경유라 50ms 캡을 상속하고, 창 읽기가 그 **같은 핸들**을
            // 받아 뒤따르는 쓰기와 요소가 갈리지 않는다. 만드는 것만으로는 AX를 부르지 않으므로
            // keyboard 전략 앱은 왕복 0건이다.
            let axTarget = AXElementSnapshot(processID: processID, acquire: axElement)
            let axText = AXWindowSnapshot(element: axTarget, read: axWindow)
            // 레이아웃도 액션당 1회 스냅샷 — 게이트(mapping)와 치환(게시 직전)이 같은 값을
            // 읽어야, 그 사이 레이아웃 전환으로 "게이트는 통과했는데 표에는 없는" 창이
            // 생기지 않는다. QWERTY면 표는 읽지 않는다 (치환 자체가 생략된다).
            let layout = LayoutSnapshot(
                isQwerty: hasQwertyCommandKeys(), commandKeyCodes: commandKeyCodes)
            let groups: [[KeyStroke]]
            let paced: Bool
            switch mapping(
                for: action, family: family, profile: profile, strategy: strategy, text: text,
                axText: axText, viewport: viewport, layout: layout) {
            case .ax(let range, let visual):
                // ① 순서 봉인 (위 `sealOrder` 주석).
                guard sealOrder(before: action) else { return }
                // ② 중단 래치는 **파괴적 쓰기 직전**에 한 번 더 — AX 경로에는 청크가 없으므로
                //    질의 지점이 "액션 사이 + 쓰기 직전"이 되어 keyboard 8타 청크보다 촘촘하다.
                guard isCurrent() else {
                    #if DEBUG
                    Logger.eventTap.debug(
                        "실행 중단 — AX 쓰기 폐기: \(String(describing: action), privacy: .public)")
                    #endif
                    return
                }
                // ③ 쓰기 **전** 단계의 실패(요소 없음·읽기 실패·사전 경계 검증 탈락)는 보고도
                //    폴백도 아닌 **스킵**이다 — 실행을 시도하지 않았기 때문이다. 그 execute의
                //    잔여까지 함께 접는 것은 "첫 미지원·첫 실패" 구조 규칙과 같은 근거다:
                //    한 키 입력 안에서 이 실패는 일시적이지 않고, 접지 않으면 `100j`가
                //    100×50ms로 게시 큐를 잡는다.
                //    (아래 `provenTarget` 주석 참고 — memo·경계 증명·실패 로그가 거기 있다.)
                guard let target = Self.provenTarget(
                    range, element: axTarget, window: axText, action: action)
                else { return }
                // ④ `written`은 흐름을 정하지 않는다 — 호출자가 outcome을 보고 끊는다. `.success`
                //    외 전부에서 끊는 것이 "실행 실패 보고는 키 입력 1건당 최대 1회"를 구조로
                //    보장하고, 미지원·경합 앱에서 동기 왕복이 곱해지는 것을 함께 막는다.
                guard written(target, action: action, effects: &effects) == .success else {
                    return
                }
                // ⑤ 확정 부수효과는 **쓰기 성공 뒤**다. Visual 아닌 액션은 `.unchanged`라 무동작
                //    이고, 되읽어 검증이 없는 것은 이 케이스가 뒤에 아무것도 게시하지 않기
                //    때문이다 — 실질 방어선은 다음 액션 읽기의 자가 검증이다.
                confirmVisual(action, update: visual, path: .accessibility)
                continue
            case .axUnavailable:
                #if DEBUG
                Logger.eventTap.debug(
                    "AX 경로 스킵 — 포커스 요소·읽기 없음, execute 잔여도 접는다: \(String(describing: action), privacy: .public)"
                )
                #endif
                return
            case .hybrid(let range, let mapped, let pacedGroups):
                // 하이브리드도 위임 그룹을 게시하므로 치환은 `.groups`와 같은 자리·같은
                // `LayoutSnapshot`을 쓴다 (게이트와 치환의 TOCTOU 봉쇄가 그대로 상속된다).
                guard let substituted = Self.substituted(mapped, layout: layout, action: action),
                    let delegated = substituted.first
                else {
                    visualAnchor.apply(.discard)
                    continue
                }
                // ① 순서 봉인 — `.ax`와 같은 자리·같은 이유다.
                guard sealOrder(before: action) else { return }
                // ② 중단 래치는 **접두 쓰기 직전까지만**이다. 이 뒤 게시 그룹까지는 원자 그룹
                //    ④라 질의가 없다 — 사이에서 끊기면 AX 선택이 화면에 잔류하고 다음 Normal
                //    `x`가 그것을 통째로 잘라낸다
                //    (`20260808_hybrid-prefix-atomic-with-first-group.md`).
                guard isCurrent() else {
                    #if DEBUG
                    Logger.eventTap.debug(
                        "실행 중단 — 하이브리드 접두 폐기: \(String(describing: action), privacy: .public)")
                    #endif
                    return
                }
                guard let target = Self.provenTarget(
                    range, element: axTarget, window: axText, action: action)
                else { return }
                // ③ **CGEvent 생성을 쓰기 앞으로 당긴다.** 그룹을 만들 수 없는데 접두만 쓰면
                //    선택이 잔류하는 그 창이 그대로 열린다 — 같은 결정의 후반부다.
                guard let delegatedEvents = Self.events(for: delegated) else {
                    Logger.eventTap.error(
                        "CGEvent 생성 실패 — 접두 쓰기 없이 액션 폐기: \(String(describing: action), privacy: .public)"
                    )
                    continue
                }
                // ④ 접두 쓰기 — 실패 처리는 `.ax`와 같다(폴백 없음, execute 잔여 중단).
                guard written(target, action: action, effects: &effects) == .success else {
                    return
                }
                // ⑤ 되읽어 검증 — 쓴 범위가 착지해야 파괴 단계가 나간다. 실패는 보고가 아니라
                //    무동작 + execute 잔여 중단이다(쓰기는 `.success`였고 파괴는 시도 전).
                guard verifiedSelection(target.element, matches: target.range) else {
                    effects.noteVerifyMismatch(action: action)
                    return
                }
                // ⑥ 게시는 **래치 질의를 거치지 않고** 곧장 — 원자 그룹 ④다. 스트로크 간격만은
                //    `.groups`와 같은 규칙으로 둔다(2타 이상 페이싱 그룹 = `.paste`의
                //    `[Return, Cmd-V]` — 0간격 버스트에서 앞 키를 잃는 앱이 실측됐다).
                if pacedGroups, delegated.count >= 2 {
                    postSpaced(delegatedEvents)
                } else {
                    executor.post(delegatedEvents)
                }
                postedChunks += 1
                // **게시가 실제로 나간 뒤에** wise를 기억한다. `.groups`에서는 매핑 확정이 곧
                // 게시 확정에 가까웠지만, 하이브리드는 그 사이에 설계된 실패 단계(검증 불일치
                // 등)가 여럿 있어 매핑 시점 기록이면 나가지도 않은 편집의 wise가 남는다 —
                // 그 뒤 외부 복사 1회가 델타를 정확히 1로 만들면 `p`가 그 기억으로 오판된다.
                // 편집이 아닌 하이브리드(`.openLine`·`.paste`)에는 부수효과가 없어 no-op이다.
                recordEditWise(for: action)
                // 둘째 그룹부터는 원자가 아니다 — `.groups`와 **같은 청크·페이싱 루프**로
                // 낙하한다(`.paste`의 나머지 `Cmd-V`들). 그룹이 하나뿐이면 빈 배열이라 루프가
                // 그냥 지나간다.
                groups = Array(substituted.dropFirst())
                paced = pacedGroups

            case .groups(let mapped, let pacedGroups):
                guard let substituted = Self.substituted(mapped, layout: layout, action: action)
                else {
                    visualAnchor.apply(.discard)
                    continue
                }
                groups = substituted
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

    /// 되읽어 검증의 폴링 간격 — 도그푸딩 조절값이다.
    ///
    /// Notion은 `AXSelectedTextRange` 쓰기가 `.success`를 돌려준 뒤에도 적용이 **비동기**여서
    /// 되읽기가 ~6ms까지 낡은 값을 주고 ~10ms경 수렴한다(세션 0 실측). 즉시 1회 읽기로
    /// 설계하면 그 앱에서 편집 전부가 상시 헛스킵이 된다.
    private static let readbackPollInterval: TimeInterval = 0.002

    /// 되읽어 검증의 총 상한 — 실측 수렴 ~10ms의 3~4배 마진이다. 도달 = 검증 실패.
    ///
    /// `AXRead.messagingTimeout`(50ms)과 공유하지 않는 것은 의미가 달라서다 — 그쪽은 병적
    /// 정지 차단기, 이쪽은 정상 앱의 적용 지연 대기다
    /// (`20260808_ax-readback-verify-convergence-poll.md` 2항).
    private static let readbackVerifyTimeout: TimeInterval = 0.040

    /// 접두 쓰기가 착지했는가 — **신선한 선택 전용 재읽기의 수렴 폴링**이다.
    ///
    /// 첫 재읽기는 지연 없이 나가므로 즉시 일관한 앱(TextEdit 실측)에서는 폴링 비용이 0이다.
    /// 창 스냅샷(`AXWindowSnapshot`) memo를 쓰지 않는 것이 이 함수의 존재 이유다 — 그 값은
    /// 쓰기 **전**이라 비교가 자기 확인이 된다.
    ///
    /// 상한 판정에 `now` seam을 쓰므로 **테스트에서 상한 도달을 재현하려면 진행하는 `now`를
    /// 주입해야 한다** (프로덕션 `systemUptime`은 항상 진행한다). 수렴·즉시 일치 경로는
    /// 시각을 아예 보지 않는다.
    private func verifiedSelection(_ element: AXUIElement, matches range: NSRange) -> Bool {
        let deadline = now() + Self.readbackVerifyTimeout
        while true {
            if axSelection(element) == range { return true }
            guard now() < deadline else { return false }
            Thread.sleep(forTimeInterval: Self.readbackPollInterval)
        }
    }

    /// 접두·캐럿 쓰기가 겨냥할 요소와 **사전 경계 검증을 통과한** 범위.
    ///
    /// `window`가 memo라 여기서 다시 물어도 **범위를 계산한 바로 그 읽기**다 — 따로 읽으면
    /// 사전 검증이 범위와 다른 문서 상태를 기준으로 서서 방어가 아니라 장식이 된다. 요소·읽기가
    /// 여기서 `nil`인 것은 정상 경로에서는 불가능하다(계획이 그 둘을 이미 통과했고 둘 다
    /// memo다) — 옵셔널은 타입이 요구하는 형식이지 분기가 아니다. 남는 실질 분기는 경계 증명
    /// 하나이며, 그 탈락은 우리 계산이 어긋났다는 신호라 미지원 스킵(DEBUG)과 달리 항상 남긴다.
    private static func provenTarget(
        _ range: NSRange, element: AXElementSnapshot, window: AXWindowSnapshot, action: VimAction
    ) -> (element: AXUIElement, range: NSRange)? {
        guard let handle = element.value(), let focused = window.value(),
            let proven = AXWriteOutcome.provenWriteRange(
                range, characterCount: focused.characterCount)
        else {
            Logger.eventTap.error(
                "AX 쓰기 범위 증명 실패 — 스킵 [\(range.location, privacy: .public), \(range.upperBound, privacy: .public)): \(String(describing: action), privacy: .public)"
            )
            return nil
        }
        return (handle, proven)
    }

    /// 게시 직전의 단일 치환 단계 — 비-QWERTY에서만 논리 ANSI 명령 키코드(6/7/8/9)를 현재
    /// 레이아웃의 역조회 키코드로 바꾼다. QWERTY 생략이 현행 바이트 동일의 증명이다.
    ///
    /// `.groups`와 `.hybrid`가 **같은 함수를 거치는 것이 계약**이다 — 하이브리드의 오퍼레이터
    /// 그룹도 `Cmd-X`/`Cmd-C`라 치환 대상인데, 분기마다 따로 두면 한쪽이 조용히 빠진다.
    ///
    /// `nil` = 액션 폐기다. 게이트가 필요 문자를 확인한 뒤라 정상 경로에서는 도달하지 않지만
    /// (레이아웃 스냅샷을 게이트와 공유한다), ANSI 코드가 비-QWERTY로 그대로 나가는 것이 이
    /// 축의 위험 그 자체라 CGEvent 생성 실패와 같은 all-or-nothing으로 버린다.
    private static func substituted(
        _ groups: [[KeyStroke]], layout: LayoutSnapshot, action: VimAction
    ) -> [[KeyStroke]]? {
        if layout.isQwerty { return groups }
        guard let rewritten = rewritten(groups, using: layout.commandKeyCodes) else {
            Logger.eventTap.error(
                "역조회 치환 실패 — 액션 폐기: \(String(describing: action), privacy: .public)")
            return nil
        }
        return rewritten
    }

    /// AX 쓰기 1회 — 통로 호출과 효과 반영이 **한 자리에** 있어야 `.ax`와 `.hybrid`가 같은
    /// 감사 경로를 쓴다(분류·보고·요약 버킷이 한쪽에서만 바뀌는 일이 없다).
    ///
    /// 흐름은 정하지 않는다 — 호출자가 outcome을 보고 끊는 것이 `AXWriteEffects.apply`의 계약
    /// 그대로다.
    private func written(
        _ target: (element: AXUIElement, range: NSRange), action: VimAction,
        effects: inout AXWriteEffects
    ) -> AXWriteOutcome {
        let outcome = AXWriteOutcome.classify(
            writer.writeSelectedTextRange(target.element, target.range))
        effects.apply(outcome, action: action)
        return outcome
    }

    /// 이 편집이 클립보드에 남기는 내용의 wise를 기억한다 — 뒤따르는 `p`가 끝 개행
    /// 휴리스틱(앱마다 틀린다)에 기대지 않게 하는 자리다.
    ///
    /// **호출 시점이 계약이다: 게시가 확정된 뒤.** 스킵된 편집이 기억을 남기면 다음 외부 복사
    /// 한 번 뒤의 `p`가 그 wise로 오판된다(델타-1 규칙이 그때는 자가 치유하지 못한다).
    /// 위임(`.groups`)은 매핑 확정이 곧 게시 확정이라 그 자리에서 부르고, 하이브리드는 접두
    /// 쓰기·되읽어 검증이라는 실패 단계가 사이에 있어 **실제 게시 뒤에** 부른다.
    private func recordEditWise(for action: VimAction) {
        guard case .edit(let op, let range) = action else { return }
        if case .selection = range {
            // 내용 wise는 범위가 아니라 세션이 정한다 — change도 선택을 그대로 자르므로
            // (cc의 줄 유지 반올림이 없다) 세션 wise가 곧 내용이다.
            pasteWise.recordSelectionEdit()
        } else if let wise = Self.contentWise(op, range) {
            pasteWise.recordEdit(wise)
        }
    }

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
        /// 문제로 확정). 범위를 이 둘로 한정해야 스크롤(단일 화살표 그룹 — 뷰포트 유래면
        /// 최대 200타)·폴백 카운트 반복(`500x`)·카운트 버스트가 타이밍까지 현행 그대로다.
        /// 스크롤이 계속 무페이싱인 것은 드롭의 실패 방향이 "덜 스크롤"이라 무해해서다.
        case groups([[KeyStroke]], paced: Bool)
        /// **AX 쓰기 계획** — `AXSelectedTextRange`에 쓸 범위다(길이 0이면 캐럿).
        ///
        /// `.groups`(위임)와 형제 케이스인 것이 "단일 실행 드라이버"의 코드 측 모양이다:
        /// execute 루프(중단 래치·스냅샷·요약 로그)와 게이트 3종·부수효과를 그대로 공유하고
        /// **액션 분기 안쪽만** 갈린다. "AX 어댑터가 keyboard 어댑터를 부른다"(감사 안 되는
        /// 둘째 진입점)와 "디스패처가 액션 단위로 어댑터를 가른다"(execute당 계약 분열)는
        /// 둘 다 기각됐다 (`20260808_ax-delegation-table-single-driver.md`).
        ///
        /// `paced:`가 없는 것도 계약이다 — AX 쓰기는 합성 이벤트가 아니라 드롭 모드가 없어
        /// 페이싱 대상이 아니고, `paced`는 위임 전용 속성으로 남는다.
        ///
        /// `visual`은 Visual 세션의 상태 변화다(그 외 액션은 `.unchanged`). 매핑 시점에 적용할
        /// 수 없어 여기 실린다 — **쓰기 `.success` 뒤**에야 확정이고, 그 사이에 설계된 실패
        /// 단계(요소·경계 증명·쓰기 자체)가 여럿이라 매핑 시점 적용이면 나가지도 않은 액션의
        /// side가 남는다 (`recordEditWise`가 하이브리드에서 게시 뒤로 간 것과 같은 함정).
        case ax(NSRange, visual: VisualAnchorUpdate)
        /// **하이브리드** — AX 범위/캐럿 접두 쓰기 + 위임 게시 그룹. 편집(delete·change·yank)·
        /// `.openLine`·`.paste`가 이 케이스를 공유한다.
        ///
        /// 접두 쓰기(및 되읽어 검증)와 **첫 게시 그룹 사이에는 중단 질의가 없다** — 원자 그룹
        /// ④다. 사이에서 끊기면 편집의 AX 선택이 화면에 잔류하고, 다음 Normal `x`
        /// (`Shift-→, Cmd-X`)가 그것을 통째로 잘라낸다
        /// (`20260808_hybrid-prefix-atomic-with-first-group.md`).
        ///
        /// **원자인 것은 첫 그룹뿐이다** — 둘째 그룹부터는 `.groups`와 **같은 청크·페이싱
        /// 경로**를 탄다. 그룹이 여럿인 액션은 `.paste` 하나이고(`1000p` = `Cmd-V` 1,000타),
        /// 통짜로 내면 중단 래치가 파고들 틈이 없다는 것이 `.groups`에서와 같은 이유다.
        ///
        /// `paced`의 의미도 `.groups`와 같다(2타 이상 그룹의 스트로크 사이 간격). 실효 지점은
        /// `.paste`의 `[Return, Cmd-V]` 한 그룹뿐이지만 — 나머지 paste 그룹은 1타라 페이싱
        /// 규칙 밖이다 — 그 자리가 정확히 Notion 0간격 버스트 약점의 재현 지점이고, 편집·
        /// openLine은 `false`라 세션 2가 확인한 타이밍이 그대로 유지된다.
        case hybrid(NSRange, [[KeyStroke]], paced: Bool)
        /// AX 경로인데 **쓰기 시도 전 단계**가 실패했다 — 포커스 요소 미노출, 읽기 타임아웃.
        ///
        /// 보고도 폴백도 아닌 스킵이다(실행을 시도하지 않았다). `.skipped`와 갈라 두는 것은
        /// 흐름이 다르기 때문이다: 이쪽은 **execute 잔여까지 함께 접는다** — 한 키 입력 안에서
        /// 이 실패는 일시적이지 않고(Slack처럼 요소를 아예 안 여는 앱이 전형), 접지 않으면
        /// `100j`가 100×50ms로 게시 큐를 잡는다. "첫 미지원·첫 실패에서 잔여 스킵" 구조 규칙의
        /// 쓰기 전 단계 대응이다.
        case axUnavailable
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

    /// 액션 1건 처리 동안 고정되는 레이아웃 상태 — 게이트(`mapping`)와 치환(게시 직전)이
    /// 같은 값을 읽는 것이 계약이다. 따로 읽으면 그 사이 레이아웃 전환으로 게이트는
    /// 통과했는데 치환 표에는 없는 창이 생긴다.
    private struct LayoutSnapshot {
        let isQwerty: Bool
        let commandKeyCodes: [Character: CGKeyCode]

        init(isQwerty: Bool, commandKeyCodes: () -> [Character: CGKeyCode]) {
            self.isQwerty = isQwerty
            // QWERTY면 치환이 생략되므로 표를 읽을 이유가 없다.
            self.commandKeyCodes = isQwerty ? [:] : commandKeyCodes()
        }
    }

    /// 논리 ANSI 명령 키코드(6/7/8/9 = Z/X/C/V)를 역조회 키코드로 치환한다. 플래그는
    /// 보존한다 — redo의 `Shift-Cmd`는 z의 새 키코드에 그대로 얹힌다.
    ///
    /// 6/7/8/9가 명령 키 외의 의미로 시퀀스에 등장할 길은 없다: 우리가 합성하는 다른 키는
    /// 화살표·Return·기능 키뿐이고, 프로파일 스트로크 어휘(`ConfigKey`)도 문자 키를
    /// 제외한다 — `KeyboardAdapterLayoutGateTests`가 전 매퍼 출력으로 고정하는 사실이다.
    ///
    /// `nil` = 치환 대상 키코드가 표에 없다 — 호출측이 액션을 통째로 폐기한다(부분 치환은
    /// ANSI 코드가 비-QWERTY로 그대로 나가는 부분 시퀀스류의 파괴적 실행이다).
    private static func rewritten(
        _ groups: [[KeyStroke]], using codes: [Character: CGKeyCode]
    ) -> [[KeyStroke]]? {
        var result: [[KeyStroke]] = []
        result.reserveCapacity(groups.count)
        for group in groups {
            var strokes: [KeyStroke] = []
            strokes.reserveCapacity(group.count)
            for stroke in group {
                guard let character = Self.logicalCommandKeyCharacters[stroke.keyCode] else {
                    strokes.append(stroke)
                    continue
                }
                guard let keyCode = codes[character] else { return nil }
                strokes.append(KeyStroke(Int(keyCode), stroke.flags))
            }
            result.append(strokes)
        }
        return result
    }

    /// 논리 ANSI 명령 키코드 → 기대 문자. 치환과 게이트(`requiredCommandCharacters`)가
    /// 참조하는 유일한 대응표다.
    private static let logicalCommandKeyCharacters: [CGKeyCode: Character] = [
        CGKeyCode(kVK_ANSI_Z): "z", CGKeyCode(kVK_ANSI_X): "x",
        CGKeyCode(kVK_ANSI_C): "c", CGKeyCode(kVK_ANSI_V): "v",
    ]

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
    /// `text`를 읽는 것은 아래 `.edit` 분기·Visual 세션 분기·`.paste` 분기 **세 곳**이다 —
    /// 묻지 않으면 AX 왕복도 없다(lazy). `viewport`는 `.scroll` 분기만 읽는다 — 별개
    /// 프리미티브라 `text`와 리더도 수명(execute당 1회)도 다르다.
    private func mapping(
        for action: VimAction, family: ElementFamily, profile: ResolvedProfile,
        strategy: ProfileStrategy, text: FocusedTextSnapshot, axText: AXWindowSnapshot,
        viewport: ViewportSnapshot, layout: LayoutSnapshot
    ) -> Mapping {
        // 새 Visual 세션의 시작은 옛 세션 wise를 **게이트보다 앞에서** 잊는다 — note는
        // 게시 확정에 게이팅되므로, 걸러진 begin(`.nonText`·`.unresolved`) 뒤의
        // `.selection` 편집이 이전 세션의 wise로 기록되는 구멍을 여기서 막는다. 망각은
        // 기록이 아니라서 "게이트가 부수효과보다 앞" 계약을 깨지 않는다(보수 방향 —
        // 틀려봐야 휴리스틱 폴백이다).
        if case .beginSelection = action {
            pasteWise.forgetSelectionWise()
            // **새 세션의 경로도 여기서 잊는다.** 고정은 확정 뒤(`confirmVisual`)인데, AX 분기를
            // 골라 놓고 그 앞에서 실패하는 경로(요소·읽기 실패·경계 증명 실패·쓰기 실패)는
            // 확정에 도달하지 않는다 — 잊지 않으면 **AX가 된 적 없는 세션이 옛 pin을 상속해**
            // 남은 확장이 전부 스킵된다(쓴 것이 없으니 keyboard 폴백이 안전한 자리다).
            // 망각은 기록이 아니라서 위 `forgetSelectionWise`와 같은 이유로 게이트보다 앞이다.
            visualAnchor.pin(.keyboard)
        }
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
        // 비-QWERTY 레이아웃 게이트 — ANSI **문자** 키코드를 합성하는 액션만 본다. 매퍼는
        // ANSI 상수를 논리 키코드로 내고 대상 앱은 활성 레이아웃으로 재해석하므로, 치환
        // 없이는 AZERTY에서 `u`의 `Cmd-Z`가 `Cmd-W`(창 닫기 — 데이터 손실)가 된다.
        // 비-QWERTY에서는 이 액션이 필요로 하는 문자가 역조회 표에 있으면 통과시키고
        // (게시 직전 치환이 처리한다 — `execute`), 못 찾은 문자가 필요하면 종전대로
        // 보류한다(최후 방어선). 화살표·Return만 쓰는 액션(모션·스크롤·openLine·선택)은
        // 필요 문자가 없어 통과한다. 걸러내기 게이트와 같은 이유로 부수효과(`recordEdit`·
        // 클립보드 읽기)보다 앞이다.
        guard layout.isQwerty
            || Self.requiredCommandCharacters(action).allSatisfy({
                layout.commandKeyCodes[$0] != nil
            })
        else {
            return .layoutBlocked
        }

        switch action {
        case .move(let motion):
            // **AX 실행 계획의 갈림길은 여기 한 곳이다.** 게이트 3종 뒤라 위임 경로와 전제가
            // 같고, 확대 창 읽기는 그 뒤에 온다 — 게이트에 걸린 액션은 AX 왕복도 0건이다.
            if Self.usesAXWrite(action, family: family, strategy: strategy, profile: profile) {
                // 읽기 실패(포커스 요소 미노출·타임아웃)는 **`unproven`과 다른 축**이다 —
                // 창이 답을 못 한 것이 아니라 물어볼 창이 없는 것이라, 위임이 아니라 스킵이며
                // execute 잔여까지 함께 접는다 (`Mapping.axUnavailable`).
                guard let focused = axText.value() else { return .axUnavailable }
                switch FocusedTextOffsets.caretTarget(for: motion, in: focused) {
                case .caret(let offset):
                    return .ax(NSRange(location: offset, length: 0), visual: .unchanged)
                case .invalid:
                    // 미지원이 아니라 "지원하지만 Vim에서 무효" — 편집의 증명된 무게시와 같은
                    // 편이다(첫 줄 `k`류가 위임되면 실제로 캐럿이 움직인다).
                    #if DEBUG
                    Logger.eventTap.debug(
                        "AX 모션 스킵 — 오프셋이 Vim 무효를 증명했다: \(String(describing: action), privacy: .public)"
                    )
                    #endif
                    return .skipped
                case .unproven:
                    // 창이 답하지 못했다 → 아래 위임으로 낙하한다. 쓰기 시도 **전**이라
                    // 이중 실행이 원리적으로 불가하며, 쓰기 시도 **후** 실패의 폴백 금지와는
                    // 별개 축이다 (`20260808_ax-delegation-table-single-driver.md`).
                    break
                }
            }
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
            //
            // **AX 실행 계획이 먼저다** — 통과하면 확대 창(4096)이 범위를 증명하고, 그 창이
            // 위임 낙하 시 정확화 입력까지 겸한다(한 액션은 창을 한 번만 읽는다).
            var axFocused: FocusedText?
            var hybrid: Mapping?
            if Self.usesAXWrite(action, family: family, strategy: strategy, profile: profile) {
                // 읽기 실패는 `unproven`과 **다른 축**이다 — 창이 답을 못 한 것이 아니라
                // 물어볼 창이 없는 것이라, 위임이 아니라 스킵이며 execute 잔여도 접는다.
                guard let focused = axText.value() else { return .axUnavailable }
                axFocused = focused
                switch FocusedTextOffsets.editSpan(for: op, range: range, in: focused) {
                case .range(let span):
                    // 오퍼레이터 그룹은 keyboard 경로와 **같은 함수**에서 나온다 — yank
                    // collapse `←`의 프로파일 재정의·disable 전파가 두 경로에서 갈리지 않는다.
                    // `nil`(= `char_left` disable)이면 아래 위임으로 낙하해 기존 경로가
                    // `.disabledByProfile`로 정직하게 집계한다.
                    if let operatorKeys = EditKeyMapper.operatorStrokes(for: op, profile: profile) {
                        // 위임분은 `[Cmd-X]` 또는 `[Cmd-C, ←]` 한 그룹이고, 현행 keyboard 편집이
                        // 무페이싱이라 그대로 둔다 (`.paste`만 `paced: true`다).
                        hybrid = .hybrid(span, [operatorKeys], paced: false)
                    }
                case .invalid:
                    // 미지원이 아니라 "지원하지만 Vim에서 무효" — 모션의 증명된 무게시와 같은
                    // 편이다(마지막 줄 `dj`·첫 줄 `dk`가 위임되면 실제로 줄이 지워진다).
                    #if DEBUG
                    Logger.eventTap.debug(
                        "AX 편집 스킵 — 범위가 Vim 무효를 증명했다: \(String(describing: action), privacy: .public)"
                    )
                    #endif
                    return .skipped
                case .unproven:
                    // 창이 답하지 못했다 → 아래 위임으로 낙하한다. 쓰기 시도 **전**이라 이중
                    // 실행이 원리적으로 불가하며, 쓰기 시도 **후** 실패의 폴백 금지와는 별개
                    // 축이다 (`20260808_hybrid-prefix-failure-axes-clarified.md`).
                    break
                }
            }
            // 위임 낙하는 **이미 읽은 AX 창을 그대로** 정확화에 먹인다 — 256 창 재읽기는
            // 액션당 왕복을 두 배로 만들고, 4096 창은 그 초집합이라 술어에 같은 답을 낸다
            // (`20260808_ax-unproven-edit-delegation-reuses-ax-window.md`).
            let result: Mapping
            if let hybrid {
                result = hybrid
            } else {
                let focused =
                    axFocused ?? (EditKeyMapper.consultsFocusedText(range) ? text.value() : nil)
                result = Self.classifyEdit(
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
            }
            // 편집은 전부 클립보드를 쓴다(delete·change는 `Cmd-X`, yank는 `Cmd-C`) — 뒤따르는
            // `p`가 끝 개행 휴리스틱(앱마다 틀린다)에 기대지 않게 내용의 wise를 기억해 둔다.
            // **게시가 확정된 뒤에만** 기억한다 — 프로파일 disable로 스킵된 편집이 기억을
            // 남기면, 다음 외부 복사 한 번 뒤의 `p`가 그 wise로 오판된다 (게이트 2종과 같은
            // 규칙이되, 모션 disable은 매퍼 안에서야 드러나므로 판정이 앞설 수 없어 기억을
            // 뒤로 미룬다). **하이브리드는 여기서 기억하지 않는다** — 접두 쓰기·되읽어 검증이
            // 매핑과 게시 사이에 있어 실제 게시 뒤에 부른다 (`recordEditWise` doc).
            if case .groups = result { recordEditWise(for: action) }
            return result

        case .beginSelection, .extendSelection, .switchSelectionWise, .clearSelection:
            // **읽기의 두 번째 소비 지점**이다 (M5 PR-C1). 편집의 범위 술어와 달리 Visual은
            // **세션 술어**다 — 앵커 상태의 수립(진입)과 자가 검증(세션 중)이 읽기의
            // 소비자라, 어떤 액션이 읽는지는 범위가 아니라 세션 상태가 정한다.
            //
            // AX 경로가 **먼저**다 — 진입이 세션 경로를 정하고, AX로 고정된 세션은 아래
            // keyboard 재앵커 기계로 낙하하지 않는다(무상태·재정의 시퀀스 금지). `nil`은
            // "이 세션은 keyboard다"이며 그때 아래가 현행 그대로 돈다.
            if let ax = axVisualMapping(
                for: action, family: family, profile: profile, strategy: strategy, text: text,
                axText: axText) {
                return ax
            }
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
            // 위임은 매핑 확정이 곧 게시 확정에 가깝다(AX는 쓰기 성공 뒤 — `confirmVisual`).
            if case .groups = result {
                confirmVisual(action, update: update, path: .keyboard)
            }
            return result

        case .openLine(let above):
            // AX 접두는 **논리** 줄 시작/끝이라 `Cmd-←`/`Cmd-→`(시각 줄)가 못 서던 자리가
            // 함께 풀린다 — 소프트 랩 문단에서 `O`가 빈 줄을 못 만들던 수용 엣지가 그것이다.
            // 위임분(`Return`·`O`의 복귀)은 매퍼가 내므로 `.textField` 게이트와 `new_line`
            // 재정의가 keyboard 경로와 같은 함수를 지난다.
            if Self.usesAXWrite(action, family: family, strategy: strategy, profile: profile) {
                guard let focused = axText.value() else { return .axUnavailable }
                if case .at(let offset) = FocusedTextOffsets.openLineInsertion(
                    above: above, in: focused),
                    let delegated = CommandKeyMapper.openLineDelegatedStrokes(
                        above: above, family: family, profile: profile) {
                    return .hybrid(
                        NSRange(location: offset, length: 0), [delegated], paced: false)
                }
                // `.unproven`(창이 답 못 함)·위임분 `nil`(계열 게이트·모션 disable)은 아래
                // 위임으로 낙하한다. `Insertion`의 `.appendingLine`은 openLine이 내지 않지만,
                // 오면 같은 보수 방향(위임)으로 흡수된다.
            }
            return Self.classify(
                CommandKeyMapper.keyStrokes(for: action, family: family, profile: profile)
            ) {
                CommandKeyMapper.keyStrokes(for: action, family: family, profile: .empty)
            }

        case .undo, .redo:
            return Self.classify(
                CommandKeyMapper.keyStrokes(for: action, family: family, profile: profile)
            ) {
                CommandKeyMapper.keyStrokes(for: action, family: family, profile: .empty)
            }

        case .scroll(let extent, _):
            // **읽기의 네 번째 소비 지점** — 뷰포트 표시 줄 수로 반복 줄 수를 정확화한다.
            // 그 extent의 프로파일 명시값이 있으면 묻지 않고(우선순위상 AX가 어차피 진다),
            // 읽기 실패·pid 없음은 `nil`이라 현행 사다리(프로파일 → 상수 15/30) 그대로다.
            // 정확화가 줄 수만 바꾸고 `nil`을 새로 만들지 않으므로 paste처럼 프로브는 둘이다.
            let lines = CommandKeyMapper.scrollConsultsViewport(extent: extent, profile: profile)
                ? viewport.value() : nil
            #if DEBUG
            if let lines {
                Logger.eventTap.debug(
                    "스크롤 뷰포트 정확화: \(lines, privacy: .public)줄 — \(String(describing: action), privacy: .public)"
                )
            }
            #endif
            return Self.classify(
                CommandKeyMapper.keyStrokes(
                    for: action, family: family, profile: profile, viewportLines: lines)
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
            // **AX 실행 계획이 먼저다** — 접두가 화살표 조합이 아니게 되면서 keyboard가 우회
            // 장치로 덮던 자리들이 사라진다: 줄 끝 접두 생략(`pasteConsultsFocusedText`)과
            // linewise after의 꼬리 `Cmd-←` 멱등 보정자는 **폴백 경로 전담**으로 남는다.
            var axFocused: FocusedText?
            if Self.usesAXWrite(action, family: family, strategy: strategy, profile: profile) {
                // 읽기 실패는 `unproven`과 **다른 축**이다 (`.edit`·`.move`와 같은 규칙).
                guard let focused = axText.value() else { return .axUnavailable }
                axFocused = focused
                switch FocusedTextOffsets.pasteInsertion(before: before, wise: wise, in: focused) {
                case .at(let offset):
                    if let groups = CommandKeyMapper.pasteDelegatedGroups(
                        count: count, appendsLine: false, family: family, profile: profile) {
                        return .hybrid(
                            NSRange(location: offset, length: 0), groups, paced: true)
                    }
                case .appendingLine(let offset):
                    // 마지막 줄(뒤 개행 없음)의 linewise `p` — 문서 끝 캐럿 + `[Return, Cmd-V]`
                    // 원자 그룹이다. naive 문서 끝 캐럿은 병합 훼손이 실측됐고, 캐럿 쓰기만으로는
                    // 구분 개행을 만들 수 없다 (`20260808_last-line-linewise-paste-return-synthesis.md`).
                    // 위임분이 `nil`이면(단일행 필드 — `Return`이 submit) 아래 위임으로 낙하해
                    // 현행 동작(`P` 퇴행) 그대로다.
                    if let groups = CommandKeyMapper.pasteDelegatedGroups(
                        count: count, appendsLine: true, family: family, profile: profile) {
                        return .hybrid(
                            NSRange(location: offset, length: 0), groups, paced: true)
                    }
                case .unproven:
                    // 창이 답하지 못했다 → 아래 위임으로 낙하한다. 쓰기 시도 **전**이라 이중
                    // 실행이 원리적으로 불가하다 (`20260808_hybrid-prefix-failure-axes-clarified.md`).
                    break
                }
            }
            // **읽기의 세 번째 소비 지점** — charwise `p`만 줄 끝 증명을 위해 묻는다
            // (`P`·linewise는 왕복 0건 유지). 읽기 실패·pid 없음은 `nil`이라 현행 접두
            // 그대로다. 정확화가 접두를 비울 뿐 `nil`을 새로 만들지 않으므로 편집·Visual과
            // 달리 프로브는 그대로 둘이다. 위임 낙하는 **이미 읽은 AX 창을 그대로** 먹인다 —
            // 한 액션은 창을 한 번만 읽는다
            // (`20260808_ax-unproven-edit-delegation-reuses-ax-window.md`).
            let focused =
                axFocused
                ?? (CommandKeyMapper.pasteConsultsFocusedText(before: before, wise: wise)
                    ? text.value() : nil)
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

    /// Visual 액션의 **확정 부수효과** — 상태 적용·세션 경로 고정·세션 wise note가 한 몸이다.
    ///
    /// **호출 시점이 계약이다**: 위임(`.groups`)은 매핑 확정이 곧 게시 확정이라 그 자리에서,
    /// AX(`.ax`)는 쓰기 `.success`를 확인한 뒤에 부른다. 두 경로가 같은 함수를 지나야 한쪽만
    /// note를 빠뜨리거나 경로를 잘못 고정하는 일이 없다 (`EditKeyMapper.operatorStrokes`·
    /// `CommandKeyMapper`의 위임분 진입점과 같은 선례).
    ///
    /// Visual 아닌 액션(`.move` 등)은 `.unchanged`를 싣고 오며 아래 어느 분기도 타지 않는다.
    private func confirmVisual(
        _ action: VimAction, update: VisualAnchorUpdate, path: VisualAnchorTracker.Path
    ) {
        visualAnchor.apply(update)
        switch action {
        case .beginSelection(let linewise):
            // **경로는 진입에서만 정해진다** — 세션 도중 전환 금지가 pin의 존재 이유이고,
            // 폐기가 경로를 되돌리지 않는 것이 그 계약의 나머지 절반이다(`sessionPath` doc).
            visualAnchor.pin(path)
            pasteWise.noteSelectionWise(linewise ? .linewise : .charwise)
        case .switchSelectionWise(let linewise):
            // 확정된 전환의 wise만 세션 wise로 note한다 — 스킵된 전환은 화면 선택이 그대로라
            // 기억도 그대로여야 내용과 일치한다.
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
                "Visual 앵커 갱신 [\(String(describing: path), privacy: .public), \(String(describing: state.side), privacy: .public), pinned \(state.pinnedEnd, privacy: .public)]: \(String(describing: action), privacy: .public)"
            )
        case .discard:
            Logger.eventTap.debug(
                "Visual 앵커 폐기 (게시 경로): \(String(describing: action), privacy: .public)")
        case .unchanged:
            break
        }
        #endif
    }

    /// **AX로 고정된 Visual 세션의 매핑** — `nil`이면 이 세션은 keyboard이므로 호출자가 현행
    /// 재앵커 경로로 낙하한다.
    ///
    /// 진입만이 경로를 정한다: 증명되면 세션 전체가 AX이고, 못 하면 세션 전체가 keyboard다.
    /// 세션 중간에는 **위임으로 낙하하지 않는다** — AX가 써 넣은 범위 위에서는 앱이 어느 끝을
    /// 포커스로 보는지 미정의라 무상태 `Shift-→`가 앵커 반대쪽으로 자랄 수 있고, 뒤따르는 `d`가
    /// 엉뚱한 텍스트를 지운다(강등이 아니라 파괴 방향 동전 던지기)
    /// (`20260808_ax-visual-session-path-pinning.md`). 그래서 중간의 모든 실패는 스킵이다.
    ///
    /// `.clearSelection`이 여기 오지 않는 것도 결정이다 — collapse는 게시 `←` 유지다(동기 AX
    /// 쓰기가 `Cmd-C` 게시를 상시 이겨 빈 복사가 됨이 실측
    /// `20260808_ax-collapse-posted-arrow-not-caret-write.md`).
    private func axVisualMapping(
        for action: VimAction, family: ElementFamily, profile: ResolvedProfile,
        strategy: ProfileStrategy, text: FocusedTextSnapshot, axText: AXWindowSnapshot
    ) -> Mapping? {
        switch action {
        case .beginSelection(let linewise):
            guard Self.usesAXWrite(action, family: family, strategy: strategy, profile: profile),
                let processID = text.processID
            else { return nil }
            guard let focused = axText.value() else { return .axUnavailable }
            // 진입에는 Vim 무효가 없다 — `.unproven`만 오고, 그것이 곧 keyboard 세션 고정이다.
            guard
                case .range(let range, let anchor, let column) =
                    FocusedTextOffsets.visualEntrySelection(linewise: linewise, in: focused)
            else { return nil }
            // 진입 선택은 언제나 전진형이다(범위 시작 == 앵커). `V`의 원래 캐럿은 **정확값**이라
            // keyboard ⑦의 열 근사 없이 `V`→`v`가 선다.
            let state = VisualAnchorState(
                anchor: anchor, wise: linewise ? .linewise : .charwise, side: .left,
                pinnedEnd: anchor, processID: processID,
                originalCaret: linewise ? focused.selection.location : nil,
                focusLineDistance: nil, desiredColumn: column)
            return .ax(range, visual: .set(state))

        case .extendSelection(let motion):
            guard visualAnchor.sessionPath == .accessibility else { return nil }
            // 프로파일이 이름한 모션은 **정직한 스킵**이다 — 재정의 시퀀스도 무상태 시퀀스라
            // 위임 금지의 뿌리가 그대로 적용되고, 사용자 지시("이 앱에서 이 키를 쓰지 마라")를
            // 위반하지도 않는다 (`20260808_ax-visual-overridden-motion-honest-skip.md`).
            // disable은 기존 분류 그대로 집계한다.
            if profile.motionOverrides[motion] != nil {
                guard MotionKeyMapper.selectionStrokes(for: motion, profile: profile) != nil else {
                    return .disabledByProfile
                }
                return skippedAXVisual(action, "프로파일이 재정의한 모션")
            }
            return axVisualSession(
                action, family: family, profile: profile, strategy: strategy, text: text,
                axText: axText
            ) {
                state, focused in
                FocusedTextOffsets.visualExtendSelection(for: motion, anchor: state, in: focused)
            } state: { state, range, anchor, column in
                state.moved(to: range, anchor: anchor, column: column)
            }

        case .switchSelectionWise(let linewise):
            guard visualAnchor.sessionPath == .accessibility else { return nil }
            return axVisualSession(
                action, family: family, profile: profile, strategy: strategy, text: text,
                axText: axText
            ) {
                state, focused in
                FocusedTextOffsets.visualSwitchSelection(
                    toLinewise: linewise, anchor: state, in: focused)
            } state: { state, range, anchor, column in
                var next = state.moved(to: range, anchor: anchor, column: column)
                next.wise = linewise ? .linewise : .charwise
                // `v`→`V`는 charwise 앵커를 보관한다 — 그것이 `V`→`v` 복원의 유일한 원천이고,
                // AX는 그 값을 추정이 아니라 그대로 들고 있다(keyboard ⑥이 회수한 것과 갈린다).
                next.originalCaret = linewise ? state.anchor : nil
                return next
            }

        default:
            // `.clearSelection` — 위 doc.
            return nil
        }
    }

    /// AX 고정 세션의 공통 배선: 게이트 → 창 읽기 → 자가 검증 → 산출 → 상태.
    /// 실패는 전부 스킵이며(위임 금지), 요소·읽기 실패만 `.axUnavailable`(execute 잔여 접기)다.
    private func axVisualSession(
        _ action: VimAction, family: ElementFamily, profile: ResolvedProfile,
        strategy: ProfileStrategy, text: FocusedTextSnapshot, axText: AXWindowSnapshot,
        selection: (VisualAnchorState, FocusedText) -> FocusedTextOffsets.Selection,
        state next: (VisualAnchorState, NSRange, Int, Int?) -> VisualAnchorState
    ) -> Mapping {
        // 세션은 AX인데 전략·계열이 더 이상 AX가 아니다(포커스가 비텍스트로 옮겨간 자리 등) —
        // 쓸 수도 위임할 수도 없으므로 스킵이다.
        guard Self.usesAXWrite(action, family: family, strategy: strategy, profile: profile) else {
            return skippedAXVisual(action, "전략·계열이 더 이상 AX가 아니다")
        }
        guard let focused = axText.value() else { return .axUnavailable }
        // 자가 검증은 AX에서도 유지한다 — 세션 중 위임 액션(`p`·`u`)이 선택을 파괴할 수 있고,
        // 매 액션 어차피 읽으므로 비용이 0이다. 실패는 상태 폐기 + 스킵이며, **경로 pin은
        // 살아 있어** 이후 액션도 스킵이다(무상태 폴백 금지 — `sessionPath` doc).
        guard let state = visualAnchor.validated(against: focused, processID: text.processID)
        else {
            #if DEBUG
            Logger.eventTap.debug(
                "AX Visual 스킵 — 자가 검증 불일치(상태 폐기, 세션은 AX 유지): 읽은 선택 [\(focused.selection.location, privacy: .public), \(focused.selection.upperBound, privacy: .public))"
            )
            #endif
            return .skipped
        }
        switch selection(state, focused) {
        case .range(let range, let anchor, let column):
            return .ax(range, visual: .set(next(state, range, anchor, column)))
        case .invalid:
            return skippedAXVisual(action, "범위 무변화가 정확 동작이다")
        case .unproven:
            // Normal 경로와 갈리는 유일한 지점이다 — 거기서는 위임 낙하지만 AX 세션에서는
            // 무상태 시퀀스가 곧 파괴 위험이라 스킵이다.
            return skippedAXVisual(action, "창이 답하지 못했다 (세션이 AX라 위임 금지)")
        }
    }

    /// AX Visual 스킵 1건 — 사유를 아는 자리에서 자체 로그를 남긴다(`.skipped` 계약).
    /// 도그푸딩에서 이 빈도가 "세션이 죽은 채 남는가"의 판정 데이터다.
    private func skippedAXVisual(_ action: VimAction, _ reason: String) -> Mapping {
        #if DEBUG
        Logger.eventTap.debug(
            "AX Visual 스킵 — \(reason, privacy: .public): \(String(describing: action), privacy: .public)"
        )
        #endif
        return .skipped
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

    /// 이 액션을 AX 쓰기(캐럿·범위)로 실행하는가 — **위임 표의 단일 판정 지점**이다.
    ///
    /// 표가 코드에서 한 곳에 있어야 어휘가 늘어도 골격 규칙("명령 매퍼 계열 = 위임, 모션·편집·
    /// Visual 매퍼 계열 = AX")이 규칙으로 유지된다.
    ///
    /// 넷 중 하나라도 걸리면 현행 keyboard 경로 그대로다:
    /// ① 전략이 accessibility가 아니다 — **기본값 keyboard**라 미지정 앱은 동작 diff 0이다.
    /// ② 계열이 `.nonText`/`.unresolved` — **전 액션 keyboard 강등**이다. AX 대입은 텍스트 요소
    ///    전제라 Finder 리스트에서 무동작이 되고, 그러면 "모션·스크롤은 게시"라는 걸러내기
    ///    결정이 조용히 죽는다. `.unresolved`는 "모르는 동안은 보수적으로"의 연장이며 AX 쓰기는
    ///    더 위험한 방향이라 같은 규칙이 더 강하게 적용된다.
    /// ③ `j`/`k`는 위임 유지 — 오프셋 대입이 **희망 열(desired column)** 을 잃는다. 짧은 줄을
    ///    지나면 열이 영구히 깎여 현행보다 나쁜 회귀다.
    /// ④ 프로파일에 **그 액션이 이름한 모션** 항목이 있으면(strokes 재정의든 disable이든)
    ///    위임한다. 재정의는 "이 앱에서 이 모션을 달성하는 방법"이라는 사용자 지시라 AX가
    ///    덮어쓰지 않고, disable은 기존 경로가 `.disabledByProfile`로 정직하게 집계한다. 스크롤
    ///    사다리("프로파일 명시값 > AX 정확값 > 상수")와 같은 우선순위다.
    ///
    /// 편집에서 ④의 대상이 **범위가 이름한 모션까지**인 것이 계약이다 (`dw`의 `w`, `cw`의
    /// 리타깃 `e`, `dk`의 `k`). `dd`·`diw`가 내부적으로 쓰는 조합(`lineStart`·`wordBackward`
    /// 등)은 사용자가 그 액션에 대해 지시한 모션이 아니고, 여기서 보려면 `EditKeyMapper`의
    /// 시퀀스 조립표가 어댑터로 복사돼 두 곳이 갈라진다.
    ///
    /// **Visual에는 ④를 적용하지 않는다.** 재정의 시퀀스도 무상태 시퀀스라 AX로 고정된 세션에서
    /// 위임하면 무상태 폴백 금지의 뿌리를 정면으로 어긴다 — 답은 위임이 아니라 정직한 스킵이고,
    /// 그 판정은 세션 경로를 아는 `axVisualMapping`이 한다
    /// (`20260808_ax-visual-overridden-motion-honest-skip.md`). 여기서는 전략·계열만 본다.
    /// `.clearSelection`이 빠진 것도 결정이다 — collapse는 게시 `←` 유지다.
    ///
    /// `ElementFamily`에 exhaustive switch를 거는 것은 `survivesFilterGate`와 같은 규칙이다.
    /// `VimAction`에 걸지 않는 것은 매퍼와 같은 계약이다.
    private static func usesAXWrite(
        _ action: VimAction, family: ElementFamily, strategy: ProfileStrategy,
        profile: ResolvedProfile
    ) -> Bool {
        // **접힌 실효 전략**을 본다 — `profile.strategy`가 아니다. `.auto`는 콜백에서 이미
        // 판정과 함께 접혔고(`effectiveStrategy(_:verdict:)`), 프로파일에 남은 원본은 관측용
        // 라벨이다. 어느 쪽이든 `.accessibility`가 아니면 keyboard라 실패 방향이 안전하다.
        guard strategy == .accessibility else { return false }
        switch family {
        case .textArea, .textField: break
        case .nonText, .unresolved: return false
        }
        switch action {
        case .move(let motion):
            guard motion != .lineUp, motion != .lineDown else { return false }
            return profile.motionOverrides[motion] == nil
        case .edit(let op, let range):
            return namedMotions(of: range, for: op).allSatisfy {
                profile.motionOverrides[$0] == nil
            }
        case .beginSelection, .extendSelection, .switchSelectionWise:
            // ④는 위 doc대로 Visual 분기가 스킵으로 처리한다.
            return true
        case .openLine, .paste:
            // ④의 대상이 없다 — `o`의 줄 끝·`p`의 한 칸 오른쪽은 사용자가 그 액션에 대해
            // 지시한 모션이 아니라 **접두의 내부 분해**다(`dd`가 쓰는 `lineStart`와 같은 편).
            // 사용자가 지시할 수 있는 것은 `new_line`·`paste` 스트로크이고, 그 둘은 위임분에
            // 그대로 남아 매퍼를 지난다. `actions:` disable은 `mapping` 최상단이 이미 앞선다.
            return true
        default:
            return false
        }
    }

    /// 이 편집 범위가 **사용자 어휘로 이름하는** 모션 — ④ 가드의 판정 재료다.
    /// 빈 집합 = 이름한 모션이 없다(프로파일 모션 재정의와 무관하게 AX로 간다).
    /// `TextRange`에 exhaustive switch를 걸지 않는 것은 매퍼와 같은 계약이다.
    private static func namedMotions(
        of range: VimAction.TextRange, for op: VimAction.Operator
    ) -> [Motion] {
        switch range {
        case .motion(let motion, _):
            // `cw`는 `ce`로 리타깃되므로 실제로 겨냥하는 모션이 둘이다 — 판정도 둘을 본다
            // (`EditKeyMapper.retargeted`와 같은 조건).
            guard op == .change, motion == .wordForward else { return [motion] }
            return [motion, .wordEndForward]
        case .linewiseMotion(let motion, _):
            return [motion]
        default:
            // `.line`(`dd`)·`iw`·`.selection` — 이름한 모션이 없다.
            return []
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

    /// 이 액션이 합성하는 ANSI 문자 명령 키의 문자 — 비-QWERTY 게이트의 판정 재료다.
    /// 빈 집합 = 문자 명령 키를 합성하지 않는다(레이아웃 무관 통과). `.edit`은 오퍼레이터
    /// 스트로크(yank = `Cmd-C`, delete·change = `Cmd-X`), `.paste`는 `Cmd-V`,
    /// `.undo`/`.redo`는 `Cmd-Z`(redo는 같은 z에 Shift)다. `VimAction`에 exhaustive
    /// switch를 걸지 않는 것은 매퍼와 같은 계약이다.
    private static func requiredCommandCharacters(_ action: VimAction) -> Set<Character> {
        switch action {
        case .edit(let op, _):
            return op == .yank ? ["c"] : ["x"]
        case .paste:
            return ["v"]
        case .undo, .redo:
            return ["z"]
        default:
            return []
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

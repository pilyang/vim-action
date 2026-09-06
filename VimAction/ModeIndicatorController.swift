//
//  ModeIndicatorController.swift
//  VimAction
//

import AppKit
import Foundation
import Observation
import VimEngine

/// 모드·사다리·기하를 잇는 조율자 — 화면에 떠 있는 것의 단일 소유자.
///
/// 겹은 둘이다. **순간 표시(flash)** 는 모드가 바뀔 때마다 ~1초 떴다 사라지고, **상시 배지**는
/// 비-Insert 모드 동안 계속 붙어 있는다 (`20260906_mode-indicator-hybrid-display-policy.md`).
/// 갱신은 **이벤트 기반만**이다 — 타이머 폴링도, 키마다 재배치도 없다
/// (`20260906_mode-indicator-anchor-ladder-event-driven.md` 결정 3). 트리거는 다섯이고 전부
/// 아래 `reconcile` 하나로 모인다: 모드 전환 / 앵커 이벤트(포커스·앱 활성화·창 이동·리사이즈·
/// 디스플레이 재구성) / 사다리 변화 / 설정 토글.
@MainActor
@Observable
final class ModeIndicatorController {
    /// 기하 읽기 전용 직렬 큐. **리졸버의 `readQueue`를 재사용하지 않는 것이 계약이다** —
    /// 콜드 앱에서 이 읽기는 요소·position·size·창까지 AX 호출 여섯 번(최악 50ms×6)이 될 수
    /// 있는데, 리졸버 큐는 **키 디스패치가 의존하는 포커스 계열 캐시**를 먹인다. 표시용 읽기가
    /// 그 캐시를 지연시키면 앱 전환 직후 `.unresolved` 창이 넓어져 첫 편집이 조용히 떨어진다.
    /// QoS를 `.utility`로 낮춘 것도 같은 이유다(리졸버는 `.userInitiated`). ~600ms 프로브
    /// 때문에 큐를 따로 두는 `AXTrustProber`와 같은 근거·같은 형태다.
    private nonisolated static let geometryQueue = DispatchQueue(
        label: "dev.pilyang.VimAction.mode-indicator-geometry", qos: .utility)

    /// 트리거가 함께 밀어 넣는 상태 한 묶음. 컨트롤러가 사다리를 스스로 조회하지 않는 것이
    /// 규칙이다 — 사다리는 `AppState`가 소유하고(`menuBarIndicator`), 여기는 받은 값으로만
    /// 판정해야 순수 함수 하나로 표 테스트가 된다.
    nonisolated struct Inputs: Equatable {
        var mode: Mode
        var indicator: MenuBarIndicator
        var processID: pid_t?

        init(mode: Mode, indicator: MenuBarIndicator, processID: pid_t?) {
            self.mode = mode
            self.indicator = indicator
            self.processID = processID
        }
    }

    /// 지금 화면에 있어야 할 것. `nil`(= `presentation`이 답하지 않음)이면 아무것도 표시하지
    /// 않는다.
    nonisolated struct Presentation: Equatable {
        var label: String
        /// Insert만 `false`다 — flash는 뜨되 배지는 남지 않는다. 상시 배지가 "지금 위험한
        /// 모드다"를 뜻하려면 기본 상태(Insert)에는 없어야 한다.
        var showsBadge: Bool
        var processID: pid_t
    }

    /// 표시 판정 — **이 기능의 순수 계층이다.** AX도 AppKit도 부르지 않아 표로 검증된다.
    ///
    /// 표시 조건은 메뉴바 사다리를 그대로 재사용한다 — `.mode`가 아니면(탭 고장·마스터 off·
    /// 앱별 disabled·Secure Input) 아무것도 띄우지 않는다. 가로채지 않는 상태에서 모드 라벨을
    /// 띄우면 메뉴바에서 없앤 "가로채지 않는데 Normal이라고 말하는" 거짓말을 화면 한가운데서
    /// 되풀이하게 된다 (`20260906_mode-indicator-hybrid-display-policy.md` 결정 3).
    nonisolated static func presentation(isEnabled: Bool, inputs: Inputs) -> Presentation? {
        guard isEnabled, case .mode = inputs.indicator, let processID = inputs.processID else {
            return nil
        }
        return Presentation(
            label: inputs.mode.overlayLabel,
            showsBadge: inputs.mode.showsPersistentBadge,
            processID: processID)
    }

    /// 새 기하 읽기를 띄워야 하는가 — **순수 함수라 표로 검증한다.** 판정이 틀리면 증상이
    /// 조용하다: 모자라면 배지가 낡은 자리에 남고, 넘치면 전환마다 AX 왕복이 곱해진다.
    ///
    /// **같은 상태를 같은 토큰으로 이미 읽고 있으면 그 읽기가 그대로 답이다.** 이 가지가
    /// 없으면 모드 전환마다 읽기가 두 번 난다: 사다리 관찰 루프의 재무장이 `mode`의 willSet에서
    /// 예약돼 전환 읽기가 착지하기 전에 뒤따라 오는데, 그때 `pendingFlash`가 아직 서 있어
    /// 판정이 참이 된다. 그러면 토큰이 올라가 방금 띄운 읽기가 폐기되고, 콜드 앱에서 flash가
    /// 왕복 하나만큼(최악 50ms×N) 늦게 뜬다.
    nonisolated static func needsGeometryRead(
        desired: Presentation, current: Presentation?, inFlight: InFlight?, token: Int,
        pendingFlash: Bool, rereadGeometry: Bool
    ) -> Bool {
        if !rereadGeometry, let inFlight, inFlight.request == desired, inFlight.token == token {
            return false
        }
        // 밀린 flash는 그릴 프레임이 있어야 하고, 배지는 기하가 상했거나 상태가 달라졌을 때만
        // 다시 읽는다 — Insert에서 앵커 이벤트가 AX 왕복 0건인 것이 이 두 번째 항이다.
        return pendingFlash || (desired.showsBadge && (rereadGeometry || desired != current))
    }

    /// 온스크린 인디케이터 on/off. **런타임 SSOT는 이 프로퍼티**이고 didSet이 저장을
    /// 책임진다 — 실행 중 외부 `defaults write`는 재시작까지 무시된다 (탈출 옵션과 같은
    /// 소유 모델). 유일하게 `@ObservationIgnored`가 아닌 저장 프로퍼티다: Settings 토글이
    /// 여기 바인딩된다.
    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            defaults.set(isEnabled, forKey: PreferenceKeys.onScreenModeIndicatorEnabled)
            // 마지막으로 받은 상태에서 다시 판정한다 — off면 즉시 사라지고, on이면 지금
            // Normal·Visual인 경우 배지가 바로 뜬다. 자기 상태 변경을 관찰 그래프로
            // 우회시킬 이유가 없다.
            reconcile(flashes: false, rereadGeometry: false)
        }
    }

    @ObservationIgnored private nonisolated(unsafe) let defaults: UserDefaults

    /// 아직 화면에 반영되지 않은 최신 요청. 읽는 도중 새 트리거가 오면 여기만 덮어써
    /// **최신 상태 하나로 접힌다**.
    @ObservationIgnored private var pending: Presentation?
    /// **flash 요청은 `pending`과 따로 산다.** 같이 담아 두면 읽는 사이에 들어온 앵커·사다리
    /// 이벤트가 `pending`을 덮어써 정당한 flash가 통째로 사라진다 — Cmd-Tab(앱 활성화) 직후
    /// Esc는 흔한 조합이라 실제로 난다. `finish`가 실제로 그렸을 때와 표시가 통째로 막혔을
    /// 때만 내려간다.
    @ObservationIgnored private var pendingFlash = false
    /// 진행 중인 읽기 — 요청과 그것을 띄운 시점의 토큰. **토큰까지 들고 있는 것이 계약이다**:
    /// 요청만 보면 "사다리를 벗어났다 돌아오는" 사이에 폐기가 예약된 읽기를 아직 쓸 수 있는
    /// 것으로 오인해 아무것도 그리지 않는다.
    nonisolated struct InFlight: Equatable {
        var request: Presentation
        var token: Int
    }

    /// 마지막으로 트리거가 밀어 넣은 상태. 토글 didSet이 여기서 다시 판정한다.
    @ObservationIgnored private var lastInputs: Inputs?
    /// 지금 그리기로 되어 있는 것. **직전 이벤트가 아니라 이 값과만 비교한다** — 사다리
    /// 관찰 루프는 레벨 트리거(중간 전이가 유실되고 현재 값으로 수렴)라 엣지 비교가 성립하지
    /// 않는다.
    @ObservationIgnored private var current: Presentation?
    @ObservationIgnored private var inFlight: InFlight?
    /// 늦게 착지한 읽기를 버리기 위한 토큰 — 표시 상태를 바꾸는 **모든** 트리거가 올린다.
    /// 사다리를 벗어날 때 `pending`을 비우는 것만으로는 부족하다: 이미 떠 있는 읽기가 착지해
    /// "가로채지 않는데 NORMAL이라고 말하는" 라벨을 띄운다
    /// (`FocusedElementResolver.refreshToken`과 같은 장치·같은 이유).
    @ObservationIgnored private var token = 0

    /// 패널은 첫 표시에서야 만든다 — 런치 시 `NSPanel`을 만들지 않고, 표시할 일이 없는
    /// 실행(권한 미허용, 계속 Insert, 토글 off)에서는 끝까지 만들어지지 않는다.
    @ObservationIgnored private var flashPanel: ModeIndicatorPanel?
    @ObservationIgnored private var badgePanel: ModeIndicatorPanel?

    /// `defaults` 주입은 테스트용이다 — `.standard`를 쓰면 TEST_HOST가 앱 프로세스라
    /// 실기기에서 영속된 값이 새어 들어온다 (`EventTapController`와 같은 이유).
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(
            forKey: PreferenceKeys.onScreenModeIndicatorEnabled,
            default: PreferenceKeys.onScreenModeIndicatorEnabledDefault)
    }

    // MARK: - 트리거

    /// 모드가 바뀌었다. **탭 콜백의 동기 구간에서 불린다** — 여기서 하는 일은 판정(순수) +
    /// 요청 대입 + 큐 적재 1회뿐이고, AX 읽기와 `NSScreen` 조회는 전부 뒤로 밀린다
    /// (콜백 경량 불변식, `20260725_callback-light-invariant.md`).
    func modeDidChange(_ inputs: Inputs) {
        lastInputs = inputs
        reconcile(flashes: true, rereadGeometry: true)
    }

    /// 앵커가 움직였을 수 있다 — 포커스 요소 변경·앱 활성화·창 이동·리사이즈·디스플레이
    /// 재구성. 모드는 그대로이므로 flash는 없고, 배지가 떠 있어야 할 때만 다시 읽는다
    /// (Insert에서는 앵커 이벤트가 AX 왕복 0건이다).
    func anchorDidChange(_ inputs: Inputs) {
        lastInputs = inputs
        reconcile(flashes: false, rereadGeometry: true)
    }

    /// 사다리가 바뀌었을 수 있다 — 탭 고장·마스터 off·킬스위치·앱별 disabled·Secure Input·
    /// 설정 리로드. 기하는 그대로이므로 **표시할 것이 실제로 달라졌을 때만** 읽는다.
    func stateDidChange(_ inputs: Inputs) {
        lastInputs = inputs
        reconcile(flashes: false, rereadGeometry: false)
    }

    // MARK: - 조율

    /// 다섯 트리거의 유일한 합류점. 멱등하다 — 같은 입력으로 몇 번을 불러도 화면도 읽기도
    /// 늘지 않는다.
    private func reconcile(flashes: Bool, rereadGeometry: Bool) {
        guard let inputs = lastInputs,
            let desired = Self.presentation(isEnabled: isEnabled, inputs: inputs)
        else {
            // 표시가 통째로 막힌 모든 사유(사다리 이탈·토글 off·pid 없음·아직 아무 입력도
            // 받지 않음)가 이 한 자리로 모인다. 페이드 없이 즉시 감춘다.
            token &+= 1
            pending = nil
            pendingFlash = false
            current = nil
            flashPanel?.hide()
            badgePanel?.hide()
            return
        }
        // 우리 자신이 최전면이 되면(메뉴바 아이콘 클릭·설정 창) 리졸버가 우리 pid에 붙는데,
        // 사다리는 비자신 캐시 축이라 여전히 `.mode`다 — 그대로 두면 배지가 **우리 설정 창
        // 위로** 옮겨 붙는다. 감추지는 않는다: 메뉴를 열 때마다 배지가 깜빡이면 그게 더 나쁘다.
        guard desired.processID != Self.ownProcessID else {
            // 읽지도 `current`를 건드리지도 않지만 **거짓말은 지운다**: 우리가 최전면인 동안
            // Insert로 바뀌면(우리 창에서 Esc·i) 이전 앱 요소에 남은 "NORMAL" 배지가 다음
            // 앵커 이벤트까지 사실이 아닌 채로 붙어 있다.
            if !desired.showsBadge { badgePanel?.hide() }
            return
        }
        if flashes { pendingFlash = true }
        let needsRead = Self.needsGeometryRead(
            desired: desired, current: current, inFlight: inFlight, token: token,
            pendingFlash: pendingFlash, rereadGeometry: rereadGeometry)
        // **판정보다 뒤여야 한다**: 앞으로 옮기면 `desired != current`가 영원히 거짓이라
        // 상태가 달라져도 다시 읽지 않는다.
        current = desired
        if !desired.showsBadge { badgePanel?.hide() }
        guard needsRead else {
            // 아무것도 달라지지 않았다 — **토큰을 올리지 않는다.** 올리면 진행 중인 읽기가
            // 폐기돼 방금 요청한 flash가 화면에 닿지 못한다.
            return
        }
        token &+= 1
        pending = desired
        pump()
    }

    /// 읽기는 **한 번에 하나만** 띄운다. 버스트 중 요청이 쌓이면 큐가 아니라 `pending` 한 칸이
    /// 최신 것만 들고 있다가 이번 읽기가 끝난 뒤 이어 돈다 — 창 드래그처럼 알림이 연달아
    /// 오는 경로에서 AX 왕복이 이벤트 수만큼 곱해지지 않는다.
    private func pump() {
        guard inFlight == nil, let request = pending else { return }
        pending = nil
        let token = self.token
        inFlight = InFlight(request: request, token: token)
        Self.geometryQueue.async { [weak self] in
            let anchors = ModeIndicatorGeometryReader.read(processID: request.processID)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finish(request, token: token, anchors: anchors)
                }
            }
        }
    }

    private func finish(
        _ request: Presentation, token: Int, anchors: ModeIndicatorLayout.Anchors
    ) {
        inFlight = nil
        // 읽는 사이에 상태가 또 바뀌었다 — 이 결과는 이미 낡았다. 그리지 않고 바로 다음
        // 읽기로 넘어가야 낡은 라벨이 한 프레임 스치지 않는다. 표시가 막힌 전환이었다면
        // `pending`이 비어 있어 `pump()`가 no-op이고, 화면은 그쪽이 이미 감췄다.
        guard token == self.token else {
            pump()
            return
        }
        // `NSScreen`은 메인에서만 읽는다 — 순수 계층은 그 결과를 값으로 받는다.
        let screens = NSScreen.screens
        guard let primary = screens.first else { return }
        let layoutScreens = screens.map {
            ModeIndicatorLayout.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        // 읽기 한 번의 앵커로 두 프레임을 만든다 — 크기만 다르고 사다리·배치·클램프는 같다.
        func frame(for style: ModeIndicatorStyle) -> NSRect? {
            ModeIndicatorLayout.panelFrame(
                anchors: anchors,
                size: ModeIndicatorPanel.size(for: request.label, style: style),
                screens: layoutScreens, primaryScreenMaxY: primary.frame.maxY)
        }
        guard let badgeFrame = frame(for: .badge), let flashFrame = frame(for: .flash) else {
            // 사다리의 마지막 단 — 붙일 곳이 없으면 표시하지 않는다. **재시도는 없다**:
            // 앵커가 없다는 것이 답이고, 다음 앵커 이벤트가 이 경로를 다시 부른다.
            //
            // 여기서 flash 요청을 **버리는 것**이 계약이다. 들고 있으면 그 요청이 다음 앵커
            // 이벤트(창 이동 등)에 얹혀 살아나, 한참 전에 끝난 전환의 라벨이 엉뚱한 때 번쩍인다.
            // 순간 표시는 그 순간에 매인 알림이라 놓쳤으면 만료되는 것이 맞다.
            pendingFlash = false
            flashPanel?.hide()
            badgePanel?.hide()
            return
        }
        if pendingFlash {
            pendingFlash = false
            let panel = flashPanel ?? ModeIndicatorPanel(style: .flash)
            flashPanel = panel
            panel.flash(request.label, at: flashFrame)
        }
        if request.showsBadge {
            let panel = badgePanel ?? ModeIndicatorPanel(style: .badge)
            badgePanel = panel
            panel.show(request.label, at: badgeFrame)
        } else {
            badgePanel?.hide()
        }
    }

    /// VimAction 자신의 pid — 앵커로 삼지 않기 위한 비교값이다.
    private nonisolated static let ownProcessID = ProcessInfo.processInfo.processIdentifier
}

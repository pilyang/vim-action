//
//  AppState.swift
//  VimAction
//

import AppKit
import Foundation
import Observation
import os
import VimEngine

/// 앱 셸이 관찰하는 UI 상태와 전역 컴포넌트(권한 모니터, 이벤트 탭)의 소유자.
@Observable
final class AppState {
    let permissionMonitor = AccessibilityPermissionMonitor()
    let eventTap = EventTapController()

    /// 앱 시작 시 1회: 권한 확인 → 탭 설치 시도, 미허용이면 부여 감지 폴링 시작.
    func bootstrap() {
        // TEST_HOST로 launch된 단위 테스트 실행 중에는 시동하지 않는다 —
        // 테스트가 라이브 이벤트 탭을 설치하거나 권한 폴링을 돌리면 안 된다.
        if isRunningUnderXCTest() {
            // 이 변수가 일반 launch에 새어 들어오면 앱이 통째로 비활성이 되므로 흔적을 남긴다.
            Logger.eventTap.notice("XCTest 환경변수 감지 — bootstrap 생략 (탭 설치·권한 폴링 비활성)")
            return
        }
        permissionMonitor.onGranted = { [eventTap] in
            eventTap.startIfPermitted()
        }
        permissionMonitor.refresh()
        // 미허용이어도 항상 호출한다 — "설치 보류" 로그가 launch 시 관측 가능해야 한다.
        eventTap.startIfPermitted()
        if !permissionMonitor.isTrusted {
            permissionMonitor.startPollingUntilGranted()
        }
    }

    /// 메뉴바 글리프 — 탭이 안 돌면 비활성(square.dashed), 토글 off면 square.slash,
    /// Secure Input 억제 중이면 lock.square, 그 외 모드 글리프 (PRD §7.7 최소 구현).
    /// 우선순위: 탭 고장 > 토글 off > Secure Input — 고장이면 토글과 무관하게 가로채기
    /// 불가능하고, 사용자가 끈 상태(off)는 OS의 일시 억제 표시보다 우선한다.
    var menuBarGlyph: String {
        switch eventTap.status {
        case .running, .secureInput:
            guard eventTap.isInterceptionEnabled else { return "square.slash" }
            return eventTap.status == .secureInput ? "lock.square" : eventTap.mode.menuBarGlyph
        default:
            return "square.dashed"
        }
    }

    /// Visual-line일 때만 참 — 메뉴바 라벨이 커스텀 "Vl" 글리프로 wise를
    /// 구분한다 (fill 축은 "차단 여부"라 wise에 재사용할 수 없음). 모드 글리프가
    /// 실제로 표시되는 조건에서만 참이 되도록 `menuBarGlyph`와 같은 우선순위를 따른다.
    var menuBarShowsVisualLineGlyph: Bool {
        eventTap.status == .running && eventTap.isInterceptionEnabled
            && eventTap.mode == .visualLine
    }

    /// 메뉴바 라벨이 그리는 최종 글리프 이미지. 모든 상태 글리프를 같은 심볼
    /// 설정으로 렌더해 크기를 통일한다 — SF Symbol은 SwiftUI 폰트 유래 크기,
    /// 커스텀 "Vl"은 고정 크기로 렌더 경로가 갈리면 크기가 어긋난다.
    var menuBarImage: NSImage {
        menuBarShowsVisualLineGlyph
            ? .visualLineMenuBarGlyph
            : .menuBarSymbol(named: menuBarGlyph)
    }

    /// VoiceOver 등 사람이 읽는 메뉴바 상태 문구.
    var menuBarAccessibilityLabel: String {
        switch eventTap.status {
        case .running, .secureInput:
            guard eventTap.isInterceptionEnabled else { return "VimAction — disabled" }
            return eventTap.status == .secureInput
                ? "VimAction — paused for secure input"
                : "VimAction — \(eventTap.mode.displayName) mode"
        default:
            return "VimAction — inactive"
        }
    }
}

extension Mode {
    /// 메뉴바 아이템에 표시할 SF Symbol 이름. macOS 표현은 앱 레이어에만 둔다
    /// (엔진 `Mode`는 플랫폼을 모른다). fill은 "키 차단 여부" 축이다 — 차단
    /// 모드(Normal/Visual)는 fill, 통과 모드(Insert)는 미채움. Visual-line은
    /// 커스텀 "Vl" 템플릿 글리프(`NSImage.visualLineMenuBarGlyph`)가 대신 표시되며
    /// 여기 값은 폴백이다 (`AppState.menuBarShowsVisualLineGlyph`).
    var menuBarGlyph: String {
        switch self {
        case .normal: "n.square.fill"
        case .insert: "i.square"
        case .visualChar, .visualLine: "v.square.fill"
        }
    }

    /// 접근성 레이블 등 사람이 읽는 모드 이름.
    var displayName: String {
        switch self {
        case .normal: "Normal"
        case .insert: "Insert"
        case .visualChar: "Visual"
        case .visualLine: "Visual Line"
        }
    }
}

extension NSImage {
    /// 메뉴바 글리프 공통 심볼 설정 — 모든 상태 글리프가 같은 크기로 렌더되도록
    /// 한 곳에서 고정한다.
    private static let menuBarSymbolConfiguration = NSImage.SymbolConfiguration(
        pointSize: 15, weight: .regular
    )

    /// SF Symbol을 메뉴바 공통 설정으로 렌더한다. 이름은 이 파일의 상수에서만
    /// 오므로 항상 유효하다.
    static func menuBarSymbol(named name: String) -> NSImage {
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        return symbol.withSymbolConfiguration(menuBarSymbolConfiguration) ?? symbol
    }

    /// Visual-line 전용 메뉴바 글리프 — SF Symbols의 글자 사각형은 1글자뿐이라
    /// (vl.square 부재) "Vl"을 채운 사각형에서 뚫어낸 커스텀 템플릿 이미지를 그린다.
    /// 실제 `square.fill` 심볼(공통 설정)을 바탕으로 그려 다른 모드 글리프와
    /// 크기·모서리·비율이 일치하며, isTemplate이라 라이트/다크 외양은 시스템이 입힌다.
    static let visualLineMenuBarGlyph: NSImage = {
        let base = menuBarSymbol(named: "square.fill")
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            // 0.62·-0.4는 SF 글자 심볼의 컷아웃 메트릭에 맞춘 값 — v.square.fill의
            // 글자 bbox(높이 7.5pt, y 4.5)와 픽셀 스캔으로 일치를 확인했다.
            let text = NSAttributedString(
                string: "Vl",
                attributes: [
                    .font: NSFont.systemFont(ofSize: rect.height * 0.62, weight: .bold),
                    .foregroundColor: NSColor.black,
                ]
            )
            let textSize = text.size()
            NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
            text.draw(
                at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2 - 0.4)
            )
            return true
        }
        image.isTemplate = true
        return image
    }()
}

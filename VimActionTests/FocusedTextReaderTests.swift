//
//  FocusedTextReaderTests.swift
//  VimActionTests
//

import Foundation
import Testing

@testable import VimAction

/// 임의의 읽기 결과 — 값 자체는 아무 의미가 없다. 이 파일이 고정하는 것은 **언제·몇 번·어디서**
/// 읽는가이지 무엇을 읽는가가 아니다 (실제 AX 값의 검증은 실기기 몫).
private let sampleText = FocusedText(
    selection: NSRange(location: 10, length: 0), characterCount: 100,
    window: "hello", windowRange: NSRange(location: 0, length: 5))

/// 리더를 호출한 pid를 기록하는 가짜 — 실기기 AX 없이 seam을 관측한다.
private func recordingReader(
    returning value: FocusedText? = sampleText,
    onRead: @escaping @Sendable (pid_t) -> Void
) -> FocusedTextReader {
    FocusedTextReader { processID in
        onRead(processID)
        return value
    }
}

/// 액션별 lazy 스냅샷의 계약 — **읽기 시점·횟수·컨텍스트**가 전부다.
///
/// 이 세 축이 결정 문서가 형태를 고른 이유 그 자체다: 시점(lazy)은 버스트 안에서 캐럿이
/// 움직이기 때문이고, 횟수(액션당 1회)는 Notion `selectedRange`가 웜에서도 7~16ms이기
/// 때문이며, 컨텍스트(게시 큐)는 콜백·메인 AX 무접촉 불변식 때문이다.
struct FocusedTextSnapshotTests {
    @Test("만들기만 해서는 읽지 않는다 — lazy")
    func constructionDoesNotRead() {
        nonisolated(unsafe) var reads = 0
        let snapshot = FocusedTextSnapshot(
            processID: 42, reader: recordingReader { _ in reads += 1 })

        withExtendedLifetime(snapshot) {}

        #expect(reads == 0)
    }

    @Test("첫 물음에 주어진 pid로 정확히 1회 읽는다")
    func firstQueryReadsOnceWithGivenProcessID() {
        nonisolated(unsafe) var seen: [pid_t] = []
        let snapshot = FocusedTextSnapshot(
            processID: 42, reader: recordingReader { seen.append($0) })

        #expect(snapshot.value() == sampleText)
        #expect(seen == [42])
    }

    /// 액션 1건 안에서 여러 소비자(모션 정확화 + 경계 포화 판정 등)가 물어도 AX 왕복은
    /// 하나여야 한다 — Notion에서 왕복 1회가 7ms다.
    @Test("두 번째 물음은 기억된 값을 낸다 — 액션당 읽기 1회")
    func repeatedQueriesReuseTheFirstRead() {
        nonisolated(unsafe) var reads = 0
        let snapshot = FocusedTextSnapshot(
            processID: 42, reader: recordingReader { _ in reads += 1 })

        #expect(snapshot.value() == sampleText)
        #expect(snapshot.value() == sampleText)
        #expect(snapshot.value() == sampleText)
        #expect(reads == 1)
    }

    /// **실패도 기억한다**는 것이 요점이다. 기억하지 않으면 타임아웃(캡 50ms)이 나는 앱에서
    /// 한 액션이 물음 수만큼 50ms를 곱해 문다.
    @Test("읽기 실패는 nil이고 그 실패도 기억된다")
    func failedReadIsMemoizedAsNil() {
        nonisolated(unsafe) var reads = 0
        let snapshot = FocusedTextSnapshot(
            processID: 42,
            reader: recordingReader(returning: nil) { _ in reads += 1 })

        #expect(snapshot.value() == nil)
        #expect(snapshot.value() == nil)
        #expect(reads == 1, "실패를 기억하지 않으면 물을 때마다 AX 왕복이 되풀이된다")
    }

    /// pid가 없으면 읽을 대상이 없다 — 읽기 실패와 **같은 `nil`**이다. 소비자의 폴백이
    /// 하나뿐이라 구분할 이유가 없다.
    @Test("pid가 없으면 리더를 아예 부르지 않는다")
    func missingProcessIDSkipsTheReader() {
        nonisolated(unsafe) var reads = 0
        let snapshot = FocusedTextSnapshot(
            processID: nil, reader: recordingReader { _ in reads += 1 })

        #expect(snapshot.value() == nil)
        #expect(reads == 0)
    }

    /// **콜백·메인 AX 무접촉 불변식의 코드 측 보증**: 읽기는 물은 컨텍스트에서 그대로
    /// 동기 실행되고 어디로도 홉하지 않는다. 홉이 생기는 순간 "AX는 게시 큐에서만"이
    /// 조용히 깨지므로 계약으로 고정한다.
    ///
    /// `sync`가 아니라 `async`+세마포어인 것은 `sync`가 호출 스레드(여기서는 메인)에서
    /// 블록을 실행할 수 있어 "메인이 아니다"를 확인할 수 없기 때문이다.
    @Test("리더는 물은 큐 위에서 동기로 실행된다 — 홉 없음")
    func readerRunsSynchronouslyOnTheCallingQueue() {
        let key = DispatchSpecificKey<String>()
        let queue = DispatchQueue(label: "dev.pilyang.VimActionTests.posting")
        queue.setSpecific(key: key, value: "posting")

        nonisolated(unsafe) var observedQueue: String?
        nonisolated(unsafe) var observedMainThread = true
        let snapshot = FocusedTextSnapshot(
            processID: 42,
            reader: FocusedTextReader { _ in
                observedQueue = DispatchQueue.getSpecific(key: key)
                observedMainThread = Thread.isMainThread
                return sampleText
            })

        let finished = DispatchSemaphore(value: 0)
        queue.async {
            _ = snapshot.value()
            finished.signal()
        }
        #expect(finished.wait(timeout: .now() + 5) == .success)

        #expect(observedQueue == "posting", "리더가 물은 큐를 벗어났다")
        #expect(observedMainThread == false, "AX는 메인 스레드에 들어오지 않는다")
    }
}

/// 창 계산은 순수 함수라 표로 검증한다 — 문서 경계 clamp가 PR-B의 경계 포화 판정이 딛는
/// 바닥이다. AX 호출 자체(속성 조회·파라미터화 속성)는 실기기 몫이고, 여기서 고정하는 것은
/// "무엇을 요청하는가"다.
struct FocusedTextWindowTests {
    @Test("캐럿 양옆 반경만큼 잡되 문서 경계에서 잘린다")
    func windowIsClampedToDocumentBounds() {
        let radius = FocusedTextReader.windowRadius

        // 문서 한가운데 — 양쪽 다 반경 그대로.
        #expect(
            FocusedTextReader.window(
                around: NSRange(location: 1_000, length: 0), characterCount: 5_000)
                == NSRange(location: 1_000 - radius, length: radius * 2))

        // 문서 시작 — 왼쪽이 0에서 잘린다.
        #expect(
            FocusedTextReader.window(around: NSRange(location: 0, length: 0), characterCount: 5_000)
                == NSRange(location: 0, length: radius))

        // 문서 끝 — 오른쪽이 문서 길이에서 잘린다 (마지막 줄 `dgg`·마지막 단어 `dw` 판정).
        #expect(
            FocusedTextReader.window(
                around: NSRange(location: 5_000, length: 0), characterCount: 5_000)
                == NSRange(location: 5_000 - radius, length: radius))

        // 문서가 반경보다 짧으면 통째로.
        #expect(
            FocusedTextReader.window(around: NSRange(location: 3, length: 0), characterCount: 10)
                == NSRange(location: 0, length: 10))
    }

    /// 선택은 점이 아니라 범위다 — 반경은 **선택 양 끝** 바깥으로 잡아야 Visual 앵커 쪽
    /// 텍스트도 창 안에 들어온다.
    @Test("선택 범위는 양 끝 바깥으로 반경을 잡는다")
    func windowSurroundsTheWholeSelection() {
        let radius = FocusedTextReader.windowRadius

        #expect(
            FocusedTextReader.window(
                around: NSRange(location: 1_000, length: 50), characterCount: 5_000)
                == NSRange(location: 1_000 - radius, length: 50 + radius * 2))
    }

    /// 빈 문서는 빈 창이며 **실패가 아니다** — 빈 검색창처럼 정상적인 상태다.
    @Test("빈 문서는 길이 0인 창")
    func emptyDocumentYieldsEmptyWindow() {
        #expect(
            FocusedTextReader.window(around: NSRange(location: 0, length: 0), characterCount: 0)
                == NSRange(location: 0, length: 0))
    }

    /// 문서와 아귀가 맞지 않는 보고는 읽기 실패와 같은 편이다 — 에러코드로 갈리지 않는
    /// 계약을 여기서도 지킨다.
    @Test("말이 안 되는 범위는 nil")
    func nonsensicalRangesFail() {
        #expect(
            FocusedTextReader.window(around: NSRange(location: -1, length: 0), characterCount: 10)
                == nil)
        #expect(
            FocusedTextReader.window(around: NSRange(location: 5, length: 0), characterCount: -1)
                == nil)
    }
}

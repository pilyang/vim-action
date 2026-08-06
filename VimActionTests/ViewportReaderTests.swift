//
//  ViewportReaderTests.swift
//  VimActionTests
//

import Foundation
import Testing

@testable import VimAction

/// 리더를 호출한 pid를 기록하는 가짜 — 실기기 AX 없이 seam을 관측한다
/// (`FocusedTextReaderTests`의 `recordingReader`와 같은 형태).
private func recordingReader(
    returning value: Int? = 40,
    onRead: @escaping @Sendable (pid_t) -> Void
) -> ViewportReader {
    ViewportReader { processID in
        onRead(processID)
        return value
    }
}

/// execute당 lazy 스냅샷의 계약 — `FocusedTextSnapshotTests`의 미러다. **수명만 다르다**
/// (액션당이 아니라 execute당 1회 — 뷰포트 높이는 버스트 중 불변): 그 차이는
/// `KeyboardAdapterViewportTests`가 고정하고, 여기는 스냅샷 자체의 시점·횟수·컨텍스트다.
struct ViewportSnapshotTests {
    @Test("만들기만 해서는 읽지 않는다 — lazy")
    func constructionDoesNotRead() {
        nonisolated(unsafe) var reads = 0
        let snapshot = ViewportSnapshot(
            processID: 42, reader: recordingReader { _ in reads += 1 })

        withExtendedLifetime(snapshot) {}

        #expect(reads == 0)
    }

    @Test("첫 물음에 주어진 pid로 정확히 1회 읽는다")
    func firstQueryReadsOnceWithGivenProcessID() {
        nonisolated(unsafe) var seen: [pid_t] = []
        let snapshot = ViewportSnapshot(
            processID: 42, reader: recordingReader { seen.append($0) })

        #expect(snapshot.value() == 40)
        #expect(seen == [42])
    }

    @Test("두 번째 물음은 기억된 값을 낸다")
    func repeatedQueriesReuseTheFirstRead() {
        nonisolated(unsafe) var reads = 0
        let snapshot = ViewportSnapshot(
            processID: 42, reader: recordingReader { _ in reads += 1 })

        #expect(snapshot.value() == 40)
        #expect(snapshot.value() == 40)
        #expect(reads == 1)
    }

    /// **실패도 기억한다** — 기억하지 않으면 타임아웃(캡 50ms) 앱에서 물음 수만큼 캡을 문다.
    @Test("읽기 실패는 nil이고 그 실패도 기억된다")
    func failedReadIsMemoizedAsNil() {
        nonisolated(unsafe) var reads = 0
        let snapshot = ViewportSnapshot(
            processID: 42,
            reader: recordingReader(returning: nil) { _ in reads += 1 })

        #expect(snapshot.value() == nil)
        #expect(snapshot.value() == nil)
        #expect(reads == 1, "실패를 기억하지 않으면 물을 때마다 AX 왕복이 되풀이된다")
    }

    @Test("pid가 없으면 리더를 아예 부르지 않는다")
    func missingProcessIDSkipsTheReader() {
        nonisolated(unsafe) var reads = 0
        let snapshot = ViewportSnapshot(
            processID: nil, reader: recordingReader { _ in reads += 1 })

        #expect(snapshot.value() == nil)
        #expect(reads == 0)
    }

    /// **콜백·메인 AX 무접촉 불변식의 코드 측 보증** — `FocusedTextSnapshot`과 같은 계약이다.
    @Test("리더는 물은 큐 위에서 동기로 실행된다 — 홉 없음")
    func readerRunsSynchronouslyOnTheCallingQueue() {
        let key = DispatchSpecificKey<String>()
        let queue = DispatchQueue(label: "dev.pilyang.VimActionTests.viewportPosting")
        queue.setSpecific(key: key, value: "posting")

        nonisolated(unsafe) var observedQueue: String?
        nonisolated(unsafe) var observedMainThread = true
        let snapshot = ViewportSnapshot(
            processID: 42,
            reader: ViewportReader { _ in
                observedQueue = DispatchQueue.getSpecific(key: key)
                observedMainThread = Thread.isMainThread
                return 40
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

/// 뷰포트 증명은 순수 함수라 표로 검증한다 — **문서 전체 가시를 기각하는 것**이 이 표의
/// 존재 이유다: Notion이 visible을 문서 전체로 오보하는 것이 실측됐고(198줄 — 한 화면일 수
/// 없다), 클램프만으로는 실패 방향이 "과다 스크롤"이다. AX 호출 자체는 실기기 몫이다.
struct ViewportProvenTests {
    @Test("뷰포트 규모의 범위는 그대로 통과한다")
    func viewportScaleRangePasses() {
        #expect(
            ViewportReader.provenViewport(
                NSRange(location: 0, length: 6_372), characterCount: 27_000)
                == NSRange(location: 0, length: 6_372))
        // 스크롤로 내려간 상태 — location > 0, 끝이 문서 끝에 닿아도 전체가 아니면 뷰포트다.
        #expect(
            ViewportReader.provenViewport(
                NSRange(location: 23_880, length: 11_940), characterCount: 35_820)
                == NSRange(location: 23_880, length: 11_940))
    }

    @Test("문서 전체 가시는 증명 실패다 — Notion 오보 가드")
    func wholeDocumentVisibleFails() {
        // Notion 실측 그대로 — visible = 문서 전체.
        #expect(
            ViewportReader.provenViewport(
                NSRange(location: 0, length: 5_486), characterCount: 5_486) == nil)
        // 정말 문서 전체가 보이는 짧은 문서도 같은 편이다 — 그런 문서에서는 화살표가 문서
        // 끝에서 포화해 스크롤 정밀도가 애초에 의미 없다.
        #expect(
            ViewportReader.provenViewport(NSRange(location: 0, length: 27), characterCount: 27)
                == nil)
    }

    @Test("말이 안 되는 범위는 nil — 빈 범위·음수·문서 밖")
    func nonsensicalRangesFail() {
        #expect(
            ViewportReader.provenViewport(NSRange(location: 0, length: 0), characterCount: 100)
                == nil)
        #expect(
            ViewportReader.provenViewport(NSRange(location: -1, length: 50), characterCount: 100)
                == nil)
        // 범위 끝이 문서 길이를 넘는 보고 — lineForIndex에 문서 밖 인덱스를 물을 수 없다.
        #expect(
            ViewportReader.provenViewport(NSRange(location: 80, length: 50), characterCount: 100)
                == nil)
    }
}

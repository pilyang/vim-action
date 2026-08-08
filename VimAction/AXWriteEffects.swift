//
//  AXWriteEffects.swift
//  VimAction
//

import Foundation
import os
import VimEngine

/// **`AXWriteOutcome`이 값으로 돌려준 소비자 행동을 실제 효과로 실행하는 지점** — 보고 1건,
/// 관측 로그, 전용 요약 버킷이 여기서 나간다.
///
/// 분류(`AXWriteOutcome.classify`)와 실행이 갈려 있는 이유는 그 타입의 doc 주석에 있다: 분류가
/// 로깅까지 하면 default-deny 화이트리스트 표를 테스트로 고정할 수 없다. 반대로 여기는 표를
/// 다시 판정하지 않는다 — 클래스마다 무엇을 할지만 안다.
///
/// **수명은 execute 1회**(= 키 입력 1건)다. 그것이 두 계약의 근거다:
///   ① 보고는 인스턴스당 최대 1회로 접힌다 — "실행 실패 보고는 원인 키 입력 1건당 최대 1회"
///      (`20260726_execution-failure-report-granularity.md`). `100j`가 액션 100건으로 전개되는
///      구조라, 접지 않으면 한 근본 원인이 100건으로 세어져 폭주 임계를 즉시 넘긴다.
///   ② 로그는 발생마다가 아니라 **요약 1줄**이다 (`KeyboardAdapter`의 미지원·레이아웃 버킷과
///      같은 형태). 같은 이유로 error 로그도 도배되면 안 된다.
///
/// 게시 직렬 큐 위에서만 산다 — `now` seam이 그 큐에서 불리는 것이 실패 시각 캡처 계약의
/// 전부다 (아래 `apply` 주석).
nonisolated struct AXWriteEffects {
    /// 클래스별 누적 — 개수와 **첫 액션 1개**만 든다 (요약에 쓰는 것이 그뿐이라 액션을 쌓지
    /// 않는다, 기존 버킷과 같은 규칙).
    private struct Bucket {
        var count: Int
        let first: VimAction
    }

    /// 관측 로그가 앱을 특정하는 수단. `.illegalArgument` 빈도는 **D1 종료 시 보고 승격
    /// 재심사의 판정 데이터**인데, 어느 앱이 거부했는지 모르면 "오프셋 공간 불일치"라는 신호가
    /// 아무 데도 쓸 수 없는 숫자가 된다.
    private let bundleID: String?

    /// 실패 보고 seam — `EventTapController.reportExecutionFailure(at:)`로 가는 통로다.
    /// 주입인 이유는 `ActionExecutor.postEvent`와 같다(테스트가 배선을 동기로 관측한다)이고,
    /// 시각을 인자로 싣는 이유는 아래 `apply`에 있다.
    private let report: @Sendable (TimeInterval) -> Void

    /// 실패 시각 캡처 seam. 프로덕션은 `systemUptime`(단조 증가)이다.
    private let now: @Sendable () -> TimeInterval

    private var buckets: [AXWriteOutcome: Bucket] = [:]

    /// 이미 보고했는가 — 위 계약 ①의 래치다.
    private var reported = false

    init(
        bundleID: String?,
        report: @escaping @Sendable (TimeInterval) -> Void,
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.bundleID = bundleID
        self.report = report
        self.now = now
    }

    /// AX 쓰기 1건의 결과를 반영한다.
    ///
    /// **실패 시각은 여기서 — 게시 큐에서 — 캡처한다.** 카운터는 컨트롤러의 MainActor 격리
    /// 안에서만 돌므로 보고는 메인 홉을 타는데(`20260725_failure-burst-autodisable-shape.md`
    /// 4항), 홉이 착지한 시각으로 세면 메인 스톨 뒤 뭉쳐 착지한 보고들이 1초 창에 몰려
    /// **거짓 트립**한다. 시각만 실어 보내면 창 판정은 실제로 실패가 난 시점을 본다
    /// (`20260808_ax-write-failure-whitelist-no-fallback.md` 구조 규칙 ②).
    ///
    /// `.failure` 외에는 보고하지 않는다 — 보고 의미론이 "실행을 시도했는데 깨졌다"뿐이라는
    /// default-deny의 실행 측 절반이다. 스킵 클래스들은 집계만 되고 요약에서 갈라져 나간다.
    ///
    /// 이 함수는 **다음 액션을 실행할지 정하지 않는다** — "첫 실패에서 execute 잔여를 통째로
    /// 스킵"은 드라이버 루프의 구조라 호출자(실행 드라이버)가 outcome을 보고 정한다.
    mutating func apply(_ outcome: AXWriteOutcome, action: VimAction) {
        if var bucket = buckets[outcome] {
            bucket.count += 1
            buckets[outcome] = bucket
        } else {
            buckets[outcome] = Bucket(count: 1, first: action)
        }

        guard outcome == .failure, !reported else { return }
        reported = true
        report(now())
    }

    /// 클래스별 누적 — 요약 로그는 단언할 수 없으므로(os.Logger) **버킷이 섞이지 않는다**를
    /// 테스트가 여기로 본다. 섞이면 심사자가 앱의 정적 미지원(강등 신호)과 일시적 경합을
    /// 구분하지 못한다.
    func count(of outcome: AXWriteOutcome) -> Int { buckets[outcome]?.count ?? 0 }

    /// execute 끝에서 1회 — 클래스마다 최대 한 줄이다.
    func logSummary() {
        for row in Self.summaryRows {
            guard let bucket = buckets[row.outcome] else { continue }
            #if !DEBUG
            // 스킵 2종 요약은 관례대로 DEBUG 빌드 전용이다 — 기존 미지원·레이아웃·프로파일
            // 버킷과 같은 편이며, 릴리스에서 살아남아야 하는 것은 error와 관측 `.info`뿐이다.
            if row.level == .debug { continue }
            #endif
            Logger.eventTap.log(
                level: row.level,
                "\(row.label, privacy: .public) ×\(bucket.count, privacy: .public) [\(self.bundleID ?? "앱 미상", privacy: .public)]: \(String(describing: bucket.first), privacy: .public)"
            )
        }
    }

    /// 요약 표 — **클래스별 로그 레벨이 곧 계약이다.** `.success`가 없는 것도 계약이다(성공은
    /// 로그를 남기지 않는다).
    ///
    /// `.illegalArgument`만 `.info`이고 `#if DEBUG` 밖인 것이 관례에서 벗어난 자리다: 이 로그는
    /// 도그푸딩 중 켜 둔 stream이 아니라 **사후에** 읽히는 판정 데이터라
    /// (`log show --info`), `.debug`로 두면 승격 재심사가 볼 것이 남지 않는다
    /// (`20260808_ax-illegal-argument-observation-log-level.md`).
    private static let summaryRows: [(outcome: AXWriteOutcome, level: OSLogType, label: String)] = [
        (.failure, .error, "AX 쓰기 실패 — 보고됨"),
        (.illegalArgument, .info, "AX 쓰기 거부(illegalArgument) — 관측 전용"),
        (.unsupportedSkip, .debug, "AX 미지원 스킵"),
        (.contentionSkip, .debug, "AX 경합 스킵"),
        (.apiDisabled, .error, "AX 권한 회수(apiDisabled) — 쓰기 불가"),
        (.unexpected, .error, "AX 미지 응답 — 미보고 스킵"),
    ]
}

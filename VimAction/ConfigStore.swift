//
//  ConfigStore.swift
//  VimAction
//

import Foundation
import Observation
import os
import VimActionConfig

/// `~/.config/vim-action/` 설정의 앱측 소유자 — 시딩·로드·리로드를 수행하고, 결과를
/// 실행 경로가 소비할 형태(`ResolvedProfile`·disable 집합)로 들고 있는다.
///
/// `VimActionConfig`는 Bundle·FileManager·os.log를 모른다 — 실제 IO seam 주입과
/// **경고·에러를 os.log로 흘리는 단일 지점**이 여기다. 흘리지 않으면 사용자의 오타가
/// 조용히 무시된다. `ConfigError`(파일 통째 무효)는 로그로 부족해 UI(메뉴 상태 라인·
/// Settings·리로드 알림)가 이 값을 직접 읽는다.
///
/// init은 IO를 하지 않는다 — `AppState`가 XCTest·#Preview에서도 생성되기 때문이다.
/// IO는 `seedAndLoad()`(bootstrap, XCTest 가드 뒤)와 `reload()`(메뉴 트리거)뿐이다.
@MainActor
@Observable
final class ConfigStore {
    private let seeder: ConfigSeeder
    private let loader: ConfigLoader
    /// 프로파일 경로 조합의 앱측 출처. **주입된 값이어야 한다** — `ConfigPaths`를 직접
    /// 참조하면 유닛 테스트가 실제 `~/.config/vim-action/profiles`에 파일을 만든다.
    private let profilesDirectory: String
    /// scaffold 생성 전 존재 확인용 — 쓰기와 같은 seam을 쓴다(판정과 쓰기가 어긋나지 않는다).
    private let seederFileSystem: ConfigSeeder.FileSystem
    private let bundledConfig: () -> String?
    private let bundledProfiles: () -> [String: String]

    /// 마지막으로 **적용된** 스냅샷 — 리로드가 실패하면 직전 유효 설정이 그대로 남는다.
    private(set) var appliedSnapshot = ConfigSnapshot()
    /// 실행 경로가 소비하는 형태 — 로드 시 1회 변환 (`ResolvedProfile` 참고).
    private(set) var resolvedProfiles: [String: ResolvedProfile] = [:]
    /// 마지막 로드의 경고·에러 — 적용 여부와 무관하게 항상 최신이다 (UI가 보여줄 값).
    private(set) var warnings: [ConfigWarning] = []
    private(set) var errors: [ConfigError] = []

    private var hasAppliedOnce = false

    init(
        configPath: String = ConfigPaths.configPath,
        profilesDirectory: String = ConfigPaths.profilesDirectory,
        loaderFileSystem: ConfigLoader.FileSystem = .live,
        seederFileSystem: ConfigSeeder.FileSystem = .live,
        bundledConfig: @escaping () -> String? = BundledConfig.config,
        bundledProfiles: @escaping () -> [String: String] = BundledConfig.profiles
    ) {
        seeder = ConfigSeeder(
            configPath: configPath, profilesDirectory: profilesDirectory,
            fileSystem: seederFileSystem
        )
        loader = ConfigLoader(
            configPath: configPath, profilesDirectory: profilesDirectory,
            fileSystem: loaderFileSystem
        )
        self.profilesDirectory = profilesDirectory
        self.seederFileSystem = seederFileSystem
        self.bundledConfig = bundledConfig
        self.bundledProfiles = bundledProfiles
    }

    /// `config.yaml` `apps` 맵에서 `false`인 앱 — `FrontmostAppGate`에 푸시된다.
    /// 맵에 없는 앱은 없는 것(기본 on)이고, 판정 정책은 게이트 몫이다.
    var disabledBundleIDs: Set<String> {
        Set(appliedSnapshot.global.apps.filter { !$0.value }.keys)
    }

    /// 키 입력 시점 프로파일 조회 — 딕셔너리 읽기뿐이다 (콜백 경량 불변식).
    func resolvedProfile(for bundleID: String?) -> ResolvedProfile {
        guard let bundleID else { return .empty }
        return resolvedProfiles[bundleID] ?? .empty
    }

    /// 그 앱의 프로파일 파일 경로. `ConfigSeeder`가 내부에서 만드는 경로와 같은 형식이어야
    /// 하며, 그 합의는 `ConfigStoreTests`가 지킨다.
    func profilePath(for bundleID: String) -> String {
        "\(profilesDirectory)/\(bundleID).yaml"
    }

    /// 메뉴 항목 제목이 'Open'인지 'Create'인지 — 쓰기와 같은 seam으로 묻는다.
    func hasProfile(for bundleID: String) -> Bool {
        seederFileSystem.fileExists(profilePath(for: bundleID))
    }

    /// 메뉴 '프로파일 열기' 진입점. 파일이 있으면 그 경로를, 없으면 주석뿐인 scaffold를
    /// 만든 뒤 경로를 준다.
    ///
    /// 쓰기는 시딩과 **같은 경로**(`ConfigSeeder.seed`)를 탄다 — 시더가 `fileExists`면 내용을
    /// 보지 않고 `.skippedExisting`을 돌려주므로 "기존 파일 절대 무수정" 불변식이 여기서
    /// 다시 구현되지 않는다. 생성 후 리로드는 하지 않는다: 전부 주석이라 적용될 것이 없고,
    /// "편집 후 Reload Config"가 기존 계약이다.
    ///
    /// - Returns: 열어야 할 경로. 쓰기 실패나 파일명으로 쓸 수 없는 bundle id면 nil.
    func prepareProfileFile(for bundleID: String) -> String? {
        // bundle id는 다른 프로세스에서 흘러온 문자열이 파일 경로가 되는 유일한 지점이다.
        guard !bundleID.isEmpty, !bundleID.contains("/"), !bundleID.hasPrefix(".") else {
            Logger.config.error("프로파일 파일명으로 쓸 수 없는 bundle id — \(bundleID, privacy: .public)")
            return nil
        }
        let path = profilePath(for: bundleID)
        let outcomes = seeder.seed(
            config: nil, profiles: [bundleID: profileScaffoldYAML(bundleID: bundleID)])
        switch outcomes[path] {
        case .written:
            Logger.config.notice("프로파일 scaffold 생성 — \(path, privacy: .public)")
        case .failed, nil:
            Logger.config.error("프로파일 scaffold 생성 실패 — \(path, privacy: .public)")
            return nil
        case .skippedExisting:
            break  // 정상 — 이미 있는 파일을 그대로 연다
        }
        return path
    }

    /// bootstrap 1회: 번들 기본 파일 시딩(없는 파일만 — 기존 파일은 내용을 보지 않고
    /// 그대로) 후 최초 로드.
    func seedAndLoad() {
        let outcomes = seeder.seed(config: bundledConfig(), profiles: bundledProfiles())
        for (path, outcome) in outcomes.sorted(by: { $0.key < $1.key }) {
            switch outcome {
            case .written:
                Logger.config.notice("기본 설정 시딩 — \(path, privacy: .public)")
            case .failed:
                Logger.config.error("기본 설정 시딩 실패 — \(path, privacy: .public)")
            case .skippedExisting:
                break  // 정상 — 사용자 파일 소유권 존중
            }
        }
        load()
    }

    /// 메뉴 'Reload Config' 트리거. 반환은 파일 통째 에러 없음 여부 — 실패 시 직전
    /// 유효 설정이 유지되고, 호출자(메뉴)가 에러를 사용자에게 보인다.
    @discardableResult
    func reload() -> Bool { load() }

    @discardableResult
    private func load() -> Bool {
        let result = loader.load()
        warnings = result.warnings
        errors = result.errors
        for warning in result.warnings {
            Logger.config.notice(
                "설정 항목 무시 — \(warning.file, privacy: .public) \(warning.path, privacy: .public): \(self.describe(warning.kind), privacy: .public)"
            )
        }
        for error in result.errors {
            Logger.config.error(
                "설정 파일 무효 — \(error.file, privacy: .public): \(error.message, privacy: .public)"
            )
        }
        // 에러가 있으면 직전 유효 스냅샷을 유지한다. 단 **최초 로드는 부분 스냅샷이라도
        // 적용한다** — 깨진 파일은 로더가 이미 부재 처리했고, 유지할 직전 설정이 없다.
        if result.errors.isEmpty || !hasAppliedOnce {
            apply(result.snapshot)
        }
        return result.errors.isEmpty
    }

    private func apply(_ snapshot: ConfigSnapshot) {
        appliedSnapshot = snapshot
        resolvedProfiles = snapshot.profiles.mapValues(ResolvedProfile.init)
        hasAppliedOnce = true
        Logger.config.info(
            "설정 적용 — off \(self.disabledBundleIDs.count)앱, 프로파일 \(snapshot.profiles.count)개"
        )
    }

    private func describe(_ kind: ConfigWarning.Kind) -> String {
        switch kind {
        case .unknownKey: return "미지 키"
        case .invalidValue(let raw): return "무효 값 '\(raw)'"
        case .invalidKeyStroke(let token): return "무효 키 토큰 '\(token)'"
        }
    }
}

/// 메뉴바 상태 라인·Settings 공용 설정 상태 한 줄. 순수 함수 — 분기 전부를 유닛
/// 테스트로 커버한다 (`SettingsView`의 상태 문구 함수들과 같은 패턴).
nonisolated func configStatusText(profileCount: Int, errors: [ConfigError]) -> String {
    switch errors.count {
    case 0:
        return profileCount == 1 ? "Config: 1 profile" : "Config: \(profileCount) profiles"
    case 1:
        return "Config error — \((errors[0].file as NSString).lastPathComponent)"
    default:
        return "Config errors — \(errors.count) files"
    }
}

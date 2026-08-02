//
//  ConfigFileSystem.swift
//  VimAction
//

import Foundation
import VimActionConfig

/// `VimActionConfig`의 파일시스템 seam 실구현 — 패키지는 `FileManager`를 모르고
/// (Foundation 금지 불변식), 실제 IO는 전부 여기서 주입한다. 테스트는 인메모리
/// seam을 자기 것으로 주입하므로 이 `.live`들은 프로덕션 경로에서만 쓰인다.
nonisolated extension ConfigLoader.FileSystem {
    static let live = ConfigLoader.FileSystem(
        readFile: { try? String(contentsOfFile: $0, encoding: .utf8) },
        listDirectory: { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }
    )
}

nonisolated extension ConfigSeeder.FileSystem {
    static let live = ConfigSeeder.FileSystem(
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        createDirectory: {
            (try? FileManager.default.createDirectory(
                atPath: $0, withIntermediateDirectories: true
            )) != nil
        },
        writeFile: { path, contents in
            (try? contents.write(toFile: path, atomically: true, encoding: .utf8)) != nil
        }
    )
}

import Foundation
import XCTest
@testable import Omnia

final class NativePlaybackLegalCatalogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NativePlaybackLegalCatalogTests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Licenses"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        root = nil
    }

    func testLoadsSortedLocalNoticesFromSPDXPackages() throws {
        try writeSBOM(packages: [
            package(name: "mpv", version: "0.41.0", license: "LGPL-2.1-or-later"),
            package(name: "ffmpeg", version: "8.1.2", license: "LGPL-2.1-or-later")
        ])
        try Data("mpv notice".utf8).write(
            to: root.appendingPathComponent("Licenses/mpv.txt")
        )
        try Data("ffmpeg notice".utf8).write(
            to: root.appendingPathComponent("Licenses/ffmpeg.txt")
        )

        let notices = try NativePlaybackLegalCatalog.notices(at: root)

        XCTAssertEqual(notices.map(\.name), ["ffmpeg", "mpv"])
        XCTAssertEqual(notices.first?.version, "8.1.2")
        XCTAssertEqual(notices.first?.licenseExpression, "LGPL-2.1-or-later")
        XCTAssertEqual(notices.first?.text, "ffmpeg notice")
    }

    func testRejectsPackageNameThatCouldEscapeLicenseDirectory() throws {
        try writeSBOM(packages: [
            package(name: "../secret", version: "1.0.0", license: "MIT")
        ])

        XCTAssertThrowsError(try NativePlaybackLegalCatalog.notices(at: root))
    }

    func testRejectsOversizedLicenseNotice() throws {
        try writeSBOM(packages: [
            package(name: "sample", version: "1.0.0", license: "MIT")
        ])
        try Data(repeating: 65, count: NativePlaybackLegalCatalog.maximumNoticeBytes + 1)
            .write(to: root.appendingPathComponent("Licenses/sample.txt"))

        XCTAssertThrowsError(try NativePlaybackLegalCatalog.notices(at: root))
    }

    private func package(name: String, version: String, license: String) -> [String: Any] {
        [
            "name": name,
            "versionInfo": version,
            "licenseDeclared": license
        ]
    }

    private func writeSBOM(packages: [[String: Any]]) throws {
        let data = try JSONSerialization.data(withJSONObject: ["packages": packages])
        try data.write(to: root.appendingPathComponent("native-playback.spdx.json"))
    }
}

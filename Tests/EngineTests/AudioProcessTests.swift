import XCTest
import Foundation
import CoreAudio
@testable import Core

final class AudioProcessTests: XCTestCase {
    /// Build an AudioProcess with sensible defaults for the field under test.
    private func proc(_ id: AudioObjectID, _ name: String, bundleID: String = "",
                      regular: Bool = true, output: Bool = false) -> AudioProcess {
        AudioProcess(audioObjectID: id, pid: pid_t(id), bundleID: bundleID, name: name,
                     icon: nil, isRunningOutput: output, isRegularApp: regular)
    }

    func testSilentRegularShows() {
        let rows = AudioProcess.visibleRows(
            from: [proc(1, "Spotify", bundleID: "com.spotify.client", regular: true, output: false)],
            tappedBundleIDs: []
        )
        XCTAssertEqual(rows.map(\.name), ["Spotify"])
    }

    func testDaemonsExcluded() {
        let rows = AudioProcess.visibleRows(
            from: [
                proc(1, "audiomxd", bundleID: "com.apple.audiomxd", regular: false, output: false),
                proc(2, "Spotify", bundleID: "com.spotify.client", regular: true)
            ],
            tappedBundleIDs: []
        )
        XCTAssertEqual(rows.map(\.name), ["Spotify"])
    }

    func testDedupesMultiProcess() {
        let rows = AudioProcess.visibleRows(
            from: [
                proc(1, "Google Chrome", bundleID: "com.google.Chrome", regular: true),
                proc(2, "Google Chrome", bundleID: "com.google.Chrome.helper", regular: true),
                proc(3, "Google Chrome", bundleID: "com.google.Chrome.helper", regular: true)
            ],
            tappedBundleIDs: []
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "Google Chrome")
    }

    func testPrefersOutputtingRepresentative() {
        let rows = AudioProcess.visibleRows(
            from: [
                proc(1, "Google Chrome", bundleID: "com.google.Chrome", regular: true, output: false),
                proc(2, "Google Chrome", bundleID: "com.google.Chrome.helper", regular: true, output: true)
            ],
            tappedBundleIDs: []
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].bundleID, "com.google.Chrome.helper")
        XCTAssertTrue(rows[0].isRunningOutput)
    }

    func testTappedShowsRegardless() {
        let rows = AudioProcess.visibleRows(
            from: [proc(1, "Weird", bundleID: "com.weird.bg", regular: false, output: false)],
            tappedBundleIDs: ["com.weird.bg"]
        )
        XCTAssertEqual(rows.map(\.name), ["Weird"])
    }

    func testSortedByName() {
        let rows = AudioProcess.visibleRows(
            from: [
                proc(1, "Spotify", bundleID: "com.spotify.client"),
                proc(2, "Discord", bundleID: "com.hnc.Discord"),
                proc(3, "google chrome", bundleID: "com.google.Chrome")
            ],
            tappedBundleIDs: []
        )
        XCTAssertEqual(rows.map(\.name), ["Discord", "google chrome", "Spotify"])
    }
}

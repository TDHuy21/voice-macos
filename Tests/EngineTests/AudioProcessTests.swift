import Testing
import Foundation
import CoreAudio
@testable import Core

@Suite struct AudioProcessTests {
    /// Build an AudioProcess with sensible defaults for the field under test.
    private func proc(_ id: AudioObjectID, _ name: String, bundleID: String = "",
                      regular: Bool = true, output: Bool = false) -> AudioProcess {
        AudioProcess(audioObjectID: id, pid: pid_t(id), bundleID: bundleID, name: name,
                     icon: nil, isRunningOutput: output, isRegularApp: regular)
    }

    @Test func silentRegularShows() {
        let rows = AudioProcess.visibleRows(
            from: [proc(1, "Spotify", bundleID: "com.spotify.client", regular: true, output: false)],
            tappedBundleIDs: []
        )
        #expect(rows.map(\.name) == ["Spotify"])
    }

    @Test func daemonsExcluded() {
        let rows = AudioProcess.visibleRows(
            from: [
                proc(1, "audiomxd", bundleID: "com.apple.audiomxd", regular: false, output: false),
                proc(2, "Spotify", bundleID: "com.spotify.client", regular: true)
            ],
            tappedBundleIDs: []
        )
        #expect(rows.map(\.name) == ["Spotify"])
    }

    @Test func dedupesMultiProcess() {
        let rows = AudioProcess.visibleRows(
            from: [
                proc(1, "Google Chrome", bundleID: "com.google.Chrome", regular: true),
                proc(2, "Google Chrome", bundleID: "com.google.Chrome.helper", regular: true),
                proc(3, "Google Chrome", bundleID: "com.google.Chrome.helper", regular: true)
            ],
            tappedBundleIDs: []
        )
        #expect(rows.count == 1)
        #expect(rows[0].name == "Google Chrome")
    }

    @Test func prefersOutputtingRepresentative() {
        let rows = AudioProcess.visibleRows(
            from: [
                proc(1, "Google Chrome", bundleID: "com.google.Chrome", regular: true, output: false),
                proc(2, "Google Chrome", bundleID: "com.google.Chrome.helper", regular: true, output: true)
            ],
            tappedBundleIDs: []
        )
        #expect(rows.count == 1)
        #expect(rows[0].bundleID == "com.google.Chrome.helper")
        #expect(rows[0].isRunningOutput)
    }

    @Test func tappedShowsRegardless() {
        let rows = AudioProcess.visibleRows(
            from: [proc(1, "Weird", bundleID: "com.weird.bg", regular: false, output: false)],
            tappedBundleIDs: ["com.weird.bg"]
        )
        #expect(rows.map(\.name) == ["Weird"])
    }

    @Test func sortedByName() {
        let rows = AudioProcess.visibleRows(
            from: [
                proc(1, "Spotify", bundleID: "com.spotify.client"),
                proc(2, "Discord", bundleID: "com.hnc.Discord"),
                proc(3, "google chrome", bundleID: "com.google.Chrome")
            ],
            tappedBundleIDs: []
        )
        #expect(rows.map(\.name) == ["Discord", "google chrome", "Spotify"])
    }
}

import Testing
import Foundation
import AppKit
import AVFoundation
import CoreAudio
@testable import Core
@testable import Engine

@MainActor
@Suite struct BreakTimerManagerTests {

    // MARK: - Event classification tests (pure function, no tap required)
    @Test func eventClassification() {
        func check(keycode: CGKeyCode, flags: CGEventFlags = [], expected: Bool) {
            let result = shouldSuppressEvent(keycode: keycode, flags: flags)
            #expect(result == expected)
        }

        // Suppressed shortcuts
        check(keycode: 48, flags: .maskCommand, expected: true)
        check(keycode: 48, flags: [.maskCommand, .maskShift], expected: true)
        check(keycode: 99, expected: true)
        check(keycode: 12, flags: .maskCommand, expected: true)
        check(keycode: 13, flags: .maskCommand, expected: true)
        check(keycode: 4, flags: .maskCommand, expected: true)
        check(keycode: 50, flags: .maskCommand, expected: true)
        check(keycode: 46, flags: .maskCommand, expected: true)
        check(keycode: 53, expected: true)

        // Should NOT suppress
        check(keycode: 0, expected: false)
        check(keycode: 49, expected: false)
        check(keycode: 36, expected: false)
        check(keycode: 126, expected: false)
        check(keycode: 122, expected: false)
    }

    // MARK: - State machine tests using a mock clock
    @Test func stateMachineTransitions() {
        func withFreshManager(_ studySecs: TimeInterval = 60,
                              _ breakSecs: TimeInterval = 20,
                              body: (BreakTimerManager) -> Void) -> BreakTimerManager {
            let m = BreakTimerManager()
            m.studyDuration = studySecs
            m.breakDuration = breakSecs
            body(m)
            return m
        }

        // idle -> studying on start()
        _ = withFreshManager { m in
            #expect(m.phase == .idle)
            m.start()
            #expect(m.phase == .studying)
        }

        // stop() from studying -> idle
        _ = withFreshManager { m in
            m.start()
            m.stop()
            #expect(m.phase == .idle)
        }

        // stop() from idle is no-op
        _ = withFreshManager { m in
            m.stop()
            #expect(m.phase == .idle)
        }

        // Re-entrancy: start() while studying is no-op
        _ = withFreshManager { m in
            m.start()
            let deadline1 = m.remaining
            m.start()
            #expect(m.remaining == deadline1)
            #expect(m.phase == .studying)
        }

        // skip() from idle is no-op
        _ = withFreshManager { m in
            m.skip()
            #expect(m.phase == .idle)
        }

        // endBreak with timeout reason triggers auto-loop -> studying
        _ = withFreshManager { m in
            m.start()
            m.endBreak(reason: .timeout)
            #expect(m.phase == .idle)
        }

        // endBreak with stopped reason does NOT auto-loop
        _ = withFreshManager { m in
            m.start()
            m.endBreak(reason: .stopped)
            #expect(m.phase == .idle)
        }
    }

    // MARK: - Volume Ducking & Unducking Tests
    @Test func volumeDuckingAndUnducking() throws {
        let manager = AudioEngineManager.shared
        manager.clearActiveNodesForTesting()
        
        let btm = BreakTimerManager.shared
        btm.stop() // ensure starting from idle
        
        // 1. Setup mock active nodes and initial volumes
        let app1 = "com.spotify.client"
        let app2 = "com.apple.Music"
        
        let sampleRate: Double = 48000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let ringBuffer = RingBuffer(capacity: 1024)
        var tapASBD = AudioStreamBasicDescription()
        tapASBD.mSampleRate = sampleRate
        tapASBD.mFormatID = kAudioFormatLinearPCM
        tapASBD.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian
        tapASBD.mBytesPerPacket = 8
        tapASBD.mFramesPerPacket = 1
        tapASBD.mBytesPerFrame = 8
        tapASBD.mChannelsPerFrame = 2
        tapASBD.mBitsPerChannel = 32
        
        let node1 = try #require(AppAudioNode(ringBuffers: [ringBuffer], sourceFormat: tapASBD, engineFormat: format))
        let node2 = try #require(AppAudioNode(ringBuffers: [ringBuffer], sourceFormat: tapASBD, engineFormat: format))
        
        manager.activeNodes[app1] = node1
        manager.activeNodes[app2] = node2
        
        manager.setVolume(bundleID: app1, volume: 0.8)
        manager.setVolume(bundleID: app2, volume: 0.5)
        
        #expect(manager.getVolume(bundleID: app1) == 0.8)
        #expect(manager.getVolume(bundleID: app2) == 0.5)
        
        // Start and transit to breaking phase, which automatically ducks active app volumes to 10%
        btm.start()
        btm.enterBreaking()
        #expect(btm.phase == .breaking)
        
        // 2. Verify ducked volumes
        #expect(abs(manager.getVolume(bundleID: app1) - 0.08) < 0.001)
        #expect(abs(manager.getVolume(bundleID: app2) - 0.05) < 0.001)
        #expect(btm.preBreakVolumes[app1] == 0.8)
        #expect(btm.preBreakVolumes[app2] == 0.5)
        
        // 3. Verify duckNewNode: ducks newly tapped apps mid-break, capturing their original volume,
        // and does not overwrite it if called again.
        let app3 = "com.apple.Safari"
        let node3 = try #require(AppAudioNode(ringBuffers: [ringBuffer], sourceFormat: tapASBD, engineFormat: format))
        manager.activeNodes[app3] = node3
        manager.setVolume(bundleID: app3, volume: 0.6)
        
        btm.duckNewNode(bundleID: app3)
        #expect(abs(manager.getVolume(bundleID: app3) - 0.06) < 0.001)
        #expect(btm.preBreakVolumes[app3] == 0.6)
        
        // If called again, it should not overwrite original volume
        btm.duckNewNode(bundleID: app3)
        #expect(btm.preBreakVolumes[app3] == 0.6)
        
        // 4. Verify unduckAudio preserves user manual change if it deviates from ducked volume
        // Change app1 volume manually to 0.4 (deviating from ducked volume 0.08)
        manager.setVolume(bundleID: app1, volume: 0.4)
        
        // App2 and App3 remain at their ducked volumes (0.05 and 0.06)
        btm.unduckAudio()
        
        // App1 volume should remain at 0.4 (manual change preserved)
        #expect(manager.getVolume(bundleID: app1) == 0.4)
        
        // App2 and App3 volumes should be restored to original pre-break levels (0.5 and 0.6)
        #expect(abs(manager.getVolume(bundleID: app2) - 0.5) < 0.001)
        #expect(abs(manager.getVolume(bundleID: app3) - 0.6) < 0.001)
        
        // Clean up
        btm.stop()
        manager.clearActiveNodesForTesting()
    }
}

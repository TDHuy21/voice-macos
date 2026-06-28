import Testing
import AVFoundation
@testable import Engine
@testable import Core

@Suite struct AudioEngineIntegrationTests {
    
    @Test func offlineRenderingFlow() throws {
        let sampleRate: Double = 48000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        
        let engine = AVAudioEngine()
        
        // 1. Enable manual rendering mode (offline)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        
        // 2. Initialize RingBuffer and fill with a test signal (Sine wave at 440Hz)
        let ringBuffer = RingBuffer(capacity: 64 * 1024)
        let sineFreq: Double = 440.0
        let framesCount = 2048
        
        // Prepare interleaved float sine wave
        var sineData = [Float](repeating: 0, count: framesCount * 2)
        for i in 0..<framesCount {
            let t = Double(i) / sampleRate
            let val = Float(sin(2.0 * .pi * sineFreq * t))
            sineData[i * 2] = val     // Left
            sineData[i * 2 + 1] = val // Right
        }
        
        // Write to ring buffer
        let bytesWritten = sineData.withUnsafeBufferPointer { ptr in
            ringBuffer.write(ptr.baseAddress!, byteCount: framesCount * 2 * MemoryLayout<Float>.size)
        }
        #expect(bytesWritten == framesCount * 2 * MemoryLayout<Float>.size)
        
        // 3. Create AppAudioNode (input: 48000Hz stereo interleaved float)
        var tapASBD = AudioStreamBasicDescription()
        tapASBD.mSampleRate = sampleRate
        tapASBD.mFormatID = kAudioFormatLinearPCM
        tapASBD.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagsNativeEndian // interleaved
        tapASBD.mBytesPerPacket = 8
        tapASBD.mFramesPerPacket = 1
        tapASBD.mBytesPerFrame = 8
        tapASBD.mChannelsPerFrame = 2
        tapASBD.mBitsPerChannel = 32
        
        let appNode = try #require(AppAudioNode(ringBuffers: [ringBuffer], sourceFormat: tapASBD, engineFormat: format), "Failed to create AppAudioNode")
        
        // 4. Attach nodes and connect
        engine.attach(appNode.sourceNode)
        engine.attach(appNode.eqNode)
        
        engine.connect(appNode.sourceNode, to: appNode.eqNode, format: format)
        engine.connect(appNode.eqNode, to: engine.mainMixerNode, format: format)
        
        // Ensure volume is full (1.0)
        appNode.volume = 1.0
        
        // 5. Start engine
        try engine.start()
        
        // 6. Prepare rendering destination buffer
        let renderBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        
        // 7. Render 512 frames offline
        let status = try engine.renderOffline(512, to: renderBuffer)
        #expect(status == .success)
        #expect(renderBuffer.frameLength == 512)
        
        // 8. Analyze render buffer (calculate Root Mean Square - RMS)
        var sumSquares: Float = 0.0
        let channelData = renderBuffer.floatChannelData!
        let leftChannel = channelData[0]
        let rightChannel = channelData[1]
        
        for i in 0..<512 {
            sumSquares += leftChannel[i] * leftChannel[i]
            sumSquares += rightChannel[i] * rightChannel[i]
        }
        let rms = sqrt(sumSquares / Float(512 * 2))
        
        print("AudioEngineIntegrationTests: RMS with volume 1.0 = \(rms)")
        #expect(rms > 0.001)
        
        // 9. Test Volume Control (Set volume to 0.0 / mute)
        appNode.volume = 0.0
        
        // Render next 512 frames
        let renderBufferMuted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        let statusMuted = try engine.renderOffline(512, to: renderBufferMuted)
        #expect(statusMuted == .success)
        
        var sumSquaresMuted: Float = 0.0
        let channelDataMuted = renderBufferMuted.floatChannelData!
        let leftMuted = channelDataMuted[0]
        let rightMuted = channelDataMuted[1]
        
        for i in 0..<512 {
            sumSquaresMuted += leftMuted[i] * leftMuted[i]
            sumSquaresMuted += rightMuted[i] * rightMuted[i]
        }
        let rmsMuted = sqrt(sumSquaresMuted / Float(512 * 2))
        
        print("AudioEngineIntegrationTests: RMS with volume 0.0 = \(rmsMuted)")
        #expect(rmsMuted < 0.00001)
        
        // Stop engine
        engine.stop()
    }
}

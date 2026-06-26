#!/usr/bin/env swift

// Standalone RingBuffer test — run directly: swift Tests/run_ring_buffer_tests.swift
// No framework dependencies needed.

import Foundation

// ─── Inline RingBuffer (copy from Sources/Core/RingBuffer.swift) ───
// We inline it here so this file can run standalone without SPM.

import libkern

final class RingBuffer {
    private let capacity: Int
    private let buffer: UnsafeMutablePointer<UInt8>
    
    private var writeOffset: Int = 0
    private var readOffset: Int = 0
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        self.buffer.initialize(repeating: 0, count: capacity)
    }
    
    deinit { buffer.deallocate() }
    
    var bytesAvailableForRead: Int {
        OSMemoryBarrier()
        let w = writeOffset; let r = readOffset
        return w >= r ? (w - r) : (capacity - r + w)
    }
    
    var bytesAvailableForWrite: Int { capacity - 1 - bytesAvailableForRead }
    
    @discardableResult
    func write(_ data: UnsafeRawPointer, byteCount: Int) -> Int {
        let w = writeOffset; let r = readOffset
        let available = capacity - 1 - (w >= r ? (w - r) : (capacity - r + w))
        guard available >= byteCount else { return 0 }
        let rawBuffer = UnsafeMutableRawPointer(buffer)
        let firstPart = min(byteCount, capacity - w)
        rawBuffer.advanced(by: w).copyMemory(from: data, byteCount: firstPart)
        if firstPart < byteCount {
            rawBuffer.copyMemory(from: data.advanced(by: firstPart), byteCount: byteCount - firstPart)
        }
        OSMemoryBarrier()
        writeOffset = (w + byteCount) % capacity
        return byteCount
    }
    
    @discardableResult
    func writeOverwriting(_ data: UnsafeRawPointer, byteCount: Int) -> Int {
        guard byteCount > 0 && byteCount < capacity else { return 0 }
        let w = writeOffset; let r = readOffset
        let used = w >= r ? (w - r) : (capacity - r + w)
        let available = capacity - 1 - used
        if available < byteCount {
            let deficit = byteCount - available
            OSMemoryBarrier()
            readOffset = (r + deficit) % capacity
        }
        let rawBuffer = UnsafeMutableRawPointer(buffer)
        let firstPart = min(byteCount, capacity - w)
        rawBuffer.advanced(by: w).copyMemory(from: data, byteCount: firstPart)
        if firstPart < byteCount {
            rawBuffer.copyMemory(from: data.advanced(by: firstPart), byteCount: byteCount - firstPart)
        }
        OSMemoryBarrier()
        writeOffset = (w + byteCount) % capacity
        return byteCount
    }
    
    @discardableResult
    func read(_ dest: UnsafeMutableRawPointer, byteCount: Int) -> Int {
        let r = readOffset; let w = writeOffset
        let available = w >= r ? (w - r) : (capacity - r + w)
        guard available >= byteCount else { return 0 }
        let rawBuffer = UnsafeRawPointer(buffer)
        let firstPart = min(byteCount, capacity - r)
        dest.copyMemory(from: rawBuffer.advanced(by: r), byteCount: firstPart)
        if firstPart < byteCount {
            dest.advanced(by: firstPart).copyMemory(from: rawBuffer, byteCount: byteCount - firstPart)
        }
        OSMemoryBarrier()
        readOffset = (r + byteCount) % capacity
        return byteCount
    }
    
    func clear() { writeOffset = 0; readOffset = 0; OSMemoryBarrier() }
}

// ─── Test Harness ───

var passed = 0
var failed = 0
var failures: [String] = []

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    if a != b {
        let m = msg.isEmpty ? "assertEqual: \(a) != \(b)" : "\(msg): \(a) != \(b)"
        failures.append("line \(line): \(m)")
    }
}

func assertTrue(_ cond: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    if !cond { failures.append("line \(line): \(msg.isEmpty ? "assertTrue failed" : msg)") }
}

func assertGT(_ a: Int, _ b: Int, _ msg: String = "", file: String = #file, line: Int = #line) {
    if a <= b { failures.append("line \(line): \(msg.isEmpty ? "\(a) <= \(b)" : "\(msg): \(a) <= \(b)")") }
}

func runTest(_ name: String, _ body: () -> Void) {
    let prev = failures.count
    body()
    if failures.count == prev { passed += 1; print("  ✅ \(name)") }
    else { failed += 1; print("  ❌ \(name)") }
}

// ─── Tests ───

print("━━━ RingBuffer Tests ━━━\n")

runTest("basic round-trip") {
    let rb = RingBuffer(capacity: 64)
    let src: [UInt8] = [1, 2, 3, 4, 5]
    let w = src.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: src.count) }
    assertEqual(w, 5)
    assertEqual(rb.bytesAvailableForRead, 5)
    var dst = [UInt8](repeating: 0, count: 5)
    let r = dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 5) }
    assertEqual(r, 5); assertEqual(dst, src)
}

runTest("read underflow returns 0") {
    let rb = RingBuffer(capacity: 64)
    [UInt8(10), 20].withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 2) }
    var dst = [UInt8](repeating: 0, count: 5)
    let r = dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 5) }
    assertEqual(r, 0); assertEqual(rb.bytesAvailableForRead, 2)
}

runTest("bytesAvailableForWrite") {
    let rb = RingBuffer(capacity: 16)
    assertEqual(rb.bytesAvailableForWrite, 15)
    [UInt8](repeating: 0xAA, count: 10).withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 10) }
    assertEqual(rb.bytesAvailableForWrite, 5)
}

runTest("write() drops when full") {
    let rb = RingBuffer(capacity: 8)
    [UInt8](repeating: 0xAA, count: 7).withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 7) }
    let w = [UInt8(0xBB)].withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 1) }
    assertEqual(w, 0, "write() drops data when full")
}

runTest("writeOverwriting: normal (has space)") {
    let rb = RingBuffer(capacity: 64)
    let src: [UInt8] = [1, 2, 3]
    let w = src.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 3) }
    assertEqual(w, 3)
    var dst = [UInt8](repeating: 0, count: 3)
    dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 3) }
    assertEqual(dst, src)
}

runTest("writeOverwriting: discards oldest when FULL ⭐") {
    let rb = RingBuffer(capacity: 8) // usable = 7
    [UInt8](1...7).withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 7) }
    assertEqual(rb.bytesAvailableForWrite, 0)

    let w = [UInt8](8...10).withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 3) }
    assertEqual(w, 3, "MUST succeed — this is THE FIX")
    assertEqual(rb.bytesAvailableForRead, 7)

    var dst = [UInt8](repeating: 0, count: 7)
    dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 7) }
    assertEqual(dst, [4, 5, 6, 7, 8, 9, 10])
}

runTest("writeOverwriting: partial space") {
    let rb = RingBuffer(capacity: 8)
    [UInt8](1...5).withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 5) }
    let w = [UInt8](10...13).withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 4) }
    assertEqual(w, 4)
    assertEqual(rb.bytesAvailableForRead, 7)
    var dst = [UInt8](repeating: 0, count: 7)
    dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 7) }
    assertEqual(dst, [3, 4, 5, 10, 11, 12, 13])
}

runTest("writeOverwriting: rejects byteCount >= capacity") {
    let rb = RingBuffer(capacity: 8)
    let w = [UInt8](repeating: 0xFF, count: 8).withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 8) }
    assertEqual(w, 0)
}

runTest("writeOverwriting: rejects zero") {
    let rb = RingBuffer(capacity: 8)
    let w = [UInt8(1)].withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 0) }
    assertEqual(w, 0)
}

runTest("wrap-around write/read") {
    let rb = RingBuffer(capacity: 8)
    [UInt8](repeating: 0xAA, count: 5).withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 5) }
    var t = [UInt8](repeating: 0, count: 5)
    t.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 5) }
    let b: [UInt8] = [1, 2, 3, 4, 5, 6, 7]
    b.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 7) }
    var dst = [UInt8](repeating: 0, count: 7)
    dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 7) }
    assertEqual(dst, b)
}

runTest("writeOverwriting: wrap-around") {
    let rb = RingBuffer(capacity: 8)
    [UInt8](repeating: 0, count: 5).withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 5) }
    var t = [UInt8](repeating: 0, count: 5)
    t.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 5) }
    [UInt8](1...7).withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 7) }
    [UInt8](8...10).withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 3) }
    var dst = [UInt8](repeating: 0, count: 7)
    dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 7) }
    assertEqual(dst, [4, 5, 6, 7, 8, 9, 10])
}

runTest("clear resets buffer") {
    let rb = RingBuffer(capacity: 16)
    [UInt8](repeating: 0xCC, count: 10).withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 10) }
    rb.clear()
    assertEqual(rb.bytesAvailableForRead, 0)
    assertEqual(rb.bytesAvailableForWrite, 15)
}

runTest("audio pipeline: writeOverwriting never starves reader ⭐") {
    let rb = RingBuffer(capacity: 8192)
    let chunk = 960
    var wd = [UInt8](repeating: 0, count: chunk)
    var rd = [UInt8](repeating: 0, count: chunk)

    for i in 0..<10 {
        wd[0] = UInt8(i & 0xFF)
        wd.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: chunk) }
    }
    assertGT(rb.bytesAvailableForRead, 0, "Buffer must have data")

    let avail = rb.bytesAvailableForRead
    let chunks = avail / chunk
    assertGT(chunks, 0, "Reader must find data")
    for _ in 0..<chunks {
        assertEqual(rd.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: chunk) }, chunk)
    }

    // Phase 3: Normal steady-state — write/read interleaved.
    // The key assertion: every read returns a full chunk. No starvation, no silence.
    let wptr = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
    let rptr = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)

    for i in 0..<100 {
        for j in 0..<chunk { wptr[j] = UInt8(i & 0xFF) }
        rb.writeOverwriting(wptr, byteCount: chunk)
        rptr.initialize(repeating: 0xFE, count: chunk)
        let r = rb.read(rptr, byteCount: chunk)
        assertEqual(r, chunk, "Steady-state: reader must always get data (no starvation)")
        // Data is FIFO-ordered: reads may return the PREVIOUS write's data,
        // which is correct ring buffer behavior — the important thing is r == chunk.
    }
    wptr.deallocate()
    rptr.deallocate()
}

runTest("write() causes starvation (documents the bug)") {
    let rb = RingBuffer(capacity: 4096)
    let chunk = 960
    var wd = [UInt8](repeating: 0xAA, count: chunk)
    var last = chunk
    while last > 0 { last = wd.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: chunk) } }
    wd = [UInt8](repeating: 0xBB, count: chunk)
    let dropped = wd.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: chunk) }
    assertEqual(dropped, 0, "write() drops when full — the bug")
}

runTest("writeOverwriting never drops under pressure (the fix) ⭐") {
    let rb = RingBuffer(capacity: 4096)
    let chunk = 960
    for i in 0..<20 {
        var wd = [UInt8](repeating: UInt8(i & 0xFF), count: chunk)
        wd.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: chunk) }
    }
    assertGT(rb.bytesAvailableForRead, 0, "Data available")
    var rd = [UInt8](repeating: 0, count: chunk)
    let r = rd.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: chunk) }
    assertEqual(r, chunk, "Reader gets full chunk")
}

// ─── Summary ───
print("\n━━━ Results ━━━")
print("\(passed + failed) tests: \(passed) passed, \(failed) failed")
if !failures.isEmpty { print("\nFailures:"); for f in failures { print("  ⚠️  \(f)") } }
exit(failed > 0 ? 1 : 0)

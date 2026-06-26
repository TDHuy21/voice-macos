import Foundation
@testable import Core

// Lightweight test runner — no XCTest/Testing dependency needed.
// Works with plain `swift test` on CLI-only (no Xcode) setups.

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    let file: String
    let line: Int
    var description: String { "\(file):\(line): \(message)" }
}

private var passed = 0
private var failed = 0
private var failures: [String] = []

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
    if a != b {
        let m = msg.isEmpty ? "assertEqual failed: \(a) != \(b)" : "\(msg): \(a) != \(b)"
        failures.append("\(file):\(line): \(m)")
        failed += 1
    }
}

func assertTrue(_ condition: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
    if !condition {
        let m = msg.isEmpty ? "assertTrue failed" : msg
        failures.append("\(file):\(line): \(m)")
        failed += 1
    }
}

func assertGreaterThan(_ a: Int, _ b: Int, _ msg: String = "", file: String = #file, line: Int = #line) {
    if a <= b {
        let m = msg.isEmpty ? "assertGreaterThan failed: \(a) <= \(b)" : "\(msg): \(a) <= \(b)"
        failures.append("\(file):\(line): \(m)")
        failed += 1
    }
}

func runTest(_ name: String, _ body: () -> Void) {
    let prevFailed = failed
    body()
    if failed == prevFailed {
        passed += 1
        print("  ✅ \(name)")
    } else {
        print("  ❌ \(name)")
    }
}

func printSummary() {
    print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
    for f in failures { print("  FAIL: \(f)") }
    if failed > 0 { exit(1) }
}

// ─────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────

print("RingBufferTests:")

runTest("basic round-trip") {
    let rb = RingBuffer(capacity: 64)
    let src: [UInt8] = [1, 2, 3, 4, 5]
    let written = src.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: src.count) }
    assertEqual(written, 5)
    assertEqual(rb.bytesAvailableForRead, 5)

    var dst = [UInt8](repeating: 0, count: 5)
    let readCount = dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 5) }
    assertEqual(readCount, 5)
    assertEqual(dst, src)
}

runTest("read underflow") {
    let rb = RingBuffer(capacity: 64)
    let src: [UInt8] = [10, 20]
    src.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 2) }

    var dst = [UInt8](repeating: 0, count: 5)
    let readCount = dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 5) }
    assertEqual(readCount, 0)
    assertEqual(rb.bytesAvailableForRead, 2, "data untouched")
}

runTest("bytesAvailableForWrite") {
    let rb = RingBuffer(capacity: 16) // usable = 15
    assertEqual(rb.bytesAvailableForWrite, 15)

    let src = [UInt8](repeating: 0xAA, count: 10)
    src.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 10) }
    assertEqual(rb.bytesAvailableForWrite, 5)
}

runTest("write() drops entire block when buffer is full") {
    let rb = RingBuffer(capacity: 8)
    let a = [UInt8](repeating: 0xAA, count: 7)
    a.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 7) }
    assertEqual(rb.bytesAvailableForWrite, 0)

    let b: [UInt8] = [0xBB]
    let wrote = b.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 1) }
    assertEqual(wrote, 0, "write() drops data when full")
}

runTest("writeOverwriting stores data when buffer has space") {
    let rb = RingBuffer(capacity: 64)
    let src: [UInt8] = [1, 2, 3]
    let wrote = src.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 3) }
    assertEqual(wrote, 3)

    var dst = [UInt8](repeating: 0, count: 3)
    dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 3) }
    assertEqual(dst, src)
}

runTest("writeOverwriting discards oldest data when full") {
    let rb = RingBuffer(capacity: 8) // usable = 7
    let a: [UInt8] = [1, 2, 3, 4, 5, 6, 7]
    a.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 7) }

    let b: [UInt8] = [8, 9, 10]
    let wrote = b.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 3) }
    assertEqual(wrote, 3, "writeOverwriting must succeed when full — THIS IS THE FIX")

    assertEqual(rb.bytesAvailableForRead, 7)
    var dst = [UInt8](repeating: 0, count: 7)
    dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 7) }
    assertEqual(dst, [4, 5, 6, 7, 8, 9, 10])
}

runTest("writeOverwriting partial space") {
    let rb = RingBuffer(capacity: 8)
    let a: [UInt8] = [1, 2, 3, 4, 5]
    a.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 5) }

    let b: [UInt8] = [10, 11, 12, 13]
    let wrote = b.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 4) }
    assertEqual(wrote, 4)

    assertEqual(rb.bytesAvailableForRead, 7)
    var dst = [UInt8](repeating: 0, count: 7)
    dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 7) }
    assertEqual(dst, [3, 4, 5, 10, 11, 12, 13])
}

runTest("writeOverwriting rejects byteCount >= capacity") {
    let rb = RingBuffer(capacity: 8)
    let big = [UInt8](repeating: 0xFF, count: 8)
    let wrote = big.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 8) }
    assertEqual(wrote, 0)
}

runTest("writeOverwriting rejects zero-length") {
    let rb = RingBuffer(capacity: 8)
    let src: [UInt8] = [1]
    let wrote = src.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 0) }
    assertEqual(wrote, 0)
}

runTest("wrap-around write/read") {
    let rb = RingBuffer(capacity: 8)
    let a = [UInt8](repeating: 0xAA, count: 5)
    a.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 5) }
    var trash = [UInt8](repeating: 0, count: 5)
    trash.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 5) }

    let b: [UInt8] = [1, 2, 3, 4, 5, 6, 7]
    b.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 7) }

    var dst = [UInt8](repeating: 0, count: 7)
    dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 7) }
    assertEqual(dst, b)
}

runTest("writeOverwriting wrap-around") {
    let rb = RingBuffer(capacity: 8)
    let padding = [UInt8](repeating: 0, count: 5)
    padding.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 5) }
    var trash = [UInt8](repeating: 0, count: 5)
    trash.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 5) }

    let a: [UInt8] = [1, 2, 3, 4, 5, 6, 7]
    a.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 7) }

    let b: [UInt8] = [8, 9, 10]
    b.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: 3) }

    var dst = [UInt8](repeating: 0, count: 7)
    dst.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: 7) }
    assertEqual(dst, [4, 5, 6, 7, 8, 9, 10])
}

runTest("clear resets buffer") {
    let rb = RingBuffer(capacity: 16)
    let src = [UInt8](repeating: 0xCC, count: 10)
    src.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: 10) }
    assertEqual(rb.bytesAvailableForRead, 10)
    rb.clear()
    assertEqual(rb.bytesAvailableForRead, 0)
    assertEqual(rb.bytesAvailableForWrite, 15)
}

runTest("audio pipeline: writeOverwriting never starves reader") {
    let rb = RingBuffer(capacity: 8192)
    let chunkSize = 960
    var writeData = [UInt8](repeating: 0, count: chunkSize)
    var readData = [UInt8](repeating: 0, count: chunkSize)

    // Phase 1: Writer runs ahead — 10 writes, 0 reads
    for i in 0..<10 {
        writeData[0] = UInt8(i & 0xFF)
        writeData.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: chunkSize) }
    }
    assertGreaterThan(rb.bytesAvailableForRead, 0, "Buffer must have data")

    // Phase 2: Reader catches up
    let available = rb.bytesAvailableForRead
    let chunksToRead = available / chunkSize
    assertGreaterThan(chunksToRead, 0, "Reader must find data — not starved")

    for _ in 0..<chunksToRead {
        let read = readData.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: chunkSize) }
        assertEqual(read, chunkSize)
    }

    // Phase 3: Steady-state
    for i in 0..<100 {
        writeData[0] = UInt8(i & 0xFF)
        writeData.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: chunkSize) }
        let read = readData.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: chunkSize) }
        assertEqual(read, chunkSize, "Steady-state: reader should always get data")
        assertEqual(readData[0], UInt8(i & 0xFF), "Data should be fresh")
    }
}

runTest("original write() causes starvation (the bug)") {
    let rb = RingBuffer(capacity: 4096)
    let chunkSize = 960
    var writeData = [UInt8](repeating: 0xAA, count: chunkSize)
    var lastWrote = chunkSize
    while lastWrote > 0 {
        lastWrote = writeData.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: chunkSize) }
    }
    writeData = [UInt8](repeating: 0xBB, count: chunkSize)
    let dropped = writeData.withUnsafeBytes { rb.write($0.baseAddress!, byteCount: chunkSize) }
    assertEqual(dropped, 0, "write() drops data when full — this is the bug")
}

runTest("writeOverwriting never drops under pressure (the fix)") {
    let rb = RingBuffer(capacity: 4096)
    let chunkSize = 960
    var readData = [UInt8](repeating: 0, count: chunkSize)

    for i in 0..<20 {
        var writeData = [UInt8](repeating: UInt8(i & 0xFF), count: chunkSize)
        writeData.withUnsafeBytes { rb.writeOverwriting($0.baseAddress!, byteCount: chunkSize) }
    }

    assertGreaterThan(rb.bytesAvailableForRead, 0, "writeOverwriting keeps data available")
    let read = readData.withUnsafeMutableBytes { rb.read($0.baseAddress!, byteCount: chunkSize) }
    assertEqual(read, chunkSize, "Reader gets a full chunk — no starvation")
}

printSummary()

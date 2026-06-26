import Foundation
import libkern // For OSMemoryBarrier

public final class RingBuffer: @unchecked Sendable {
    private let capacity: Int
    private let buffer: UnsafeMutablePointer<UInt8>
    
    private var writeOffset: Int = 0
    private var readOffset: Int = 0
    
    public init(capacity: Int) {
        self.capacity = capacity
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        self.buffer.initialize(repeating: 0, count: capacity)
    }
    
    deinit {
        buffer.deallocate()
    }
    
    public var bytesAvailableForRead: Int {
        OSMemoryBarrier()
        let w = writeOffset
        let r = readOffset
        if w >= r {
            return w - r
        } else {
            return capacity - r + w
        }
    }
    
    public var bytesAvailableForWrite: Int {
        return capacity - 1 - bytesAvailableForRead
    }
    
    @discardableResult
    public func write(_ data: UnsafeRawPointer, byteCount: Int) -> Int {
        let w = writeOffset
        let r = readOffset
        
        let available = capacity - 1 - (w >= r ? (w - r) : (capacity - r + w))
        guard available >= byteCount else {
            return 0 // Buffer full / not enough space
        }
        
        let rawBuffer = UnsafeMutableRawPointer(buffer)
        let firstPart = min(byteCount, capacity - w)
        rawBuffer.advanced(by: w).copyMemory(from: data, byteCount: firstPart)
        
        if firstPart < byteCount {
            let secondPart = byteCount - firstPart
            rawBuffer.copyMemory(from: data.advanced(by: firstPart), byteCount: secondPart)
        }
        
        OSMemoryBarrier() // Ensure data memory writes are visible before updating index
        writeOffset = (w + byteCount) % capacity
        return byteCount
    }
    
    /// Write data into the ring buffer, overwriting oldest unread data when full.
    ///
    /// Unlike `write()` which drops the entire incoming block when there isn't
    /// enough free space, this method advances the read pointer to discard the
    /// oldest samples and always stores the newest data. This is the correct
    /// behaviour for real-time audio capture where losing the *newest* samples
    /// causes permanent silence (the render thread starves).
    @discardableResult
    public func writeOverwriting(_ data: UnsafeRawPointer, byteCount: Int) -> Int {
        guard byteCount > 0 && byteCount < capacity else { return 0 }
        
        let w = writeOffset
        let r = readOffset
        let used = w >= r ? (w - r) : (capacity - r + w)
        let available = capacity - 1 - used
        
        // If not enough space, advance read pointer to free exactly what we need.
        if available < byteCount {
            let deficit = byteCount - available
            OSMemoryBarrier()
            readOffset = (r + deficit) % capacity
        }
        
        // Now write the data (same logic as write()).
        let rawBuffer = UnsafeMutableRawPointer(buffer)
        let firstPart = min(byteCount, capacity - w)
        rawBuffer.advanced(by: w).copyMemory(from: data, byteCount: firstPart)
        
        if firstPart < byteCount {
            let secondPart = byteCount - firstPart
            rawBuffer.copyMemory(from: data.advanced(by: firstPart), byteCount: secondPart)
        }
        
        OSMemoryBarrier()
        writeOffset = (w + byteCount) % capacity
        return byteCount
    }
    
    @discardableResult
    public func read(_ dest: UnsafeMutableRawPointer, byteCount: Int) -> Int {
        let r = readOffset
        let w = writeOffset
        
        let available = w >= r ? (w - r) : (capacity - r + w)
        guard available >= byteCount else {
            return 0 // Not enough data
        }
        
        let rawBuffer = UnsafeRawPointer(buffer)
        let firstPart = min(byteCount, capacity - r)
        dest.copyMemory(from: rawBuffer.advanced(by: r), byteCount: firstPart)
        
        if firstPart < byteCount {
            let secondPart = byteCount - firstPart
            dest.advanced(by: firstPart).copyMemory(from: rawBuffer, byteCount: secondPart)
        }
        
        OSMemoryBarrier() // Ensure reads are complete before updating index
        readOffset = (r + byteCount) % capacity
        return byteCount
    }
    
    public func clear() {
        writeOffset = 0
        readOffset = 0
        OSMemoryBarrier()
    }
}

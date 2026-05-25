import Foundation

final class RingBuffer {
    private var storage: [Float]
    private let capacity: Int
    private var writeIndex: Int = 0
    private var count: Int = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        self.storage = Array(repeating: 0, count: max(1, capacity))
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        count = 0
        storage.withUnsafeMutableBufferPointer { buffer in
            buffer.initialize(repeating: 0)
        }
    }

    func append(_ samples: UnsafeBufferPointer<Float>) {
        lock.lock()
        defer { lock.unlock() }
        for sample in samples {
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
            count = min(capacity, count + 1)
        }
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0 else { return [] }
        let start = (writeIndex - count + capacity) % capacity
        if start + count <= capacity {
            return Array(storage[start..<(start + count)])
        }
        let first = storage[start..<capacity]
        let second = storage[0..<(count - first.count)]
        return Array(first + second)
    }
}

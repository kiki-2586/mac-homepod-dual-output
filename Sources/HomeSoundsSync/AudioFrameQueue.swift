import Synchronization

/// One capture producer, one background consumer. Full queues drop NEW blocks;
/// the producer never overwrites storage while the consumer is reading it.
final class AudioFrameQueue {
    private let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    private let written = Atomic<Int64>(0)
    private let consumed = Atomic<Int64>(0)
    private let drops = Atomic<Int64>(0)
    var droppedFrames: Int64 { drops.load(ordering: .relaxed) }
    var queuedFrames: Int64 { written.load(ordering:.acquiring)-consumed.load(ordering:.acquiring) }
    init(capacityFrames: Int) {
        precondition(capacityFrames > 0)
        capacity = capacityFrames
        storage = .allocate(capacity: capacityFrames * 2)
        storage.initialize(repeating: 0, count: capacityFrames * 2)
    }
    deinit { storage.deallocate() }
    @discardableResult func push(_ source: UnsafePointer<Float>, frames: Int) -> Bool {
        guard frames > 0 else { return true }
        let w = written.load(ordering: .relaxed)
        let r = consumed.load(ordering: .acquiring)
        guard frames <= capacity, w-r+Int64(frames) <= Int64(capacity) else {
            drops.wrappingAdd(Int64(frames), ordering: .relaxed); return false
        }
        for frame in 0..<frames {
            let index = Int((w+Int64(frame)) % Int64(capacity))*2
            storage[index] = source[frame*2]; storage[index+1] = source[frame*2+1]
        }
        written.store(w+Int64(frames), ordering: .releasing)
        return true
    }
    func pop(maxFrames: Int) -> [Float] {
        let r = consumed.load(ordering: .relaxed)
        let count = min(maxFrames,Int(written.load(ordering: .acquiring)-r))
        guard count > 0 else { return [] }
        var result = [Float](repeating:0,count:count*2)
        for frame in 0..<count {
            let index = Int((r+Int64(frame)) % Int64(capacity))*2
            result[frame*2] = storage[index]; result[frame*2+1] = storage[index+1]
        }
        consumed.store(r+Int64(count),ordering:.releasing)
        return result
    }
    /// Only while producer and consumer are stopped.
    func reset() { written.store(0,ordering:.relaxed); consumed.store(0,ordering:.relaxed) }
}

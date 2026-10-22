import Foundation
import Darwin
import Synchronization

final class FifoFeed {
    private let path: String
    private let queue = AudioFrameQueue(capacityFrames: 384000)
    private let runningFlag = Atomic<Bool>(false)
    private let done = DispatchSemaphore(value: 0)
    private let connectedFlag = Atomic<Bool>(false)
    private let sentBytes = Atomic<Int64>(0)
    private var converter: PCM48kConverter?
    private var thread: Thread?
    private let failureCode = Atomic<Int>(0)
    private var maximumBacklog = 12000
    var discontinuityReason: String? {
        switch failureCode.load(ordering:.acquiring) {
        case 1:return "音频队列积压，原同步时间线已失效。请重新开始。"
        case 2:return "HomePod 后端音频管道已断开。"
        case 3:return "HomePod 后端停止接收音频。请重新开始。"
        case 4:return "音频格式转换失败。"
        default:return nil
        }
    }
    var connected: Bool { connectedFlag.load(ordering:.acquiring) }
    var bytesSent: Int64 { sentBytes.load(ordering:.relaxed) }
    var droppedFrames: Int64 { queue.droppedFrames }
    init(path: String) { self.path = path }
    deinit { stop() }
    func configure(inputSampleRate: Double) throws {
        precondition(!runningFlag.load(ordering:.acquiring))
        converter = try PCM48kConverter(inputSampleRate:inputSampleRate)
        maximumBacklog = Int(inputSampleRate * 0.25)
    }
    func feed(interleaved source: UnsafePointer<Float>, frames: Int) {
        guard runningFlag.load(ordering:.relaxed),failureCode.load(ordering:.relaxed)==0 else { return }
        if !queue.push(source,frames:frames) {failureCode.store(1,ordering:.releasing)}
    }
    func start() {
        guard thread == nil, !runningFlag.exchange(true,ordering:.acquiringAndReleasing), let converter else {
            if self.converter == nil { runningFlag.store(false,ordering:.releasing) }
            return
        }
        queue.reset(); sentBytes.store(0,ordering:.relaxed);failureCode.store(0,ordering:.releasing)
        let thread = Thread { [self] in writerLoop(converter); done.signal() }
        self.thread = thread
        thread.name = "local.mac-homepod.fifo"
        thread.start()
    }
    func stop() {
        guard thread != nil else { return }
        runningFlag.store(false,ordering:.releasing)
        done.wait()
        thread = nil
        connectedFlag.store(false,ordering:.releasing)
    }
    private func writerLoop(_ converter: PCM48kConverter) {
        var fd: Int32 = -1
        defer { if fd>=0 { close(fd) }; connectedFlag.store(false,ordering:.releasing) }
        while runningFlag.load(ordering:.acquiring),failureCode.load(ordering:.acquiring)==0 {
            if queue.queuedFrames > maximumBacklog {failureCode.store(1,ordering:.releasing);break}
            if fd<0 {
                fd = open(path,O_WRONLY|O_NONBLOCK)
                if fd<0 { usleep(10000); continue }
                _ = fcntl(fd,F_SETNOSIGPIPE,1)
                connectedFlag.store(true,ordering:.releasing)
            }
            let samples = queue.pop(maxFrames:2048)
            if samples.isEmpty { usleep(2000); continue }
            do {
                let pcm = try samples.withUnsafeBufferPointer { try converter.convert(interleaved:$0.baseAddress!,frames:samples.count/2) }
                let success = pcm.withUnsafeBytes { bytes -> Bool in
                    guard let base=bytes.baseAddress else { return true }
                    var offset=0
                    var progress=ProcessInfo.processInfo.systemUptime
                    while offset<bytes.count, runningFlag.load(ordering:.acquiring) {
                        let n=write(fd,base+offset,bytes.count-offset)
                        if n>0 { offset+=n; sentBytes.wrappingAdd(Int64(n),ordering:.relaxed);progress=ProcessInfo.processInfo.systemUptime }
                        else if n<0 && errno==EINTR { continue }
                        else if n<0 && (errno==EAGAIN || errno==EWOULDBLOCK) {
                            if ProcessInfo.processInfo.systemUptime-progress>0.25 {failureCode.store(3,ordering:.releasing);return false}
                            usleep(2000)
                        }
                        else { return false }
                    }
                    return offset==bytes.count
                }
                if !success {
                    if runningFlag.load(ordering:.acquiring),failureCode.load(ordering:.acquiring)==0 {failureCode.store(2,ordering:.releasing)}
                    break
                }
            } catch { DBG.log("FIFO conversion failed: \(error)"); failureCode.store(4,ordering:.releasing); break }
        }
    }
}

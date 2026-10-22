import Foundation
import Darwin
@main struct AudioPipelineTests {
 static func main() throws {
  for rate in [44100.0, 48000, 96000, 192000] {
   let converter = try PCM48kConverter(inputSampleRate: rate)
   var samples: [Int16] = []
   var offset = 0
   while offset < Int(rate) {
    let frames = min(511, Int(rate) - offset)
    let input = (0..<frames).flatMap { i -> [Float] in
     let v = Float(sin(2 * Double.pi * 1000 * Double(offset+i) / rate) * 0.5)
     return [v,v]
    }
    samples += try input.withUnsafeBufferPointer { try converter.convert(interleaved: $0.baseAddress!, frames: frames) }
    offset += frames
   }
   samples += try converter.finish()
   precondition(abs(samples.count / 2 - 48000) <= 64, "wrong rate conversion: \(rate), frames \(samples.count/2)")
   let left = stride(from: 4000, to: min(samples.count, 90000), by: 2).map { samples[$0] }
   let crossings = zip(left,left.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
   precondition((890...905).contains(crossings), "frequency changed: \(crossings)")
   print("PASS: \(Int(rate)) → 48000 Hz, \(samples.count/2) frames")
  }
  do { _ = try PCM48kConverter(inputSampleRate: 0); fatalError("accepted invalid rate") } catch {}
  let converter = try PCM48kConverter(inputSampleRate: 48000)
  let bad: [Float] = [.nan,.infinity,-.infinity,4,-4,0]
  let normalized = try bad.withUnsafeBufferPointer { try converter.convert(interleaved: $0.baseAddress!,frames:3) } + converter.finish()
  precondition(normalized.contains(0), "nonfinite input must become silence")
  let queue = AudioFrameQueue(capacityFrames: 4)
  let input: [Float] = [1,2,3,4,5,6,7,8]
  input.withUnsafeBufferPointer { precondition(queue.push($0.baseAddress!,frames:4)) }
  input.withUnsafeBufferPointer { precondition(!queue.push($0.baseAddress!,frames:1), "must not overwrite unread audio") }
  precondition(queue.pop(maxFrames:2) == [1,2,3,4])
  input.withUnsafeBufferPointer { precondition(queue.push($0.baseAddress!,frames:2)) }
  precondition(queue.pop(maxFrames:4) == [5,6,7,8,1,2,3,4])
  print("PASS: bounded FIFO preserves unread data and wrap order")
  let path = NSTemporaryDirectory() + "hp-fifo-" + UUID().uuidString
  precondition(mkfifo(path, 0o600) == 0)
  defer { unlink(path) }
  let fifo = FifoFeed(path:path)
  try fifo.configure(inputSampleRate:48000)
  fifo.start()
  let start = Date()
  fifo.stop()
  precondition(Date().timeIntervalSince(start)<1, "no-reader stop blocked")
  let fd = open(path,O_RDONLY|O_NONBLOCK)
  precondition(fd >= 0)
  fifo.start()
  let block = [Float](repeating:0.5,count:4096)
  block.withUnsafeBufferPointer { fifo.feed(interleaved:$0.baseAddress!,frames:2048) }
  usleep(100000)
  var bytes = [UInt8](repeating:0,count:8192)
  let n = read(fd,&bytes,bytes.count)
  precondition(n>0, "no PCM delivered")
  close(fd)
  block.withUnsafeBufferPointer { fifo.feed(interleaved:$0.baseAddress!,frames:2048) }
  usleep(50000)
  precondition(fifo.discontinuityReason != nil, "disconnect must invalidate calibrated session")
  fifo.stop()
  let reader = open(path,O_RDONLY|O_NONBLOCK)
  fifo.start()
  for _ in 0..<60 { block.withUnsafeBufferPointer { fifo.feed(interleaved:$0.baseAddress!,frames:2048) } }
  usleep(100000)
  let cancellation = Date()
  fifo.stop()
  precondition(Date().timeIntervalSince(cancellation)<1, "backpressured stop blocked")
  close(reader)
  print("PASS: FIFO no-reader cancellation, PCM delivery, reader disconnect, backpressure cancellation")
 }
}

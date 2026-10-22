import Foundation
import CoreAudio
@main struct CaptureConfigTests {
 static func main() throws {
  let tap = ProcessTapCapture.systemDescription(excluding: [42])
  precondition(tap.isExclusive, "must include all other processes, not just Music")
  precondition(tap.processes == [42], "must exclude our renderer")
  precondition(tap.isMixdown && !tap.isMono, "must produce stereo")
  precondition(tap.muteBehavior == .mutedWhenTapped, "original audio must recover when tap stops")
  let capture = ProcessTapCapture(ring: DelayRingBuffer(capacityFrames: 96000), fifo: nil)
  capture.stop(); capture.stop()
  print("PASS: global stereo capture exclusion, mute lifecycle, idempotent stop")
 }
}

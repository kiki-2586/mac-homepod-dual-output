import Foundation
import CoreAudio
@main struct CaptureConfigTests {
 static func main() throws {
  let tap = ProcessTapCapture.systemDescription(excluding: [42])
  precondition(tap.isExclusive, "must include all other processes, not just Music")
  precondition(tap.processes == [42], "must exclude our renderer")
  precondition(tap.isMixdown && !tap.isMono, "must produce stereo")
  precondition(tap.muteBehavior == .mutedWhenTapped, "original audio must recover when tap stops")
  let native = ProcessTapCapture.systemDescription(excluding: [42], mode: .nativeAirPlay)
  precondition(native.muteBehavior == .unmuted, "native HomePod audio must continue during capture")
  precondition(native.processes == [42] && native.isExclusive, "local delayed replay must not feed back")
  for channels: NativeChannelMode in [.macLeft, .macRight] {
   let split = ProcessTapCapture.systemDescription(excluding: [42], mode: .nativeAirPlay, channelMode: channels)
   guard split.muteBehavior == .mutedWhenTapped, split.isExclusive, split.processes == [42] else {
    print("FAIL: split must replace the original and exclude its own re-rendered audio"); exit(1)
   }
  }
  let capture = ProcessTapCapture(ring: DelayRingBuffer(capacityFrames: 96000), fifo: nil)
  capture.stop(); capture.stop()
  print("PASS: global stereo capture exclusion, mute lifecycle, idempotent stop")
 }
}

import Foundation

@main struct StereoOutputTests {
    static func main() {
        // Catch channel leakage, swapped routing, and gain steps at start/stop.
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "PASS" : "FAIL"): \(name)")
            if !condition { failures += 1 }
        }
        func rendered(_ input: [Float], channel: StereoChannel, gain: Float = 1) -> [Float] {
            var result = input
            var processor = StereoOutputProcessor(rampFrames: 0)
            result.withUnsafeMutableBufferPointer {
                processor.process($0.baseAddress!, frames: $0.count / 2, channel: channel, gain: gain)
            }
            return result
        }
        let input: [Float] = [0.25, -0.5, 0, 0.75, -0.25, 0]
        check("stereo preserves both independent source channels", rendered(input, channel: .stereo) == input)
        check("left output excludes all right-only signal", rendered(input, channel: .left) == [0.25, 0.25, 0, 0, -0.25, -0.25])
        check("right output excludes all left-only signal", rendered(input, channel: .right) == [-0.5, -0.5, 0.75, 0.75, 0, 0])
        check("software volume applies to the selected channel", rendered(input, channel: .left, gain: 0.5) == [0.125, 0.125, 0, 0, -0.125, -0.125])
        check("boost is bounded at the output", rendered([0.9, -0.9], channel: .stereo, gain: 1.5) == [1, -1])
        check("normal pair assigns L to Mac and R to AirPlay", NativeChannelMode.macLeft.localChannel == .left && NativeChannelMode.macLeft.airplayChannel == .right)
        check("swap assigns R to Mac and L to AirPlay", NativeChannelMode.macRight.localChannel == .right && NativeChannelMode.macRight.airplayChannel == .left)
        check("stereo follow does not replace the native stream", !NativeChannelMode.stereo.replacesNativeAudio)
        check("split permits exactly the built-in speaker", NativeChannelMode.macLeft.accepts(localUIDs: ["BuiltInSpeakerDevice"]))
        check("split rejects missing or additional local speakers", !NativeChannelMode.macLeft.accepts(localUIDs: []) && !NativeChannelMode.macLeft.accepts(localUIDs: ["BuiltInSpeakerDevice", "USB"]) && !NativeChannelMode.macLeft.accepts(localUIDs: ["USB"]))

        var processor = StereoOutputProcessor(rampFrames: 100)
        var silence = [Float](repeating: 0, count: 800)
        silence.withUnsafeMutableBufferPointer { processor.process($0.baseAddress!, frames: 400, channel: .stereo, gain: 1) }
        var attack = [Float](repeating: 1, count: 202)
        attack.withUnsafeMutableBufferPointer { processor.process($0.baseAddress!, frames: 101, channel: .stereo, gain: 1) }
        check("prefill silence does not consume the fade-in", attack[0] == 0 && attack[200] > 0.999)
        check("fade-in has no step larger than one ramp increment", zip(stride(from: 2, to: 202, by: 2), stride(from: 0, to: 200, by: 2)).allSatisfy { abs(attack[$0.0] - attack[$0.1]) <= 0.01001 })
        var release = [Float](repeating: 1, count: 202)
        release.withUnsafeMutableBufferPointer { processor.process($0.baseAddress!, frames: 101, channel: .stereo, gain: 0) }
        check("stop fades down instead of cutting a full-amplitude sample", release[0] > 0.999 && release[100] > 0.49 && release[100] < 0.51 && release[200] == 0)

        // Capture and AirPlay request different block sizes (observed 512/558).
        // A zero/sub-block buffer used to inject silent holes during steady play.
        let ring = DelayRingBuffer(capacityFrames: 48000 * 4)
        let reader = DelayReader(ring: ring)
        let source = [Float](repeating: 0.25, count: 1024)
        var output = [Float](repeating: 0, count: 1116)
        var nextCapture = 0, nextRender = 179, holes = 0
        while nextRender < 48000 * 10 {
            if nextCapture <= nextRender {
                source.withUnsafeBufferPointer { ring.write(interleaved: $0.baseAddress!, frames: 512) }
                nextCapture += 512
            } else {
                let delay = Int(NativeChannelMode.macLeft.airplayBufferMs * 48)
                output.withUnsafeMutableBufferPointer { reader.read(into: $0.baseAddress!, frames: 558, delayFrames: delay, resyncThreshold: 12000) }
                if nextRender > 48000 { holes += output.filter { $0 == 0 }.count }
                nextRender += 558
            }
        }
        check("native replay buffer prevents holes across 512/558 callback cadence", holes == 0)
        exit(failures == 0 ? 0 : 1)
    }
}

import Foundation

enum StereoChannel: Int { case stereo = -1, left = 0, right = 1 }

enum NativeChannelMode: String, CaseIterable {
    case stereo, macLeft, macRight
    var replacesNativeAudio: Bool { self != .stereo }
    var localChannel: StereoChannel { self == .stereo ? .stereo : (self == .macLeft ? .left : .right) }
    var airplayChannel: StereoChannel { self == .stereo ? .stereo : (self == .macLeft ? .right : .left) }
    // A single AirPlay render block underruns against the independent tap clock.
    // 40 ms eliminated holes in the 512/558-frame hardware trial.
    var airplayBufferMs: Double { 40 }
    var title: String {
        switch self {
        case .stereo: return "立体声同播"
        case .macLeft: return "Mac 左 · HomePod 右"
        case .macRight: return "Mac 右 · HomePod 左"
        }
    }
    func accepts(localUIDs: Set<String>) -> Bool {
        !replacesNativeAudio || localUIDs == ["BuiltInSpeakerDevice"]
    }
}

/// Audio-thread-owned channel selection and gain ramp. No allocation or locking.
/// Initial buffer silence must not consume the attack envelope.
struct StereoOutputProcessor {
    private let rampFrames: Int
    private var current: Float = 0
    private var target: Float = -1
    private var step: Float = 0
    private var remaining = 0
    private var started = false

    init(rampFrames: Int) { self.rampFrames = max(0, rampFrames) }

    mutating func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channel: StereoChannel, gain: Float) {
        let gain = max(0, min(1.5, gain))
        if gain != target {
            target = gain
            remaining = rampFrames
            step = remaining > 0 ? (target - current) / Float(remaining) : 0
            if remaining == 0 { current = target }
        }
        for frame in 0..<frames {
            var left = samples[frame * 2], right = samples[frame * 2 + 1]
            switch channel {
            case .stereo: break
            case .left: right = left
            case .right: left = right
            }
            if abs(left) > 0.0000001 || abs(right) > 0.0000001 { started = true }
            samples[frame * 2] = max(-1, min(1, left * current))
            samples[frame * 2 + 1] = max(-1, min(1, right * current))
            if started && remaining > 0 {
                remaining -= 1
                current = remaining == 0 ? target : current + step
            }
        }
    }
}

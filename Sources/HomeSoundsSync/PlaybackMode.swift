import Foundation

enum PlaybackMode: String {
    case relay
    case nativeAirPlay

    var usesBackend: Bool { self == .relay }
    func delayKey(for uid: String) -> String {
        self == .relay ? "delay." + uid : "nativeDelay." + uid
    }
}

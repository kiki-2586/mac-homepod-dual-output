import Foundation

/// Main-thread session generation also tags discovery and asynchronous teardown.
final class PlaybackLifecycle {
    enum Phase {case idle,starting,running,stopping}
    private(set) var phase:Phase = .idle
    private(set) var generation=0
    func isCurrent(_ token:Int)->Bool{generation==token}
    func beginStart()->Int?{
        guard phase == .idle else{return nil}
        generation+=1;phase = .starting;return generation
    }
    func beginStop()->Int{generation+=1;phase = .stopping;return generation}
    func finishStart(_ token:Int,running:Bool){guard isCurrent(token) else{return};phase=running ? .running:.idle}
    func finishStop(_ token:Int){guard isCurrent(token) else{return};phase = .idle}
}

final class AudioFlowMonitor {
    enum State {case waiting,flowing,stalled}
    private var frames:Int64=0,bytes:Int64=0
    private var started=0.0,captureProgress=0.0,sendProgress=0.0
    private var sawCapture=false,sawSend=false
    private var requiresBackend=true
    private var startupTimeout=45.0
    func begin(frames:Int64,bytes:Int64,now:Double,requiresBackend:Bool=true,startupTimeout:Double=45){
        self.requiresBackend=requiresBackend
        self.startupTimeout=startupTimeout
        self.frames=frames;self.bytes=bytes;started=now
        captureProgress=now;sendProgress=now;sawCapture=false;sawSend=false
    }
    func evaluate(frames:Int64,bytes:Int64,connected:Bool,now:Double)->State{
        if frames>self.frames{captureProgress=now;sawCapture=true}
        if bytes>self.bytes{sendProgress=now;sawSend=true}
        self.frames=frames;self.bytes=bytes
        if !requiresBackend {
            if sawCapture {return now-captureProgress<6 ? .flowing:.stalled}
            return now-started>startupTimeout ? .stalled:.waiting
        }
        let healthy=connected && sawCapture && sawSend && now-captureProgress<6 && now-sendProgress<6
        if healthy{return .flowing}
        if sawCapture && sawSend {
            if now-captureProgress>6 || now-sendProgress>6 || !connected{return .stalled}
        } else if now-started>startupTimeout{return .stalled}
        return .waiting
    }
}

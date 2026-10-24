import Foundation
@main struct PlaybackLifecycleTests {
 static func main() {
  let lifecycle=PlaybackLifecycle()
  let first=lifecycle.beginStart()!
  precondition(lifecycle.isCurrent(first))
  let stop=lifecycle.beginStop()
  precondition(!lifecycle.isCurrent(first),"stopped startup can still capture")
  precondition(lifecycle.beginStart()==nil,"start allowed while deselection is pending")
  lifecycle.finishStop(stop)
  let second=lifecycle.beginStart()!
  precondition(lifecycle.isCurrent(second))
  lifecycle.finishStop(stop)
  precondition(lifecycle.isCurrent(second),"old teardown changed new session")
  lifecycle.finishStart(second,running:true)
  precondition(lifecycle.phase == .running)
  let monitor=AudioFlowMonitor()
  monitor.begin(frames:0,bytes:0,now:0)
  precondition(monitor.evaluate(frames:1,bytes:4,connected:true,now:1) == .flowing)
  precondition(monitor.evaluate(frames:1,bytes:4,connected:true,now:14) == .stalled,"lifetime counters concealed stalled capture")
  monitor.begin(frames:0,bytes:0,now:0)
  _=monitor.evaluate(frames:1,bytes:4,connected:true,now:1)
  precondition(monitor.evaluate(frames:200,bytes:4,connected:true,now:14) == .stalled,"blocked FIFO concealed by live capture")
  monitor.begin(frames:0,bytes:0,now:0)
  precondition(monitor.evaluate(frames:1,bytes:0,connected:false,now:2) == .waiting)
  // Native AirPlay owns the remote path: local capture must not wait for a FIFO.
  monitor.begin(frames:0,bytes:0,now:0,requiresBackend:false)
  precondition(monitor.evaluate(frames:48000,bytes:0,connected:false,now:1) == .flowing,
               "native follow incorrectly requires an OwnTone connection")
  precondition(monitor.evaluate(frames:48000,bytes:0,connected:false,now:8) == .stalled,
               "native follow concealed stopped capture")
  monitor.begin(frames:0,bytes:0,now:0,requiresBackend:false)
  precondition(monitor.evaluate(frames:0,bytes:0,connected:false,now:46) == .stalled)
  // Replacing native audio must restore quickly if capture never starts.
  monitor.begin(frames:0,bytes:0,now:0,requiresBackend:false,startupTimeout:6)
  guard monitor.evaluate(frames:0,bytes:0,connected:false,now:7) == .stalled else {
   print("FAIL: native split must not leave original audio muted for the normal 45-second startup timeout"); exit(1)
  }
  // A new normal follow session gets its original permission-prompt grace period.
  monitor.begin(frames:0,bytes:0,now:0,requiresBackend:false)
  precondition(monitor.evaluate(frames:0,bytes:0,connected:false,now:7) == .waiting)
  // Switching back must restore the remote-path requirement.
  monitor.begin(frames:0,bytes:0,now:0)
  precondition(monitor.evaluate(frames:48000,bytes:0,connected:false,now:1) == .waiting)
  print("PASS: stopped startup invalidated, teardown serializes restart, stale response isolation, post-flow stall detection")
 }
}

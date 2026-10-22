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
  print("PASS: stopped startup invalidated, teardown serializes restart, stale response isolation, post-flow stall detection")
 }
}

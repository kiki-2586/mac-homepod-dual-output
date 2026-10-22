import Foundation
import Darwin
@main struct ServiceFilesystemTests {
 static func main() throws {
  let root=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("hp-service-"+UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:root)}
  try OwnToneService.prepareDirectories(at:root)
  let pipe=root.appendingPathComponent("media/system.pipe").path
  var metadata=stat();precondition(lstat(pipe,&metadata)==0 && (metadata.st_mode&S_IFMT)==S_IFIFO)
  try OwnToneService.prepareDirectories(at:root)
  unlink(pipe)
  try Data("keep me".utf8).write(to:URL(fileURLWithPath:pipe))
  do{try OwnToneService.prepareDirectories(at:root);fatalError("overwrote ordinary file")}catch{}
  let preserved=try String(contentsOfFile:pipe,encoding:.utf8)
  precondition(preserved=="keep me")
  unlink(pipe);symlink("/tmp/unrelated",pipe)
  do{try OwnToneService.prepareDirectories(at:root);fatalError("accepted symlink")}catch{}
  let child=Process();child.executableURL=URL(fileURLWithPath:"/usr/local/bin/python3")
  child.arguments=["-u","-c","import signal,time;signal.signal(signal.SIGTERM,signal.SIG_IGN);print(1,flush=True);time.sleep(120)"]
  let output=Pipe();child.standardOutput=output;try child.run()
  _=output.fileHandleForReading.readData(ofLength:2)
  let before=Date()
  ProcessTermination.stop(child,grace:0.1)
  precondition(!child.isRunning && Date().timeIntervalSince(before)<1,"backend termination blocked")
  print("PASS: private FIFO creation, file and symlink preservation, bounded unresponsive backend termination")
 }
}

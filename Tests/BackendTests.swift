import Foundation
@main struct BackendTests {
 static func main() async throws {
  let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/local/bin/python3")
  process.arguments=["-u","Tests/mock_server.py"]
  let pipe=Pipe();process.standardOutput=pipe;try process.run()
  defer {process.terminate();process.waitUntilExit()}
  var line=Data()
  while true { let b=pipe.fileHandleForReading.readData(ofLength:1);if b.isEmpty { throw NSError(domain:"test-server",code:1) };if b==Data([10]){break};line.append(b) }
  let port=Int(String(data:line,encoding:.utf8)!)!
  let base=URL(string:"http://127.0.0.1:\(port)")!
  let client=OwnToneClient(baseURL:base)
  let outputs=try await client.airplayOutputs()
  precondition(outputs.count==1 && outputs[0].id=="speaker-1")
  try await client.setVolume(id:"a/b ?",volume:999)
  let (data,_)=try await URLSession.shared.data(from:base.appendingPathComponent("last"))
  let last=try JSONSerialization.jsonObject(with:data) as! [String:Any]
  precondition((last["body"] as! [String:Int])["volume"]==100)
  precondition((last["path"] as! String).contains("a%2Fb%20%3F"),"unsafe output id path")
  do { _=try await OwnToneClient(baseURL:base.appendingPathComponent("bad")).airplayOutputs();fatalError("500 was swallowed") } catch {}
  do { _=try await OwnToneClient(baseURL:base.appendingPathComponent("invalid")).airplayOutputs();fatalError("invalid JSON was swallowed") } catch {}
  print("PASS: AirPlay output filtering, encoded IDs, volume bounds, HTTP failures, schema failures")
 }
}

import Foundation
import Darwin

enum ProcessTermination {
    /// Only used for this application's own independently launched backend.
    static func stop(_ process:Process,grace:TimeInterval=1) {
        guard process.isRunning else{return}
        process.terminate()
        let deadline=ProcessInfo.processInfo.systemUptime+grace
        while process.isRunning,ProcessInfo.processInfo.systemUptime<deadline{usleep(10000)}
        if process.isRunning{_ = kill(process.processIdentifier,SIGKILL)}
        process.waitUntilExit()
    }
}

import Foundation
import Darwin

final class OwnToneService {
    static let bufferDurationMS = 500
    static var dataDirectory: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("MacHomePod",isDirectory:true)
    }
    enum ServiceError: LocalizedError {
        case missingBackend, unsafePipe, launch(String)
        var errorDescription: String? {
            switch self {
            case .missingBackend:return "未找到 OwnTone 后端，请使用完整构建版本。"
            case .unsafePipe:return "音频管道路径被普通文件或链接占用，已停止以避免覆盖文件。"
            case .launch(let reason):return "无法启动 HomePod 后端：\(reason)"
            }
        }
    }
    private var process: Process?
    private var logHandle: FileHandle?
    var isRunning: Bool {process?.isRunning == true}
    var exitStatus: Int32? {guard let process,!process.isRunning else{return nil};return process.terminationStatus}
    static var logURL: URL {dataDirectory.appendingPathComponent("backend.log")}
    var backendURL: URL? {
        if let resources=Bundle.main.resourceURL {
            let url=resources.appendingPathComponent("backend/usr/sbin/owntone")
            if FileManager.default.isExecutableFile(atPath:url.path){return url}
        }
        return nil
    }
    func start() throws {
        if isRunning {return}
        guard let binary=backendURL else{throw ServiceError.missingBackend}
        stop()
        let directory=Self.dataDirectory
        try Self.prepareDirectories(at:directory)
        let config=directory.appendingPathComponent("owntone.conf")
        try Self.configuration(at:directory).write(to:config,atomically:true,encoding:.utf8)
        FileManager.default.createFile(atPath:Self.logURL.path,contents:nil)
        let log=try FileHandle(forWritingTo:Self.logURL);try log.seekToEnd()
        let child=Process();child.executableURL=binary
        let sqliteModule=binary.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("lib/owntone-sqlext.so")
        child.arguments=["-f","-c",config.path,"-s",sqliteModule.path,"-P",directory.appendingPathComponent("owntone.pid").path]
        child.standardOutput=log;child.standardError=log
        do {try child.run()} catch {try? log.close();throw ServiceError.launch(error.localizedDescription)}
        logHandle=log;process=child
    }
    func stop() {
        if let process {ProcessTermination.stop(process)}
        process=nil;try? logHandle?.close();logHandle=nil
    }
    deinit {stop()}
    static func prepareDirectories(at directory: URL) throws {
        for sub in ["", "media", "cache"] {
            try FileManager.default.createDirectory(at:directory.appendingPathComponent(sub),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        }
        let path=directory.appendingPathComponent("media/system.pipe").path
        var information=stat()
        if lstat(path,&information)==0 {
            guard (information.st_mode & S_IFMT)==S_IFIFO else{throw ServiceError.unsafePipe}
        } else {
            guard errno==ENOENT, mkfifo(path,0o600)==0 else{throw ServiceError.unsafePipe}
        }
    }
    static func configuration(at directory: URL) -> String {
        func quote(_ s: String)->String{s.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")}
        let root=quote(directory.path)
        return """
        general {
          uid = "\(quote(NSUserName()))"
          db_path = "\(root)/cache/songs3.db"
          cache_dir = "\(root)/cache"
          logfile = "\(root)/backend.log"
          loglevel = info
          bind_address = "127.0.0.1"
          trusted_networks = { "localhost" }
          websocket_port = 0
          speaker_autoselect = no
          start_buffer_ms = \(Self.bufferDurationMS)
        }
        library {
          name = "Mac HomePod"
          port = 3689
          directories = { "\(root)/media" }
          pipe_autostart = true
          pipe_sample_rate = 48000
          pipe_bits_per_sample = 16
        }
        audio { type = "disabled" }
        """
    }
}

import Foundation

struct OwnToneClient {
    struct Output: Decodable {
        let id: String
        let name: String
        let type: String
        let selected: Bool
        let volume: Int
    }
    enum ClientError: LocalizedError {
        case http(Int), invalidResponse
        var errorDescription: String? {
            switch self {
            case .http(let code): return "HomePod 后端请求失败（HTTP \(code)）。"
            case .invalidResponse: return "HomePod 后端返回的数据格式不正确。"
            }
        }
    }
    let baseURL: URL
    let session: URLSession
    init(baseURL: URL = URL(string:"http://127.0.0.1:3689")!, session: URLSession = .shared) {
        self.baseURL=baseURL; self.session=session
    }
    func airplayOutputs() async throws -> [Output] {
        struct Response: Decodable { let outputs: [Output] }
        let data=try await request(path:"/api/outputs")
        return try JSONDecoder().decode(Response.self,from:data).outputs.filter { $0.type.hasPrefix("AirPlay") }
    }
    func setSelected(id: String, on: Bool) async throws {
        _=try await request(path:outputPath(id),body:JSONSerialization.data(withJSONObject:["selected":on]))
    }
    func setVolume(id: String, volume: Int) async throws {
        _=try await request(path:outputPath(id),body:JSONSerialization.data(withJSONObject:["volume":max(0,min(100,volume))]))
    }
    private func outputPath(_ id: String) -> String {
        let allowed=CharacterSet.alphanumerics.union(CharacterSet(charactersIn:"-._~"))
        return "/api/outputs/"+(id.addingPercentEncoding(withAllowedCharacters:allowed) ?? "")
    }
    private func request(path: String, body: Data? = nil) async throws -> Data {
        var components=URLComponents(url:baseURL,resolvingAgainstBaseURL:false)!
        components.percentEncodedPath=components.percentEncodedPath+path
        guard let url=components.url else {throw ClientError.invalidResponse}
        var request=URLRequest(url:url);request.timeoutInterval=3
        if let body {request.httpMethod="PUT";request.httpBody=body;request.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let (data,response)=try await session.data(for:request)
        guard let response=response as? HTTPURLResponse else {throw ClientError.invalidResponse}
        guard (200..<300).contains(response.statusCode) else {throw ClientError.http(response.statusCode)}
        return data
    }
}

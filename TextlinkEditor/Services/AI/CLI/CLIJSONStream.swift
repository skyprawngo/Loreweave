import Foundation

/// JSONL is framed as bytes, so a pipe read may split any UTF-8 scalar safely.
struct CLIJSONStream {
    private var pending = Data()
    private(set) var response = ""
    private(set) var usage: AIContextUsage?
    private(set) var sessionId: String?
    private(set) var completed = false
    private(set) var failed = false
    private(set) var malformed = false
    private(set) var authenticationFailure = false

    mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var chunks: [String] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            if let chunk = consume(line) { chunks.append(chunk) }
        }
        return chunks
    }

    mutating func finish() {
        if !pending.isEmpty { _ = consume(pending); pending.removeAll() }
    }

    private mutating func consume(_ line: Data) -> String? {
        guard !line.isEmpty else { return nil }
        guard let json = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            malformed = true
            return nil
        }
        if let reported = AIContextUsage.parse(json) { usage = reported }
        if let id = json["session_id"] as? String { sessionId = id }
        switch json["type"] as? String {
        case "thread.started":
            sessionId = json["thread_id"] as? String
        case "item.completed":
            if let item = json["item"] as? [String: Any], item["type"] as? String == "agent_message",
               let text = item["text"] as? String {
                let chunk = response.isEmpty ? text : "\n\n" + text
                response += chunk
                return chunk
            }
        case "turn.completed": completed = true
        case "turn.failed", "error":
            failed = true
            authenticationFailure = Self.isAuthenticationFailure(String(decoding: line, as: UTF8.self))
        case "stream_event":
            if let event = json["event"] as? [String: Any],
               let delta = event["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta", let text = delta["text"] as? String {
                response += text
                return text
            }
        case "result":
            completed = true
            failed = json["is_error"] as? Bool == true || (json["subtype"] as? String).map { $0 != "success" } == true
            if let result = json["result"] as? String { response = result }
            if failed { authenticationFailure = Self.isAuthenticationFailure(String(decoding: line, as: UTF8.self)) }
        default: break
        }
        return nil
    }
    static func isAuthenticationFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["authentication", "not logged in", "login required", "please log in", "invalid api key", "unauthorized"].contains(where: lower.contains)
    }

}


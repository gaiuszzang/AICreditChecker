import Foundation

/// 한 개의 사용량 게이지 (예: 월 크레딧, 5시간 한도, 주간 한도)
struct UsageMeter: Identifiable {
    enum Kind {
        case money(used: Double, limit: Double, currency: String)
        case percentOnly
    }

    let id = UUID()
    let title: String
    let kind: Kind
    let percent: Double   // 0...100
    let resetAt: Date?
}

struct ProviderUsage {
    let plan: String?
    let meters: [UsageMeter]
}

enum ProviderState {
    case loading
    case notInstalled
    case notLoggedIn(String)
    case expired(String)
    case error(String)
    case ok(ProviderUsage)

    var usage: ProviderUsage? {
        if case .ok(let u) = self { return u }
        return nil
    }
}

enum Provider: String, CaseIterable, Identifiable {
    case claude = "Claude Code"
    case codex = "Codex"
    case grok = "Grok"
    case antigravity = "Antigravity"
    var id: String { rawValue }

    var executable: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        case .grok: "grok"
        case .antigravity: "agy"
        }
    }

    /// 토큰 만료 시 CLI가 스스로 갱신하도록 실행할 인자 목록. 사용량을 쓰지 않는 명령부터 시도한다.
    var renewCommands: [[String]] {
        switch self {
        case .claude: ClaudeProvider.renewCommands
        case .codex: CodexProvider.renewCommands
        case .grok: GrokProvider.renewCommands
        case .antigravity: AntigravityProvider.renewCommands
        }
    }
}

enum ProviderError: Error {
    case http(Int)
    case badResponse
}

// MARK: - 공용 헬퍼

enum Env {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// GUI 앱은 PATH가 최소한이라 대표 설치 경로를 직접 확인
    static func findExecutable(_ name: String) -> String? {
        let dirs = [
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".claude/local").path,
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".grok/bin").path,
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
        ]
        let fm = FileManager.default
        return dirs.map { "\($0)/\(name)" }.first { fm.isExecutableFile(atPath: $0) }
    }

    static func run(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// CLI를 비대화형으로 실행하고 끝날 때까지 기다린다. 제한 시간을 넘기면 종료시키고 false.
    static func runCLI(_ path: String, _ args: [String], timeout: TimeInterval) async -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.currentDirectoryURL = FileManager.default.temporaryDirectory
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = ([URL(fileURLWithPath: path).deletingLastPathComponent().path, env["PATH"] ?? ""]
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]).joined(separator: ":")
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice

        return await withCheckedContinuation { cont in
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus == 0) }
            do { try p.run() } catch {
                p.terminationHandler = nil
                cont.resume(returning: false)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if p.isRunning { p.terminate() }
            }
        }
    }

    static func getJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await URLSession.shared.data(for: request)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ProviderError.http(code) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.badResponse
        }
        return obj
    }
}

func num(_ v: Any?) -> Double? {
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) }
    return nil
}

func isoDate(_ v: Any?) -> Date? {
    guard let s = v as? String else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}

/// 다음 달 1일 0시 (월간 한도 초기화 시점 추정용)
func startOfNextMonth() -> Date? {
    let cal = Calendar.current
    guard let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) else { return nil }
    return cal.date(byAdding: .month, value: 1, to: start)
}

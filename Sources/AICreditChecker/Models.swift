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
    var id: String { rawValue }
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

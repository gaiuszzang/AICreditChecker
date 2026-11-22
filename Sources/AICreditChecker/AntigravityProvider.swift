import Foundation

/// Antigravity CLI(agy) 로그인 정보(macOS 키체인)로 모델 사용량 조회. 토큰은 읽기만 함.
enum AntigravityProvider {
    private enum LoadedToken {
        case missing
        case expired
        case ready(String)
    }

    private struct Probe {
        var json: [String: Any]?
        var status: Int?
        var network = false
    }

    private static let base = "https://daily-cloudcode-pa.googleapis.com/v1internal:"

    static let renewCommands = [["models"]]

    static func fetch() async -> ProviderState {
        let installed = Env.findExecutable("agy") != nil
            || FileManager.default.fileExists(atPath: Env.home.appendingPathComponent(".gemini/antigravity-cli").path)
        guard installed else { return .notInstalled }

        switch loadToken() {
        case .missing:
            return .notLoggedIn("터미널에서 agy 실행 후 로그인하세요")
        case .expired:
            return .expired("토큰 만료 · agy 를 한 번 실행하면 갱신돼요")
        case .ready(let token):
            async let summary = probe("retrieveUserQuotaSummary", token: token)
            async let quota = probe("retrieveUserQuota", token: token)
            async let assist = probe("loadCodeAssist", token: token, body: ["metadata": ["ideType": "ANTIGRAVITY"]])
            let (s, q, a) = await (summary, quota, assist)

            if s.status == 401 || q.status == 401 {
                return .expired("토큰 만료 · agy 를 한 번 실행하면 갱신돼요")
            }
            guard s.json != nil || q.json != nil else {
                if s.network && q.network { return .error("네트워크 오류") }
                return .error("조회 실패 (HTTP \(s.status ?? q.status ?? 0))")
            }
            return .ok(ProviderUsage(plan: plan(a.json), meters: parse(summary: s.json, quota: q.json)))
        }
    }

    /// 모델별 응답의 Gemini 한도를 먼저, 요약 응답의 그룹별(Claude·GPT 등) 5시간·주간 한도를 다음에 게이지로 바꾼다.
    /// 응답은 남은 비율(`remainingFraction`, 0...1)이라 사용률로 뒤집는다.
    static func parse(summary: [String: Any]?, quota: [String: Any]?) -> [UsageMeter] {
        var meters: [UsageMeter] = []

        // Gemini 모델은 요약에 없고 모델별로 같은 한도를 공유한다. 가장 많이 쓴 값을 보여 준다.
        let gemini = (quota?["buckets"] as? [[String: Any]] ?? []).filter {
            ($0["modelId"] as? String)?.hasPrefix("gemini") == true && num($0["remainingFraction"]) != nil
        }
        if let worst = gemini.min(by: { num($0["remainingFraction"])! < num($1["remainingFraction"])! }) {
            meters.append(UsageMeter(
                title: "Gemini 모델",
                kind: .percentOnly,
                percent: (1 - num(worst["remainingFraction"])!) * 100,
                resetAt: isoDate(worst["resetTime"])
            ))
        }

        for group in summary?["groups"] as? [[String: Any]] ?? [] {
            let name = groupLabel(group["displayName"] as? String)
            let buckets = (group["buckets"] as? [[String: Any]] ?? []).sorted {
                windowOrder($0["window"]) < windowOrder($1["window"])
            }
            for bucket in buckets {
                guard let remaining = num(bucket["remainingFraction"]) else { continue }
                meters.append(UsageMeter(
                    title: "\(name) · \(windowLabel(bucket))",
                    kind: .percentOnly,
                    percent: (1 - remaining) * 100,
                    resetAt: isoDate(bucket["resetTime"])
                ))
            }
        }
        return meters
    }

    private static func loadToken() -> LoadedToken {
        // agy는 go-keyring으로 저장하며 security CLI가 ACL에 포함돼 있어 권한 팝업이 뜨지 않음
        guard var raw = Env.run("/usr/bin/security", ["find-generic-password", "-s", "gemini", "-a", "antigravity", "-w"])
        else { return .missing }
        let prefix = "go-keyring-base64:"
        if raw.hasPrefix(prefix) {
            guard let decoded = Data(base64Encoded: String(raw.dropFirst(prefix.count))),
                  let text = String(data: decoded, encoding: .utf8) else { return .missing }
            raw = text
        }
        guard let data = raw.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = root["token"] as? [String: Any],
              let access = token["access_token"] as? String, !access.isEmpty
        else { return .missing }

        if let exp = expiry(token["expiry"]), exp <= Date() { return .expired }
        return .ready(access)
    }

    /// Go가 기록한 만료 시각은 소수점 이하가 6자리 이상이라 ISO8601DateFormatter가 못 읽는 경우가 있다.
    private static func expiry(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        if let d = isoDate(s) { return d }
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return isoDate(trimmed)
    }

    private static func probe(_ method: String, token: String, body: [String: Any] = [:]) async -> Probe {
        var req = URLRequest(url: URL(string: base + method)!)
        req.httpMethod = "POST"
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("antigravity AICreditChecker", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        do {
            return Probe(json: try await Env.getJSON(req))
        } catch ProviderError.http(let code) {
            return Probe(status: code)
        } catch {
            return Probe(network: true)
        }
    }

    private static func plan(_ json: [String: Any]?) -> String? {
        let tier = json?["paidTier"] as? [String: Any] ?? json?["currentTier"] as? [String: Any]
        return tier?["name"] as? String
    }

    private static func groupLabel(_ raw: String?) -> String {
        switch raw {
        case "Claude and GPT models": return "Other 모델"
        case let s?: return s
        case nil: return "모델"
        }
    }

    private static func windowOrder(_ window: Any?) -> Int {
        switch window as? String {
        case "5h": return 0
        case "daily": return 1
        case "weekly": return 2
        default: return 3
        }
    }

    private static func windowLabel(_ bucket: [String: Any]) -> String {
        switch bucket["window"] as? String {
        case "5h": return "5시간 한도"
        case "daily": return "일간 한도"
        case "weekly": return "주간 한도"
        default: return (bucket["displayName"] as? String) ?? "한도"
        }
    }
}

import Foundation

/// Grok CLI 로그인 정보(~/.grok/auth.json)로 구독 사용량 조회. 토큰은 읽기만 함.
enum GrokProvider {
    private enum LoadedToken {
        case missing
        case expired
        case ready(String)
    }

    private struct Probe {
        var config: [String: Any]?
        var status: Int?
        var network = false
    }

    static func fetch() async -> ProviderState {
        let home = ProcessInfo.processInfo.environment["GROK_HOME"].map { URL(fileURLWithPath: $0) }
            ?? Env.home.appendingPathComponent(".grok")
        let installed = Env.findExecutable("grok") != nil
            || FileManager.default.isExecutableFile(atPath: home.appendingPathComponent("bin/grok").path)
            || FileManager.default.fileExists(atPath: home.path)
        guard installed else { return .notInstalled }

        switch loadToken(home) {
        case .missing:
            return .notLoggedIn("터미널에서 grok login 하세요")
        case .expired:
            return .error("토큰 만료 · grok 를 한 번 실행하면 갱신돼요")
        case .ready(let token):
            guard let weeklyURL = billingURL("/billing?format=credits"),
                  let monthlyURL = billingURL("/billing")
            else { return .error("조회 실패") }

            let version = clientVersion(home)
            async let weekly = probe(request(weeklyURL, token: token, version: version))
            async let monthly = probe(request(monthlyURL, token: token, version: version))
            let (w, m) = await (weekly, monthly)

            if w.status == 401 || m.status == 401 {
                return .error("토큰 만료 · grok 를 한 번 실행하면 갱신돼요")
            }
            guard w.config != nil || m.config != nil else {
                if w.network && m.network { return .error("네트워크 오류") }
                return .error("조회 실패 (HTTP \(w.status ?? m.status ?? 0))")
            }
            return .ok(ProviderUsage(plan: nil, meters: parse(weekly: w.config, monthly: m.config)))
        }
    }

    /// 주간 크레딧 응답과 월간 포함 한도 응답을 게이지로 바꾼다.
    /// 금액 필드 `val`은 센트다. 한도가 0이면 주간 비율만 쓰는 계정이라 금액 바를 만들지 않는다.
    static func parse(weekly: [String: Any]?, monthly: [String: Any]?) -> [UsageMeter] {
        var meters: [UsageMeter] = []
        if let weekly {
            let combined = num(weekly["creditUsagePercent"])
            let reset = periodEnd(weekly)
            if let combined {
                meters.append(UsageMeter(title: "주간 한도", kind: .percentOnly, percent: combined, resetAt: reset))
            }
            let rows = products(weekly)
            let redundant = rows.count == 1 && combined != nil && abs(rows[0].percent - combined!) < 0.5
            if !redundant {
                for row in rows {
                    meters.append(UsageMeter(
                        title: "주간 · \(productLabel(row.name))",
                        kind: .percentOnly,
                        percent: row.percent,
                        resetAt: reset
                    ))
                }
            }
            if let cap = cents(weekly["onDemandCap"]), cap > 0 {
                let used = cents(weekly["onDemandUsed"]) ?? 0
                meters.append(moneyMeter(title: "추가 사용량", used: used, limit: cap, resetAt: reset))
            }
        }
        if let monthly, let limit = cents(monthly["monthlyLimit"]), limit > 0 {
            let used = cents(monthly["used"]) ?? 0
            meters.append(moneyMeter(
                title: "월간 포함 사용량",
                used: used,
                limit: limit,
                resetAt: isoDate(monthly["billingPeriodEnd"])
            ))
        }
        return meters
    }

    private static func loadToken(_ home: URL) -> LoadedToken {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let root = try? JSONSerialization.jsonObject(with: data)
        else { return .missing }

        let now = Date()
        var usable: [(token: String, exp: Date?)] = []
        var sawExpired = false
        for entry in credentialDicts(in: root) {
            guard let token = entry["key"] as? String, !token.isEmpty else { continue }
            let exp = isoDate(entry["expires_at"])
            if let exp, exp <= now {
                sawExpired = true
                continue
            }
            usable.append((token, exp))
        }
        guard let best = usable.max(by: { ($0.exp ?? .distantPast) < ($1.exp ?? .distantPast) }) else {
            return sawExpired ? .expired : .missing
        }
        return .ready(best.token)
    }

    private static func credentialDicts(in value: Any) -> [[String: Any]] {
        if let dict = value as? [String: Any] {
            var found: [[String: Any]] = []
            if dict["key"] is String { found.append(dict) }
            for child in dict.values { found.append(contentsOf: credentialDicts(in: child)) }
            return found
        }
        if let list = value as? [Any] {
            return list.flatMap { credentialDicts(in: $0) }
        }
        return []
    }

    private static func clientVersion(_ home: URL) -> String {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("version.json")),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = obj["version"] as? String, !version.isEmpty
        else { return "1.0.77" }
        return version
    }

    private static func billingURL(_ suffix: String) -> URL? {
        let raw = ProcessInfo.processInfo.environment["GROK_CLI_CHAT_PROXY_BASE_URL"]
            ?? "https://cli-chat-proxy.grok.com/v1"
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + suffix)
    }

    private static func request(_ url: URL, token: String, version: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(version, forHTTPHeaderField: "x-grok-client-version")
        req.setValue("build", forHTTPHeaderField: "x-grok-client-mode")
        req.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        req.setValue("xai-grok-build/\(version)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        return req
    }

    private static func probe(_ req: URLRequest) async -> Probe {
        do {
            let json = try await Env.getJSON(req)
            return Probe(config: json["config"] as? [String: Any] ?? json)
        } catch ProviderError.http(let code) {
            return Probe(status: code)
        } catch {
            return Probe(network: true)
        }
    }

    private static func products(_ config: [String: Any]) -> [(name: String, percent: Double)] {
        guard let rows = config["productUsage"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let name = row["product"] as? String, !name.isEmpty,
                  let percent = num(row["usagePercent"]) else { return nil }
            return (name, percent)
        }
    }

    private static func periodEnd(_ config: [String: Any]) -> Date? {
        if let period = config["currentPeriod"] as? [String: Any], let end = isoDate(period["end"]) {
            return end
        }
        return isoDate(config["billingPeriodEnd"])
    }

    /// `{"val": 123}` 또는 숫자. 단위는 센트.
    private static func cents(_ value: Any?) -> Double? {
        if let obj = value as? [String: Any] { return num(obj["val"]) }
        return num(value)
    }

    private static func moneyMeter(title: String, used: Double, limit: Double, resetAt: Date?) -> UsageMeter {
        UsageMeter(
            title: title,
            kind: .money(used: used / 100, limit: limit / 100, currency: "USD"),
            percent: used / limit * 100,
            resetAt: resetAt
        )
    }

    private static func productLabel(_ raw: String) -> String {
        switch raw {
        case "GrokBuild": return "Grok Build"
        case "GrokAppBuilder": return "App Builder"
        case "GrokTasks": return "Tasks"
        default:
            var label = ""
            for ch in raw {
                if ch.isUppercase, let last = label.last, last != " " { label.append(" ") }
                label.append(ch)
            }
            return label
        }
    }
}

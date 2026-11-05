import Foundation

/// Codex CLI 로그인 정보(~/.codex/auth.json)로 ChatGPT 사용량 조회. 토큰은 읽기만 함.
enum CodexProvider {
    static func fetch() async -> ProviderState {
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? Env.home.appendingPathComponent(".codex")
        let installed = Env.findExecutable("codex") != nil
            || FileManager.default.fileExists(atPath: codexHome.path)
        guard installed else { return .notInstalled }

        guard let data = try? Data(contentsOf: codexHome.appendingPathComponent("auth.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .notLoggedIn("터미널에서 codex login 하세요") }

        guard let tokens = root["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty
        else {
            if root["OPENAI_API_KEY"] is String {
                return .notLoggedIn("API 키 모드는 사용량 조회 불가 · ChatGPT로 로그인 필요")
            }
            return .notLoggedIn("터미널에서 codex login 하세요")
        }

        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        if let account = tokens["account_id"] as? String {
            req.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        req.setValue("AICreditChecker", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        do {
            let json = try await Env.getJSON(req)
            return .ok(ProviderUsage(plan: json["plan_type"] as? String, meters: parse(json)))
        } catch ProviderError.http(401) {
            return .error("토큰 만료 · codex 를 한 번 실행하면 갱신돼요")
        } catch ProviderError.http(let code) {
            return .error("조회 실패 (HTTP \(code))")
        } catch {
            return .error("네트워크 오류")
        }
    }

    static func parse(_ json: [String: Any]) -> [UsageMeter] {
        var meters: [UsageMeter] = []

        // Plus/Pro 등의 롤링 윈도우 한도
        if let rl = json["rate_limit"] as? [String: Any] {
            for key in ["primary_window", "secondary_window"] {
                guard let w = rl[key] as? [String: Any], let pct = num(w["used_percent"]) else { continue }
                meters.append(UsageMeter(
                    title: windowTitle(seconds: num(w["limit_window_seconds"])),
                    kind: .percentOnly,
                    percent: pct,
                    resetAt: resetDate(w)
                ))
            }
        }

        // Enterprise 사용자별 지출 한도
        if let sc = json["spend_control"] as? [String: Any],
           let lim = sc["individual_limit"] as? [String: Any],
           let used = num(lim["used"]), let limit = num(lim["limit"]), limit > 0 {
            meters.append(UsageMeter(
                title: "사용 크레딧",
                kind: .money(used: used, limit: limit, currency: ((lim["unit"] as? String) ?? "usd").uppercased()),
                percent: used / limit * 100,
                resetAt: resetDate(lim)
            ))
        }
        return meters
    }

    private static func resetDate(_ d: [String: Any]) -> Date? {
        if let at = num(d["reset_at"]) { return Date(timeIntervalSince1970: at) }
        if let after = num(d["reset_after_seconds"]) { return Date().addingTimeInterval(after) }
        return nil
    }

    private static func windowTitle(seconds: Double?) -> String {
        guard let s = seconds else { return "사용 한도" }
        let hours = Int(s / 3600)
        if hours >= 24 * 7 { return "주간 한도" }
        if hours >= 24 { return "\(hours / 24)일 한도" }
        return "\(hours)시간 한도"
    }
}

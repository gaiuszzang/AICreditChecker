import Foundation

/// Claude Code 로그인 정보(macOS 키체인)로 사용량 조회.
/// 토큰은 읽기만 하고 갱신하지 않음 — 리프레시 토큰이 회전되면 Claude Code 로그인이 깨질 수 있기 때문.
enum ClaudeProvider {
    private struct Credentials {
        let accessToken: String
        let expiresAt: Date?
        let plan: String?
    }

    static func fetch() async -> ProviderState {
        let installed = Env.findExecutable("claude") != nil
            || FileManager.default.fileExists(atPath: Env.home.appendingPathComponent(".claude").path)
        guard installed else { return .notInstalled }

        guard let cred = loadCredentials() else {
            return .notLoggedIn("터미널에서 claude 실행 후 /login 하세요")
        }
        if let exp = cred.expiresAt, exp < Date() {
            return .error("토큰 만료 · claude 를 한 번 실행하면 갱신돼요")
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(cred.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("AICreditChecker", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        do {
            let json = try await Env.getJSON(req)
            return .ok(ProviderUsage(plan: cred.plan, meters: parse(json)))
        } catch ProviderError.http(401) {
            return .error("토큰 만료 · claude 를 한 번 실행하면 갱신돼요")
        } catch ProviderError.http(let code) {
            return .error("조회 실패 (HTTP \(code))")
        } catch {
            return .error("네트워크 오류")
        }
    }

    private static func loadCredentials() -> Credentials? {
        // 1) macOS 키체인 (security CLI는 해당 항목 ACL에 포함돼 있어 권한 팝업이 뜨지 않음)
        var raw = Env.run("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        // 2) 파일 방식 (일부 설치 환경)
        if raw == nil {
            let file = Env.home.appendingPathComponent(".claude/.credentials.json")
            raw = try? String(contentsOf: file, encoding: .utf8)
        }
        guard let data = raw?.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }

        let exp = num(oauth["expiresAt"]).map { Date(timeIntervalSince1970: $0 / 1000) }
        return Credentials(accessToken: token, expiresAt: exp, plan: oauth["subscriptionType"] as? String)
    }

    static func parse(_ json: [String: Any]) -> [UsageMeter] {
        var meters: [UsageMeter] = []

        // 구독 플랜(Pro/Max)의 롤링 윈도우 한도
        let windows: [(String, String)] = [
            ("five_hour", "5시간 한도"),
            ("seven_day", "주간 한도"),
            ("seven_day_opus", "주간 한도 (Opus)"),
            ("seven_day_sonnet", "주간 한도 (Sonnet)"),
        ]
        for (key, title) in windows {
            guard let w = json[key] as? [String: Any], let util = num(w["utilization"]) else { continue }
            meters.append(UsageMeter(title: title, kind: .percentOnly, percent: util, resetAt: isoDate(w["resets_at"])))
        }

        // 크레딧(금액) 한도 — Enterprise/Team 또는 추가 사용량
        if let spend = json["spend"] as? [String: Any],
           (spend["enabled"] as? Bool) != false,
           let used = spend["used"] as? [String: Any],
           let limit = spend["limit"] as? [String: Any],
           let usedMinor = num(used["amount_minor"]),
           let limitMinor = num(limit["amount_minor"]), limitMinor > 0 {
            let usedScale = pow(10, num(used["exponent"]) ?? 2)
            let limitScale = pow(10, num(limit["exponent"]) ?? 2)
            let u = usedMinor / usedScale, l = limitMinor / limitScale
            meters.append(UsageMeter(
                title: "사용 크레딧",
                kind: .money(used: u, limit: l, currency: (used["currency"] as? String) ?? "USD"),
                percent: u / l * 100,
                resetAt: startOfNextMonth()
            ))
        } else if let extra = json["extra_usage"] as? [String: Any],
                  (extra["is_enabled"] as? Bool) == true,
                  let usedMinor = num(extra["used_credits"]),
                  let limitMinor = num(extra["monthly_limit"]), limitMinor > 0 {
            let scale = pow(10, num(extra["decimal_places"]) ?? 2)
            let u = usedMinor / scale, l = limitMinor / scale
            meters.append(UsageMeter(
                title: "사용 크레딧",
                kind: .money(used: u, limit: l, currency: (extra["currency"] as? String) ?? "USD"),
                percent: num(extra["utilization"]) ?? (u / l * 100),
                resetAt: startOfNextMonth()
            ))
        }
        return meters
    }
}

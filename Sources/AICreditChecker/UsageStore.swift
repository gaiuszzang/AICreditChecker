import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    static let refreshInterval: TimeInterval = 10 * 60
    static let renewTimeout: TimeInterval = 90

    var claude: ProviderState = .loading
    var codex: ProviderState = .loading
    var grok: ProviderState = .loading
    var antigravity: ProviderState = .loading
    var renewing: Set<Provider> = []
    var lastUpdated: Date?
    var isRefreshing = false

    private var loop: Task<Void, Never>?

    init() { start() }

    func state(for p: Provider) -> ProviderState {
        switch p {
        case .claude: claude
        case .codex: codex
        case .grok: grok
        case .antigravity: antigravity
        }
    }

    private func set(_ s: ProviderState, for p: Provider) {
        switch p {
        case .claude: claude = s
        case .codex: codex = s
        case .grok: grok = s
        case .antigravity: antigravity = s
        }
    }

    private nonisolated static func fetch(_ p: Provider) async -> ProviderState {
        switch p {
        case .claude: await ClaudeProvider.fetch()
        case .codex: await CodexProvider.fetch()
        case .grok: await GrokProvider.fetch()
        case .antigravity: await AntigravityProvider.fetch()
        }
    }

    func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        async let c = ClaudeProvider.fetch()
        async let x = CodexProvider.fetch()
        async let g = GrokProvider.fetch()
        async let a = AntigravityProvider.fetch()
        let (cs, xs, gs, ag) = await (c, x, g, a)
        claude = cs
        codex = xs
        grok = gs
        antigravity = ag
        lastUpdated = Date()
        isRefreshing = false
    }

    /// 토큰 만료 시 사용자가 누르면 해당 CLI를 실행해 CLI 스스로 토큰을 갱신하게 한다.
    /// 앱은 인증 정보를 직접 쓰지 않고, 실행 후 다시 조회해 만료가 풀렸는지만 확인한다.
    func renew(_ p: Provider) async {
        guard !renewing.contains(p) else { return }
        guard let path = Env.findExecutable(p.executable) else {
            set(.error("\(p.executable) 실행 파일을 찾지 못함 · 터미널에서 직접 실행하세요"), for: p)
            return
        }
        renewing.insert(p)
        defer { renewing.remove(p) }

        for args in p.renewCommands {
            _ = await Env.runCLI(path, args, timeout: Self.renewTimeout)
            let s = await Self.fetch(p)
            set(s, for: p)
            if case .expired = s { continue }
            return
        }
        set(.expired("갱신 실패 · 터미널에서 \(p.executable) 를 실행하세요"), for: p)
    }
}

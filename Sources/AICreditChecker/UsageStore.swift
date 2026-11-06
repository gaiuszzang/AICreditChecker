import Foundation
import Observation

@MainActor
@Observable
final class UsageStore {
    static let refreshInterval: TimeInterval = 10 * 60

    var claude: ProviderState = .loading
    var codex: ProviderState = .loading
    var grok: ProviderState = .loading
    var lastUpdated: Date?
    var isRefreshing = false

    private var loop: Task<Void, Never>?

    init() { start() }

    func state(for p: Provider) -> ProviderState {
        switch p {
        case .claude: claude
        case .codex: codex
        case .grok: grok
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
        let (cs, xs, gs) = await (c, x, g)
        claude = cs
        codex = xs
        grok = gs
        lastUpdated = Date()
        isRefreshing = false
    }
}

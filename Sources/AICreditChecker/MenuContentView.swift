import SwiftUI
import ServiceManagement

struct MenuContentView: View {
    let store: UsageStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Provider.allCases) { p in
                ProviderSection(provider: p, state: store.state(for: p))
                Divider().padding(.vertical, 6)
            }

            MenuRow {
                Task { await store.refresh() }
            } content: {
                Text("새로 고침")
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(updatedText)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(.quaternary))
                }
            }

            Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }

            Divider().padding(.vertical, 6)

            MenuRow { NSApp.terminate(nil) } content: { Text("AI Credit Checker 종료") }
        }
        .padding(8)
        .frame(width: 380)
    }

    private var updatedText: String {
        if store.isRefreshing { return "업데이트 중…" }
        guard let d = store.lastUpdated else { return "-" }
        if Date().timeIntervalSince(d) < 60 { return "방금 업데이트됨" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ko_KR")
        return "\(f.localizedString(for: d, relativeTo: Date()))에 업데이트됨"
    }
}

private struct ProviderSection: View {
    let provider: Provider
    let state: ProviderState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(header)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 4)

            switch state {
            case .loading:
                status("불러오는 중…")
            case .notInstalled:
                status("설치되어 있지 않음")
            case .notLoggedIn(let msg):
                status("로그인 안 됨 · \(msg)")
            case .error(let msg):
                status(msg, color: .orange)
            case .ok(let usage) where usage.meters.isEmpty:
                status("표시할 사용량 한도가 없음")
            case .ok(let usage):
                ForEach(usage.meters) { MeterView(meter: $0) }
            }
        }
    }

    private var header: String {
        if let plan = state.usage?.plan, !plan.isEmpty {
            return "\(provider.rawValue) · \(plan.uppercased())"
        }
        return provider.rawValue
    }

    private func status(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.bottom, 2)
    }
}

private struct MeterView: View {
    let meter: UsageMeter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .font(.callout)

            ProgressView(value: min(max(meter.percent, 0), 100), total: 100)
                .progressViewStyle(.linear)
                .tint(tint)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }

    private var title: String {
        switch meter.kind {
        case .money(let used, let limit, let currency):
            return "\(meter.title) · \(money(limit, currency)) 중 \(money(used, currency))"
        case .percentOnly:
            return meter.title
        }
    }

    private var detail: String {
        var s = "\(Int(meter.percent.rounded()))%"
        if let r = meter.resetAt { s += " · \(resetText(r)) 초기화" }
        return s
    }

    private var tint: Color {
        switch meter.percent {
        case ..<70: return .accentColor
        case ..<90: return .orange
        default: return .red
        }
    }

    private func money(_ v: Double, _ currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "ko_KR")
        f.currencyCode = currency
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    private func resetText(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = d.timeIntervalSinceNow < 24 * 3600 ? "a h:mm" : "M월 d일"
        return f.string(from: d)
    }
}

/// 메뉴 항목처럼 호버 하이라이트되는 버튼 행
private struct MenuRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack { content() }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.primary.opacity(0.1) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

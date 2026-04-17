import SwiftUI
import WidgetKit

struct ContentView: View {
    @StateObject private var model = PricklesModel()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // TEMPORARY: embedded widget-view preview for debugging the
                    // blank-widget rendering issue on the home screen. Remove
                    // once the widget is confirmed rendering correctly.
                    DebugWidgetPreview(status: model.status, caption: model.caption)
                        .padding(.top, 20)
                        .padding(.bottom, 12)

                    QuestionHeadline()
                        .padding(.top, 24)
                        .padding(.bottom, 42)

                    PolaroidHero(
                        state: model.status.state,
                        caption: model.caption,
                        isStale: model.status.isStale
                    )
                    .padding(.horizontal, 24)

                    BelowPolaroid(status: model.status, detail: model.detail, lastChecked: model.status.lastChecked)
                        .padding(.top, 32)
                        .padding(.horizontal, 24)

                    HistorySection(entries: model.history.entries)
                        .padding(.top, 56)
                        .padding(.horizontal, 24)

                    FooterView()
                        .padding(.top, 56)
                        .padding(.bottom, 48)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.reload(force: true) }
        }
        .task { await model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await model.reload() }
        }
    }

    private var backgroundGradient: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: 0xF29D3C, alpha: 0.14), .clear],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: 600
            )
            RadialGradient(
                colors: [Color(hex: 0xA94328, alpha: 0.06), .clear],
                center: .init(x: 0.5, y: 1.0),
                startRadius: 0,
                endRadius: 600
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Model

@MainActor
final class PricklesModel: ObservableObject {
    @Published var status: PricklesStatus = PricklesAPI.statusOrPlaceholder()
    @Published var history: PricklesHistory = PricklesAPI.historyOrPlaceholder()
    @Published var caption: String = ""
    @Published var detail: String = ""

    private var renderedState: PricklesState?

    init() {
        rollCopyIfNeeded()
    }

    func reload(force: Bool = false) async {
        async let newStatus: PricklesStatus? = try? await PricklesAPI.fetchStatus()
        async let newHistory: PricklesHistory? = try? await PricklesAPI.fetchHistory()

        let status = await newStatus
        let history = await newHistory

        if let status {
            self.status = status
        }
        if let history {
            self.history = history
        }

        rollCopyIfNeeded(force: force)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func rollCopyIfNeeded(force: Bool = false) {
        if force || renderedState != status.state || caption.isEmpty {
            let pick = StateCopy.pickRandom(for: status.state)
            caption = pick.caption
            detail = pick.detail
            renderedState = status.state
        }
    }
}

// MARK: - Debug widget preview (temporary)
//
// Renders a 170x170 square that replicates the SmallWidget view exactly. Lets
// us verify the widget view works in isolation without going through iOS's
// widget pipeline. Remove once the home-screen widget is confirmed working.

struct DebugWidgetPreview: View {
    let status: PricklesStatus
    let caption: String

    private var stateAccent: Color {
        Theme.stateColorOnDark(status.state)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("widget preview (debug)")
                .font(Theme.karla(size: 10, weight: .medium))
                .foregroundStyle(Theme.textDim)
                .textCase(.uppercase)
                .tracking(1)

            ZStack {
                LinearGradient(
                    colors: [Color(hex: 0x3A2416), Color(hex: 0x1F140C)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(hex: 0xF29D3C, alpha: 0.40), Color(hex: 0xF29D3C, alpha: 0.14), .clear],
                    center: .init(x: 0.5, y: 0.30),
                    startRadius: 0,
                    endRadius: 180
                )
                RadialGradient(
                    colors: [stateAccent.opacity(0.22), .clear],
                    center: .init(x: 0.5, y: 1.0),
                    startRadius: 0,
                    endRadius: 150
                )

                VStack(spacing: 4) {
                    Image(status.state == .good ? "normal" : "dead")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 140, maxHeight: 140)
                        .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 5)
                        .layoutPriority(0)

                    Text(caption)
                        .font(Theme.caveat(size: 25, bold: true))
                        .foregroundStyle(stateAccent)
                        .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 1)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .lineSpacing(-4)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                        .padding(.horizontal, 2)
                }
                .padding(.top, 4)
                .padding(.bottom, 16)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(width: 170, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - Headline

struct QuestionHeadline: View {
    var body: some View {
        Text("How's Prickles feeling?")
            .font(Theme.caprasimo(size: 42))
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .lineLimit(2)
            .padding(.horizontal, 24)
    }
}

// MARK: - Polaroid hero (sized for phone)

struct PolaroidHero: View {
    let state: PricklesState
    let caption: String
    let isStale: Bool

    var body: some View {
        PolaroidView(
            state: state,
            caption: caption,
            isStale: isStale,
            tilted: true,
            captionSize: 36,
            paperInset: 16,
            paperBottomInset: 22
        )
        .frame(maxWidth: 320)
    }
}

// MARK: - Below polaroid: detail + last checked + incident prose

struct BelowPolaroid: View {
    let status: PricklesStatus
    let detail: String
    let lastChecked: Date?

    var body: some View {
        VStack(spacing: 10) {
            Text(detail)
                .font(Theme.karla(size: 17, weight: .medium))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            if status.state == .error, let incident = status.sources?.anthropic?.activeIncident, let name = incident.name {
                IncidentProse(name: name, url: incident.url)
            }

            if let lastChecked {
                Text("Last checked \(DateHelpers.relativeTime(from: lastChecked))")
                    .font(Theme.karla(size: 13))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }
}

struct IncidentProse: View {
    let name: String
    let url: String?

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                Link(destination: u) {
                    (
                        Text("Claude is reportedly having an issue: ") +
                        Text(name).foregroundColor(Theme.text).bold() +
                        Text(". See what's up →").foregroundColor(Theme.accent)
                    )
                }
            } else {
                (
                    Text("Claude is reportedly having an issue: ") +
                    Text(name).foregroundColor(Theme.text).bold()
                )
            }
        }
        .font(Theme.karla(size: 15))
        .foregroundStyle(Theme.textMuted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 460)
    }
}

// MARK: - History

struct HistorySection: View {
    let entries: [PricklesHistory.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RECENT MOODS")
                .font(Theme.karla(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Theme.textMuted)

            if entries.isEmpty {
                Text("No recent mood swings. Prickles has been stable.")
                    .font(Theme.karla(size: 14))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 8) {
                    ForEach(entries.prefix(5)) { entry in
                        HistoryRow(entry: entry)
                    }
                }
            }

            if let url = URL(string: "https://status.anthropic.com/history") {
                Link("See Claude's full incident history →", destination: url)
                    .font(Theme.karla(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 32)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
    }
}

struct HistoryRow: View {
    let entry: PricklesHistory.Entry

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Theme.stateColor(entry.state))
                .frame(width: 9, height: 9)
                .overlay(
                    entry.isOngoing ?
                        Circle()
                            .stroke(Theme.stateColor(entry.state).opacity(0.5), lineWidth: 4)
                            .scaleEffect(1.4)
                        : nil
                )

            Text(entry.state.rawValue.capitalized)
                .font(Theme.karla(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)

            Spacer(minLength: 8)

            Text(DateHelpers.historyMeta(from: entry.from, to: entry.to))
                .font(Theme.karla(size: 12))
                .foregroundStyle(Theme.textDim)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.bgSoft)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Footer

struct FooterView: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                footerLink("Privacy", url: "https://jessica-he.com/prickles/privacy.html")
                Text("·").foregroundStyle(Theme.textDim)
                footerLink("Terms", url: "https://jessica-he.com/prickles/terms.html")
                Text("·").foregroundStyle(Theme.textDim)
                footerLink("Support", url: "mailto:jessh1821@gmail.com?subject=Prickles%20feedback")
            }
            .font(Theme.karla(size: 14))

            Link(destination: URL(string: "https://status.anthropic.com")!) {
                Text("Open status.anthropic.com")
                    .font(Theme.karla(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(.top, 4)

            Text("Prickles is an unofficial hedgehog featuring the vibes of Claude. Data from status.anthropic.com. Not affiliated with Anthropic PBC. Claude is a trademark of Anthropic.")
                .font(Theme.karla(size: 12))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .padding(.top, 8)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
    }

    private func footerLink(_ title: String, url: String) -> some View {
        Group {
            if let u = URL(string: url) {
                Link(title, destination: u)
                    .foregroundStyle(Theme.textMuted)
            } else {
                Text(title).foregroundStyle(Theme.textMuted)
            }
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif

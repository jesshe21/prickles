import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct PricklesEntry: TimelineEntry {
    let date: Date
    let status: PricklesStatus
    let caption: String
    let detail: String
}

// MARK: - Timeline provider

struct PricklesProvider: TimelineProvider {

    func placeholder(in context: Context) -> PricklesEntry {
        let status = PricklesStatus.placeholderGood
        let pick = StateCopy.pick(for: status.state, seed: status.stateSince)
        return PricklesEntry(date: Date(), status: status, caption: pick.caption, detail: pick.detail)
    }

    func getSnapshot(in context: Context, completion: @escaping (PricklesEntry) -> Void) {
        let status = PricklesAPI.cachedStatus() ?? .placeholderGood
        let pick = StateCopy.pick(for: status.state, seed: status.stateSince)
        completion(PricklesEntry(date: Date(), status: status, caption: pick.caption, detail: pick.detail))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PricklesEntry>) -> Void) {
        Task {
            let status = (try? await PricklesAPI.fetchStatus()) ?? PricklesAPI.cachedStatus() ?? .placeholderGood
            let pick = StateCopy.pick(for: status.state, seed: status.stateSince)
            let entry = PricklesEntry(date: Date(), status: status, caption: pick.caption, detail: pick.detail)
            let nextRefresh = Date().addingTimeInterval(15 * 60) // hint 15 min — Apple throttles as it sees fit
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
}

// MARK: - Widget definition

struct PricklesWidget: Widget {
    let kind = "PricklesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PricklesProvider()) { entry in
            PricklesWidgetView(entry: entry)
                .widgetContainerBackground(Theme.bg)
        }
        .configurationDisplayName("Prickles")
        .description("A tiny hedgehog who feels whatever Claude feels.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Family-aware root

struct PricklesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PricklesEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidget(entry: entry)
        case .accessoryRectangular:
            RectangularWidget(entry: entry)
        case .accessoryCircular:
            CircularWidget(entry: entry)
        default:
            SmallWidget(entry: entry)
        }
    }
}

// MARK: - System Small (home screen — the hero)
//
// Earlier versions wrapped the hedgehog in a tilted polaroid card to match the
// webpage. At .systemSmall bounds that ate most of the space and the tilt was
// imperceptible, so we dropped the paper card entirely: the widget is now just
// Prickles floating on a warm radial glow with the caption underneath. The
// hedgehog art has its own dark vignette baked in, so it blends cleanly with
// the widget's dark brown container.

struct SmallWidget: View {
    let entry: PricklesEntry

    private var stateAccent: Color {
        Theme.stateColorOnDark(entry.status.state)
    }

    var body: some View {
        ZStack {
            // Layered warm gradient: diagonal base + orange halo from top
            // + a soft state-colored wash from the bottom.
            LinearGradient(
                colors: [
                    Color(hex: 0x3A2416),
                    Color(hex: 0x1F140C),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(hex: 0xF29D3C, alpha: 0.40),
                    Color(hex: 0xF29D3C, alpha: 0.14),
                    .clear,
                ],
                center: .init(x: 0.5, y: 0.30),
                startRadius: 0,
                endRadius: 180
            )

            RadialGradient(
                colors: [
                    stateAccent.opacity(0.22),
                    .clear,
                ],
                center: .init(x: 0.5, y: 1.0),
                startRadius: 0,
                endRadius: 150
            )

            VStack(spacing: 4) {
                Image(entry.status.state == .good ? "normal" : "dead")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 140, maxHeight: 140)
                    .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 5)
                    .layoutPriority(0)

                Text(entry.caption)
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

            if entry.status.isStale {
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color(red: 235/255, green: 208/255, blue: 150/255, opacity: 0.85))
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("Data may be out of date")
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
    }
}

// MARK: - Accessory Rectangular (lock screen strip)

struct RectangularWidget: View {
    let entry: PricklesEntry

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.photoBG)
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.caption)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text("Prickles")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var imageName: String {
        entry.status.state == .good ? "normal" : "dead"
    }
}

// MARK: - Accessory Circular (lock screen tiny circle)

struct CircularWidget: View {
    let entry: PricklesEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(imageName)
                .resizable()
                .scaledToFit()
                .padding(6)
        }
    }

    private var imageName: String {
        entry.status.state == .good ? "normal" : "dead"
    }
}

// MARK: - Container-background shim

extension View {
    /// Returns a view whose container background is the given color on iOS 17+
    /// and a plain `.background` on iOS 16.
    @ViewBuilder
    func widgetContainerBackground(_ color: Color) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(color, for: .widget)
        } else {
            self.background(color)
        }
    }
}

// Widget previews (the `#Preview(_:as:)` form) require iOS 17+. The shared
// PolaroidView has its own previews that cover the visual work.

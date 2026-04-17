import SwiftUI

/// A cream polaroid card with a square photo area and an optional handwritten caption.
/// Used by both the widget (small, tilted) and the host app (large, tilted).
struct PolaroidView: View {
    let state: PricklesState
    let caption: String?
    let isStale: Bool
    var tilted: Bool = true
    var captionSize: CGFloat = 32
    var paperInset: CGFloat = Theme.Polaroid.paperInset
    var paperBottomInset: CGFloat = Theme.Polaroid.paperBottomInset

    private var imageName: String {
        switch state {
        case .good: return "normal"
        case .error: return "dead"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Photo area (dark) — image is inset so Prickles has breathing room
            // against the dark square instead of filling edge-to-edge.
            ZStack {
                Theme.photoBG
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .accessibilityLabel("Prickles the hedgehog — \(state.rawValue)")
                if isStale {
                    staleDot
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(Theme.caveat(size: captionSize, bold: true))
                    .foregroundStyle(Theme.stateColor(state))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 12)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, paperInset)
        .padding(.top, paperInset)
        .padding(.bottom, paperBottomInset)
        .background(
            RoundedRectangle(cornerRadius: Theme.Polaroid.cornerRadius, style: .continuous)
                .fill(Theme.paper)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Polaroid.cornerRadius, style: .continuous)
                .stroke(Theme.paperEdge, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 28, x: 0, y: 18)
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 6)
        .rotationEffect(tilted ? Theme.Polaroid.rotation : .zero)
    }

    private var staleDot: some View {
        Circle()
            .fill(Color(red: 215/255, green: 188/255, blue: 140/255, opacity: 0.65))
            .frame(width: 10, height: 10)
            .overlay(
                Circle().stroke(Theme.photoBG.opacity(0.4), lineWidth: 2)
            )
    }
}

#if DEBUG
#Preview("Polaroid — good") {
    PolaroidView(state: .good, caption: "feeling great!", isStale: false)
        .padding()
        .background(Theme.bg)
}

#Preview("Polaroid — error") {
    PolaroidView(state: .error, caption: "Prickles has DIED", isStale: false)
        .padding()
        .background(Theme.bg)
}
#endif

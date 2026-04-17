import SwiftUI

enum Theme {

    // MARK: - Colors (ported from docs/index.html :root variables)

    static let bg         = Color(hex: 0x1F140C)
    static let bgSoft     = Color(hex: 0x2A1C12)
    static let paper      = Color(hex: 0xFFFCF3)
    static let paperEdge  = Color(hex: 0xE8DCC2)
    static let photoBG    = Color(hex: 0x1D1310)
    static let text       = Color(hex: 0xF7E6C8)
    static let textMuted  = Color(hex: 0xB09680)
    static let textDim    = Color(hex: 0x826A4E)
    static let accent     = Color(hex: 0xF29D3C)
    static let good       = Color(hex: 0x5A8C3A)
    static let error      = Color(hex: 0xA94328)
    /// Brighter state colors designed to read well against the dark warm background
    /// (the muted `good`/`error` above are tuned for the cream polaroid surface).
    static let goodOnDark  = Color(hex: 0xA8D664)
    static let errorOnDark = Color(hex: 0xEE7755)
    static let border     = Color(red: 242/255, green: 226/255, blue: 192/255, opacity: 0.08)

    static func stateColor(_ state: PricklesState) -> Color {
        switch state {
        case .good: return good
        case .error: return error
        }
    }

    static func stateColorOnDark(_ state: PricklesState) -> Color {
        switch state {
        case .good: return goodOnDark
        case .error: return errorOnDark
        }
    }

    // MARK: - Fonts

    /// Family names as registered by iOS. Karla and Caveat are bundled as variable
    /// fonts so the family name alone is enough; weight is applied via SwiftUI's
    /// `.weight()` modifier, which maps to the TrueType wght axis on iOS 16+.
    enum FontName {
        static let caveat = "Caveat"
        static let caprasimo = "Caprasimo-Regular"
        static let karla = "Karla"
    }

    static func caprasimo(size: CGFloat) -> Font {
        .custom(FontName.caprasimo, size: size)
    }

    static func caveat(size: CGFloat, bold: Bool = true) -> Font {
        .custom(FontName.caveat, size: size).weight(bold ? .bold : .regular)
    }

    static func karla(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(FontName.karla, size: size).weight(weight)
    }

    // MARK: - Layout constants (polaroid)

    enum Polaroid {
        static let rotation: Angle = .degrees(-2.5)
        static let paperInset: CGFloat = 16
        static let paperBottomInset: CGFloat = 22
        static let cornerRadius: CGFloat = 4
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8)  & 0xff) / 255.0
        let b = Double(hex         & 0xff) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

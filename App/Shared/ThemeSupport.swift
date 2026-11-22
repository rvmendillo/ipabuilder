import SwiftUI
import ReyForgeCore

extension Color {
    /// Parses "#RGB", "#RRGGBB" or "#RRGGBBAA".
    init?(hex: String) {
        guard let c = ColorNames.rgba(hex) else { return nil }
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return ColorNames.hex(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
    }
}

/// Resolves theme tokens, system color names and hex strings for the current color scheme.
struct ThemePalette {
    var theme: Theme
    var dark: Bool

    func color(_ token: String?, fallback: Color = .primary) -> Color {
        guard let raw = token?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return fallback }
        switch raw.lowercased() {
        case "primary", "accent", "tint", "brand": return Color(hex: theme.accent) ?? .accentColor
        case "text", "label", "foreground": return Color(hex: dark ? theme.darkText : theme.text) ?? .primary
        case "secondarytext", "textsecondary", "muted", "subtitle", "secondarylabel": return Color(hex: dark ? theme.darkSecondaryText : theme.secondaryText) ?? .secondary
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "brown": return .brown
        case "gray", "grey": return .gray
        case "black": return .black
        case "white": return .white
        case "clear", "transparent": return .clear
        default:
            let hex = theme.resolve(raw, dark: dark)
            return Color(hex: hex) ?? fallback
        }
    }

    var accent: Color { color("accent") }
    var background: Color { Color(hex: dark ? theme.darkBackground : theme.background) ?? Color(.systemGroupedBackground) }
    var surface: Color { Color(hex: dark ? theme.darkSurface : theme.surface) ?? Color(.secondarySystemGroupedBackground) }

    @ViewBuilder
    func fill(_ f: Fill?) -> some View {
        if let f = f {
            let colors = f.colors.map { color($0, fallback: accent) }
            switch f.kind {
            case .solid: (colors.first ?? accent)
            case .linear:
                let (s, e) = ThemePalette.points(angle: f.angle)
                LinearGradient(colors: colors.count > 1 ? colors : colors + colors, startPoint: s, endPoint: e)
            case .radial: RadialGradient(colors: colors.count > 1 ? colors : colors + colors, center: .center, startRadius: 0, endRadius: 260)
            case .angular: AngularGradient(colors: colors.count > 1 ? colors + [colors[0]] : colors + colors, center: .center)
            }
        } else {
            Color.clear
        }
    }

    func shapeStyle(_ f: Fill) -> AnyShapeStyle {
        let colors = f.colors.map { color($0, fallback: accent) }
        switch f.kind {
        case .solid: return AnyShapeStyle(colors.first ?? accent)
        case .linear:
            let (s, e) = ThemePalette.points(angle: f.angle)
            return AnyShapeStyle(LinearGradient(colors: colors.count > 1 ? colors : colors + colors, startPoint: s, endPoint: e))
        case .radial: return AnyShapeStyle(RadialGradient(colors: colors.count > 1 ? colors : colors + colors, center: .center, startRadius: 0, endRadius: 260))
        case .angular: return AnyShapeStyle(AngularGradient(colors: colors.count > 1 ? colors + [colors[0]] : colors + colors, center: .center))
        }
    }

    static func points(angle: Double) -> (UnitPoint, UnitPoint) {
        let r = angle * .pi / 180
        let dx = cos(r) / 2, dy = sin(r) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    var fontDesign: Font.Design {
        switch theme.fontDesign {
        case "rounded": return .rounded
        case "serif": return .serif
        case "monospaced": return .monospaced
        default: return .default
        }
    }
}

enum FontMapper {
    static func textStyle(_ s: String?) -> Font.TextStyle {
        switch s ?? "body" {
        case "largeTitle": return .largeTitle
        case "title": return .title
        case "title2": return .title2
        case "title3": return .title3
        case "headline": return .headline
        case "subheadline": return .subheadline
        case "callout": return .callout
        case "footnote": return .footnote
        case "caption": return .caption
        case "caption2": return .caption2
        default: return .body
        }
    }

    static func weight(_ s: String?) -> Font.Weight? {
        switch s ?? "" {
        case "ultraLight": return .ultraLight
        case "thin": return .thin
        case "light": return .light
        case "regular": return .regular
        case "medium": return .medium
        case "semibold": return .semibold
        case "bold": return .bold
        case "heavy": return .heavy
        case "black": return .black
        default: return nil
        }
    }

    static func design(_ s: String?) -> Font.Design? {
        switch s ?? "" {
        case "rounded": return .rounded
        case "serif": return .serif
        case "monospaced": return .monospaced
        case "default": return .default
        default: return nil
        }
    }

    static func font(_ spec: FontSpec?) -> Font? {
        guard let spec = spec else { return nil }
        var f: Font
        if let size = spec.size, size > 0 {
            f = .system(size: size, weight: weight(spec.weight) ?? .regular, design: design(spec.design) ?? .default)
        } else {
            f = .system(textStyle(spec.style), design: design(spec.design) ?? .default)
            if let w = weight(spec.weight) { f = f.weight(w) }
        }
        if spec.italic == true { f = f.italic() }
        return f
    }
}

extension HAlign {
    var horizontal: HorizontalAlignment {
        switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }
    var frameAlignment: Alignment {
        switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }
    var textAlignment: TextAlignment {
        switch self { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }
}

extension Value {
    var date: Date? { ExpressionEngine.parseDate(self) }
}

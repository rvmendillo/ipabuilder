import Foundation

// MARK: - Theme

public struct Theme: Codable, Hashable {
    public enum Appearance: String, Codable, CaseIterable { case system, light, dark }

    public var appearance: Appearance
    public var accent: String
    public var secondaryAccent: String
    public var background: String
    public var surface: String
    public var text: String
    public var secondaryText: String
    public var darkBackground: String
    public var darkSurface: String
    public var darkText: String
    public var darkSecondaryText: String
    public var success: String
    public var warning: String
    public var danger: String
    public var fontDesign: String
    public var cornerRadius: Double
    public var spacing: Double
    public var presetID: String?

    public init(appearance: Appearance = .system, accent: String = "#5B5BF7", secondaryAccent: String = "#A855F7",
                background: String = "#F2F2F7", surface: String = "#FFFFFF", text: String = "#111114", secondaryText: String = "#6B6B76",
                darkBackground: String = "#000000", darkSurface: String = "#1C1C1E", darkText: String = "#FFFFFF", darkSecondaryText: String = "#A1A1AA",
                success: String = "#34C759", warning: String = "#FF9F0A", danger: String = "#FF3B30",
                fontDesign: String = "default", cornerRadius: Double = 14, spacing: Double = 16, presetID: String? = nil) {
        self.appearance = appearance; self.accent = accent; self.secondaryAccent = secondaryAccent
        self.background = background; self.surface = surface; self.text = text; self.secondaryText = secondaryText
        self.darkBackground = darkBackground; self.darkSurface = darkSurface; self.darkText = darkText; self.darkSecondaryText = darkSecondaryText
        self.success = success; self.warning = warning; self.danger = danger
        self.fontDesign = fontDesign; self.cornerRadius = cornerRadius; self.spacing = spacing; self.presetID = presetID
    }

    enum CodingKeys: String, CodingKey {
        case appearance, accent, secondaryAccent, background, surface, text, secondaryText, darkBackground, darkSurface, darkText,
             darkSecondaryText, success, warning, danger, fontDesign, cornerRadius, spacing, presetID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Theme()
        appearance = c.value(.appearance, d.appearance); accent = c.value(.accent, d.accent)
        secondaryAccent = c.value(.secondaryAccent, d.secondaryAccent); background = c.value(.background, d.background)
        surface = c.value(.surface, d.surface); text = c.value(.text, d.text); secondaryText = c.value(.secondaryText, d.secondaryText)
        darkBackground = c.value(.darkBackground, d.darkBackground); darkSurface = c.value(.darkSurface, d.darkSurface)
        darkText = c.value(.darkText, d.darkText); darkSecondaryText = c.value(.darkSecondaryText, d.darkSecondaryText)
        success = c.value(.success, d.success); warning = c.value(.warning, d.warning); danger = c.value(.danger, d.danger)
        fontDesign = c.value(.fontDesign, d.fontDesign); cornerRadius = c.value(.cornerRadius, d.cornerRadius)
        spacing = c.value(.spacing, d.spacing); presetID = c.optional(.presetID)
    }

    /// Resolves a theme token, system color name or hex string to a hex string for the given scheme.
    public func resolve(_ token: String, dark: Bool) -> String {
        let t = token.trimmingCharacters(in: .whitespaces)
        switch t.lowercased() {
        case "accent", "primary", "tint", "brand": return accent
        case "secondary", "secondaryaccent", "accent2": return secondaryAccent
        case "background", "bg": return dark ? darkBackground : background
        case "surface", "card", "secondarybackground": return dark ? darkSurface : surface
        case "text", "label", "foreground", "onbackground": return dark ? darkText : text
        case "secondarytext", "textsecondary", "muted", "subtitle", "secondarylabel": return dark ? darkSecondaryText : secondaryText
        case "success": return success
        case "warning": return warning
        case "danger", "error", "destructive": return danger
        default: return ColorNames.hex(for: t) ?? t
        }
    }
}

// MARK: - Theme presets

public struct ThemePreset: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let theme: Theme
    public let iconBackground: [String]
}

public enum ThemePresets {
    public static let all: [ThemePreset] = [
        preset("forge", "ReyForge", accent: "#6C5CFF", second: "#FF7A45", bg: "#F4F3FF", surface: "#FFFFFF", design: "rounded", radius: 16),
        preset("ocean", "Ocean", accent: "#0A84FF", second: "#30D5C8", bg: "#EEF5FF", surface: "#FFFFFF", design: "default", radius: 14),
        preset("sunset", "Sunset", accent: "#FF5E3A", second: "#FF2A68", bg: "#FFF4EF", surface: "#FFFFFF", design: "rounded", radius: 18),
        preset("forest", "Forest", accent: "#2E9E5B", second: "#9BC53D", bg: "#F1F8F2", surface: "#FFFFFF", design: "default", radius: 14),
        preset("midnight", "Midnight", accent: "#7D7AFF", second: "#64D2FF", bg: "#0B0B14", surface: "#16162A", design: "default", radius: 16, appearance: .dark),
        preset("mono", "Monochrome", accent: "#111111", second: "#6B6B6B", bg: "#F5F5F5", surface: "#FFFFFF", design: "default", radius: 10),
        preset("candy", "Candy", accent: "#FF4FA3", second: "#8B5CF6", bg: "#FFF0F8", surface: "#FFFFFF", design: "rounded", radius: 22),
        preset("luxury", "Luxury", accent: "#C9A227", second: "#8C6D1F", bg: "#0E0D0B", surface: "#1B1914", design: "serif", radius: 8, appearance: .dark),
        preset("mint", "Mint", accent: "#00B894", second: "#00CEC9", bg: "#EFFBF8", surface: "#FFFFFF", design: "rounded", radius: 16),
        preset("coffee", "Coffee", accent: "#8B5E3C", second: "#D4A373", bg: "#FAF5EF", surface: "#FFFFFF", design: "serif", radius: 12),
        preset("neon", "Neon", accent: "#39FF14", second: "#00E5FF", bg: "#050505", surface: "#121212", design: "monospaced", radius: 6, appearance: .dark),
        preset("royal", "Royal", accent: "#4338CA", second: "#DB2777", bg: "#F5F3FF", surface: "#FFFFFF", design: "default", radius: 14),
    ]

    static func preset(_ id: String, _ name: String, accent: String, second: String, bg: String, surface: String, design: String, radius: Double, appearance: Theme.Appearance = .system) -> ThemePreset {
        var t = Theme()
        t.presetID = id
        t.accent = accent
        t.secondaryAccent = second
        t.fontDesign = design
        t.cornerRadius = radius
        t.appearance = appearance
        if appearance == .dark {
            t.darkBackground = bg; t.darkSurface = surface
            t.background = bg; t.surface = surface
            t.text = "#FFFFFF"; t.secondaryText = "#A1A1AA"
        } else {
            t.background = bg; t.surface = surface
        }
        return ThemePreset(id: id, name: name, theme: t, iconBackground: [accent, second])
    }

    public static func named(_ name: String) -> ThemePreset? {
        let key = name.lowercased()
        return all.first { $0.id == key || $0.name.lowercased() == key }
    }
}

// MARK: - Brand

public struct IconSpec: Codable, Hashable {
    public enum Kind: String, Codable, CaseIterable { case symbol, emoji, text, image }
    public var kind: Kind
    public var symbol: String
    public var emoji: String
    public var text: String
    public var imageAsset: String?
    public var background: Fill
    public var glyphColor: String
    public var glyphScale: Double
    public var showsShine: Bool

    public init(kind: Kind = .symbol, symbol: String = "sparkles", emoji: String = "🚀", text: String = "A", imageAsset: String? = nil,
                background: Fill = .linear(["#6C5CFF", "#FF7A45"]), glyphColor: String = "#FFFFFF", glyphScale: Double = 0.56, showsShine: Bool = true) {
        self.kind = kind; self.symbol = symbol; self.emoji = emoji; self.text = text; self.imageAsset = imageAsset
        self.background = background; self.glyphColor = glyphColor; self.glyphScale = glyphScale; self.showsShine = showsShine
    }

    enum CodingKeys: String, CodingKey { case kind, symbol, emoji, text, imageAsset, background, glyphColor, glyphScale, showsShine }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = IconSpec()
        kind = c.value(.kind, d.kind); symbol = c.value(.symbol, d.symbol); emoji = c.value(.emoji, d.emoji)
        text = c.value(.text, d.text); imageAsset = c.optional(.imageAsset); background = c.value(.background, d.background)
        glyphColor = c.value(.glyphColor, d.glyphColor); glyphScale = c.value(.glyphScale, d.glyphScale); showsShine = c.value(.showsShine, d.showsShine)
    }
}

public struct SplashSpec: Codable, Hashable {
    public enum Animation: String, Codable, CaseIterable { case fade, zoom, slide, pulse, none }
    public var enabled: Bool
    public var animation: Animation
    public var duration: Double
    public var background: Fill?
    public var showsIcon: Bool
    public var title: String
    public var subtitle: String

    public init(enabled: Bool = true, animation: Animation = .zoom, duration: Double = 1.2, background: Fill? = nil,
                showsIcon: Bool = true, title: String = "", subtitle: String = "") {
        self.enabled = enabled; self.animation = animation; self.duration = duration; self.background = background
        self.showsIcon = showsIcon; self.title = title; self.subtitle = subtitle
    }

    enum CodingKeys: String, CodingKey { case enabled, animation, duration, background, showsIcon, title, subtitle }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SplashSpec()
        enabled = c.value(.enabled, d.enabled); animation = c.value(.animation, d.animation); duration = c.value(.duration, d.duration)
        background = c.optional(.background); showsIcon = c.value(.showsIcon, d.showsIcon)
        title = c.value(.title, d.title); subtitle = c.value(.subtitle, d.subtitle)
    }
}

public struct Brand: Codable, Hashable {
    public var displayName: String
    public var tagline: String
    public var icon: IconSpec
    public var splash: SplashSpec
    public var showsMadeWithBadge: Bool
    public var copyright: String

    public init(displayName: String, tagline: String = "", icon: IconSpec = IconSpec(), splash: SplashSpec = SplashSpec(), showsMadeWithBadge: Bool = true, copyright: String = "") {
        self.displayName = displayName; self.tagline = tagline; self.icon = icon; self.splash = splash
        self.showsMadeWithBadge = showsMadeWithBadge; self.copyright = copyright
    }

    enum CodingKeys: String, CodingKey { case displayName, tagline, icon, splash, showsMadeWithBadge, copyright }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = c.value(.displayName, "App"); tagline = c.value(.tagline, ""); icon = c.value(.icon, IconSpec())
        splash = c.value(.splash, SplashSpec()); showsMadeWithBadge = c.value(.showsMadeWithBadge, true); copyright = c.value(.copyright, "")
    }

    /// iOS truncates Home Screen names around 12 characters.
    public var homeScreenNameWarning: String? {
        displayName.count > 14 ? "Long names get truncated on the Home Screen. Consider \(displayName.count) → 12 characters." : nil
    }
}

// MARK: - Colors

public enum ColorNames {
    /// Apple system colors (light appearance) plus common CSS names.
    public static let table: [String: String] = [
        "red": "#FF3B30", "orange": "#FF9500", "yellow": "#FFCC00", "green": "#34C759", "mint": "#00C7BE", "teal": "#30B0C7",
        "cyan": "#32ADE6", "blue": "#007AFF", "indigo": "#5856D6", "purple": "#AF52DE", "pink": "#FF2D55", "brown": "#A2845E",
        "gray": "#8E8E93", "grey": "#8E8E93", "black": "#000000", "white": "#FFFFFF", "clear": "#00000000", "transparent": "#00000000",
        "gold": "#C9A227", "silver": "#C0C0C0", "navy": "#1E3A8A", "maroon": "#800000", "olive": "#808000", "lime": "#84CC16",
        "magenta": "#FF00FF", "violet": "#8B5CF6", "lavender": "#B4A7F5", "coral": "#FF7F50", "salmon": "#FA8072", "peach": "#FFB38A",
        "beige": "#F5F0E6", "cream": "#FFF8E7", "charcoal": "#36454F", "slate": "#64748B", "sky": "#38BDF8", "rose": "#F43F5E",
        "emerald": "#10B981", "amber": "#F59E0B", "crimson": "#DC143C", "turquoise": "#40E0D0", "aqua": "#00FFFF", "tan": "#D2B48C",
        "darkgray": "#3A3A3C", "lightgray": "#D1D1D6", "darkblue": "#0A3D91", "lightblue": "#9AD0FF", "darkgreen": "#1E7B3A",
        "lightgreen": "#A7F3D0", "darkred": "#8B0000", "burgundy": "#800020", "plum": "#8E4585", "mustard": "#E1AD01", "sand": "#E6D3A3",
    ]

    public static let systemNames = ["red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo", "purple", "pink", "brown", "gray", "black", "white"]

    public static func hex(for name: String) -> String? {
        let key = name.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if let h = table[key] { return h }
        if isHex(name) { return normalizedHex(name) }
        return nil
    }

    public static func isHex(_ s: String) -> Bool {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() } else { return false }
        return [3, 6, 8].contains(t.count) && t.allSatisfy { $0.isHexDigit }
    }

    public static func normalizedHex(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        return "#" + t.uppercased()
    }

    /// Returns RGBA components 0...1 for a hex string.
    public static func rgba(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        guard isHex(hex) else { return nil }
        let t = String(normalizedHex(hex).dropFirst())
        var v: UInt64 = 0
        guard Scanner(string: t).scanHexInt64(&v) else { return nil }
        if t.count == 8 {
            return (Double((v >> 24) & 0xFF) / 255, Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
        }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, 1)
    }

    public static func hex(r: Double, g: Double, b: Double, a: Double = 1) -> String {
        func c(_ x: Double) -> String { String(format: "%02X", Int((min(max(x, 0), 1) * 255).rounded())) }
        return "#" + c(r) + c(g) + c(b) + (a < 0.999 ? c(a) : "")
    }

    /// Relative luminance, used to choose readable foreground colors.
    public static func luminance(_ hex: String) -> Double {
        guard let c = rgba(hex) else { return 0.5 }
        func lin(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    public static func readableForeground(on hex: String) -> String {
        luminance(hex) > 0.45 ? "#111114" : "#FFFFFF"
    }

    public static func mix(_ a: String, _ b: String, _ t: Double) -> String {
        guard let x = rgba(a), let y = rgba(b) else { return a }
        return hex(r: x.r + (y.r - x.r) * t, g: x.g + (y.g - x.g) * t, b: x.b + (y.b - x.b) * t, a: x.a + (y.a - x.a) * t)
    }
}

import Foundation

public enum ComponentType: String, Codable, CaseIterable, Hashable {
    // Layout
    case vstack, hstack, zstack, scroll, grid, card, groupBox, disclosure, pager, spacer, divider
    // Lists & forms
    case list, form, section, listRow, navLink, labeledContent
    // Text
    case text, label, badge, link
    // Media
    case image, icon, avatar, video, audio, web, map, qr
    // Data display
    case statCard, chart, gauge, progress, rating, timer, empty
    // Controls
    case button, menu, shareLink, signInApple, toggle, slider, stepper
    // Inputs
    case textField, secureField, textEditor, searchField, picker, datePicker, colorPicker, photoPicker
    // Shapes
    case shape, gradient

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ComponentType(rawValue: raw) ?? ComponentType.alias(raw) ?? .text
    }

    /// Accepts legacy and friendly names (ReyForge 2.x kinds, SwiftUI names, AI variations).
    public static func alias(_ raw: String) -> ComponentType? {
        let k = raw.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        let map: [String: ComponentType] = [
            "vstack": .vstack, "column": .vstack, "stack": .vstack, "hstack": .hstack, "row": .hstack, "zstack": .zstack, "freelayout": .zstack, "canvas": .zstack,
            "scrollview": .scroll, "scroll": .scroll, "carousel": .scroll, "lazyvgrid": .grid, "grid": .grid, "card": .card, "groupbox": .groupBox,
            "disclosuregroup": .disclosure, "disclosure": .disclosure, "accordion": .disclosure, "tabview": .pager, "pager": .pager, "pageview": .pager,
            "spacer": .spacer, "divider": .divider, "separator": .divider, "list": .list, "form": .form, "section": .section,
            "listrow": .listRow, "cell": .listRow, "navigationlink": .navLink, "navlink": .navLink, "labeledcontent": .labeledContent, "info": .labeledContent,
            "text": .text, "title": .text, "heading": .text, "caption": .text, "paragraph": .text, "label": .label, "badge": .badge, "tag": .badge, "chip": .badge,
            "link": .link, "image": .image, "asyncimage": .image, "photo": .image, "symbol": .icon, "sfsymbol": .icon, "icon": .icon, "avatar": .avatar,
            "video": .video, "videoplayer": .video, "audio": .audio, "player": .audio, "webview": .web, "web": .web, "map": .map, "mapview": .map,
            "qr": .qr, "qrcode": .qr, "stat": .statCard, "statcard": .statCard, "kpi": .statCard, "metric": .statCard, "chart": .chart, "graph": .chart,
            "gauge": .gauge, "progress": .progress, "progressview": .progress, "progressbar": .progress, "rating": .rating, "stars": .rating,
            "timer": .timer, "stopwatch": .timer, "countdown": .timer, "empty": .empty, "contentunavailable": .empty, "emptystate": .empty,
            "button": .button, "menu": .menu, "sharelink": .shareLink, "share": .shareLink, "signinwithapple": .signInApple, "applesignin": .signInApple,
            "toggle": .toggle, "switch": .toggle, "slider": .slider, "stepper": .stepper, "textfield": .textField, "input": .textField, "field": .textField,
            "securefield": .secureField, "password": .secureField, "texteditor": .textEditor, "textarea": .textEditor, "editor": .textEditor,
            "searchfield": .searchField, "search": .searchField, "searchbar": .searchField, "picker": .picker, "segmented": .picker, "dropdown": .picker,
            "select": .picker, "datepicker": .datePicker, "date": .datePicker, "colorpicker": .colorPicker, "color": .colorPicker,
            "photopicker": .photoPicker, "photospicker": .photoPicker, "shape": .shape, "rectangle": .shape, "roundedrectangle": .shape,
            "circle": .shape, "capsule": .shape, "ellipse": .shape, "gradient": .gradient,
        ]
        return map[k]
    }
}

public enum ComponentCategory: String, CaseIterable, Hashable {
    case layout = "Layout", lists = "Lists & Forms", text = "Text", media = "Media", data = "Data", controls = "Controls", inputs = "Inputs", shapes = "Shapes"

    public var symbol: String {
        switch self {
        case .layout: return "square.split.2x2"
        case .lists: return "list.bullet.rectangle"
        case .text: return "textformat"
        case .media: return "photo.on.rectangle"
        case .data: return "chart.bar.xaxis"
        case .controls: return "switch.2"
        case .inputs: return "character.cursor.ibeam"
        case .shapes: return "circle.square"
        }
    }
}

public enum PropertyKind: Hashable {
    case text, multiline, bool, color, symbol, url, image, list, chartData, markers, expression, screen, date
    case number(min: Double?, max: Double?, step: Double?)
    case options([String])
}

public struct PropertySpec: Hashable {
    public let key: String
    public let label: String
    public let kind: PropertyKind
    public let defaultValue: Value
    public let help: String

    public init(_ key: String, _ label: String, _ kind: PropertyKind, _ defaultValue: Value = .null, help: String = "") {
        self.key = key; self.label = label; self.kind = kind; self.defaultValue = defaultValue; self.help = help
    }
}

public struct ComponentSpec {
    public let type: ComponentType
    public let title: String
    public let symbol: String
    public let category: ComponentCategory
    public let summary: String
    public let isContainer: Bool
    public let properties: [PropertySpec]
    public let events: [EventKind]
    public let bindable: ValueKind?
    public let supportsRepeat: Bool
    public let defaultStyle: Style
    public let rfsKeyword: String

    public func defaultValue(for key: String) -> Value {
        properties.first { $0.key == key }?.defaultValue ?? .null
    }

    public var defaultProps: [String: Value] {
        var d: [String: Value] = [:]
        for p in properties where !p.defaultValue.isNull { d[p.key] = p.defaultValue }
        return d
    }

    /// A fully configured instance as inserted from the library.
    public func makeNode() -> Node {
        var node = Node(type: type, props: defaultProps, style: defaultStyle)
        switch type {
        case .menu:
            node.children = [
                Node(type: .button, props: ["title": "Edit", "icon": "pencil", "variant": "plain"]),
                Node(type: .button, props: ["title": "Duplicate", "icon": "plus.square.on.square", "variant": "plain"]),
                Node(type: .button, props: ["title": "Delete", "icon": "trash", "variant": "plain", "role": "destructive"]),
            ]
        case .list:
            node.children = [
                Node(type: .listRow, props: ["title": "First item", "subtitle": "Details", "icon": "star.fill", "accessory": "chevron"]),
                Node(type: .listRow, props: ["title": "Second item", "subtitle": "Details", "icon": "heart.fill", "accessory": "chevron"]),
            ]
        case .form:
            var section = ComponentRegistry.spec(for: .section).makeNode()
            section.props["header"] = "Preferences"
            section.children = [
                Node(type: .toggle, props: ["title": "Notifications"]),
                Node(type: .picker, props: ["title": "Theme", "options": ["System", "Light", "Dark"], "variant": "menu"]),
            ]
            node.children = [section]
        case .section:
            node.children = [Node(type: .listRow, props: ["title": "Row", "icon": "circle", "accessory": "chevron"])]
        case .pager:
            node.children = (1...3).map { i in
                Node(type: .vstack, props: ["spacing": 12, "alignment": "center"], style: Style(padding: Insets(all: 24)), children: [
                    Node(type: .icon, props: ["symbol": .string(["sparkles", "bolt.fill", "checkmark.seal.fill"][i - 1]), "size": 64]),
                    Node(type: .text, props: ["text": .string("Page \(i)"), "alignment": "center"], style: Style(font: FontSpec(style: "title2", weight: "bold"))),
                    Node(type: .text, props: ["text": "Swipe to continue", "alignment": "center"], style: Style(foreground: "secondaryText")),
                ])
            }
        case .card:
            node.children = [
                Node(type: .text, props: ["text": "Card title"], style: Style(font: FontSpec(style: "headline"))),
                Node(type: .text, props: ["text": "Supporting text goes here."], style: Style(foreground: "secondaryText")),
            ]
        case .hstack:
            node.children = [
                Node(type: .statCard, props: ["title": "Steps", "value": "8,412", "icon": "figure.walk"]),
                Node(type: .statCard, props: ["title": "Calories", "value": "512", "icon": "flame.fill", "tint": "orange"]),
            ]
        case .vstack:
            node.children = [
                Node(type: .text, props: ["text": "Stack item"], style: Style(font: FontSpec(style: "headline"))),
                Node(type: .text, props: ["text": "Another item"]),
            ]
        case .zstack:
            node.children = [
                Node(type: .shape, props: ["shape": "circle", "fill": "accent"], style: Style(width: .fixed(90), height: .fixed(90), offsetX: 24, offsetY: 24)),
                Node(type: .text, props: ["text": "Drag me anywhere"], style: Style(offsetX: 130, offsetY: 60, font: FontSpec(style: "headline"))),
            ]
        case .grid:
            node.children = (0..<4).map { i in
                Node(type: .card, props: ["spacing": 6], style: Style(padding: Insets(all: 12), background: .solid("surface"), shadow: .small), children: [
                    Node(type: .icon, props: ["symbol": .string(["leaf.fill", "drop.fill", "sun.max.fill", "moon.stars.fill"][i]), "size": 26]),
                    Node(type: .text, props: ["text": .string(["Garden", "Water", "Sun", "Night"][i])], style: Style(font: FontSpec(style: "headline"))),
                ])
            }
        case .scroll:
            node.children = (0..<4).map { i in
                Node(type: .image, props: ["source": .string("https://picsum.photos/seed/rf\(i)/400/300"), "contentMode": "fill"],
                     style: Style(width: .fixed(180), height: .fixed(120), cornerRadius: 14))
            }
        case .groupBox:
            node.children = [Node(type: .text, props: ["text": "Grouped content"])]
        case .disclosure:
            node.children = [Node(type: .text, props: ["text": "Hidden details revealed when expanded."], style: Style(foreground: "secondaryText"))]
        default: break
        }
        return node
    }
}

// MARK: - Registry

public enum ComponentRegistry {
    static let alignH: PropertyKind = .options(["leading", "center", "trailing"])

    public static let all: [ComponentSpec] = [
        // Layout
        ComponentSpec(type: .vstack, title: "Vertical Stack", symbol: "square.3.layers.3d", category: .layout, summary: "Arranges items top to bottom",
                      isContainer: true, properties: [PropertySpec("spacing", "Spacing", .number(min: 0, max: 80, step: 2), 12), PropertySpec("alignment", "Alignment", alignH, "leading")],
                      events: [.tap, .appear], bindable: nil, supportsRepeat: true, defaultStyle: Style(), rfsKeyword: "VSTACK"),
        ComponentSpec(type: .hstack, title: "Horizontal Stack", symbol: "rectangle.split.3x1", category: .layout, summary: "Arranges items side by side",
                      isContainer: true, properties: [PropertySpec("spacing", "Spacing", .number(min: 0, max: 80, step: 2), 12),
                                                      PropertySpec("alignment", "Alignment", .options(["top", "center", "bottom"]), "center"),
                                                      PropertySpec("equalWidths", "Equal widths", .bool, true)],
                      events: [.tap], bindable: nil, supportsRepeat: true, defaultStyle: Style(), rfsKeyword: "HSTACK"),
        ComponentSpec(type: .zstack, title: "Free Layout", symbol: "square.stack.3d.down.right", category: .layout, summary: "Drag children to any position (ZStack)",
                      isContainer: true, properties: [PropertySpec("clipsContent", "Clip content", .bool, true)],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill, height: .fixed(240), background: .solid("surface"), cornerRadius: 16), rfsKeyword: "ZSTACK"),
        ComponentSpec(type: .scroll, title: "Scroll View", symbol: "arrow.left.and.right.square", category: .layout, summary: "Scrollable row or column (carousel)",
                      isContainer: true, properties: [PropertySpec("axis", "Direction", .options(["horizontal", "vertical"]), "horizontal"),
                                                      PropertySpec("spacing", "Spacing", .number(min: 0, max: 60, step: 2), 12),
                                                      PropertySpec("paging", "Paging", .bool, false), PropertySpec("showsIndicators", "Indicators", .bool, false)],
                      events: [], bindable: nil, supportsRepeat: true, defaultStyle: Style(), rfsKeyword: "SCROLL"),
        ComponentSpec(type: .grid, title: "Grid", symbol: "square.grid.2x2", category: .layout, summary: "Lazy grid with columns",
                      isContainer: true, properties: [PropertySpec("columns", "Columns", .number(min: 1, max: 6, step: 1), 2), PropertySpec("spacing", "Spacing", .number(min: 0, max: 40, step: 2), 12)],
                      events: [], bindable: nil, supportsRepeat: true, defaultStyle: Style(), rfsKeyword: "GRID"),
        ComponentSpec(type: .card, title: "Card", symbol: "rectangle.on.rectangle", category: .layout, summary: "Rounded surface with padding and shadow",
                      isContainer: true, properties: [PropertySpec("spacing", "Spacing", .number(min: 0, max: 40, step: 2), 8), PropertySpec("alignment", "Alignment", alignH, "leading")],
                      events: [.tap, .longPress], bindable: nil, supportsRepeat: true,
                      defaultStyle: Style(width: .fill, padding: Insets(all: 16), background: .solid("surface"), shadow: .small), rfsKeyword: "CARD"),
        ComponentSpec(type: .groupBox, title: "Group Box", symbol: "square.on.square.dashed", category: .layout, summary: "Native GroupBox with label",
                      isContainer: true, properties: [PropertySpec("title", "Title", .text, "Group"), PropertySpec("icon", "Icon", .symbol, "")],
                      events: [], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill), rfsKeyword: "GROUP"),
        ComponentSpec(type: .disclosure, title: "Disclosure Group", symbol: "chevron.down.square", category: .layout, summary: "Expandable section",
                      isContainer: true, properties: [PropertySpec("title", "Title", .text, "More details"), PropertySpec("expanded", "Expanded", .bool, false)],
                      events: [], bindable: .bool, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "DISCLOSURE"),
        ComponentSpec(type: .pager, title: "Page View", symbol: "rectangle.portrait.on.rectangle.portrait", category: .layout, summary: "Swipeable pages (TabView page style)",
                      isContainer: true, properties: [PropertySpec("showsIndicators", "Page dots", .bool, true), PropertySpec("autoAdvance", "Auto-advance seconds", .number(min: 0, max: 30, step: 1), 0)],
                      events: [.change], bindable: .number, supportsRepeat: true, defaultStyle: Style(width: .fill, height: .fixed(320)), rfsKeyword: "PAGER"),
        ComponentSpec(type: .spacer, title: "Spacer", symbol: "arrow.up.and.down", category: .layout, summary: "Flexible empty space",
                      isContainer: false, properties: [PropertySpec("minLength", "Size", .number(min: 0, max: 400, step: 4), 16)],
                      events: [], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "SPACER"),
        ComponentSpec(type: .divider, title: "Divider", symbol: "minus", category: .layout, summary: "Hairline separator",
                      isContainer: false, properties: [], events: [], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "DIVIDER"),
        // Lists & forms
        ComponentSpec(type: .list, title: "List", symbol: "list.bullet.rectangle", category: .lists, summary: "Native list with rows and swipe actions",
                      isContainer: true, properties: [PropertySpec("variant", "Style", .options(["insetGrouped", "plain", "grouped", "inset"]), "insetGrouped"),
                                                      PropertySpec("header", "Header", .text, ""), PropertySpec("footer", "Footer", .text, "")],
                      events: [], bindable: nil, supportsRepeat: true, defaultStyle: Style(width: .fill), rfsKeyword: "LIST"),
        ComponentSpec(type: .form, title: "Form", symbol: "list.bullet.rectangle.portrait", category: .lists, summary: "Grouped settings-style form",
                      isContainer: true, properties: [], events: [], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill), rfsKeyword: "FORM"),
        ComponentSpec(type: .section, title: "Section", symbol: "rectangle.grid.1x2", category: .lists, summary: "Section with header and footer",
                      isContainer: true, properties: [PropertySpec("header", "Header", .text, "Section"), PropertySpec("footer", "Footer", .text, "")],
                      events: [], bindable: nil, supportsRepeat: true, defaultStyle: Style(), rfsKeyword: "SECTION"),
        ComponentSpec(type: .listRow, title: "List Row", symbol: "list.bullet", category: .lists, summary: "Title, subtitle, icon and trailing value",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Row title"), PropertySpec("subtitle", "Subtitle", .text, ""),
                                                       PropertySpec("value", "Trailing value", .text, ""), PropertySpec("icon", "Icon / image", .image, "circle.fill"),
                                                       PropertySpec("iconColor", "Icon color", .color, "accent"), PropertySpec("badge", "Badge", .text, ""),
                                                       PropertySpec("accessory", "Accessory", .options(["none", "chevron", "checkmark", "info"]), "none"),
                                                       PropertySpec("deleteLabel", "Swipe action label", .text, "Delete")],
                      events: [.tap, .longPress, .delete], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "ROW"),
        ComponentSpec(type: .navLink, title: "Navigation Link", symbol: "arrow.right.circle", category: .lists, summary: "Row that pushes another screen",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Open details"), PropertySpec("subtitle", "Subtitle", .text, ""),
                                                       PropertySpec("icon", "Icon", .symbol, "arrow.right.circle.fill"), PropertySpec("iconColor", "Icon color", .color, "accent"),
                                                       PropertySpec("destination", "Destination", .screen, "")],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "NAVLINK"),
        ComponentSpec(type: .labeledContent, title: "Labeled Content", symbol: "text.append", category: .lists, summary: "Label with a trailing value",
                      isContainer: false, properties: [PropertySpec("title", "Label", .text, "Version"), PropertySpec("value", "Value", .text, "1.0")],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "INFO"),
        // Text
        ComponentSpec(type: .text, title: "Text", symbol: "textformat", category: .text, summary: "Text with Markdown and {{variables}}",
                      isContainer: false, properties: [PropertySpec("text", "Text", .multiline, "Hello, world!"), PropertySpec("alignment", "Alignment", alignH, "leading"),
                                                       PropertySpec("lineLimit", "Line limit (0 = none)", .number(min: 0, max: 20, step: 1), 0),
                                                       PropertySpec("markdown", "Markdown", .bool, true)],
                      events: [.tap, .longPress], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "TEXT"),
        ComponentSpec(type: .label, title: "Label", symbol: "tag", category: .text, summary: "Icon and title (SwiftUI Label)",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Favorites"), PropertySpec("icon", "Icon", .symbol, "star.fill"),
                                                       PropertySpec("iconColor", "Icon color", .color, "accent"),
                                                       PropertySpec("variant", "Style", .options(["titleAndIcon", "iconOnly", "titleOnly"]), "titleAndIcon")],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "LABEL"),
        ComponentSpec(type: .badge, title: "Badge", symbol: "capsule", category: .text, summary: "Small capsule tag",
                      isContainer: false, properties: [PropertySpec("text", "Text", .text, "New"), PropertySpec("color", "Color", .color, "accent"),
                                                       PropertySpec("variant", "Style", .options(["filled", "tinted", "outlined"]), "tinted"), PropertySpec("icon", "Icon", .symbol, "")],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "BADGE"),
        ComponentSpec(type: .link, title: "Link", symbol: "link", category: .text, summary: "Opens a URL",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Learn more"), PropertySpec("url", "URL", .url, "https://www.apple.com"),
                                                       PropertySpec("icon", "Icon", .symbol, "")],
                      events: [], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "LINK"),
        // Media
        ComponentSpec(type: .image, title: "Image", symbol: "photo", category: .media, summary: "Remote URL, imported photo or SF Symbol",
                      isContainer: false, properties: [PropertySpec("source", "Image", .image, "https://picsum.photos/seed/reyforge/800/500"),
                                                       PropertySpec("contentMode", "Content mode", .options(["fill", "fit"]), "fill"),
                                                       PropertySpec("overlayText", "Overlay text", .text, "")],
                      events: [.tap, .longPress], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill, height: .fixed(180), cornerRadius: 16), rfsKeyword: "IMAGE"),
        ComponentSpec(type: .icon, title: "SF Symbol", symbol: "star.square", category: .media, summary: "Any of 6,000+ SF Symbols",
                      isContainer: false, properties: [PropertySpec("symbol", "Symbol", .symbol, "star.fill"), PropertySpec("size", "Size", .number(min: 8, max: 240, step: 2), 32),
                                                       PropertySpec("renderingMode", "Rendering", .options(["monochrome", "hierarchical", "palette", "multicolor"]), "hierarchical"),
                                                       PropertySpec("secondaryColor", "Secondary color", .color, "secondary"),
                                                       PropertySpec("effect", "Animation", .options(["none", "pulse", "bounce", "variableColor", "breathe", "wiggle"]), "none")],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(foreground: "accent"), rfsKeyword: "ICON"),
        ComponentSpec(type: .avatar, title: "Avatar", symbol: "person.crop.circle", category: .media, summary: "Profile photo or initials",
                      isContainer: false, properties: [PropertySpec("name", "Name", .text, "Alex Morgan"), PropertySpec("image", "Photo URL", .image, ""),
                                                       PropertySpec("size", "Size", .number(min: 20, max: 200, step: 2), 56),
                                                       PropertySpec("status", "Status", .options(["none", "online", "away", "busy"]), "none")],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "AVATAR"),
        ComponentSpec(type: .video, title: "Video Player", symbol: "play.rectangle", category: .media, summary: "AVKit video player",
                      isContainer: false, properties: [PropertySpec("url", "Video URL", .url, "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"),
                                                       PropertySpec("autoplay", "Autoplay", .bool, false), PropertySpec("loops", "Loop", .bool, false)],
                      events: [], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill, height: .fixed(220), cornerRadius: 16), rfsKeyword: "VIDEO"),
        ComponentSpec(type: .audio, title: "Audio Player", symbol: "waveform", category: .media, summary: "Play audio from a URL",
                      isContainer: false, properties: [PropertySpec("url", "Audio URL", .url, "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3"),
                                                       PropertySpec("title", "Title", .text, "Morning Session"), PropertySpec("artist", "Artist", .text, "ReyForge Radio"),
                                                       PropertySpec("artwork", "Artwork", .image, "https://picsum.photos/seed/album/400/400")],
                      events: [], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill), rfsKeyword: "AUDIO"),
        ComponentSpec(type: .web, title: "Web View", symbol: "safari", category: .media, summary: "Embedded web page (WKWebView)",
                      isContainer: false, properties: [PropertySpec("url", "URL", .url, "https://www.apple.com")],
                      events: [], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill, height: .fixed(380), cornerRadius: 16), rfsKeyword: "WEB"),
        ComponentSpec(type: .map, title: "Map", symbol: "map", category: .media, summary: "MapKit map with markers",
                      isContainer: false, properties: [PropertySpec("title", "Place name", .text, "Apple Park"), PropertySpec("latitude", "Latitude", .number(min: -90, max: 90, step: 0.0001), 37.3349),
                                                       PropertySpec("longitude", "Longitude", .number(min: -180, max: 180, step: 0.0001), -122.009),
                                                       PropertySpec("span", "Zoom (degrees)", .number(min: 0.001, max: 60, step: 0.005), 0.03),
                                                       PropertySpec("markers", "Markers", .markers, "Apple Park:37.3349,-122.009"),
                                                       PropertySpec("variant", "Style", .options(["standard", "imagery", "hybrid"]), "standard"),
                                                       PropertySpec("interactive", "Interactive", .bool, true)],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill, height: .fixed(220), cornerRadius: 16), rfsKeyword: "MAP"),
        ComponentSpec(type: .qr, title: "QR Code", symbol: "qrcode", category: .media, summary: "Generated QR code",
                      isContainer: false, properties: [PropertySpec("content", "Content", .text, "https://github.com/rvmendillo/ipabuilder"), PropertySpec("size", "Size", .number(min: 60, max: 360, step: 10), 180)],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "QR"),
        // Data
        ComponentSpec(type: .statCard, title: "Stat Card", symbol: "chart.bar.doc.horizontal", category: .data, summary: "KPI tile with value and trend",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Revenue"), PropertySpec("value", "Value", .text, "$12.4K"),
                                                       PropertySpec("delta", "Change", .text, "+8.2%"), PropertySpec("icon", "Icon", .symbol, "chart.line.uptrend.xyaxis"),
                                                       PropertySpec("tint", "Tint", .color, "accent")],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill), rfsKeyword: "STAT"),
        ComponentSpec(type: .chart, title: "Chart", symbol: "chart.xyaxis.line", category: .data, summary: "Swift Charts: bar, line, area, pie",
                      isContainer: false, properties: [PropertySpec("kind", "Type", .options(["bar", "line", "area", "point", "pie", "donut"]), "bar"),
                                                       PropertySpec("title", "Title", .text, "This week"),
                                                       PropertySpec("data", "Data", .chartData, "Mon:4,Tue:7,Wed:5,Thu:9,Fri:6,Sat:11,Sun:8"),
                                                       PropertySpec("xField", "Label field", .text, "label"), PropertySpec("yField", "Value field", .text, "value"),
                                                       PropertySpec("color", "Color", .color, "accent"), PropertySpec("showsGrid", "Grid lines", .bool, true)],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill, height: .fixed(200)), rfsKeyword: "CHART"),
        ComponentSpec(type: .gauge, title: "Gauge", symbol: "gauge.with.dots.needle.67percent", category: .data, summary: "Native Gauge",
                      isContainer: false, properties: [PropertySpec("label", "Label", .text, "Battery"), PropertySpec("value", "Value", .expression, 72),
                                                       PropertySpec("min", "Minimum", .number(min: nil, max: nil, step: 1), 0), PropertySpec("max", "Maximum", .number(min: nil, max: nil, step: 1), 100),
                                                       PropertySpec("variant", "Style", .options(["circular", "circularCapacity", "linear", "linearCapacity"]), "circularCapacity"),
                                                       PropertySpec("tint", "Tint", .color, "accent"), PropertySpec("symbol", "Symbol", .symbol, "")],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "GAUGE"),
        ComponentSpec(type: .progress, title: "Progress View", symbol: "progress.indicator", category: .data, summary: "Linear, circular or indeterminate",
                      isContainer: false, properties: [PropertySpec("label", "Label", .text, "Uploading"), PropertySpec("value", "Value (0–total, empty = spinner)", .expression, 0.6),
                                                       PropertySpec("total", "Total", .number(min: 0.0001, max: nil, step: 1), 1),
                                                       PropertySpec("variant", "Style", .options(["linear", "circular"]), "linear"), PropertySpec("showsValue", "Show percentage", .bool, true),
                                                       PropertySpec("tint", "Tint", .color, "accent")],
                      events: [], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill), rfsKeyword: "PROGRESS"),
        ComponentSpec(type: .rating, title: "Rating", symbol: "star.leadinghalf.filled", category: .data, summary: "Star rating (interactive)",
                      isContainer: false, properties: [PropertySpec("value", "Value", .expression, 4), PropertySpec("max", "Stars", .number(min: 1, max: 10, step: 1), 5),
                                                       PropertySpec("interactive", "Tappable", .bool, true), PropertySpec("symbol", "Symbol", .symbol, "star.fill"),
                                                       PropertySpec("color", "Color", .color, "yellow")],
                      events: [.change], bindable: .number, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "RATING"),
        ComponentSpec(type: .timer, title: "Timer", symbol: "timer", category: .data, summary: "Countdown or stopwatch with controls",
                      isContainer: false, properties: [PropertySpec("mode", "Mode", .options(["countdown", "stopwatch"]), "countdown"),
                                                       PropertySpec("seconds", "Countdown seconds", .number(min: 1, max: 86400, step: 5), 300),
                                                       PropertySpec("showsControls", "Show controls", .bool, true), PropertySpec("tint", "Tint", .color, "accent")],
                      events: [.submit], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill), rfsKeyword: "TIMER"),
        ComponentSpec(type: .empty, title: "Empty State", symbol: "tray", category: .data, summary: "ContentUnavailableView",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "No Items"), PropertySpec("symbol", "Symbol", .symbol, "tray"),
                                                       PropertySpec("message", "Message", .text, "Items you add will appear here."), PropertySpec("actionTitle", "Button", .text, "")],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill), rfsKeyword: "EMPTY"),
        // Controls
        ComponentSpec(type: .button, title: "Button", symbol: "rectangle.and.hand.point.up.left", category: .controls, summary: "Tap to run actions",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Continue"), PropertySpec("icon", "Icon", .symbol, ""),
                                                       PropertySpec("variant", "Style", .options(["prominent", "bordered", "plain", "borderless", "glass", "capsule", "destructive", "link"]), "prominent"),
                                                       PropertySpec("size", "Size", .options(["small", "regular", "large"]), "large"), PropertySpec("fullWidth", "Full width", .bool, true),
                                                       PropertySpec("role", "Role", .options(["none", "destructive", "cancel"]), "none"), PropertySpec("tint", "Tint", .color, "")],
                      events: [.tap, .longPress], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "BUTTON"),
        ComponentSpec(type: .menu, title: "Menu", symbol: "filemenu.and.selection", category: .controls, summary: "Pop-up menu of buttons",
                      isContainer: true, properties: [PropertySpec("title", "Title", .text, "Options"), PropertySpec("icon", "Icon", .symbol, "ellipsis.circle"),
                                                      PropertySpec("variant", "Style", .options(["bordered", "plain", "prominent"]), "bordered")],
                      events: [], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "MENU"),
        ComponentSpec(type: .shareLink, title: "Share Link", symbol: "square.and.arrow.up", category: .controls, summary: "Native share sheet",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Share"), PropertySpec("item", "Text or URL", .text, "https://github.com/rvmendillo/ipabuilder"),
                                                       PropertySpec("icon", "Icon", .symbol, "square.and.arrow.up")],
                      events: [], bindable: nil, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "SHARE"),
        ComponentSpec(type: .signInApple, title: "Sign in with Apple", symbol: "apple.logo", category: .controls, summary: "Apple-style sign-in button",
                      isContainer: false, properties: [PropertySpec("variant", "Style", .options(["black", "white", "whiteOutline"]), "black"),
                                                       PropertySpec("title", "Title", .text, "Sign in with Apple")],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill, height: .fixed(50)), rfsKeyword: "APPLE"),
        ComponentSpec(type: .toggle, title: "Toggle", symbol: "switch.2", category: .controls, summary: "On/off switch bound to a variable",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Notifications"), PropertySpec("subtitle", "Subtitle", .text, ""),
                                                       PropertySpec("icon", "Icon", .symbol, ""), PropertySpec("isOn", "Initially on", .bool, true),
                                                       PropertySpec("variant", "Style", .options(["switch", "button", "checkbox"]), "switch"), PropertySpec("tint", "Tint", .color, "accent")],
                      events: [.change], bindable: .bool, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "TOGGLE"),
        ComponentSpec(type: .slider, title: "Slider", symbol: "slider.horizontal.3", category: .controls, summary: "Continuous value control",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Volume"), PropertySpec("value", "Initial value", .number(min: nil, max: nil, step: 1), 50),
                                                       PropertySpec("min", "Minimum", .number(min: nil, max: nil, step: 1), 0), PropertySpec("max", "Maximum", .number(min: nil, max: nil, step: 1), 100),
                                                       PropertySpec("step", "Step (0 = smooth)", .number(min: 0, max: nil, step: 1), 1), PropertySpec("showsValue", "Show value", .bool, true),
                                                       PropertySpec("minSymbol", "Min symbol", .symbol, "speaker.fill"), PropertySpec("maxSymbol", "Max symbol", .symbol, "speaker.wave.3.fill"),
                                                       PropertySpec("tint", "Tint", .color, "accent")],
                      events: [.change], bindable: .number, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "SLIDER"),
        ComponentSpec(type: .stepper, title: "Stepper", symbol: "plusminus.circle", category: .controls, summary: "Increment / decrement control",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Guests"), PropertySpec("value", "Initial value", .number(min: nil, max: nil, step: 1), 2),
                                                       PropertySpec("min", "Minimum", .number(min: nil, max: nil, step: 1), 0), PropertySpec("max", "Maximum", .number(min: nil, max: nil, step: 1), 10),
                                                       PropertySpec("step", "Step", .number(min: 0.01, max: nil, step: 1), 1), PropertySpec("format", "Label format", .text, "{{value}}")],
                      events: [.change], bindable: .number, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "STEPPER"),
        // Inputs
        ComponentSpec(type: .textField, title: "Text Field", symbol: "character.cursor.ibeam", category: .inputs, summary: "Single-line text input",
                      isContainer: false, properties: [PropertySpec("placeholder", "Placeholder", .text, "Your name"), PropertySpec("title", "Label", .text, ""),
                                                       PropertySpec("icon", "Icon", .symbol, ""),
                                                       PropertySpec("keyboard", "Keyboard", .options(["default", "email", "number", "decimal", "phone", "url"]), "default"),
                                                       PropertySpec("contentType", "Autofill", .options(["none", "name", "email", "username", "phone", "address", "oneTimeCode"]), "none"),
                                                       PropertySpec("autocapitalize", "Capitalization", .options(["sentences", "words", "characters", "never"]), "sentences"),
                                                       PropertySpec("variant", "Style", .options(["filled", "rounded", "underline", "plain"]), "filled")],
                      events: [.change, .submit], bindable: .text, supportsRepeat: false, defaultStyle: Style(width: .fill), rfsKeyword: "FIELD"),
        ComponentSpec(type: .secureField, title: "Secure Field", symbol: "lock.rectangle", category: .inputs, summary: "Password input",
                      isContainer: false, properties: [PropertySpec("placeholder", "Placeholder", .text, "Password"), PropertySpec("title", "Label", .text, ""),
                                                       PropertySpec("icon", "Icon", .symbol, "lock"), PropertySpec("variant", "Style", .options(["filled", "rounded", "underline", "plain"]), "filled")],
                      events: [.change, .submit], bindable: .text, supportsRepeat: false, defaultStyle: Style(width: .fill), rfsKeyword: "SECURE"),
        ComponentSpec(type: .textEditor, title: "Text Editor", symbol: "text.alignleft", category: .inputs, summary: "Multi-line text input",
                      isContainer: false, properties: [PropertySpec("placeholder", "Placeholder", .text, "Write something…"), PropertySpec("minHeight", "Height", .number(min: 60, max: 600, step: 10), 140)],
                      events: [.change], bindable: .text, supportsRepeat: false, defaultStyle: Style(width: .fill), rfsKeyword: "EDITOR"),
        ComponentSpec(type: .searchField, title: "Search Field", symbol: "magnifyingglass", category: .inputs, summary: "Search bar",
                      isContainer: false, properties: [PropertySpec("placeholder", "Placeholder", .text, "Search")],
                      events: [.change, .submit], bindable: .text, supportsRepeat: false, defaultStyle: Style(width: .fill), rfsKeyword: "SEARCH"),
        ComponentSpec(type: .picker, title: "Picker", symbol: "list.bullet.circle", category: .inputs, summary: "Menu, segmented, wheel or inline picker",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Size"), PropertySpec("options", "Options", .list, ["Small", "Medium", "Large"]),
                                                       PropertySpec("variant", "Style", .options(["menu", "segmented", "wheel", "inline", "palette"]), "segmented")],
                      events: [.change], bindable: .text, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "PICKER"),
        ComponentSpec(type: .datePicker, title: "Date Picker", symbol: "calendar", category: .inputs, summary: "Compact, graphical or wheel date picker",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Date"),
                                                       PropertySpec("components", "Components", .options(["date", "time", "dateTime"]), "date"),
                                                       PropertySpec("variant", "Style", .options(["compact", "graphical", "wheel"]), "compact")],
                      events: [.change], bindable: .date, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "DATE"),
        ComponentSpec(type: .colorPicker, title: "Color Picker", symbol: "paintpalette", category: .inputs, summary: "System color picker",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Color"), PropertySpec("supportsOpacity", "Opacity", .bool, false)],
                      events: [.change], bindable: .color, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "COLOR"),
        ComponentSpec(type: .photoPicker, title: "Photos Picker", symbol: "photo.badge.plus", category: .inputs, summary: "Pick a photo from the library",
                      isContainer: false, properties: [PropertySpec("title", "Title", .text, "Choose photo"), PropertySpec("icon", "Icon", .symbol, "photo.on.rectangle.angled")],
                      events: [.change], bindable: .image, supportsRepeat: false, defaultStyle: Style(), rfsKeyword: "PHOTO"),
        // Shapes
        ComponentSpec(type: .shape, title: "Shape", symbol: "circle.square", category: .shapes, summary: "Rectangle, circle, capsule, ellipse",
                      isContainer: false, properties: [PropertySpec("shape", "Shape", .options(["roundedRectangle", "rectangle", "circle", "capsule", "ellipse"]), "roundedRectangle"),
                                                       PropertySpec("fill", "Fill", .color, "accent"), PropertySpec("strokeColor", "Stroke", .color, ""),
                                                       PropertySpec("strokeWidth", "Stroke width", .number(min: 0, max: 20, step: 0.5), 0)],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fixed(120), height: .fixed(80)), rfsKeyword: "SHAPE"),
        ComponentSpec(type: .gradient, title: "Gradient", symbol: "circle.lefthalf.filled", category: .shapes, summary: "Linear, radial or angular gradient",
                      isContainer: false, properties: [PropertySpec("colors", "Colors", .list, ["accent", "secondary"]),
                                                       PropertySpec("kind", "Type", .options(["linear", "radial", "angular"]), "linear"),
                                                       PropertySpec("angle", "Angle", .number(min: 0, max: 360, step: 5), 135)],
                      events: [.tap], bindable: nil, supportsRepeat: false, defaultStyle: Style(width: .fill, height: .fixed(140), cornerRadius: 20), rfsKeyword: "GRADIENT"),
    ]

    private static let byType: [ComponentType: ComponentSpec] = Dictionary(uniqueKeysWithValues: all.map { ($0.type, $0) })

    public static func spec(for type: ComponentType) -> ComponentSpec { byType[type]! }

    public static func specs(in category: ComponentCategory) -> [ComponentSpec] { all.filter { $0.category == category } }

    public static func search(_ query: String) -> [ComponentSpec] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.title.lowercased().contains(q) || $0.summary.lowercased().contains(q) || $0.type.rawValue.lowercased().contains(q) || $0.rfsKeyword.lowercased().contains(q) }
    }

    /// Which component types a container accepts (nil = anything).
    public static func allowedChildren(of type: ComponentType) -> Set<ComponentType>? {
        switch type {
        case .menu: return [.button, .divider]
        default: return nil
        }
    }

    public static func canContain(_ parent: ComponentType, _ child: ComponentType) -> Bool {
        guard spec(for: parent).isContainer else { return false }
        if let allowed = allowedChildren(of: parent) { return allowed.contains(child) }
        return true
    }
}

import SwiftUI
import Charts
import PhotosUI
import ReyForgeCore

struct LeafView: View {
    let node: Node
    let scope: Scope

    var body: some View {
        switch node.type {
        case .text: TextNode(node: node, scope: scope)
        case .label: LabelNode(node: node, scope: scope)
        case .badge: BadgeNode(node: node, scope: scope)
        case .link: LinkNode(node: node, scope: scope)
        case .image: ImageNode(node: node, scope: scope)
        case .icon: IconNode(node: node, scope: scope)
        case .avatar: AvatarNode(node: node, scope: scope)
        case .video: VideoNode(node: node, scope: scope)
        case .audio: AudioNode(node: node, scope: scope)
        case .web: WebNode(node: node, scope: scope)
        case .map: MapNode(node: node, scope: scope)
        case .qr: QRNode(node: node, scope: scope)
        case .statCard: StatCardNode(node: node, scope: scope)
        case .chart: ChartNode(node: node, scope: scope)
        case .gauge: GaugeNode(node: node, scope: scope)
        case .progress: ProgressNode(node: node, scope: scope)
        case .rating: RatingNode(node: node, scope: scope)
        case .timer: TimerNode(node: node, scope: scope)
        case .empty: EmptyStateNode(node: node, scope: scope)
        case .button: ButtonNode(node: node, scope: scope)
        case .shareLink: ShareNode(node: node, scope: scope)
        case .signInApple: AppleSignInNode(node: node, scope: scope)
        case .toggle: ToggleNode(node: node, scope: scope)
        case .slider: SliderNode(node: node, scope: scope)
        case .stepper: StepperNode(node: node, scope: scope)
        case .textField, .secureField: FieldNode(node: node, scope: scope)
        case .textEditor: EditorNode(node: node, scope: scope)
        case .searchField: SearchNode(node: node, scope: scope)
        case .picker: PickerNode(node: node, scope: scope)
        case .datePicker: DateNode(node: node, scope: scope)
        case .colorPicker: ColorNode(node: node, scope: scope)
        case .photoPicker: PhotoNode(node: node, scope: scope)
        case .listRow: RowNode(node: node, scope: scope)
        case .navLink: NavLinkNode(node: node, scope: scope)
        case .labeledContent: InfoNode(node: node, scope: scope)
        case .divider: Divider()
        case .spacer: Spacer(minLength: CGFloat(node.number("minLength") ?? 16)).frame(minHeight: CGFloat(node.number("minLength") ?? 16))
        case .shape: ShapeNode(node: node, scope: scope)
        case .gradient: GradientNode(node: node, scope: scope)
        default: EmptyView()
        }
    }
}

// MARK: - Text

struct TextNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        let raw = store.string(node, "text", scope)
        let align = HAlign(rawValue: node.string("alignment")) ?? .leading
        let limit = Int(node.number("lineLimit") ?? 0)
        Group {
            if node.bool("markdown"), let attr = try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attr)
            } else {
                Text(verbatim: raw)
            }
        }
        .multilineTextAlignment(align.textAlignment)
        .lineLimit(limit > 0 ? limit : nil)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct LabelNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let title = store.string(node, "title", scope)
        let icon = store.string(node, "icon", scope)
        let label = Label {
            Text(title)
        } icon: {
            Image(systemName: icon.isEmpty ? "star.fill" : icon).foregroundStyle(palette.color(node.string("iconColor"), fallback: palette.accent))
        }
        switch node.string("variant") {
        case "iconOnly": label.labelStyle(.iconOnly)
        case "titleOnly": label.labelStyle(.titleOnly)
        default: label.labelStyle(.titleAndIcon)
        }
    }
}

struct BadgeNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let c = palette.color(node.string("color"), fallback: palette.accent)
        let icon = node.string("icon")
        let text = store.string(node, "text", scope)
        HStack(spacing: 4) {
            if !icon.isEmpty { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .modifier(BadgeStyle(variant: node.string("variant"), color: c))
    }
}

struct BadgeStyle: ViewModifier {
    let variant: String
    let color: Color
    func body(content: Content) -> some View {
        switch variant {
        case "filled": content.foregroundStyle(.white).background(color, in: Capsule())
        case "outlined": content.foregroundStyle(color).overlay(Capsule().strokeBorder(color, lineWidth: 1.2))
        default: content.foregroundStyle(color).background(color.opacity(0.15), in: Capsule())
        }
    }
}

struct LinkNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        let title = store.string(node, "title", scope)
        let icon = node.string("icon")
        Button { store.openURL(store.string(node, "url", scope)) } label: {
            if icon.isEmpty { Text(title) } else { Label(title, systemImage: icon) }
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Images & symbols

struct ImageNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let source = store.string(node, "source", scope)
        let fill = node.string("contentMode") != "fit"
        let overlay = store.string(node, "overlayText", scope)
        SourceImage(source: source, fill: fill)
            .frame(maxWidth: node.style.width == nil ? .infinity : nil)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                if !overlay.isEmpty {
                    Text(overlay).font(.headline).foregroundStyle(.white)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                }
            }
    }
}

/// Resolves "symbol:", "asset:", file and remote image sources.
struct SourceImage: View {
    let source: String
    let fill: Bool
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette

    var body: some View {
        let s = source.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("symbol:") || (!s.contains("/") && s.contains(".") && UIImage(systemName: s) != nil) {
            Image(systemName: s.hasPrefix("symbol:") ? String(s.dropFirst(7)) : s)
                .resizable().scaledToFit().padding(12)
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if s.hasPrefix("asset:"), let img = store.image(forAsset: String(s.dropFirst(6))) {
            resizable(Image(uiImage: img))
        } else if s.hasPrefix("file://"), let url = URL(string: s), let img = UIImage(contentsOfFile: url.path) {
            resizable(Image(uiImage: img))
        } else if let url = URL(string: s), s.hasPrefix("http") {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image): resizable(image)
                case .failure: placeholder(symbol: "photo")
                default: placeholder(symbol: nil)
                }
            }
        } else {
            placeholder(symbol: "photo")
        }
    }

    @ViewBuilder func resizable(_ image: Image) -> some View {
        if fill {
            Color.clear.overlay(image.resizable().scaledToFill()).clipped()
        } else {
            image.resizable().scaledToFit()
        }
    }

    func placeholder(symbol: String?) -> some View {
        ZStack {
            palette.surface
            LinearGradient(colors: [palette.accent.opacity(0.18), palette.accent.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let symbol = symbol { Image(systemName: symbol).font(.title).foregroundStyle(palette.accent.opacity(0.6)) } else { ProgressView() }
        }
    }
}

struct IconNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    @State private var tick = 0
    var body: some View {
        let name = store.string(node, "symbol", scope)
        let size = CGFloat(store.number(node, "size", scope) ?? 32)
        let primary = palette.color(node.style.foreground, fallback: palette.accent)
        let secondary = palette.color(node.string("secondaryColor"), fallback: primary.opacity(0.5))
        let base = Image(systemName: UIImage(systemName: name) != nil ? name : "questionmark.square.dashed")
            .font(.system(size: size, weight: FontMapper.weight(node.style.font?.weight) ?? .regular))
        Group {
            switch node.string("renderingMode") {
            case "multicolor": base.symbolRenderingMode(.multicolor)
            case "palette": base.symbolRenderingMode(.palette).foregroundStyle(primary, secondary)
            case "monochrome": base.symbolRenderingMode(.monochrome).foregroundStyle(primary)
            default: base.symbolRenderingMode(.hierarchical).foregroundStyle(primary)
            }
        }
        .modifier(SymbolEffectModifier(effect: node.string("effect"), tick: tick))
        .task(id: node.string("effect")) {
            let e = node.string("effect")
            guard e == "bounce" || e == "wiggle" else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                tick += 1
            }
        }
    }
}

struct SymbolEffectModifier: ViewModifier {
    let effect: String
    let tick: Int
    func body(content: Content) -> some View {
        switch effect {
        case "pulse": content.symbolEffect(.pulse)
        case "variableColor": content.symbolEffect(.variableColor.iterative)
        case "bounce": content.symbolEffect(.bounce, value: tick)
        case "breathe":
            if #available(iOS 18.0, *) { content.symbolEffect(.breathe) } else { content.symbolEffect(.pulse) }
        case "wiggle":
            if #available(iOS 18.0, *) { content.symbolEffect(.wiggle, value: tick) } else { content.symbolEffect(.bounce, value: tick) }
        default: content
        }
    }
}

struct AvatarNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let name = store.string(node, "name", scope)
        let image = store.string(node, "image", scope)
        let size = CGFloat(store.number(node, "size", scope) ?? 56)
        let initials = name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
        ZStack {
            if image.isEmpty {
                LinearGradient(colors: [palette.accent, palette.color("secondary", fallback: palette.accent)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(initials.isEmpty ? "?" : initials).font(.system(size: size * 0.38, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            } else {
                SourceImage(source: image, fill: true)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            let status = node.string("status")
            if status != "none" && !status.isEmpty {
                Circle().fill(status == "online" ? Color.green : (status == "away" ? Color.yellow : Color.red))
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
    }
}

// MARK: - Data display

struct StatCardNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let tint = palette.color(node.string("tint"), fallback: palette.accent)
        let delta = store.string(node, "delta", scope)
        let negative = delta.hasPrefix("-") || delta.hasPrefix("−")
        let icon = store.string(node, "icon", scope)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon.isEmpty ? "chart.bar.fill" : icon)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer(minLength: 4)
                if !delta.isEmpty {
                    Text(delta).font(.caption2.weight(.bold))
                        .foregroundStyle(negative ? Color.red : Color.green)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background((negative ? Color.red : Color.green).opacity(0.12), in: Capsule())
                }
            }
            Text(store.string(node, "value", scope)).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(store.string(node, "title", scope)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: palette.theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(palette.dark ? 0 : 0.06), radius: 6, y: 3)
    }
}

struct ChartPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
}

struct ChartNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette

    var points: [ChartPoint] {
        let raw = store.resolve(node.prop("data"), scope: scope)
        let xf = node.string("xField").isEmpty ? "label" : node.string("xField")
        let yf = node.string("yField").isEmpty ? "value" : node.string("yField")
        switch raw {
        case .array(let items):
            return items.enumerated().map { i, v in
                if case .object = v { return ChartPoint(label: v[xf].stringValue.isEmpty ? "\(i + 1)" : v[xf].stringValue, value: v[yf].numberValue ?? 0) }
                return ChartPoint(label: "\(i + 1)", value: v.numberValue ?? 0)
            }
        default:
            let s = raw.stringValue
            if let json = Value.fromJSONString(s), case .array = json { return ChartNode.points(from: json, xf, yf) }
            return s.split(separator: ",").enumerated().compactMap { i, part in
                let kv = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2 { return ChartPoint(label: kv[0], value: Value.parseNumber(kv[1]) ?? 0) }
                return Value.parseNumber(String(part)).map { ChartPoint(label: "\(i + 1)", value: $0) }
            }
        }
    }

    static func points(from v: Value, _ xf: String, _ yf: String) -> [ChartPoint] {
        v.arrayValue.enumerated().map { i, p in ChartPoint(label: p[xf].stringValue.isEmpty ? "\(i + 1)" : p[xf].stringValue, value: p[yf].numberValue ?? p.numberValue ?? 0) }
    }

    var body: some View {
        let data = points
        let kind = node.string("kind")
        let color = palette.color(node.string("color"), fallback: palette.accent)
        let grid = node.bool("showsGrid")
        VStack(alignment: .leading, spacing: 6) {
            let title = store.string(node, "title", scope)
            if !title.isEmpty && node.props["title"] != nil { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
            Chart(data) { p in
                switch kind {
                case "line":
                    LineMark(x: .value("Label", p.label), y: .value("Value", p.value)).interpolationMethod(.catmullRom).foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 3))
                    PointMark(x: .value("Label", p.label), y: .value("Value", p.value)).foregroundStyle(color)
                case "area":
                    AreaMark(x: .value("Label", p.label), y: .value("Value", p.value)).interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.5), color.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Label", p.label), y: .value("Value", p.value)).interpolationMethod(.catmullRom).foregroundStyle(color)
                case "point":
                    PointMark(x: .value("Label", p.label), y: .value("Value", p.value)).foregroundStyle(color).symbolSize(80)
                case "pie", "donut":
                    SectorMark(angle: .value("Value", p.value), innerRadius: .ratio(kind == "donut" ? 0.58 : 0), angularInset: 1.5)
                        .foregroundStyle(by: .value("Label", p.label)).cornerRadius(4)
                default:
                    BarMark(x: .value("Label", p.label), y: .value("Value", p.value)).foregroundStyle(color.gradient).cornerRadius(5)
                }
            }
            .chartXAxis(kind == "pie" || kind == "donut" ? .hidden : .automatic)
            .chartYAxis(kind == "pie" || kind == "donut" || !grid ? .hidden : .automatic)
            .chartLegend(kind == "pie" || kind == "donut" ? .visible : .hidden)
        }
    }
}

struct GaugeNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let lo = store.number(node, "min", scope) ?? 0
        let hi = max(lo + 0.0001, store.number(node, "max", scope) ?? 100)
        let v = min(max(store.number(node, "value", scope) ?? 0, lo), hi)
        let label = store.string(node, "label", scope)
        let symbol = node.string("symbol")
        let tint = palette.color(node.string("tint"), fallback: palette.accent)
        let gauge = Gauge(value: v, in: lo...hi) {
            if symbol.isEmpty { Text(label) } else { Image(systemName: symbol) }
        } currentValueLabel: {
            Text(Value.format(number: (v * 10).rounded() / 10))
        } minimumValueLabel: {
            Text(Value.format(number: lo)).font(.caption2)
        } maximumValueLabel: {
            Text(Value.format(number: hi)).font(.caption2)
        }
        .tint(tint)
        VStack(spacing: 4) {
            switch node.string("variant") {
            case "circular": gauge.gaugeStyle(.accessoryCircular).scaleEffect(1.3).frame(width: 80, height: 80)
            case "linear": gauge.gaugeStyle(.accessoryLinear)
            case "linearCapacity": gauge.gaugeStyle(.linearCapacity)
            default: gauge.gaugeStyle(.accessoryCircularCapacity).scaleEffect(1.3).frame(width: 80, height: 80)
            }
            if ["circular", "circularCapacity", ""].contains(node.string("variant")) && !label.isEmpty {
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct ProgressNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let label = store.string(node, "label", scope)
        let total = max(0.0001, store.number(node, "total", scope) ?? 1)
        let rawValue = store.resolve(node.prop("value"), scope: scope)
        let tint = palette.color(node.string("tint"), fallback: palette.accent)
        let showValue = node.bool("showsValue")
        if rawValue.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(spacing: 10) {
                ProgressView().tint(tint)
                if !label.isEmpty { Text(label).foregroundStyle(.secondary) }
            }
        } else {
            let v = min(max(rawValue.numberValue ?? 0, 0), total)
            if node.string("variant") == "circular" {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(tint.opacity(0.18), lineWidth: 7)
                        Circle().trim(from: 0, to: v / total).stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                        if showValue { Text("\(Int((v / total * 100).rounded()))%").font(.caption.weight(.bold)) }
                    }
                    .frame(width: 54, height: 54)
                    .animation(.easeInOut, value: v)
                    if !label.isEmpty { Text(label).font(.subheadline) }
                }
            } else {
                ProgressView(value: v, total: total) {
                    if !label.isEmpty { Text(label).font(.subheadline) }
                } currentValueLabel: {
                    if showValue { Text("\(Int((v / total * 100).rounded()))%") }
                }
                .tint(tint)
                .animation(.easeInOut, value: v)
            }
        }
    }
}

struct RatingNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let maxStars = max(1, Int(store.number(node, "max", scope) ?? 5))
        let bound = node.binding.map { store.state.value($0).numberValue } ?? nil
        let value = bound ?? store.number(node, "value", scope) ?? 0
        let symbol = node.string("symbol").isEmpty ? "star.fill" : node.string("symbol")
        let color = palette.color(node.string("color"), fallback: .yellow)
        HStack(spacing: 4) {
            ForEach(1...maxStars, id: \.self) { i in
                let filled = Double(i) <= value.rounded(.toNearestOrAwayFromZero)
                Image(systemName: filled ? symbol : symbol.replacingOccurrences(of: ".fill", with: ""))
                    .foregroundStyle(filled ? color : Color.secondary.opacity(0.5))
                    .font(.title3)
                    .onTapGesture {
                        guard store.mode == .run, node.bool("interactive") else { return }
                        store.haptic("selection")
                        if let b = node.binding { store.setValue(b, .number(Double(i))) }
                        store.fire(.change, node: node, scope: scope.with("value", .number(Double(i))))
                    }
            }
        }
    }
}

struct TimerNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    @State private var running = false
    @State private var startedAt: Date?
    @State private var accumulated: TimeInterval = 0
    @State private var finished = false

    var body: some View {
        let countdown = node.string("mode") != "stopwatch"
        let total = store.number(node, "seconds", scope) ?? 300
        let tint = palette.color(node.string("tint"), fallback: palette.accent)
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let elapsed = accumulated + (running ? context.date.timeIntervalSince(startedAt ?? context.date) : 0)
            let shown = countdown ? max(0, total - elapsed) : elapsed
            VStack(spacing: 14) {
                ZStack {
                    Circle().stroke(tint.opacity(0.15), lineWidth: 10)
                    Circle().trim(from: 0, to: countdown ? CGFloat(shown / max(total, 1)) : CGFloat((elapsed.truncatingRemainder(dividingBy: 60)) / 60))
                        .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text(TimerNode.format(shown)).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                .frame(width: 180, height: 180)
                if node.bool("showsControls") {
                    HStack(spacing: 14) {
                        Button(running ? "Pause" : "Start", systemImage: running ? "pause.fill" : "play.fill") { toggle(countdown: countdown, total: total) }
                            .buttonStyle(.borderedProminent).tint(tint)
                        Button("Reset", systemImage: "arrow.counterclockwise") { running = false; startedAt = nil; accumulated = 0; finished = false }
                            .buttonStyle(.bordered)
                    }
                    .allowsHitTesting(store.mode == .run)
                }
            }
            .frame(maxWidth: .infinity)
            .onChange(of: shown <= 0) { _, done in
                if done && countdown && running && !finished {
                    finished = true; running = false; accumulated = total
                    store.haptic("success")
                    store.fire(.submit, node: node, scope: scope)
                }
            }
        }
    }

    func toggle(countdown: Bool, total: Double) {
        if running {
            accumulated += Date().timeIntervalSince(startedAt ?? Date())
            running = false
        } else {
            if countdown && accumulated >= total { accumulated = 0; finished = false }
            startedAt = Date()
            running = true
        }
        store.haptic("light")
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

struct EmptyStateNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        let action = store.string(node, "actionTitle", scope)
        ContentUnavailableView {
            Label(store.string(node, "title", scope), systemImage: node.string("symbol").isEmpty ? "tray" : node.string("symbol"))
        } description: {
            Text(store.string(node, "message", scope))
        } actions: {
            if !action.isEmpty {
                Button(action) { store.run(node.handlers(for: .tap), scope: scope) }.buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Controls

struct ButtonNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette

    var body: some View {
        let title = store.string(node, "title", scope)
        let icon = store.string(node, "icon", scope)
        let variant = node.string("variant")
        let full = node.bool("fullWidth")
        let role: ButtonRole? = node.string("role") == "destructive" || variant == "destructive" ? .destructive : (node.string("role") == "cancel" ? .cancel : nil)
        let tintKey = node.string("tint")
        let tint = variant == "destructive" ? Color.red : palette.color(tintKey.isEmpty ? "accent" : tintKey, fallback: palette.accent)
        let label = HStack(spacing: 6) {
            if !icon.isEmpty { Image(systemName: icon) }
            if !title.isEmpty { Text(title) }
        }
        .frame(maxWidth: full ? .infinity : nil)
        .padding(.vertical, full && node.string("size") == "large" ? 4 : 0)
        let button = Button(role: role) {
            store.run(node.handlers(for: .tap), scope: scope)
        } label: { label }
            .controlSize(controlSize)
            .tint(tint)
        ButtonVariant(button: button, variant: variant, tint: tint)
    }

    var controlSize: ControlSize {
        switch node.string("size") {
        case "small": return .small
        case "regular": return .regular
        default: return .large
        }
    }
}

struct ButtonVariant<B: View>: View {
    let button: B
    let variant: String
    let tint: Color
    var body: some View {
        switch variant {
        case "bordered": button.buttonStyle(.bordered)
        case "plain": button.buttonStyle(.plain).foregroundStyle(tint)
        case "borderless": button.buttonStyle(.borderless)
        case "link": button.buttonStyle(.borderless).underline()
        case "capsule": button.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        case "glass":
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) { button.buttonStyle(.glass) } else { button.buttonStyle(.bordered) }
            #else
            button.buttonStyle(.bordered)
            #endif
        default: button.buttonStyle(.borderedProminent)
        }
    }
}

struct ShareNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        let item = store.string(node, "item", scope)
        let title = store.string(node, "title", scope)
        let icon = node.string("icon").isEmpty ? "square.and.arrow.up" : node.string("icon")
        Group {
            if let url = URL(string: item), item.hasPrefix("http") {
                ShareLink(item: url) { Label(title, systemImage: icon) }
            } else {
                ShareLink(item: item.isEmpty ? title : item) { Label(title, systemImage: icon) }
            }
        }
        .buttonStyle(.bordered)
    }
}

struct AppleSignInNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        let variant = node.string("variant")
        let dark = variant == "black"
        Button { store.run(node.handlers(for: .tap), scope: scope) } label: {
            HStack(spacing: 6) {
                Image(systemName: "apple.logo")
                Text(store.string(node, "title", scope).isEmpty ? "Sign in with Apple" : store.string(node, "title", scope))
            }
            .font(.system(size: 19, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(dark ? Color.white : Color.black)
            .background(dark ? Color.black : Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { if variant == "whiteOutline" { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black, lineWidth: 1) } }
        }
        .buttonStyle(.plain)
    }
}

struct ToggleNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let title = store.string(node, "title", scope)
        let subtitle = store.string(node, "subtitle", scope)
        let icon = node.string("icon")
        let binding = store.boolBinding(node.binding, initial: node.bool("isOn"), node: node, scope: scope)
        let tint = palette.color(node.string("tint"), fallback: palette.accent)
        let toggle = Toggle(isOn: binding) {
            HStack(spacing: 12) {
                if !icon.isEmpty {
                    Image(systemName: icon).foregroundStyle(.white).font(.subheadline)
                        .frame(width: 28, height: 28).background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .tint(tint)
        switch node.string("variant") {
        case "button": toggle.toggleStyle(.button)
        case "checkbox": toggle.toggleStyle(CheckboxToggleStyle(tint: tint))
        default: toggle.toggleStyle(.switch)
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square").foregroundStyle(configuration.isOn ? tint : .secondary).font(.title3)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

struct SliderNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let lo = store.number(node, "min", scope) ?? 0
        let hi = max(lo + 0.0001, store.number(node, "max", scope) ?? 100)
        let step = store.number(node, "step", scope) ?? 1
        let binding = store.numberBinding(node.binding, initial: store.number(node, "value", scope) ?? lo, node: node, scope: scope)
        let title = store.string(node, "title", scope)
        VStack(alignment: .leading, spacing: 4) {
            if !title.isEmpty || node.bool("showsValue") {
                HStack {
                    Text(title)
                    Spacer()
                    if node.bool("showsValue") { Text(Value.format(number: (binding.wrappedValue * 100).rounded() / 100)).foregroundStyle(.secondary).monospacedDigit() }
                }
            }
            Group {
                if step > 0 {
                    Slider(value: binding, in: lo...hi, step: step) { Text(title) } minimumValueLabel: { symbol("minSymbol") } maximumValueLabel: { symbol("maxSymbol") }
                } else {
                    Slider(value: binding, in: lo...hi) { Text(title) } minimumValueLabel: { symbol("minSymbol") } maximumValueLabel: { symbol("maxSymbol") }
                }
            }
            .tint(palette.color(node.string("tint"), fallback: palette.accent))
        }
    }

    @ViewBuilder func symbol(_ key: String) -> some View {
        let s = node.string(key)
        if s.isEmpty { EmptyView() } else { Image(systemName: s).foregroundStyle(.secondary) }
    }
}

struct StepperNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        let lo = store.number(node, "min", scope) ?? 0
        let hi = max(lo, store.number(node, "max", scope) ?? 10)
        let step = max(0.0001, store.number(node, "step", scope) ?? 1)
        let binding = store.numberBinding(node.binding, initial: store.number(node, "value", scope) ?? lo, node: node, scope: scope)
        let format = node.string("format")
        let valueText = Template.render(format.isEmpty || format == "{{value}}" ? "{{value}}" : format, scope: scope.with("value", .number(binding.wrappedValue)))
        Stepper(value: binding, in: lo...hi, step: step) {
            HStack {
                Text(store.string(node, "title", scope))
                Spacer()
                Text(valueText).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

// MARK: - Inputs

struct FieldNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    @State private var revealed = false

    var body: some View {
        let placeholder = store.string(node, "placeholder", scope)
        let title = store.string(node, "title", scope)
        let icon = node.string("icon")
        let binding = store.stringBinding(node.binding, initial: "", node: node, scope: scope)
        VStack(alignment: .leading, spacing: 6) {
            if !title.isEmpty { Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
            HStack(spacing: 10) {
                if !icon.isEmpty { Image(systemName: icon).foregroundStyle(.secondary) }
                Group {
                    if node.type == .secureField && !revealed {
                        SecureField(placeholder, text: binding)
                    } else {
                        TextField(placeholder, text: binding)
                            .keyboardType(keyboard)
                            .textContentType(contentType)
                            .textInputAutocapitalization(capitalization)
                            .autocorrectionDisabled(node.string("keyboard") == "email" || node.string("keyboard") == "url")
                    }
                }
                .onSubmit { store.fire(.submit, node: node, scope: scope.with("value", .string(binding.wrappedValue))) }
                if node.type == .secureField {
                    Button { revealed.toggle() } label: { Image(systemName: revealed ? "eye.slash" : "eye").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .modifier(FieldChrome(variant: node.string("variant"), palette: palette))
        }
    }

    var keyboard: UIKeyboardType {
        switch node.string("keyboard") {
        case "email": return .emailAddress
        case "number": return .numberPad
        case "decimal": return .decimalPad
        case "phone": return .phonePad
        case "url": return .URL
        default: return .default
        }
    }

    var contentType: UITextContentType? {
        switch node.string("contentType") {
        case "name": return .name
        case "email": return .emailAddress
        case "username": return .username
        case "phone": return .telephoneNumber
        case "address": return .fullStreetAddress
        case "oneTimeCode": return .oneTimeCode
        default: return node.type == .secureField ? .password : nil
        }
    }

    var capitalization: TextInputAutocapitalization {
        switch node.string("autocapitalize") {
        case "words": return .words
        case "characters": return .characters
        case "never": return .never
        default: return node.string("keyboard") == "email" || node.string("keyboard") == "url" ? .never : .sentences
        }
    }
}

struct FieldChrome: ViewModifier {
    let variant: String
    let palette: ThemePalette
    @Environment(\.inNativeList) var inNativeList
    func body(content: Content) -> some View {
        if inNativeList {
            content
        } else {
            switch variant {
            case "rounded":
                content.padding(.horizontal, 12).padding(.vertical, 11)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.secondary.opacity(0.35)))
            case "underline":
                content.padding(.vertical, 8).overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.4)).frame(height: 1) }
            case "plain":
                content
            default:
                content.padding(.horizontal, 14).padding(.vertical, 13)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: max(10, palette.theme.cornerRadius - 4), style: .continuous))
            }
        }
    }
}

struct EditorNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let binding = store.stringBinding(node.binding, initial: "", node: node, scope: scope)
        let placeholder = store.string(node, "placeholder", scope)
        ZStack(alignment: .topLeading) {
            TextEditor(text: binding).scrollContentBackground(.hidden).padding(8)
            if binding.wrappedValue.isEmpty {
                Text(placeholder).foregroundStyle(.tertiary).padding(.horizontal, 13).padding(.vertical, 16).allowsHitTesting(false)
            }
        }
        .frame(minHeight: CGFloat(node.number("minHeight") ?? 140))
        .background(palette.surface, in: RoundedRectangle(cornerRadius: max(10, palette.theme.cornerRadius - 4), style: .continuous))
    }
}

struct SearchNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        let binding = store.stringBinding(node.binding, initial: "", node: node, scope: scope)
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(store.string(node, "placeholder", scope), text: binding)
                .submitLabel(.search)
                .onSubmit { store.fire(.submit, node: node, scope: scope.with("value", .string(binding.wrappedValue))) }
            if !binding.wrappedValue.isEmpty {
                Button { binding.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PickerNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        let options = store.resolve(node.prop("options"), scope: scope).arrayValue.map { $0.stringValue }.filter { !$0.isEmpty }
        let opts = options.isEmpty ? ["Option 1", "Option 2"] : options
        let binding = store.stringBinding(node.binding, initial: opts.first ?? "", node: node, scope: scope)
        let title = store.string(node, "title", scope)
        let picker = Picker(title, selection: binding) {
            ForEach(opts, id: \.self) { Text($0).tag($0) }
        }
        VStack(alignment: .leading, spacing: 6) {
            switch node.string("variant") {
            case "segmented":
                if !title.isEmpty { Text(title).font(.subheadline).foregroundStyle(.secondary) }
                picker.pickerStyle(.segmented).labelsHidden()
            case "wheel": picker.pickerStyle(.wheel).frame(maxHeight: 150)
            case "inline": picker.pickerStyle(.inline)
            case "palette": picker.pickerStyle(.palette)
            default:
                HStack {
                    Text(title)
                    Spacer()
                    picker.pickerStyle(.menu).labelsHidden()
                }
            }
        }
    }
}

struct DateNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        let binding = store.dateBinding(node.binding, node: node, scope: scope)
        let components: DatePickerComponents = {
            switch node.string("components") {
            case "time": return [.hourAndMinute]
            case "dateTime": return [.date, .hourAndMinute]
            default: return [.date]
            }
        }()
        let picker = DatePicker(store.string(node, "title", scope), selection: binding, displayedComponents: components)
        switch node.string("variant") {
        case "graphical": picker.datePickerStyle(.graphical)
        case "wheel": picker.datePickerStyle(.wheel)
        default: picker.datePickerStyle(.compact)
        }
    }
}

struct ColorNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        ColorPicker(store.string(node, "title", scope), selection: store.colorBinding(node.binding, node: node, scope: scope, palette: palette), supportsOpacity: node.bool("supportsOpacity"))
    }
}

struct PhotoNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @State private var item: PhotosPickerItem?
    var body: some View {
        let title = store.string(node, "title", scope)
        PhotosPicker(selection: $item, matching: .images) {
            Label(title, systemImage: node.string("icon").isEmpty ? "photo.on.rectangle.angled" : node.string("icon"))
        }
        .buttonStyle(.bordered)
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    let path = store.storePickedImage(data)
                    store.setValue(node.binding, .string(path))
                    store.fire(.change, node: node, scope: scope.with("value", .string(path)))
                }
            }
        }
    }
}

// MARK: - Rows

struct RowNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    @Environment(\.inNativeList) var inNativeList

    var body: some View {
        let title = store.string(node, "title", scope)
        let subtitle = store.string(node, "subtitle", scope)
        let value = store.string(node, "value", scope)
        let icon = store.string(node, "icon", scope)
        let badge = store.string(node, "badge", scope)
        let accessory = node.string("accessory")
        let tint = palette.color(node.string("iconColor"), fallback: palette.accent)
        let row = HStack(spacing: 12) {
            if !icon.isEmpty {
                if icon.hasPrefix("http") || icon.hasPrefix("file") || icon.hasPrefix("asset:") {
                    SourceImage(source: icon, fill: true).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    Image(systemName: UIImage(systemName: icon) != nil ? icon : "circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary).lineLimit(2)
                if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if !badge.isEmpty {
                Text(badge).font(.caption.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 2).background(Color.red, in: Capsule())
            }
            if !value.isEmpty { Text(value).foregroundStyle(.secondary).lineLimit(1) }
            switch accessory {
            case "chevron": Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            case "checkmark": Image(systemName: "checkmark").foregroundStyle(palette.accent).fontWeight(.semibold)
            case "info": Image(systemName: "info.circle").foregroundStyle(palette.accent)
            default: EmptyView()
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        let tap = node.handlers(for: .tap)
        let delete = node.handlers(for: .delete)
        Group {
            if inNativeList || !(node.style.background == nil && store.mode == .design) {
                row
            } else {
                row.padding(.horizontal, 14).background(palette.surface, in: RoundedRectangle(cornerRadius: max(10, palette.theme.cornerRadius - 2), style: .continuous))
            }
        }
        .onTapGesture { if store.mode == .run && !tap.isEmpty { store.run(tap, scope: scope) } }
        .contextMenu {
            if store.mode == .run && !delete.isEmpty {
                Button(role: .destructive) { store.run(delete, scope: scope) } label: { Label(node.string("deleteLabel").isEmpty ? "Delete" : node.string("deleteLabel"), systemImage: "trash") }
            }
        }
    }
}

struct NavLinkNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let icon = store.string(node, "icon", scope)
        let subtitle = store.string(node, "subtitle", scope)
        Button {
            let dest = node.string("destination")
            if store.mode == .run, let id = store.project.screen(id: dest)?.id ?? store.project.screen(named: dest)?.id { store.navigate(to: id, style: "push") }
            store.run(node.handlers(for: .tap), scope: scope)
        } label: {
            HStack(spacing: 12) {
                if !icon.isEmpty {
                    Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(palette.color(node.string("iconColor"), fallback: palette.accent), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.string(node, "title", scope)).foregroundStyle(.primary)
                    if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct InfoNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        LabeledContent(store.string(node, "title", scope), value: store.string(node, "value", scope)).padding(.vertical, 2)
    }
}

// MARK: - Shapes

struct ShapeNode: View {
    let node: Node
    let scope: Scope
    @Environment(\.palette) var palette
    var body: some View {
        let fill = palette.color(node.string("fill"), fallback: palette.accent)
        let stroke = node.string("strokeColor")
        let lw = CGFloat(node.number("strokeWidth") ?? 0)
        let sc = palette.color(stroke, fallback: .clear)
        switch node.string("shape") {
        case "circle": Circle().fill(fill).overlay(Circle().strokeBorder(sc, lineWidth: lw))
        case "rectangle": Rectangle().fill(fill).overlay(Rectangle().strokeBorder(sc, lineWidth: lw))
        case "capsule": Capsule().fill(fill).overlay(Capsule().strokeBorder(sc, lineWidth: lw))
        case "ellipse": Ellipse().fill(fill).overlay(Ellipse().strokeBorder(sc, lineWidth: lw))
        default:
            let r = node.style.cornerRadius ?? palette.theme.cornerRadius
            RoundedRectangle(cornerRadius: r, style: .continuous).fill(fill).overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(sc, lineWidth: lw))
        }
    }
}

struct GradientNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    var body: some View {
        let colors = store.resolve(node.prop("colors"), scope: scope).arrayValue.map { $0.stringValue }
        let kind = Fill.Kind(rawValue: node.string("kind")) ?? .linear
        palette.fill(Fill(kind: kind, colors: colors.isEmpty ? ["accent", "secondary"] : colors, angle: node.number("angle") ?? 135))
    }
}

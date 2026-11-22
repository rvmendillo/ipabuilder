import SwiftUI
import PhotosUI
import ReyForgeCore

// MARK: - Color tokens

enum ColorTokens {
    static let theme = ["accent", "secondary", "text", "secondaryText", "background", "surface", "success", "warning", "danger"]
    static let system = ["white", "black", "red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue", "indigo", "purple", "pink", "brown", "gray", "clear"]
    static func title(_ t: String) -> String {
        switch t {
        case "secondaryText": return "Secondary text"
        case "secondary": return "Secondary accent"
        default: return t.prefix(1).uppercased() + t.dropFirst()
        }
    }
}

struct Swatch: View {
    let color: Color
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            Image(systemName: "checkerboard.rectangle").resizable().opacity(0.15)
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.15)))
    }
}

/// Picks a theme token, system color or any custom color (stored as hex).
struct ColorField: View {
    let title: String
    @Binding var token: String?
    let palette: ThemePalette
    var allowsNone = true

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
            Menu {
                if allowsNone { Button("Default") { token = nil } }
                Section("Theme") {
                    ForEach(ColorTokens.theme, id: \.self) { t in
                        Button { token = t } label: { Label(ColorTokens.title(t), systemImage: token == t ? "checkmark.circle.fill" : "circle.fill") }
                    }
                }
                Section("System") {
                    ForEach(ColorTokens.system, id: \.self) { t in
                        Button { token = t } label: { Label(ColorTokens.title(t), systemImage: token == t ? "checkmark.circle.fill" : "circle") }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(token.map { $0.hasPrefix("#") ? $0.uppercased() : ColorTokens.title($0) } ?? "Default")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Swatch(color: token.map { palette.color($0) } ?? .clear)
                }
            }
            ColorPicker("", selection: Binding(get: { token.map { palette.color($0) } ?? .clear }, set: { token = $0.hexString }), supportsOpacity: true)
                .labelsHidden()
                .frame(width: 30)
        }
    }
}

// MARK: - Symbols

struct SymbolPickerView: View {
    @Binding var symbol: String
    @Environment(\.dismiss) var dismiss
    @State private var query = ""

    static let all: [String] = SymbolResolver.known.sorted()

    var results: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Self.all }
        var out = Self.all.filter { $0.contains(q) }
        let concept = SymbolResolver.symbol(forConcept: q, fallback: "")
        if !concept.isEmpty && !out.contains(concept) { out.insert(concept, at: 0) }
        if UIImage(systemName: q) != nil && !out.contains(q) { out.insert(q, at: 0) }
        return out
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 10)], spacing: 10) {
                ForEach(results, id: \.self) { name in
                    Button {
                        symbol = name
                        dismiss()
                    } label: {
                        Image(systemName: name)
                            .font(.title2)
                            .frame(width: 58, height: 52)
                            .background(RoundedRectangle(cornerRadius: 12).fill(symbol == name ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                }
            }
            .padding()
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search symbols or describe one")
        .navigationTitle("Symbols")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SymbolField: View {
    let title: String
    @Binding var symbol: String

    var body: some View {
        NavigationLink {
            SymbolPickerView(symbol: $symbol)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: UIImage(systemName: symbol) != nil ? symbol : "questionmark.square.dashed")
                    .foregroundStyle(Color.accentColor)
                Text(symbol).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// MARK: - Numbers

struct NumberField: View {
    let title: String
    @Binding var value: Double?
    var range: ClosedRange<Double> = 0...200
    var step: Double = 1
    var optional = true
    var unit = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                if optional && value != nil {
                    Button("Auto") { value = nil }.font(.caption).buttonStyle(.borderless)
                }
                TextField("Auto", value: Binding(get: { value ?? 0 }, set: { value = $0 }), format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            Slider(value: Binding(get: { min(max(value ?? range.lowerBound, range.lowerBound), range.upperBound) }, set: { value = ($0 / step).rounded() * step }), in: range)
        }
    }
}

/// Fixed number or "fill the available space".
struct DimensionField: View {
    let title: String
    @Binding var dimension: SizeDimension?
    var maxValue: Double = 600

    var mode: Binding<Int> {
        Binding(get: {
            switch dimension { case nil: return 0; case .fill?: return 1; case .fixed?: return 2 }
        }, set: { m in
            switch m {
            case 0: dimension = nil
            case 1: dimension = .fill
            default: dimension = .fixed(dimension?.fixedValue ?? 120)
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Picker(title, selection: mode) {
                    Text("Auto").tag(0)
                    Text("Fill").tag(1)
                    Text("Fixed").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
            }
            if case .fixed(let v)? = dimension {
                HStack {
                    Slider(value: Binding(get: { min(v, maxValue) }, set: { dimension = .fixed($0.rounded()) }), in: 8...maxValue)
                    TextField("", value: Binding(get: { v }, set: { dimension = .fixed(max(1, $0)) }), format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 60).textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}

struct InsetsField: View {
    let title: String
    @Binding var insets: Insets?
    @State private var perSide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                if insets != nil { Button("None") { insets = nil }.font(.caption).buttonStyle(.borderless) }
                Toggle("Per side", isOn: $perSide).labelsHidden().toggleStyle(.button).font(.caption)
                    .onAppear { perSide = !(insets?.isUniform ?? true) }
            }
            if perSide {
                side("Top", \.top); side("Leading", \.leading); side("Bottom", \.bottom); side("Trailing", \.trailing)
            } else {
                HStack {
                    Slider(value: Binding(get: { insets?.top ?? 0 }, set: { insets = Insets(all: $0.rounded()) }), in: 0...64)
                    Text("\(Int(insets?.top ?? 0))").monospacedDigit().frame(width: 32, alignment: .trailing)
                }
            }
        }
    }

    func side(_ name: String, _ kp: WritableKeyPath<Insets, Double>) -> some View {
        HStack {
            Text(name).font(.caption).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { insets?[keyPath: kp] ?? 0 }, set: { v in var i = insets ?? Insets(); i[keyPath: kp] = v.rounded(); insets = i }), in: 0...64)
            Text("\(Int(insets?[keyPath: kp] ?? 0))").monospacedDigit().frame(width: 32, alignment: .trailing)
        }
    }
}

// MARK: - Fills

struct FillField: View {
    let title: String
    @Binding var fill: Fill?
    let palette: ThemePalette
    var allowsNone = true

    var kind: Binding<String> {
        Binding(get: {
            guard let f = fill else { return "none" }
            return f.kind == .solid ? "solid" : "gradient"
        }, set: { k in
            switch k {
            case "none": fill = nil
            case "solid": fill = .solid(fill?.primaryColor ?? "surface")
            default: fill = Fill(kind: .linear, colors: (fill?.colors.count ?? 0) >= 2 ? fill!.colors : [fill?.primaryColor ?? "accent", "secondary"], angle: fill?.angle ?? 135)
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                palette.fill(fill).frame(width: 44, height: 24).clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
            }
            Picker(title, selection: kind) {
                if allowsNone { Text("None").tag("none") }
                Text("Color").tag("solid")
                Text("Gradient").tag("gradient")
            }
            .pickerStyle(.segmented)
            if let f = fill {
                if f.kind == .solid {
                    ColorField(title: "Color", token: Binding(get: { f.primaryColor }, set: { fill = .solid($0 ?? "surface") }), palette: palette, allowsNone: false)
                } else {
                    Picker("Style", selection: Binding(get: { f.kind }, set: { var x = f; x.kind = $0; fill = x })) {
                        Text("Linear").tag(Fill.Kind.linear)
                        Text("Radial").tag(Fill.Kind.radial)
                        Text("Angular").tag(Fill.Kind.angular)
                    }
                    .pickerStyle(.segmented)
                    ForEach(Array(f.colors.enumerated()), id: \.offset) { i, c in
                        HStack {
                            ColorField(title: "Stop \(i + 1)", token: Binding(get: { c }, set: { v in var x = f; x.colors[i] = v ?? "accent"; fill = x }), palette: palette, allowsNone: false)
                            if f.colors.count > 2 {
                                Button { var x = f; x.colors.remove(at: i); fill = x } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                    if f.colors.count < 5 {
                        Button { var x = f; x.colors.append("surface"); fill = x } label: { Label("Add color stop", systemImage: "plus.circle") }
                            .buttonStyle(.borderless)
                    }
                    if f.kind == .linear {
                        HStack {
                            Text("Angle").font(.caption)
                            Slider(value: Binding(get: { f.angle }, set: { var x = f; x.angle = $0.rounded(); fill = x }), in: 0...360)
                            Text("\(Int(f.angle))°").font(.caption).monospacedDigit().frame(width: 40)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Lists of text

/// Edits a list of strings, one per line.
struct LinesEditor: View {
    let title: String
    let hint: String
    @Binding var lines: [String]
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            TextEditor(text: $text)
                .font(.callout.monospaced())
                .frame(minHeight: 90, maxHeight: 180)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
                .onChange(of: text) { _, new in
                    guard loaded else { return }
                    lines = new.split(separator: "\n", omittingEmptySubsequences: true).map { String($0) }
                }
            if !hint.isEmpty { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear {
            text = lines.joined(separator: "\n")
            DispatchQueue.main.async { loaded = true }
        }
    }
}

// MARK: - Photos

struct PhotoImportButton: View {
    let title: String
    let onPick: (Data) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Label(title, systemImage: "photo.on.rectangle.angled")
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    let jpeg = UIImage(data: data).flatMap { Self.downscale($0, maxSide: 1600).jpegData(compressionQuality: 0.85) } ?? data
                    await MainActor.run { onPick(jpeg) }
                }
                await MainActor.run { item = nil }
            }
        }
    }

    static func downscale(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return image }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }
}

// MARK: - Misc

struct SectionTitle: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).textCase(nil)
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

extension Value {
    var stringList: [String] {
        switch self {
        case .array(let a): return a.map { $0.stringValue }
        case .string(let s): return s.split(whereSeparator: { $0 == "," || $0 == "\n" }).map { $0.trimmingCharacters(in: .whitespaces) }
        default: return []
        }
    }
}

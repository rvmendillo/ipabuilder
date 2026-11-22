import SwiftUI
import ReyForgeCore

/// Brand Studio: name, bundle id, icon designer, theme, launch screen and Home Screen widget.
struct BrandPanel: View {
    @ObservedObject var editor: EditorModel
    @State private var section = 0
    @State private var showSplash = false

    var project: Project { editor.project }

    func brand<T>(_ kp: WritableKeyPath<Brand, T>, _ label: String = "Edit Brand") -> Binding<T> {
        Binding(get: { editor.project.brand[keyPath: kp] }, set: { v in editor.mutate(label) { $0.brand[keyPath: kp] = v } })
    }
    func icon<T>(_ kp: WritableKeyPath<IconSpec, T>) -> Binding<T> {
        Binding(get: { editor.project.brand.icon[keyPath: kp] }, set: { v in editor.mutate("Edit Icon") { $0.brand.icon[keyPath: kp] = v } })
    }
    func theme<T>(_ kp: WritableKeyPath<Theme, T>) -> Binding<T> {
        Binding(get: { editor.project.theme[keyPath: kp] }, set: { v in editor.mutate("Edit Theme") { $0.theme[keyPath: kp] = v; $0.theme.presetID = nil } })
    }
    func splash<T>(_ kp: WritableKeyPath<SplashSpec, T>) -> Binding<T> {
        Binding(get: { editor.project.brand.splash[keyPath: kp] }, set: { v in editor.mutate("Edit Launch Screen") { $0.brand.splash[keyPath: kp] = v } })
    }
    func widget<T>(_ kp: WritableKeyPath<WidgetConfig, T>) -> Binding<T> {
        Binding(get: { editor.project.widget[keyPath: kp] }, set: { v in editor.mutate("Edit Widget") { $0.widget[keyPath: kp] = v } })
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    AppIconView(icon: project.brand.icon, theme: project.theme, size: 72, assetImage: iconImage)
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.brand.displayName).font(.title3.weight(.bold))
                        Text(project.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text("Version \(project.version) (\(project.build))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Section", selection: $section) {
                    Text("Identity").tag(0)
                    Text("Icon").tag(1)
                    Text("Theme").tag(2)
                    Text("Launch").tag(3)
                    Text("Widget").tag(4)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("brand.sections")
            }
            switch section {
            case 0: identity
            case 1: iconDesigner
            case 2: themeEditor
            case 3: launchScreen
            default: widgetEditor
            }
        }
        .fullScreenCover(isPresented: $showSplash) {
            SplashView(project: project) { showSplash = false }
                .onTapGesture { showSplash = false }
        }
    }

    var iconImage: UIImage? {
        guard project.brand.icon.kind == .image, let a = project.brand.icon.imageAsset else { return nil }
        return UIImage(contentsOfFile: editor.library.assetsFolder(for: project.id).appendingPathComponent(a).path)
    }

    // MARK: Identity

    @ViewBuilder var identity: some View {
        Section {
            TextField("Project name", text: Binding(get: { project.name }, set: { v in editor.mutate("Rename") { $0.name = v } }))
            VStack(alignment: .leading, spacing: 4) {
                TextField("Home Screen name", text: brand(\.displayName)).accessibilityIdentifier("brand.displayName")
                if let w = project.brand.homeScreenNameWarning { Text(w).font(.caption).foregroundStyle(.orange) }
            }
            TextField("Tagline", text: brand(\.tagline))
            TextField("Copyright", text: brand(\.copyright))
        } header: { SectionTitle(title: "Name", symbol: "textformat") }
        Section {
            VStack(alignment: .leading, spacing: 4) {
                TextField("com.yourname.app", text: Binding(get: { project.bundleID }, set: { v in editor.mutate("Edit Bundle ID") { $0.bundleID = v.trimmingCharacters(in: .whitespaces) } }))
                    .font(.callout.monospaced()).autocorrectionDisabled().textInputAutocapitalization(.never)
                if !BundleID.isValid(project.bundleID) {
                    Text("Use reverse-DNS like com.yourname.app (letters, numbers, dots, hyphens).").font(.caption).foregroundStyle(.red)
                }
                Button("Suggest from name") { editor.mutate("Edit Bundle ID") { $0.bundleID = BundleID.suggest(for: $0.name) } }
                    .font(.caption).buttonStyle(.borderless)
            }
            TextField("Version", text: Binding(get: { project.version }, set: { v in editor.mutate("Edit Version") { $0.version = v } }))
                .keyboardType(.decimalPad)
            Stepper("Build \(project.build)", value: Binding(get: { project.build }, set: { v in editor.mutate("Edit Build") { $0.build = max(1, v) } }), in: 1...99999)
        } header: { SectionTitle(title: "App identity", symbol: "number") } footer: {
            Text("Your provisioning profile must allow this bundle ID (wildcard profiles allow any).")
        }
        Section {
            Toggle("“Made with ReyForge” on launch screen", isOn: brand(\.showsMadeWithBadge))
        }
    }

    // MARK: Icon

    @ViewBuilder var iconDesigner: some View {
        let spec = project.brand.icon
        Section {
            HStack(spacing: 18) {
                ForEach([44.0, 60.0, 88.0], id: \.self) { s in
                    AppIconView(icon: spec, theme: project.theme, size: s, assetImage: iconImage)
                }
                Spacer()
                HomeScreenPreview(editor: editor, iconImage: iconImage)
            }
            .padding(.vertical, 4)
            Picker("Style", selection: icon(\.kind)) {
                Text("Symbol").tag(IconSpec.Kind.symbol)
                Text("Emoji").tag(IconSpec.Kind.emoji)
                Text("Text").tag(IconSpec.Kind.text)
                Text("Photo").tag(IconSpec.Kind.image)
            }
            .pickerStyle(.segmented)
            switch spec.kind {
            case .symbol: SymbolField(title: "Symbol", symbol: icon(\.symbol))
            case .emoji: TextField("Emoji", text: icon(\.emoji))
            case .text: TextField("Letters", text: icon(\.text))
            case .image:
                PhotoImportButton(title: spec.imageAsset == nil ? "Choose photo" : "Replace photo") { data in
                    let id = editor.library.storeAsset(data, projectID: project.id)
                    editor.mutate("Edit Icon") { $0.brand.icon.imageAsset = id }
                }
            }
            if spec.kind != .image {
                ColorField(title: "Glyph color", token: Binding(get: { spec.glyphColor }, set: { v in editor.mutate("Edit Icon") { $0.brand.icon.glyphColor = v ?? "#FFFFFF" } }), palette: editor.palette, allowsNone: false)
                HStack {
                    Text("Glyph size")
                    Slider(value: icon(\.glyphScale), in: 0.3...0.85)
                }
            }
            Toggle("Glossy shine", isOn: icon(\.showsShine))
        } header: { SectionTitle(title: "App icon", symbol: "app.badge") }
        Section {
            FillField(title: "Background", fill: Binding(get: { spec.background }, set: { v in editor.mutate("Edit Icon") { $0.brand.icon.background = v ?? .solid("accent") } }), palette: editor.palette, allowsNone: false)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ThemePresets.all) { preset in
                        Button {
                            editor.mutate("Edit Icon") { $0.brand.icon.background = .linear(preset.iconBackground) }
                        } label: {
                            LinearGradient(colors: preset.iconBackground.compactMap { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                    }
                }
            }
        } header: { SectionTitle(title: "Icon background", symbol: "paintbrush") }
    }

    // MARK: Theme

    @ViewBuilder var themeEditor: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(ThemePresets.all) { preset in
                    Button {
                        editor.mutate("Apply Theme") { p in
                            p.theme = preset.theme
                            p.brand.icon.background = .linear(preset.iconBackground)
                        }
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 3) {
                                ForEach([preset.theme.accent, preset.theme.secondaryAccent, preset.theme.background], id: \.self) { c in
                                    Circle().fill(Color(hex: c) ?? .gray).frame(width: 16, height: 16).overlay(Circle().stroke(Color.primary.opacity(0.1)))
                                }
                            }
                            Text(preset.name).font(.caption.weight(.medium))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(project.theme.presetID == preset.id ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("theme.\(preset.id)")
                }
            }
            .padding(.vertical, 4)
        } header: { SectionTitle(title: "Presets", symbol: "swatchpalette") }
        Section {
            Picker("Appearance", selection: theme(\.appearance)) {
                Text("System").tag(Theme.Appearance.system)
                Text("Light").tag(Theme.Appearance.light)
                Text("Dark").tag(Theme.Appearance.dark)
            }
            .pickerStyle(.segmented)
            hexColor("Accent", \.accent)
            hexColor("Secondary accent", \.secondaryAccent)
            hexColor("Background", \.background)
            hexColor("Surface (cards)", \.surface)
            hexColor("Text", \.text)
            hexColor("Secondary text", \.secondaryText)
        } header: { SectionTitle(title: "Colors", symbol: "paintpalette") }
        Section {
            hexColor("Dark background", \.darkBackground)
            hexColor("Dark surface", \.darkSurface)
            hexColor("Dark text", \.darkText)
            hexColor("Success", \.success)
            hexColor("Warning", \.warning)
            hexColor("Danger", \.danger)
        } header: { SectionTitle(title: "Dark mode & status colors", symbol: "moon") }
        Section {
            Picker("Font", selection: theme(\.fontDesign)) {
                ForEach(FontSpec.designs, id: \.self) { Text(PropertyEditor.pretty($0)).tag($0) }
            }
            HStack {
                Text("Corner radius")
                Slider(value: theme(\.cornerRadius), in: 0...32, step: 1)
                Text("\(Int(project.theme.cornerRadius))").monospacedDigit().frame(width: 28)
            }
            HStack {
                Text("Spacing")
                Slider(value: theme(\.spacing), in: 4...32, step: 1)
                Text("\(Int(project.theme.spacing))").monospacedDigit().frame(width: 28)
            }
        } header: { SectionTitle(title: "Shape & type", symbol: "textformat.size") }
    }

    func hexColor(_ title: String, _ kp: WritableKeyPath<Theme, String>) -> some View {
        ColorPicker(title, selection: Binding(get: { Color(hex: editor.project.theme[keyPath: kp]) ?? .gray }, set: { c in
            editor.mutate("Edit Theme") { p in p.theme[keyPath: kp] = c.hexString; p.theme.presetID = nil }
        }), supportsOpacity: false)
    }

    // MARK: Launch screen

    @ViewBuilder var launchScreen: some View {
        Section {
            Toggle("Animated launch screen", isOn: splash(\.enabled))
            Picker("Animation", selection: splash(\.animation)) {
                ForEach(SplashSpec.Animation.allCases, id: \.self) { Text(PropertyEditor.pretty($0.rawValue)).tag($0) }
            }
            HStack {
                Text("Duration")
                Slider(value: splash(\.duration), in: 0.4...4, step: 0.1)
                Text(String(format: "%.1fs", project.brand.splash.duration)).monospacedDigit().frame(width: 40)
            }
            Toggle("Show app icon", isOn: splash(\.showsIcon))
            TextField("Title (defaults to app name)", text: splash(\.title))
            TextField("Subtitle (defaults to tagline)", text: splash(\.subtitle))
            FillField(title: "Background", fill: splash(\.background), palette: editor.palette)
            Button { showSplash = true } label: { Label("Preview launch screen", systemImage: "play.rectangle") }
        } header: { SectionTitle(title: "Launch screen", symbol: "sparkles.rectangle.stack") }
    }

    // MARK: Widget

    @ViewBuilder var widgetEditor: some View {
        let w = project.widget
        Section {
            Toggle("Include a Home Screen widget", isOn: widget(\.enabled))
            if w.enabled {
                WidgetPreview(project: project)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        } footer: {
            Text("Widgets need a provisioning profile that also covers \(project.bundleID).widget (wildcard profiles do).")
        }
        if w.enabled {
            Section {
                TextField("Widget name", text: widget(\.name))
                TextField("Description", text: widget(\.summary))
                Picker("Size", selection: widget(\.family)) {
                    ForEach(WidgetConfig.Family.allCases, id: \.self) { Text(PropertyEditor.pretty($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Layout", selection: widget(\.layout)) {
                    ForEach(WidgetConfig.Layout.allCases, id: \.self) { Text(PropertyEditor.pretty($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: { SectionTitle(title: "Widget", symbol: "square.grid.2x2") }
            Section {
                TextField("Title", text: widget(\.title))
                TextField("Value", text: widget(\.value))
                TextField("Subtitle", text: widget(\.subtitle))
                SymbolField(title: "Symbol", symbol: widget(\.symbol))
                if w.layout == .progress {
                    HStack { Text("Progress"); Slider(value: widget(\.progress), in: 0...1) }
                }
                if w.layout == .list {
                    LinesEditor(title: "Items", hint: "One item per line.", lines: widget(\.items))
                }
                FillField(title: "Background", fill: Binding(get: { w.background }, set: { v in editor.mutate("Edit Widget") { $0.widget.background = v ?? .solid("accent") } }), palette: editor.palette, allowsNone: false)
                ColorField(title: "Text color", token: Binding(get: { w.foreground }, set: { v in editor.mutate("Edit Widget") { $0.widget.foreground = v ?? "#FFFFFF" } }), palette: editor.palette, allowsNone: false)
                Picker("Opens screen", selection: Binding(get: { w.deepLinkScreenID ?? "" }, set: { v in editor.mutate("Edit Widget") { $0.widget.deepLinkScreenID = v.isEmpty ? nil : v } })) {
                    Text("First screen").tag("")
                    ForEach(project.screens) { Text($0.name).tag($0.id) }
                }
            } header: { SectionTitle(title: "Content", symbol: "text.alignleft") }
        }
    }
}

/// A mini Home Screen with the app icon and name.
struct HomeScreenPreview: View {
    @ObservedObject var editor: EditorModel
    let iconImage: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            AppIconView(icon: editor.project.brand.icon, theme: editor.project.theme, size: 46, assetImage: iconImage)
            Text(editor.project.brand.displayName).font(.system(size: 10, weight: .medium)).foregroundStyle(.white).lineLimit(1).frame(width: 64)
        }
        .padding(10)
        .background(LinearGradient(colors: [Color(hex: "#1E3C72") ?? .blue, Color(hex: "#2A5298") ?? .indigo], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Renders the widget design the same way the widget extension does.
struct WidgetPreview: View {
    let project: Project

    var body: some View {
        let w = project.widget
        let palette = ThemePalette(theme: project.theme, dark: false)
        let fg = palette.color(w.foreground, fallback: .white)
        let size: CGSize = w.family == .small ? CGSize(width: 158, height: 158) : (w.family == .medium ? CGSize(width: 330, height: 158) : CGSize(width: 330, height: 345))
        VStack(alignment: .leading, spacing: 6) {
            switch w.layout {
            case .stat:
                Image(systemName: w.symbol).font(.title2.weight(.semibold))
                Spacer(minLength: 0)
                Text(w.value).font(.system(size: 34, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                Text(w.title).font(.headline).lineLimit(1)
                Text(w.subtitle).font(.caption).opacity(0.8).lineLimit(2)
            case .list:
                Label(w.title, systemImage: w.symbol).font(.headline)
                ForEach(Array((w.items.isEmpty ? ["First item", "Second item", "Third item"] : w.items).prefix(w.family == .large ? 8 : 3).enumerated()), id: \.offset) { _, item in
                    HStack { Circle().frame(width: 6, height: 6); Text(item).font(.subheadline).lineLimit(1) }
                }
                Spacer(minLength: 0)
            case .quote:
                Image(systemName: "quote.opening").font(.title2)
                Text(w.value).font(.system(.title3, design: .serif)).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Text(w.subtitle).font(.caption).opacity(0.8)
            case .progress:
                Label(w.title, systemImage: w.symbol).font(.headline)
                Gauge(value: min(max(w.progress, 0), 1)) { Text(w.title) } currentValueLabel: { Text("\(Int(w.progress * 100))%") }
                    .gaugeStyle(.accessoryCircularCapacity).tint(fg)
                Text(w.subtitle).font(.caption).opacity(0.85)
            }
        }
        .foregroundStyle(fg)
        .padding(16)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(palette.fill(w.background))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

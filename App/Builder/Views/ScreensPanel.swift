import SwiftUI
import ReyForgeCore

/// Screens, navigation (stack or tabs), and per-screen settings.
struct ScreensPanel: View {
    @ObservedObject var editor: EditorModel
    @State private var newScreenName = ""
    @State private var newAsTab = false
    @State private var showingNew = false

    static let screenIdeas: [(String, String, String)] = [
        ("Settings", "gearshape", "Add a settings screen with notifications, dark mode toggle and an about section"),
        ("Profile", "person.crop.circle", "Add a profile screen with avatar, stats and edit button"),
        ("Login", "person.badge.key", "Add a login screen with email, password validation and sign in with Apple"),
        ("List & detail", "list.bullet.rectangle", "Add a list screen of items with search that opens a detail screen"),
        ("Form", "doc.text", "Add a form screen to create a new entry with validation and a save button"),
        ("Dashboard", "chart.bar.xaxis", "Add a dashboard screen with stat cards and a chart"),
        ("Onboarding", "rectangle.stack", "Add an onboarding screen with three swipeable pages and a get started button"),
        ("Map", "map", "Add a map screen with nearby places"),
        ("Chat", "bubble.left.and.bubble.right", "Add a chat screen with messages and a message field"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(editor.project.screens) { s in
                    HStack(spacing: 10) {
                        Image(systemName: s.icon).foregroundStyle(Color.accentColor).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).font(.subheadline.weight(editor.currentScreenID == s.id ? .bold : .regular))
                            HStack(spacing: 6) {
                                if editor.project.navigation.initialScreenID == s.id { badge("Start", .green) }
                                if editor.project.isTab(s.id) { badge("Tab", .blue) }
                                Text("\(s.root.flattened.count - 1) elements").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        NavigationLink("") { Form { ScreenSettingsSections(editor: editor, screen: s) }.navigationTitle(s.name) }
                            .frame(width: 24)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editor.showScreen(s.id) }
                    .accessibilityIdentifier("screen.row.\(s.name)")
                    .contextMenu {
                        Button { editor.showScreen(s.id) } label: { Label("Open", systemImage: "arrow.right.circle") }
                        Button { editor.mutate("Duplicate Screen") { p in _ = p.duplicateScreen(id: s.id) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        Button { editor.mutate("Set Initial Screen") { $0.navigation.initialScreenID = s.id } } label: { Label("Make first screen", systemImage: "flag") }
                        if editor.project.screens.count > 1 {
                            Button(role: .destructive) { editor.mutate("Delete Screen") { p in p.removeScreen(id: s.id) } } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }
                .onMove { from, to in editor.mutate("Reorder Screens") { p in p.screens.move(fromOffsets: from, toOffset: to) } }
                .onDelete { idx in
                    guard editor.project.screens.count > idx.count else { return }
                    let ids = idx.map { editor.project.screens[$0].id }
                    editor.mutate("Delete Screen") { p in for id in ids { p.removeScreen(id: id) } }
                }
                Button { newScreenName = ""; newAsTab = editor.project.navigation.style == .tabs; showingNew = true } label: {
                    Label("New blank screen", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("screens.add")
            } header: {
                SectionTitle(title: "Screens", symbol: "rectangle.stack")
            }
            Section {
                ForEach(Self.screenIdeas, id: \.0) { idea in
                    Button {
                        editor.panel = .ai
                        editor.chat.send(idea.2)
                    } label: { Label(idea.0, systemImage: idea.1) }
                }
            } header: {
                SectionTitle(title: "Generate a screen with AI", symbol: "sparkles")
            }
            Section {
                Picker("Style", selection: Binding(get: { editor.project.navigation.style }, set: { v in
                    editor.mutate("Navigation Style") { p in
                        p.navigation.style = v
                        if v == .tabs && p.navigation.tabs.count < 2 {
                            for s in p.screens.prefix(4) where !p.isTab(s.id) { p.setTab(s.id, enabled: true) }
                        }
                    }
                })) {
                    Text("Single stack").tag(NavigationConfig.Style.stack)
                    Text("Tab bar").tag(NavigationConfig.Style.tabs)
                }
                .pickerStyle(.segmented)
                if editor.project.navigation.style == .tabs {
                    ForEach(editor.project.navigation.tabs) { tab in
                        HStack {
                            Image(systemName: tab.icon).frame(width: 24)
                            TextField("Title", text: Binding(get: { tab.title }, set: { t in
                                editor.mutate("Edit Tabs") { p in if let i = p.navigation.tabs.firstIndex(where: { $0.screenID == tab.screenID }) { p.navigation.tabs[i].title = t } }
                            }))
                            NavigationLink("") {
                                SymbolPickerView(symbol: Binding(get: { tab.icon }, set: { icon in
                                    editor.mutate("Edit Tabs") { p in if let i = p.navigation.tabs.firstIndex(where: { $0.screenID == tab.screenID }) { p.navigation.tabs[i].icon = icon } }
                                }))
                            }
                            .frame(width: 24)
                        }
                    }
                    .onMove { from, to in editor.mutate("Reorder Tabs") { p in p.navigation.tabs.move(fromOffsets: from, toOffset: to) } }
                }
            } header: {
                SectionTitle(title: "Navigation", symbol: "rectangle.split.3x1")
            } footer: {
                Text(editor.project.navigation.style == .tabs ? "Tabs need at least two screens. Toggle “Show in tab bar” in each screen's settings." : "Screens open from buttons and links with the Navigate action.")
            }
        }
        .alert("New screen", isPresented: $showingNew) {
            TextField("Name", text: $newScreenName)
            Button("Add") { editor.addScreen(name: newScreenName, asTab: newAsTab) }
            Button("Add as tab") { editor.addScreen(name: newScreenName, asTab: true) }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            if editor.screenSettingsFocus != nil { editor.screenSettingsFocus = nil }
        }
    }

    func badge(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.bold)).foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color))
    }
}

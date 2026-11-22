import SwiftUI
import UniformTypeIdentifiers
import ReyForgeCore

struct HomeView: View {
    @EnvironmentObject var library: ProjectLibrary
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var updates = UpdateService.shared
    @State private var showNew = false
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var renaming: ProjectSummary?
    @State private var renameText = ""
    @State private var deleting: ProjectSummary?
    @State private var exportItem: ExportItem?
    @State private var pendingPrompt: String?
    @State private var pendingCreate: (AppTemplate?, String, String?)?

    struct ExportItem: Identifiable { let id = UUID(); let url: URL }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    quickActions
                    if updates.updateAvailable, let r = updates.latest {
                        Button { showSettings = true } label: {
                            Label("ReyForge \(UpdateService.version(of: r)) is available — tap to update", systemImage: "arrow.down.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.green.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                    }
                    projectsSection
                    templatesSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
            .sheet(isPresented: $showNew, onDismiss: {
                // Open the editor only after the sheet is gone (presenting during dismissal is dropped).
                guard let pc = pendingCreate else { return }
                pendingCreate = nil
                let p = library.create(from: pc.0, name: pc.1)
                pendingPrompt = pc.2
                library.openProject = p
            }) {
                NewProjectSheet { template, name, prompt in pendingCreate = (template, name, prompt) }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $settings.showOnboarding) { WelcomeView() }
            .sheet(item: $exportItem) { item in ShareSheet(items: [item.url]) }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.reyforgeProject, .json, .zip, .data], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first { library.handleOpen(url) }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") { if let r = renaming { library.rename(r.id, to: renameText) }; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog("Delete \(deleting?.name ?? "project")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) { if let d = deleting { library.delete(d.id) }; deleting = nil }
            } message: { Text("This can't be undone.") }
            .alert(library.message ?? "", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
        .fullScreenCover(item: $library.openProject) { p in
            EditorView(project: p, library: library, initialPrompt: pendingPrompt)
                .environmentObject(library)
                .onDisappear { pendingPrompt = nil }
        }
        .task {
            if !Paths.isUITest && settings.updateRepo.isEmpty == false { await updates.check(settings: settings) }
        }
    }

    var header: some View {
        HStack(spacing: 14) {
            Image("BrandMark")
                .resizable().frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: RF.violet.opacity(0.4), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("ReyForge").font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(RF.gradient)
                Text("Build native iOS apps on your iPhone").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.title2).foregroundStyle(.secondary)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("home.settings")
        }
        .padding(.top, 8)
    }

    var quickActions: some View {
        HStack(spacing: 10) {
            actionCard("New app", "plus.app.fill", RF.gradient, id: "home.new") { showNew = true }
            actionCard("Import", "square.and.arrow.down.fill", LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), id: "home.import") { showImporter = true }
        }
    }

    func actionCard(_ title: String, _ symbol: String, _ fill: LinearGradient, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder var projectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your apps").font(.title3.weight(.bold))
            if library.projects.isEmpty {
                EmptyHint(symbol: "square.dashed", title: "No apps yet", message: "Start from a template below or describe your app to ReyForge AI.")
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(library.projects) { p in
                        ProjectCard(project: p)
                            .onTapGesture { library.open(p.id) }
                            .contextMenu {
                                Button { library.open(p.id) } label: { Label("Open", systemImage: "square.and.pencil") }
                                Button { renameText = p.name; renaming = p } label: { Label("Rename", systemImage: "pencil") }
                                Button { library.duplicate(p.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                Button {
                                    if let url = try? library.exportArchive(p.id) { exportItem = ExportItem(url: url) }
                                } label: { Label("Export project", systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { deleting = p } label: { Label("Delete", systemImage: "trash") }
                            }
                            .accessibilityIdentifier("project.\(p.name)")
                    }
                }
            }
        }
    }

    var templatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Templates").font(.title3.weight(.bold))
                Spacer()
                Button("See all") { showNew = true }.font(.subheadline)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Templates.all) { t in
                        TemplateCard(template: t)
                            .frame(width: 220)
                            .onTapGesture {
                                let p = library.create(from: t, name: t.name)
                                library.openProject = p
                            }
                            .accessibilityIdentifier("template.\(t.id)")
                    }
                }
            }
        }
    }
}

struct ProjectCard: View {
    let project: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppIconView(icon: project.icon, theme: project.theme, size: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.headline).lineLimit(1)
                Text("\(project.screenCount) screen\(project.screenCount == 1 ? "" : "s") · \(project.updatedAt.relative)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct TemplateCard: View {
    let template: AppTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: template.colors.compactMap { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: template.symbol).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white.opacity(0.95)).padding(14)
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(template.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(template.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// Start a new app from a template, from scratch, or by describing it to the AI.
struct NewProjectSheet: View {
    let create: (AppTemplate?, String, String?) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var prompt = ""
    @State private var category = "All"

    var categories: [String] { ["All"] + Array(Set(Templates.all.map(\.category))).sorted() }
    var templates: [AppTemplate] { category == "All" ? Templates.all : Templates.all.filter { $0.category == category } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Describe your app", systemImage: "sparkles").font(.headline)
                        TextField("e.g. A plant care app with watering reminders, a plant list and a care calendar", text: $prompt, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                            .accessibilityIdentifier("new.prompt")
                        Button {
                            let n = name.isEmpty ? Self.guessName(prompt) : name
                            dismiss()
                            create(Templates.template("blank"), n, prompt)
                        } label: {
                            Label("Build it with AI", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoundedRectangle(cornerRadius: 12).fill(RF.gradient))
                                .foregroundStyle(.white)
                                .font(.headline)
                        }
                        .disabled(prompt.trimmingCharacters(in: .whitespaces).count < 4)
                        .accessibilityIdentifier("new.buildWithAI")
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemGroupedBackground)))

                    TextField("App name (optional)", text: $name)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
                        .accessibilityIdentifier("new.name")

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(categories, id: \.self) { c in
                                Button { category = c } label: {
                                    Text(c).font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12).padding(.vertical, 7)
                                        .background(Capsule().fill(category == c ? Color.accentColor : Color(.secondarySystemGroupedBackground)))
                                        .foregroundStyle(category == c ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(templates) { t in
                            Button {
                                dismiss()
                                create(t, name.isEmpty ? t.name : name, nil)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    TemplateCard(template: t)
                                    ForEach(t.features.prefix(3), id: \.self) { f in
                                        Label(f, systemImage: "checkmark").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("new.template.\(t.id)")
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    static func guessName(_ prompt: String) -> String {
        let p = prompt.lowercased()
        for marker in ["called ", "named "] {
            if let r = p.range(of: marker) {
                let rest = prompt[r.upperBound...].split(separator: " ").prefix(3).joined(separator: " ")
                let cleaned = rest.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
                if !cleaned.isEmpty { return cleaned.capitalized }
            }
        }
        let words = prompt.split(separator: " ").filter { $0.count > 3 && !["build", "make", "create", "with", "that", "app", "application", "please"].contains($0.lowercased()) }
        return words.prefix(2).map { $0.capitalized }.joined(separator: " ").isEmpty ? "My App" : words.prefix(2).map { $0.capitalized }.joined(separator: " ")
    }
}

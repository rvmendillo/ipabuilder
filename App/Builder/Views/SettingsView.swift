import SwiftUI
import UniformTypeIdentifiers
import ReyForgeCore

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var updates = UpdateService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { AISettingsView() } label: {
                        Label { VStack(alignment: .leading) { Text("ReyForge AI"); Text((AIEngineKind(rawValue: settings.aiEngine) ?? .offline).title).font(.caption).foregroundStyle(.secondary) } } icon: { Image(systemName: "sparkles") }
                    }
                    .accessibilityIdentifier("settings.ai")
                    NavigationLink { SigningVaultView() } label: { Label("Signing certificates", systemImage: "signature") }
                        .accessibilityIdentifier("settings.signing")
                    NavigationLink { UpdatesView() } label: {
                        Label { HStack { Text("Updates"); if updates.updateAvailable { Spacer(); Text("New").font(.caption.bold()).foregroundStyle(.white).padding(.horizontal, 6).background(Capsule().fill(.green)) } } } icon: { Image(systemName: "arrow.down.circle") }
                    }
                }
                Section("Canvas") {
                    Toggle("Snap to 4 pt grid", isOn: $settings.snapToGrid)
                }
                Section {
                    NavigationLink { AboutView() } label: { Label("About ReyForge", systemImage: "info.circle") }
                } footer: {
                    Text("ReyForge \(RF.appVersion) (\(RF.appBuild))")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - AI

struct AISettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var downloader = ModelDownloader.shared
    @State private var claudeKey = ""
    @State private var openAIKey = ""
    @State private var appleStatus = ""

    var body: some View {
        Form {
            Section {
                ForEach(AIEngineKind.allCases) { kind in
                    Button { settings.aiEngine = kind.rawValue } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.symbol).frame(width: 28).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title).foregroundStyle(.primary)
                                Text(kind.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.aiEngine == kind.rawValue { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                    .accessibilityIdentifier("engine.\(kind.rawValue)")
                }
            } header: { Text("Engine") } footer: {
                Text("Every engine works with ReyForge's design engine, so small models still build complete, polished screens.")
            }
            Section {
                ForEach(LocalModel.catalog) { m in ModelRow(model: m) }
            } header: { Text("On-device models (free & open source)") } footer: {
                Text("This iPhone has \(String(format: "%.0f", LocalModel.deviceRAMGB)) GB of memory. Models run with llama.cpp on the GPU, fully offline.")
            }
            Section {
                SecureField("sk-ant-…", text: $claudeKey)
                    .onSubmit { settings.claudeAPIKey = claudeKey }
                    .onChange(of: claudeKey) { _, v in settings.claudeAPIKey = v }
                Picker("Model", selection: $settings.claudeModel) {
                    ForEach(ClaudeEngine.models, id: \.self) { Text($0).tag($0) }
                }
                Picker("Effort", selection: $settings.claudeEffort) {
                    ForEach(["low", "medium", "high"], id: \.self) { Text($0.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show thinking summaries", isOn: $settings.showAIThinking)
            } header: { Text("Claude (Anthropic API)") } footer: {
                Text("Your key is stored in the iOS Keychain and only sent to api.anthropic.com.")
            }
            Section {
                TextField("Server URL", text: $settings.openAIBaseURL).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("Model", text: $settings.openAIModel).autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("API key (optional)", text: $openAIKey).onChange(of: openAIKey) { _, v in settings.openAIKey = v }
            } header: { Text("OpenAI-compatible server") } footer: {
                Text("Works with Ollama, LM Studio, llama-server, OpenRouter and others.")
            }
            Section {
                Text(appleStatus.isEmpty ? "Checking…" : appleStatus).font(.callout)
            } header: { Text("Apple Intelligence") }
        }
        .navigationTitle("ReyForge AI")
        .onAppear {
            claudeKey = settings.claudeAPIKey
            openAIKey = settings.openAIKey
            appleStatus = Self.appleIntelligenceStatus()
        }
    }

    static func appleIntelligenceStatus() -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleIntelligenceEngine.isAvailable ? "Available on this device." : AppleIntelligenceEngine.unavailableReason
        }
        #endif
        return "Requires iOS 26 on an Apple Intelligence device."
    }
}

struct ModelRow: View {
    let model: LocalModel
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var downloader = ModelDownloader.shared

    var body: some View {
        let installed = model.localURL != nil
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.name).font(.subheadline.weight(.semibold))
                        if model.isBundled { Text("Built in").font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal, 5).background(Capsule().fill(RF.violet)) }
                    }
                    Text("\(model.bytes.byteString) · \(model.license) · \(model.summary)").font(.caption).foregroundStyle(.secondary)
                    if !model.fitsDevice { Text("Needs about \(Int(model.minRAMGB)) GB of memory — may be slow or fail on this device.").font(.caption2).foregroundStyle(.orange) }
                }
                Spacer()
                if installed {
                    if settings.localModelID == model.id && settings.aiEngine == AIEngineKind.builtin.rawValue {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Use") { settings.localModelID = model.id; settings.aiEngine = AIEngineKind.builtin.rawValue; AIEngineManager.shared.unloadLocalModel() }
                            .buttonStyle(.bordered)
                    }
                } else if let p = downloader.progress[model.id] {
                    Button { downloader.cancel(model) } label: { Image(systemName: "stop.circle") }
                    Text("\(Int(p * 100))%").font(.caption.monospacedDigit())
                } else {
                    Button("Get") { downloader.start(model) }.buttonStyle(.borderedProminent)
                }
            }
            if let p = downloader.progress[model.id] { ProgressView(value: p) }
            if let e = downloader.errors[model.id] { Text(e).font(.caption).foregroundStyle(.red) }
        }
        .swipeActions {
            if installed && !model.isBundled {
                Button(role: .destructive) { downloader.delete(model) } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }
}

// MARK: - Signing

struct SigningVaultView: View {
    @ObservedObject var vault = SigningVault.shared
    @ObservedObject var settings = AppSettings.shared
    @State private var showImport = false

    var body: some View {
        Form {
            if vault.identities.isEmpty {
                Section {
                    EmptyHint(symbol: "signature", title: "Add your certificate", message: "Import the .p12 certificate (with its password) and the .mobileprovision from your Apple Developer account or signing service. A .zip with both works too.")
                }
            }
            ForEach(vault.identities) { i in
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(i.name).font(.headline)
                            Text(i.certificateName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings.selectedSigningID == i.id {
                            Label("Default", systemImage: "checkmark.seal.fill").labelStyle(.iconOnly).foregroundStyle(.green)
                        } else {
                            Button("Use") { settings.selectedSigningID = i.id }.buttonStyle(.bordered)
                        }
                    }
                    LabeledContent("Profile", value: i.profileName)
                    LabeledContent("Type", value: i.kind)
                    LabeledContent("Team", value: "\(i.teamName) (\(i.teamID))")
                    LabeledContent("App ID", value: i.appIDPattern)
                    if i.deviceCount > 0 { LabeledContent("Devices", value: "\(i.deviceCount)") }
                    if let d = i.profileExpiry { LabeledContent("Profile expires", value: d.formatted(date: .abbreviated, time: .omitted)) }
                    if let d = i.certificateExpiry { LabeledContent("Certificate expires", value: d.formatted(date: .abbreviated, time: .omitted)) }
                    if i.isExpired { Label("Expired — import a new one", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                    HStack {
                        Button("Check revocation") { Task { await vault.checkRevocation(i) } }
                        Spacer()
                        if let r = vault.revocation[i.id] { Text(r).font(.caption).foregroundStyle(r.hasPrefix("Valid") ? .green : .secondary) }
                    }
                    Button(role: .destructive) { vault.delete(i.id) } label: { Label("Remove", systemImage: "trash") }
                }
            }
            Section {
                Button { showImport = true } label: { Label("Import certificate & profile", systemImage: "plus.circle.fill") }
                    .accessibilityIdentifier("vault.import")
            } footer: {
                Text("Files stay on this iPhone; the password is kept in the Keychain. Wildcard profiles (App ID ending in *) can sign any app, including widgets.")
            }
        }
        .navigationTitle("Signing")
        .sheet(isPresented: $showImport) { ImportIdentitySheet() }
    }
}

struct ImportIdentitySheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var files: [URL] = []
    @State private var password = ""
    @State private var name = ""
    @State private var picking = false
    @State private var error: String?

    static let types: [UTType] = [UTType(filenameExtension: "p12") ?? .data, UTType(filenameExtension: "mobileprovision") ?? .data, .zip, .data]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { picking = true } label: { Label(files.isEmpty ? "Choose files…" : "Choose again…", systemImage: "folder") }
                    ForEach(files, id: \.self) { f in Label(f.lastPathComponent, systemImage: f.pathExtension == "mobileprovision" ? "doc.badge.gearshape" : "key") }
                } header: { Text("Certificate (.p12) + profile (.mobileprovision), or a .zip") }
                Section {
                    SecureField("Certificate password", text: $password)
                    TextField("Name (optional)", text: $name)
                }
                if let e = error { Section { Label(e, systemImage: "xmark.octagon.fill").foregroundStyle(.red) } }
            }
            .navigationTitle("Add Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        do { try SigningVault.shared.importFiles(files, password: password, name: name); dismiss() }
                        catch let e { error = e.localizedDescription }
                    }
                    .disabled(files.isEmpty)
                }
            }
            .fileImporter(isPresented: $picking, allowedContentTypes: Self.types, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { files = urls; error = nil }
            }
        }
    }
}

// MARK: - Updates

struct UpdatesView: View {
    @ObservedObject var updates = UpdateService.shared
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var vault = SigningVault.shared
    @State private var token = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Installed", value: "\(updates.currentVersion) (\(updates.currentBuild))")
                if let r = updates.latest {
                    LabeledContent("Latest", value: "\(UpdateService.version(of: r))\(UpdateService.build(of: r).map { " (\($0))" } ?? "")")
                }
                Button { Task { await updates.check(settings: settings) } } label: {
                    HStack { Label("Check for updates", systemImage: "arrow.clockwise"); if updates.isChecking { Spacer(); ProgressView() } }
                }
                if !updates.status.isEmpty { Text(updates.status).font(.caption).foregroundStyle(.secondary) }
                if let e = updates.error { Text(e).font(.caption).foregroundStyle(.red) }
            }
            if let r = updates.latest {
                Section {
                    Text(r.body ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(6)
                    if let identity = vault.identity(settings.selectedSigningID) ?? vault.identities.first {
                        Button {
                            Task { await updates.install(r, identity: identity, settings: settings) }
                        } label: {
                            HStack { Label(updates.isNewer(r) ? "Download & install update" : "Reinstall this version", systemImage: "arrow.down.app.fill"); if updates.isInstalling { Spacer(); ProgressView() } }
                        }
                        .disabled(updates.isInstalling)
                        Text("Re-signed on this iPhone with “\(identity.name)”.").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        NavigationLink { SigningVaultView() } label: { Label("Add a certificate to install updates", systemImage: "signature") }
                    }
                    Toggle("Download lite build (keeps your downloaded models)", isOn: $settings.preferLiteUpdates)
                } header: { Text(r.name ?? r.tag_name) }
            }
            Section {
                TextField("Owner", text: $settings.updateOwner).autocorrectionDisabled().textInputAutocapitalization(.never)
                TextField("Repository", text: $settings.updateRepo).autocorrectionDisabled().textInputAutocapitalization(.never)
                SecureField("GitHub token (private repos only)", text: $token).onChange(of: token) { _, v in settings.githubToken = v }
            } header: { Text("Release source") } footer: {
                Text("Every push to the repository's default branch publishes a nightly build with GitHub Actions. Install it here — ReyForge re-signs it with your certificate and installs it over this copy, keeping your projects.")
            }
        }
        .navigationTitle("Updates")
        .onAppear { token = settings.githubToken }
        .task { if updates.lastChecked == nil { await updates.check(settings: settings) } }
    }
}

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image("BrandMark").resizable().frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Text("ReyForge").font(.title.weight(.heavy)).foregroundStyle(RF.gradient)
                    Text("Design, vibe-code and build native iOS apps entirely on iPhone.").font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Text("Version \(RF.appVersion) (\(RF.appBuild))").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Open source inside") {
                LabeledContent("Qwen3.5 models", value: "Apache-2.0")
                LabeledContent("llama.cpp", value: "MIT")
                LabeledContent("zsign", value: "MIT")
                LabeledContent("OpenSSL", value: "Apache-2.0")
            }
            Section("How building works") {
                Text("Your app runs on ReyForge's native SwiftUI runtime. Building copies that precompiled runtime, embeds your project, icon and launch screen, signs everything with your certificate and hands the IPA to iOS — no Mac or build server needed.")
                    .font(.callout)
            }
        }
        .navigationTitle("About")
    }
}

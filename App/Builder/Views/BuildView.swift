import SwiftUI
import UniformTypeIdentifiers
import ReyForgeCore

/// Build & install on device — no Mac, no GitHub runner.
struct BuildView: View {
    @ObservedObject var editor: EditorModel
    @StateObject private var service = BuildService()
    @ObservedObject var vault = SigningVault.shared
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) var dismiss
    @State private var includeWidget = true
    @State private var unsigned = false
    @State private var installing = false
    @State private var installError: String?
    @State private var shareItem: ShareURL?
    @State private var showVault = false

    var identity: SigningIdentity? { unsigned ? nil : vault.identity(settings.selectedSigningID) ?? vault.identities.first }
    var project: Project { editor.project }
    var issues: [ProjectIssue] { ProjectValidator.validate(project) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppIconView(icon: project.brand.icon, theme: project.theme, size: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.brand.displayName).font(.headline)
                            Text(project.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text("v\(project.version) (\(project.build)) · \(project.screens.count) screens").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !issues.isEmpty {
                    Section {
                        ForEach(Array(issues.prefix(6).enumerated()), id: \.offset) { _, issue in
                            Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.severity == .error ? .red : .orange)
                                .font(.caption)
                        }
                    } header: { Text("Checks") }
                }
                signingSection
                Section {
                    Toggle("Include Home Screen widget", isOn: $includeWidget).disabled(!project.widget.enabled)
                    Toggle("Unsigned IPA (sign elsewhere)", isOn: $unsigned)
                } header: { Text("Options") } footer: {
                    Text(unsigned ? "Produces an unsigned IPA for signers like ESign, Feather, Sideloadly or TrollStore." : "ReyForge signs the app with your certificate using zsign, then installs it through iOS.")
                }
                progressSection
                if let r = service.result { resultSection(r) }
            }
            .navigationTitle("Build App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await service.build(project: project, assets: editor.library.assets(for: project.id), identity: identity, includeWidget: includeWidget) }
                } label: {
                    HStack {
                        if service.isBuilding { ProgressView().tint(.white) }
                        Text(service.isBuilding ? "Building…" : (service.result == nil ? "Build IPA" : "Build Again"))
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(RF.gradient))
                    .foregroundStyle(.white)
                }
                .disabled(service.isBuilding || (!unsigned && identity == nil) || issues.contains { $0.severity == .error })
                .padding()
                .background(.bar)
                .accessibilityIdentifier("build.start")
            }
            .sheet(item: $shareItem) { item in ShareSheet(items: [item.url]) }
            .sheet(isPresented: $showVault) { NavigationStack { SigningVaultView() } }
            .alert("Install failed", isPresented: Binding(get: { installError != nil }, set: { if !$0 { installError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(installError ?? "") }
            .onAppear { includeWidget = project.widget.enabled }
        }
    }

    struct ShareURL: Identifiable { let id = UUID(); let url: URL }

    @ViewBuilder var signingSection: some View {
        if !unsigned {
            Section {
                if vault.identities.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No signing certificate yet", systemImage: "signature").font(.headline)
                        Text("Import your .p12 certificate and .mobileprovision once — they stay on this iPhone.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button { showVault = true } label: { Label("Add certificate", systemImage: "plus.circle.fill") }
                        .accessibilityIdentifier("build.addCertificate")
                } else {
                    Picker("Certificate", selection: Binding(get: { identity?.id ?? "" }, set: { settings.selectedSigningID = $0 })) {
                        ForEach(vault.identities) { i in Text(i.name).tag(i.id) }
                    }
                    if let i = identity, let profile = vault.profile(for: i) {
                        let problems = profile.problems(for: project.bundleID, includeWidget: includeWidget && project.widget.enabled)
                        LabeledContent("Profile", value: i.profileName)
                        LabeledContent("App ID", value: i.appIDPattern)
                        if let exp = i.profileExpiry { LabeledContent("Expires", value: exp.formatted(date: .abbreviated, time: .omitted)) }
                        ForEach(problems, id: \.self) { p in
                            Label(p, systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Button { showVault = true } label: { Label("Manage certificates", systemImage: "key.fill") }
                }
            } header: { Text("Signing") }
        }
    }

    @ViewBuilder var progressSection: some View {
        if service.step != nil || service.error != nil {
            Section {
                ForEach(BuildService.Step.allCases.filter { $0 != .done && !(unsigned && $0 == .sign) }) { step in
                    HStack {
                        stepIcon(step)
                        Text(step.title)
                        Spacer()
                    }
                    .font(.subheadline)
                }
                if let e = service.error {
                    Label(e, systemImage: "xmark.octagon.fill").foregroundStyle(.red).font(.caption)
                        .accessibilityIdentifier("build.error")
                }
                if !service.log.isEmpty {
                    DisclosureGroup("Log") {
                        ForEach(Array(service.log.enumerated()), id: \.offset) { _, l in Text(l).font(.caption.monospaced()) }
                    }
                }
            } header: { Text("Progress") }
        }
    }

    @ViewBuilder func stepIcon(_ step: BuildService.Step) -> some View {
        let current = service.step?.rawValue ?? -1
        if service.error != nil && step.rawValue == current + 1 {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else if step.rawValue < current || service.step == .done {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if step.rawValue == current {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }

    func resultSection(_ r: BuildService.Result) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(r.ipa.lastPathComponent)", systemImage: "shippingbox.fill").font(.headline)
                    .accessibilityIdentifier("build.result")
                Text("\(r.size.byteString) · built in \(String(format: "%.1f", r.seconds))s · \(r.signed ? "signed" : "unsigned")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if r.signed {
                Button {
                    installing = true
                    Task {
                        do { try await DeviceInstaller.install(ipa: r.ipa, bundleID: r.bundleID, name: r.name, version: r.version) }
                        catch { installError = error.localizedDescription }
                        installing = false
                    }
                } label: {
                    HStack { Label("Install on this iPhone", systemImage: "arrow.down.app.fill"); if installing { Spacer(); ProgressView() } }
                }
                .accessibilityIdentifier("build.install")
            }
            Button { shareItem = ShareURL(url: r.ipa) } label: { Label("Share IPA…", systemImage: "square.and.arrow.up") }
            Text("Saved in Files › On My iPhone › ReyForge › Builds").font(.caption2).foregroundStyle(.secondary)
        } header: { Text("Your app is ready") } footer: {
            if r.signed { Text("Installing uses a localhost server and a public manifest helper (api.palera.in). Keep ReyForge open until the icon appears on your Home Screen.") }
        }
    }
}

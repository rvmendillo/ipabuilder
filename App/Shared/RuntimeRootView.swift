import SwiftUI
import ReyForgeCore

/// The whole running app: splash, tab bar or navigation stack, sheets, alerts and toasts.
struct RuntimeRootView: View {
    @ObservedObject var store: RuntimeStore
    @Environment(\.colorScheme) var systemScheme

    var preferredScheme: ColorScheme? {
        if let v = store.project.variable(named: "darkMode"), v.type == .bool { return store.state.value(v.name).boolValue ? .dark : .light }
        switch store.project.theme.appearance {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

    var palette: ThemePalette { ThemePalette(theme: store.project.theme, dark: (preferredScheme ?? systemScheme) == .dark) }

    static func role(_ request: AlertRequest, _ index: Int) -> ButtonRole? {
        if request.destructiveIndex == index { return .destructive }
        if request.buttons.count > 1 && index == 0 { return .cancel }
        return nil
    }

    var alertShown: Binding<Bool> {
        Binding(get: { store.alert != nil }, set: { shown in
            guard !shown else { return }
            let a = store.alert
            store.alert = nil
            a?.resume(0)
        })
    }

    var body: some View {
        let _ = store.revision
        ZStack {
            mainContent
                .opacity(store.splashFinished ? 1 : 0)
            if !store.splashFinished {
                SplashView(project: store.project) { withAnimation(.easeOut(duration: 0.35)) { store.splashFinished = true } }
                    .transition(.opacity)
            }
        }
        .environmentObject(store)
        .environment(\.palette, palette)
        .tint(palette.accent)
        .fontDesign(palette.fontDesign)
        .preferredColorScheme(preferredScheme)
        .overlay(alignment: .top) { ToastOverlay(toast: store.toast, palette: palette) }
        .alert(store.alert?.title ?? "", isPresented: alertShown, presenting: store.alert) { request in
            ForEach(Array(request.buttons.enumerated()), id: \.offset) { i, title in
                Button(title, role: Self.role(request, i)) {
                    store.alert = nil
                    request.resume(i)
                }
            }
        } message: { request in
            if !request.message.isEmpty { Text(request.message) }
        }
        .sheet(item: $store.shareItem) { item in ShareSheet(items: [item.text]).presentationDetents([.medium, .large]) }
        .onAppear { if !(store.project.brand.splash.enabled) { store.splashFinished = true } }
    }

    @ViewBuilder var mainContent: some View {
        if store.usesTabs {
            TabView(selection: $store.selectedTab) {
                ForEach(store.project.navigation.tabs) { tab in
                    if let screen = store.project.screen(id: tab.screenID) {
                        StackHost(rootScreen: screen, key: "tab:\(tab.screenID)")
                            .tabItem { Label(tab.title, systemImage: tab.icon) }
                            .tag(tab.screenID)
                    }
                }
            }
            .presenters(store: store)
        } else if let screen = store.project.screen(id: store.rootScreenID) ?? store.project.initialScreen {
            StackHost(rootScreen: screen, key: "stack:\(screen.id)")
                .presenters(store: store)
        } else {
            ContentUnavailableView("No screens yet", systemImage: "rectangle.dashed", description: Text("Add a screen in ReyForge."))
        }
    }
}

/// A NavigationStack whose path is owned by the store.
struct StackHost: View {
    let rootScreen: Screen
    let key: String
    @EnvironmentObject var store: RuntimeStore

    var body: some View {
        NavigationStack(path: store.path(for: key)) {
            ScreenView(screen: rootScreen)
                .navigationDestination(for: String.self) { id in
                    if let s = store.project.screen(id: id) { ScreenView(screen: s) } else { Text("Missing screen") }
                }
        }
    }
}

private struct Presenters: ViewModifier {
    @ObservedObject var store: RuntimeStore
    func body(content: Content) -> some View {
        content
            .sheet(item: $store.sheet) { p in
                if let s = store.project.screen(id: p.screenID) {
                    StackHost(rootScreen: s, key: "sheet:\(p.id)")
                        .presentationDetents([.large, .medium])
                        .presentationDragIndicator(.visible)
                }
            }
            .fullScreenCover(item: $store.cover) { p in
                if let s = store.project.screen(id: p.screenID) {
                    StackHost(rootScreen: s, key: "cover:\(p.id)")
                        .overlay(alignment: .topTrailing) {
                            Button { store.cover = nil } label: {
                                Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.hierarchical).padding()
                            }
                            .accessibilityLabel("Close")
                        }
                }
            }
    }
}

extension View {
    func presenters(store: RuntimeStore) -> some View { modifier(Presenters(store: store)) }
}

struct ToastOverlay: View {
    let toast: Toast?
    let palette: ThemePalette
    var body: some View {
        if let t = toast {
            HStack(spacing: 10) {
                Image(systemName: symbol(t.style)).foregroundStyle(color(t.style))
                Text(t.message).font(.subheadline.weight(.semibold)).lineLimit(2)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityIdentifier("toast")
            .id(t.id)
        }
    }
    func symbol(_ s: String) -> String {
        switch s { case "error": return "xmark.octagon.fill"; case "warning": return "exclamationmark.triangle.fill"; case "info": return "info.circle.fill"; default: return "checkmark.circle.fill" }
    }
    func color(_ s: String) -> Color {
        switch s { case "error": return .red; case "warning": return .orange; case "info": return .blue; default: return .green }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Branding

/// Renders the project's app icon design (used on the splash, in the builder and to export PNGs).
struct AppIconView: View {
    let icon: IconSpec
    let theme: Theme
    var size: CGFloat = 120
    var rounded = true
    var assetImage: UIImage? = nil

    var body: some View {
        let palette = ThemePalette(theme: theme, dark: false)
        ZStack {
            palette.fill(icon.background)
            if icon.showsShine {
                LinearGradient(colors: [.white.opacity(0.28), .clear], startPoint: .top, endPoint: .center)
            }
            glyph(palette)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: rounded ? size * 0.2237 : 0, style: .continuous))
    }

    @ViewBuilder func glyph(_ palette: ThemePalette) -> some View {
        let g = palette.color(icon.glyphColor, fallback: .white)
        switch icon.kind {
        case .symbol:
            Image(systemName: UIImage(systemName: icon.symbol) != nil ? icon.symbol : "sparkles")
                .font(.system(size: size * icon.glyphScale, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(g)
                .shadow(color: .black.opacity(0.18), radius: size * 0.03, y: size * 0.02)
        case .emoji:
            Text(icon.emoji.isEmpty ? "🚀" : String(icon.emoji.prefix(2))).font(.system(size: size * icon.glyphScale))
        case .text:
            Text(String(icon.text.prefix(3)))
                .font(.system(size: size * icon.glyphScale * (icon.text.count > 1 ? 0.7 : 1), weight: .heavy, design: .rounded))
                .foregroundStyle(g)
                .minimumScaleFactor(0.4)
        case .image:
            if let img = assetImage { Image(uiImage: img).resizable().scaledToFill() } else { Image(systemName: "photo").foregroundStyle(g).font(.system(size: size * 0.4)) }
        }
    }

    /// Renders square PNGs for the IPA (no rounded corners — iOS applies the mask).
    @MainActor
    static func renderPNGs(icon: IconSpec, theme: Theme, assetImage: UIImage? = nil) -> [String: Data] {
        var out: [String: Data] = [:]
        for (file, px) in AppAssembler.iconSizes {
            let r = ImageRenderer(content: AppIconView(icon: icon, theme: theme, size: CGFloat(px), rounded: false, assetImage: assetImage).environment(\.colorScheme, .light))
            r.scale = 1
            r.isOpaque = true
            if let img = r.uiImage, let data = img.pngData() { out[file] = data }
        }
        return out
    }
}

struct SplashView: View {
    let project: Project
    var onFinish: () -> Void
    @State private var appeared = false
    @State private var pulse = false

    var body: some View {
        let splash = project.brand.splash
        let palette = ThemePalette(theme: project.theme, dark: project.theme.appearance == .dark)
        ZStack {
            palette.fill(splash.background ?? project.brand.icon.background).ignoresSafeArea()
            VStack(spacing: 18) {
                if splash.showsIcon {
                    AppIconView(icon: project.brand.icon, theme: project.theme, size: 112)
                        .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
                        .scaleEffect(scale(splash.animation))
                        .opacity(appeared || splash.animation == .none ? 1 : 0)
                        .offset(y: splash.animation == .slide && !appeared ? 40 : 0)
                }
                Text(splash.title.isEmpty ? project.brand.displayName : splash.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(appeared ? 1 : 0)
                let subtitle = splash.subtitle.isEmpty ? project.brand.tagline : splash.subtitle
                if !subtitle.isEmpty {
                    Text(subtitle).font(.headline).foregroundStyle(.white.opacity(0.85)).opacity(appeared ? 1 : 0)
                }
            }
            .multilineTextAlignment(.center)
            .padding(32)
            if project.brand.showsMadeWithBadge {
                VStack {
                    Spacer()
                    Text("Made with ReyForge").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7)).padding(.bottom, 24)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
            if splash.animation == .pulse { withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true } }
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.4, splash.duration)) { onFinish() }
        }
    }

    func scale(_ a: SplashSpec.Animation) -> CGFloat {
        switch a {
        case .zoom: return appeared ? 1 : 0.4
        case .pulse: return pulse ? 1.08 : 0.96
        default: return 1
        }
    }
}

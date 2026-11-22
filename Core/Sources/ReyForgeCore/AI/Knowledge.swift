import Foundation

/// Built-in answers so ReyForge AI can help even with no model loaded.
public enum Knowledge {
    struct Entry { let keywords: [String]; let answer: String }

    static let entries: [Entry] = [
        Entry(keywords: ["logic", "action", "actions", "when i tap", "on tap", "do something", "button do", "event", "flow"], answer: """
        **Adding logic**
        1. Select an element on the canvas and open the **Logic** tab in the Inspector.
        2. Pick an event (On Tap, On Change, On Appear…) and tap **Add Action**.
        3. Choose actions like *Navigate*, *Show Alert*, *Set Variable*, *If / Else*, *API Request* or *Add to List*. Actions run top to bottom and can be nested.
        Or just ask me: “when I tap Continue go to Details”.
        """),
        Entry(keywords: ["variable", "variables", "state", "data", "{{", "binding", "bind"], answer: """
        **Variables & live data**
        Open the **Data** panel to create variables (text, number, yes/no, list, object…). Bind inputs to them in the Inspector (Data → Binding) and show them in any text with `{{name}}` or expressions like `{{currency(total)}}`. Mark a variable *Persist* to keep it between launches.
        """),
        Entry(keywords: ["api", "fetch", "network", "json", "rest", "http", "backend", "server"], answer: """
        **Calling an API**
        Add an **API Request** action (Logic tab) with a URL like `https://api.open-meteo.com/v1/forecast?...`, choose GET/POST, and set *Save response to* a variable plus an optional *Response path* (e.g. `current.temperature_2m`). Use `{{variable}}` anywhere to display the result. Saved endpoints live in the Data panel.
        """),
        Entry(keywords: ["build", "ipa", "install", "sign", "signing", "certificate", "p12", "mobileprovision", "provisioning", "export"], answer: """
        **Build & install on your iPhone**
        1. Open **Signing Vault** and import your signing ZIP (or the .p12 + .mobileprovision) and password.
        2. Tap **Build & Install** in the editor. ReyForge assembles a real native IPA on-device from the precompiled runtime, signs it with your certificate (zsign) and hands it to iOS over a temporary localhost server.
        3. Confirm the install prompt. You can also **Export IPA** to share it or use **Cloud Build** (GitHub Actions).
        """),
        Entry(keywords: ["tab", "tabs", "tab bar", "navigation", "navigate", "screens", "screen"], answer: """
        **Screens & navigation**
        Use the **Screens** panel to add screens. Toggle *Show in Tab Bar* to build a tab bar app, or use navigation actions (push, sheet, full screen, replace root) to move between screens. Navigation Links in lists push screens automatically.
        """),
        Entry(keywords: ["template", "templates", "starter", "start from"], answer: """
        **Templates**
        Tap **New App** on the home screen to start from a template: Component Catalog (almost every native iOS component), Finance, Fitness, Shop, Social, Todo, Weather (live API), Settings, Onboarding + Login, Music, Restaurant Booking, Quiz and more. Every element stays editable.
        """),
        Entry(keywords: ["drag", "move", "resize", "position", "reorder", "rearrange"], answer: """
        **Moving things around**
        Tap to select, then drag the selection to reorder it or drop it into another container (the blue line shows where it lands). In a **Free Layout** container drag anywhere and use the corner handles to resize. The Layers panel supports drag-to-reorder, and the Inspector's Layout tab has exact sizes and offsets.
        """),
        Entry(keywords: ["brand", "branding", "icon", "app icon", "splash", "logo", "theme", "colors", "color", "font"], answer: """
        **Branding**
        Open **Brand Studio** to design the app icon (SF Symbol, emoji, text or photo on a gradient), pick a theme preset, set accent and background colors, typography, corner radius and the animated launch splash. The icon is rendered into the IPA when you build.
        """),
        Entry(keywords: ["model", "ai", "llm", "offline", "qwen", "claude", "apple intelligence", "ollama", "engine"], answer: """
        **AI engines**
        ReyForge AI runs fully offline with the built-in open-source Qwen model plus the ReyForge design engine. In **AI Settings** you can download a smaller or larger model, use Apple Intelligence (iOS 26), connect Claude with your own API key, or point to any OpenAI-compatible server such as Ollama on your Mac.
        """),
        Entry(keywords: ["widget", "home screen widget"], answer: """
        **Widgets**
        In **Brand Studio → Widget** enable the Home Screen widget, choose small/medium/large and a layout (stat, list, quote, progress). Widgets are included when your provisioning profile allows the extension's bundle ID (wildcard profiles work best).
        """),
        Entry(keywords: ["code", "swift", "xcode", "export code", "source"], answer: """
        **SwiftUI code**
        Open **Code** from the editor menu to view generated SwiftUI for the current screen, or export the whole project as a ZIP with Swift sources you can open in Xcode.
        """),
        Entry(keywords: ["update", "updates", "new version", "upgrade reyforge", "self update"], answer: """
        **Updating ReyForge**
        Settings → **Updates** checks the GitHub releases of your repository, downloads the new build, signs it with your certificate and installs it — no computer needed.
        """),
    ]

    public static func answer(_ question: String) -> String? {
        let q = " " + question.lowercased() + " "
        var best: (Entry, Int)?
        for e in entries {
            let score = e.keywords.reduce(0) { $0 + (q.contains($1) ? ($1.count > 5 ? 2 : 1) : 0) }
            if score > 0 && score > (best?.1 ?? 0) { best = (e, score) }
        }
        if q.contains("what can you do") || q.contains("help me") || q.trimmingCharacters(in: .whitespaces) == "help" { return capabilities }
        return best?.0.answer
    }

    public static let capabilities = """
    I can design and build your app with you:
    • **Create whole apps** — “Build a coffee shop app with ordering and rewards”
    • **Design screens** — dashboards, login, settings, profile, feed, store, cart, chat, todo, weather, quiz…
    • **Add elements** — “add a dark mode toggle and a volume slider”
    • **Edit** — select something and say “make this red and bigger”
    • **Wire logic** — “when I tap Continue go to Details”, counters, forms, API calls
    • **Restyle** — “use a dark theme with a purple accent”
    Everything I make stays draggable and editable.
    """

    public static func greeting(project: Project) -> String {
        let screens = project.screens.count
        return screens == 0
            ? "Hi! I'm ReyForge AI. Describe the app you want and I'll build the screens, components and logic for you."
            : "Hi! I'm ready to work on **\(project.brand.displayName)** (\(screens) screen\(screens == 1 ? "" : "s")). What would you like to build or change?"
    }

    public static func notUnderstood(_ message: String) -> String {
        "I couldn't turn “\(message.prefix(80))” into changes yet. Try naming a screen or element — for example “add a settings screen”, “add a chart of weekly sales”, or select something and say “make this bigger”."
    }

    public static func starterSuggestions(_ project: Project) -> [String] {
        if project.screens.isEmpty || project.screens.allSatisfy({ $0.root.children.isEmpty }) {
            return ["Build a fitness tracker app", "Create a login screen", "Make a finance dashboard"]
        }
        return ["Add a settings screen", "Add a dark mode toggle", "Change the theme to sunset"]
    }
}

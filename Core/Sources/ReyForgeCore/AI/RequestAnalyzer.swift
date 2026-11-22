import Foundation

public enum Archetype: String, CaseIterable, Hashable {
    case dashboard, login, signup, onboarding, settings, profile, feed, detail, list, cart, checkout, inbox, conversation
    case todo, notes, calendar, map, player, video, gallery, search, notifications, contact, about, store, product
    case weather, workout, recipe, booking, timer, quiz, news, leaderboard, pricing, faq

    public var keywords: [String] {
        switch self {
        case .dashboard: return ["dashboard", "overview", "home screen", "home page", "homepage", "summary", "analytics", "kpi", "kpis", "insights", "main screen", "stats screen", "statistics"]
        case .login: return ["login", "log in", "sign in", "signin", "authentication", "auth screen", "log-in", "sign-in"]
        case .signup: return ["sign up", "signup", "sign-up", "register", "registration", "create account", "create an account", "join screen"]
        case .onboarding: return ["onboarding", "walkthrough", "intro screen", "intro screens", "welcome screen", "welcome screens", "tutorial", "get started screen", "intro pages"]
        case .settings: return ["settings", "preferences", "configuration", "options screen", "account settings"]
        case .profile: return ["profile", "my account", "account page", "user page", "about me", "bio page"]
        case .feed: return ["feed", "timeline", "social feed", "news feed", "posts screen", "wall", "stories"]
        case .detail: return ["detail", "details", "detail page", "detail screen", "item page", "info page"]
        case .list: return ["list screen", "list page", "catalog", "browse", "history", "directory", "collection", "archive", "listing"]
        case .cart: return ["cart", "basket", "shopping bag", "bag screen"]
        case .checkout: return ["checkout", "check out", "payment screen", "pay screen", "billing"]
        case .inbox: return ["chat list", "inbox", "conversations", "chats", "dms", "messages screen", "messages list"]
        case .conversation: return ["chat screen", "conversation", "messaging", "chat room", "direct message", "chatbot", "chat bot", "message thread", "chat"]
        case .todo: return ["todo", "to-do", "to do", "task list", "tasks", "checklist", "reminders"]
        case .notes: return ["notes", "note taking", "notebook", "journal", "diary", "memo"]
        case .calendar: return ["calendar", "schedule", "agenda", "planner", "appointments"]
        case .map: return ["map screen", "map view", "nearby", "locations", "places", "directions", "store locator", "find us", "map page"]
        case .player: return ["music player", "now playing", "audio player", "player screen", "podcast player", "media player"]
        case .video: return ["video player", "watch screen", "movie screen", "video screen", "streaming screen"]
        case .gallery: return ["gallery", "photo grid", "photos screen", "portfolio", "album", "photo album"]
        case .search: return ["search screen", "search page", "explore", "discover"]
        case .notifications: return ["notifications", "notification center", "activity screen", "alerts screen"]
        case .contact: return ["contact", "contact us", "feedback", "support form", "help form", "get in touch", "contact form"]
        case .about: return ["about screen", "about page", "about us", "credits"]
        case .store: return ["store", "shop", "storefront", "marketplace", "product grid", "products", "online store", "shop home"]
        case .product: return ["product page", "product detail", "item detail", "product screen", "product details"]
        case .weather: return ["weather", "forecast"]
        case .workout: return ["workout", "exercise screen", "training screen", "fitness tracker", "activity tracker", "run tracker", "step tracker"]
        case .recipe: return ["recipe", "cooking screen", "ingredients"]
        case .booking: return ["booking", "reservation", "reserve", "book a table", "appointment booking", "schedule appointment", "book appointment"]
        case .timer: return ["timer", "stopwatch", "countdown", "pomodoro"]
        case .quiz: return ["quiz", "trivia", "flashcards", "flash cards"]
        case .news: return ["news", "articles", "headlines", "blog"]
        case .leaderboard: return ["leaderboard", "rankings", "high scores", "scoreboard"]
        case .pricing: return ["pricing", "paywall", "subscription", "plans screen", "upgrade screen", "premium screen"]
        case .faq: return ["faq", "help center", "frequently asked", "questions screen"]
        }
    }

    public var defaultName: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .login: return "Login"
        case .signup: return "Sign Up"
        case .onboarding: return "Welcome"
        case .settings: return "Settings"
        case .profile: return "Profile"
        case .feed: return "Feed"
        case .detail: return "Details"
        case .list: return "Browse"
        case .cart: return "Cart"
        case .checkout: return "Checkout"
        case .inbox: return "Messages"
        case .conversation: return "Chat"
        case .todo: return "Tasks"
        case .notes: return "Notes"
        case .calendar: return "Calendar"
        case .map: return "Map"
        case .player: return "Now Playing"
        case .video: return "Watch"
        case .gallery: return "Gallery"
        case .search: return "Search"
        case .notifications: return "Notifications"
        case .contact: return "Contact"
        case .about: return "About"
        case .store: return "Shop"
        case .product: return "Product"
        case .weather: return "Weather"
        case .workout: return "Workout"
        case .recipe: return "Recipe"
        case .booking: return "Book"
        case .timer: return "Timer"
        case .quiz: return "Quiz"
        case .news: return "News"
        case .leaderboard: return "Leaderboard"
        case .pricing: return "Upgrade"
        case .faq: return "Help"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .login, .signup: return "person.crop.circle"
        case .onboarding: return "sparkles"
        case .settings: return "gearshape.fill"
        case .profile: return "person.crop.circle.fill"
        case .feed: return "house.fill"
        case .detail: return "doc.text.fill"
        case .list: return "list.bullet"
        case .cart: return "cart.fill"
        case .checkout: return "creditcard.fill"
        case .inbox: return "message.fill"
        case .conversation: return "bubble.left.and.bubble.right.fill"
        case .todo: return "checklist"
        case .notes: return "note.text"
        case .calendar: return "calendar"
        case .map: return "map.fill"
        case .player: return "music.note"
        case .video: return "play.rectangle.fill"
        case .gallery: return "photo.on.rectangle"
        case .search: return "magnifyingglass"
        case .notifications: return "bell.fill"
        case .contact: return "envelope.fill"
        case .about: return "info.circle.fill"
        case .store: return "bag.fill"
        case .product: return "tag.fill"
        case .weather: return "cloud.sun.fill"
        case .workout: return "figure.run"
        case .recipe: return "frying.pan"
        case .booking: return "calendar.badge.plus"
        case .timer: return "timer"
        case .quiz: return "questionmark.circle.fill"
        case .news: return "newspaper.fill"
        case .leaderboard: return "trophy.fill"
        case .pricing: return "crown.fill"
        case .faq: return "questionmark.circle"
        }
    }
}

public struct ComponentRequest: Hashable {
    public var type: ComponentType
    public var keyword: String
    public var label: String?
    public var count: Int
    public var color: String?
    public var size: String?
    public var navigateTo: String?
    public var detail: String?
}

public struct Intent: Hashable {
    public enum Operation: String, Hashable { case createApp, createScreen, addElements, edit, delete, theme, logic, question, greeting, unknown }
    public var operation: Operation = .unknown
    public var archetypes: [Archetype] = []
    public var domain: Domain?
    public var topic: String?
    public var appName: String?
    public var screenName: String?
    public var components: [ComponentRequest] = []
    public var colors: [String] = []
    public var quoted: [String] = []
    public var targetsSelection = false
    public var targetType: ComponentType?
    public var targetLabel: String?
    public var targetScreen: String?
    public var edits: [String: String] = [:]
    public var editFlags: [String] = []
    public var logicActions: [String] = []
    public var themeAttributes: [String: String] = [:]
    public var asTab = false
    public var confidence: Double = 0
    public var raw = ""
}

public enum RequestAnalyzer {
    static let colorWords: [String] = ColorNames.table.keys.sorted { $0.count > $1.count }

    static let componentPhrases: [(String, ComponentType)] = [
        ("sign in with apple", .signInApple), ("apple sign in", .signInApple), ("date picker", .datePicker), ("datepicker", .datePicker),
        ("color picker", .colorPicker), ("colour picker", .colorPicker), ("photo picker", .photoPicker), ("image picker", .photoPicker),
        ("text field", .textField), ("textfield", .textField), ("input field", .textField), ("password field", .secureField),
        ("text editor", .textEditor), ("text area", .textEditor), ("textarea", .textEditor), ("search bar", .searchField), ("searchbar", .searchField),
        ("search field", .searchField), ("share button", .shareLink), ("share link", .shareLink), ("progress bar", .progress), ("loading spinner", .progress),
        ("spinner", .progress), ("progress", .progress), ("bar chart", .chart), ("line chart", .chart), ("pie chart", .chart), ("donut chart", .chart),
        ("area chart", .chart), ("chart", .chart), ("graph", .chart), ("stat card", .statCard), ("stat cards", .statCard), ("kpi", .statCard),
        ("kpis", .statCard), ("metric", .statCard), ("metrics", .statCard), ("stats", .statCard), ("web view", .web), ("webview", .web), ("website", .web),
        ("video player", .video), ("video", .video), ("audio player", .audio), ("music player", .audio), ("qr code", .qr), ("qr", .qr),
        ("empty state", .empty), ("navigation link", .navLink), ("nav link", .navLink), ("segmented control", .picker), ("segmented", .picker),
        ("dropdown", .picker), ("picker", .picker), ("toggle", .toggle), ("switch", .toggle), ("checkbox", .toggle), ("slider", .slider),
        ("stepper", .stepper), ("button", .button), ("buttons", .button), ("cta", .button), ("menu", .menu), ("map", .map), ("gauge", .gauge),
        ("ring", .gauge), ("rating", .rating), ("stars", .rating), ("timer", .timer), ("countdown", .timer), ("stopwatch", .timer),
        ("avatar", .avatar), ("profile picture", .avatar), ("badge", .badge), ("tag", .badge), ("chip", .badge), ("divider", .divider),
        ("separator", .divider), ("spacer", .spacer), ("gradient", .gradient), ("circle", .shape), ("rectangle", .shape), ("shape", .shape),
        ("hero image", .image), ("banner", .image), ("image", .image), ("photo", .image), ("picture", .image), ("icon", .icon), ("symbol", .icon),
        ("carousel", .scroll), ("page view", .pager), ("pager", .pager), ("slides", .pager), ("grid", .grid), ("card", .card), ("cards", .card),
        ("form", .form), ("section", .section), ("list", .list), ("row", .listRow), ("rows", .listRow), ("link", .link), ("title", .text),
        ("heading", .text), ("headline", .text), ("subtitle", .text), ("caption", .text), ("paragraph", .text), ("text", .text), ("label", .label),
        ("email field", .textField), ("name field", .textField), ("field", .textField), ("input", .textField), ("calendar", .datePicker),
    ]

    static let numberWords: [String: Int] = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "a couple of": 2, "a few": 3, "several": 3]

    // MARK: Entry point

    public static func analyze(_ raw: String, project: Project? = nil, context: EditorContext = EditorContext()) -> Intent {
        var intent = Intent()
        intent.raw = raw
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = " " + text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\n", with: " ") + " "
        intent.quoted = quotedStrings(in: text)
        intent.colors = colors(in: lower)
        intent.domain = ContentPacks.detect(lower)
        intent.topic = topic(in: text)
        if intent.domain == nil, let t = intent.topic { intent.domain = ContentPacks.detect(t) }
        intent.appName = appName(in: text)
        intent.asTab = has(lower, [" tab ", " tabs", "tab bar", "tabbar", "as a tab"])
        intent.archetypes = archetypes(in: lower)
        intent.targetScreen = project.flatMap { screenMention(in: lower, project: $0) }

        let selectionWords = [" this ", " it ", " that ", " selected", " selection", " it.", " this.", " it,", " that one", " these ", " them "]
        intent.targetsSelection = has(lower, selectionWords) && context.selectedNodeID != nil

        // Greetings and questions.
        let trimmed = lower.trimmingCharacters(in: .whitespaces)
        if ["hi", "hello", "hey", "yo", "hola", "thanks", "thank you", "thx", "ok", "okay", "cool", "nice", "great"].contains(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "!.?"))) {
            intent.operation = .greeting
            intent.confidence = 1
            return intent
        }
        let questionStarts = ["how ", "what ", "why ", "where ", "which ", "can i ", "could i ", "does ", "do i ", "is it ", "is there ", "are there ", "should ", "explain", "help", "tell me", "who "]
        let buildVerbs = ["create", "make", "build", "add", "design", "generate", "put", "insert", "change", "set", "turn", "delete", "remove"]
        let startsLikeQuestion = questionStarts.contains { trimmed.hasPrefix($0) }
        let hasBuildIntent = buildVerbs.contains { lower.contains(" \($0) ") } && (!intent.archetypes.isEmpty || !componentMentions(in: lower).isEmpty || intent.domain != nil)
        let politeRequest = ["can you ", "could you ", "would you ", "will you ", "please "].contains { trimmed.hasPrefix($0) }
        if (startsLikeQuestion || (trimmed.hasSuffix("?") && !politeRequest)) && !(hasBuildIntent && !startsLikeQuestion) && !politeRequest {
            intent.operation = .question
            intent.confidence = 0.8
            return intent
        }

        // Delete.
        let deleteVerbs = [" delete ", " remove ", " get rid of ", " erase ", " take out ", " drop the "]
        if has(lower, deleteVerbs) {
            intent.operation = .delete
            fillTarget(&intent, lower: lower, context: context)
            if intent.targetType == nil && intent.targetLabel == nil && context.selectedNodeID != nil { intent.targetsSelection = true }
            if has(lower, [" screen", " page"]) && intent.targetScreen != nil { intent.edits["screen"] = intent.targetScreen }
            intent.confidence = 0.9
            return intent
        }

        // Logic ("when I tap X go to Y", "make the button open settings").
        if let logic = logic(in: lower, text: text, project: project, context: context) {
            intent.operation = .logic
            intent.logicActions = logic.actions
            intent.targetType = logic.type
            intent.targetLabel = logic.label
            intent.targetsSelection = logic.selection
            intent.confidence = 0.85
            return intent
        }

        // Theme / branding.
        let themeMarkers = [" rename the app", " rename my app", " call my app", " app's name", " theme", " dark mode", "light mode", " color scheme", " colour scheme", " palette", " accent", " brand", " branding", " font", " typography",
                            " app icon", " rename the app", " call the app", " app name", " look and feel", " styling of the app", " whole app", " entire app", " app look", " splash"]
        let elementWords = componentMentions(in: lower)
        let screenRequest = !intent.archetypes.isEmpty && has(lower, [" screen", " page", " tab "])
        let darkModeIsControl = has(lower, [" toggle", " switch"]) && lower.contains("dark mode")
        let appLook = has(lower, [" look", " style", " vibe", " aesthetic", " feel", " colors", " colours"]) && has(lower, [" the app", " app ", " everything", " whole", " entire", " my app"]) && intent.archetypes.isEmpty
        if (has(lower, themeMarkers) || appLook) && !screenRequest && !darkModeIsControl && !(intent.targetsSelection && !has(lower, [" theme", " app icon", " app name"])) {
            intent.operation = .theme
            intent.themeAttributes = themeAttributes(lower: lower, text: text, colors: intent.colors, quoted: intent.quoted)
            intent.confidence = 0.85
            if !intent.themeAttributes.isEmpty || has(lower, [" dark", " light"]) { return intent }
            intent.operation = .unknown
        }

        // Edit the selection or a named element.
        let editVerbs = [" make ", " change ", " set ", " turn ", " update ", " rename ", " resize ", " recolor", " color ", " colour ", " paint ", " center ", " align ",
                         " increase ", " decrease ", " enlarge ", " shrink ", " bold", " round ", " restyle ", " replace ", " edit ", " modify ", " adjust ", " tweak ", " move "]
        let editAdjectives = [" bigger", " smaller", " larger", " wider", " taller", " bold", " italic", " rounded", " centered", " red", " blue", " green", " full width", " transparent", " shadow"]
        if has(lower, editVerbs) || (intent.targetsSelection && (has(lower, editAdjectives) || !intent.colors.isEmpty)) {
            var probe = intent
            fillTarget(&probe, lower: lower, context: context)
            let hasTarget = probe.targetsSelection || probe.targetType != nil || probe.targetLabel != nil
            let creating = intent.archetypes.isEmpty == false && has(lower, [" screen", " page", " app"])
            if hasTarget && !creating {
                intent = probe
                intent.operation = .edit
                (intent.edits, intent.editFlags) = edits(lower: lower, text: text, colors: intent.colors, quoted: intent.quoted)
                intent.confidence = intent.edits.isEmpty && intent.editFlags.isEmpty ? 0.4 : 0.85
                return intent
            }
        }

        // Creation.
        let mentionsApp = has(lower, [" app ", " app.", " app,", " app?", " app!", " application", " apps "])
        let mentionsScreen = has(lower, [" screen", " page", " view", " tab "])
        intent.components = componentRequests(in: lower, text: text, quoted: intent.quoted)
        let addVerb = hasAddVerb(lower)
        if lower.contains(" counter") && (addVerb || intent.components.isEmpty) && intent.archetypes.isEmpty {
            intent.operation = .addElements
            intent.confidence = 0.8
            return intent
        }
        // "weather app" names the app's topic; "dashboard for a finance app" asks for a screen.
        let archetypeIsTopic = intent.archetypes.contains { a in a.keywords.contains { lower.contains(" \($0) app") || lower.contains(" \($0) application") } }
        let archetypeIsScreen = !intent.archetypes.isEmpty && !archetypeIsTopic
        if mentionsApp && !mentionsScreen && !addVerb && (!archetypeIsScreen || intent.archetypes.count >= 2 && has(lower, [" with ", " including "])) {
            intent.operation = .createApp
            if archetypeIsTopic && intent.domain == nil, let a = intent.archetypes.first { intent.domain = ContentPacks.detect(a.keywords[0]) }
            intent.confidence = intent.domain != nil || intent.topic != nil ? 0.9 : 0.6
            return intent
        }
        // Generic containers ("a todo list where I can add tasks") don't make it an element request.
        let onlyGenericParts = intent.components.allSatisfy { [.list, .listRow, .form, .section, .card, .grid, .vstack, .hstack, .text].contains($0.type) }
        if !intent.archetypes.isEmpty && (mentionsScreen || !addVerb || intent.components.isEmpty || onlyGenericParts || mentionsApp) {
            // "add a settings screen" / "create a login page" / "dashboard for a finance app"
            intent.operation = .createScreen
            intent.screenName = screenName(in: text) ?? intent.archetypes.first?.defaultName
            intent.confidence = 0.9
            return intent
        }
        if !intent.components.isEmpty {
            intent.operation = .addElements
            intent.confidence = 0.8
            return intent
        }
        if intent.domain != nil || intent.topic != nil {
            intent.operation = mentionsScreen ? .createScreen : .createApp
            if intent.operation == .createScreen { intent.archetypes = [.dashboard]; intent.screenName = screenName(in: text) }
            intent.confidence = 0.6
            return intent
        }
        if !elementWords.isEmpty {
            intent.operation = .addElements
            intent.components = elementWords.map { ComponentRequest(type: $0.1, keyword: $0.0, label: nil, count: 1, color: nil, size: nil, navigateTo: nil, detail: nil) }
            intent.confidence = 0.5
            return intent
        }
        intent.operation = .unknown
        intent.confidence = 0.1
        return intent
    }

    // MARK: Helpers

    static func has(_ s: String, _ needles: [String]) -> Bool { needles.contains { s.contains($0) } }

    /// "add"/"insert"/… used as a verb (not "an add button").
    static func hasAddVerb(_ lower: String) -> Bool {
        let pattern = #"(^|[.,;!?]\s*|\b(?:and|then|also|please|pls|now|just|to|you|me|i|lets|let's|can|could|would|should)\s+)(add|insert|put|include|place|append)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let t = lower.trimmingCharacters(in: .whitespaces)
        return re.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil
    }

    public static func quotedStrings(in s: String) -> [String] {
        var out: [String] = []
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("‘", "’"), ("'", "'")]
        for (open, close) in pairs {
            var cur: String?
            var prev: Character = " "
            for ch in s {
                if var c = cur {
                    if ch == close && (close != "'" || true) { if !c.isEmpty { out.append(c) }; cur = nil } else { c.append(ch); cur = c }
                } else if ch == open && (open != "'" || !prev.isLetter) {
                    cur = ""
                }
                prev = ch
            }
        }
        // Drop apostrophe artifacts like "don't" fragments.
        return out.filter { $0.count >= 1 && $0.count <= 80 && !($0.contains(" ") && $0.split(separator: " ").count > 12) }
    }

    static func colors(in lower: String) -> [String] {
        var found: [(Int, String)] = []
        for w in colorWords {
            if let r = lower.range(of: " \(w) ") ?? lower.range(of: " \(w),") ?? lower.range(of: " \(w).") ?? lower.range(of: " \(w)ish") {
                if w == "clear" || w == "transparent" || w == "tan" { continue }
                let pos = lower.distance(from: lower.startIndex, to: r.lowerBound)
                if !found.contains(where: { $0.1.contains(w) || w.contains($0.1) }) { found.append((pos, w)) }
            }
        }
        // Hex codes.
        let tokens = lower.split(whereSeparator: { $0 == " " || $0 == "," })
        for t in tokens where t.hasPrefix("#") {
            let h = String(t.prefix(9)).trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
            if ColorNames.isHex(h) { found.append((lower.distance(from: lower.startIndex, to: lower.range(of: h)!.lowerBound), ColorNames.normalizedHex(h))) }
        }
        return found.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    static func archetypes(in lower: String) -> [Archetype] {
        var found: [(Int, Archetype)] = []
        for a in Archetype.allCases {
            for k in a.keywords {
                let padded = " \(k)"
                guard let r = lower.range(of: padded) else { continue }
                let after = r.upperBound < lower.endIndex ? lower[r.upperBound] : " "
                if after.isLetter && !"s".contains(after) { continue }
                let pos = lower.distance(from: lower.startIndex, to: r.lowerBound)
                if !found.contains(where: { $0.1 == a }) { found.append((pos, a)) }
                break
            }
        }
        // Disambiguate overlapping matches.
        var result = found.sorted { $0.0 < $1.0 }.map { $0.1 }
        let viaHome = ["home page", "home screen", "homepage", "main screen"].contains { lower.contains($0) } && !lower.contains("dashboard")
        if viaHome && result.count > 1 { result.removeAll { $0 == .dashboard } }
        if result.contains(.conversation) && result.contains(.inbox) { result.removeAll { $0 == .conversation } }
        if result.contains(.product) && result.contains(.store) && !lower.contains("product page") && !lower.contains("product detail") { result.removeAll { $0 == .product } }
        if result.contains(.dashboard) && result.contains(.workout) && !lower.contains("workout screen") { result.removeAll { $0 == .workout } }
        if result.contains(.calendar) && result.contains(.booking) { result.removeAll { $0 == .calendar } }
        if result.contains(.todo) && result.contains(.notes) && lower.contains("note") == false { result.removeAll { $0 == .notes } }
        return result
    }

    static func componentMentions(in lower: String) -> [(String, ComponentType)] {
        var found: [(Int, String, ComponentType)] = []
        var consumed: [Range<String.Index>] = []
        for (phrase, type) in componentPhrases {
            var search = lower.startIndex..<lower.endIndex
            while let r = lower.range(of: " \(phrase)", range: search) {
                search = r.upperBound..<lower.endIndex
                let after = r.upperBound < lower.endIndex ? lower[r.upperBound] : " "
                if after.isLetter && after != "s" { continue }
                if consumed.contains(where: { $0.overlaps(r) }) { continue }
                consumed.append(r)
                found.append((lower.distance(from: lower.startIndex, to: r.lowerBound), phrase, type))
            }
        }
        return found.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
    }

    static let labelMarkers = [" for ", " called ", " named ", " labeled ", " labelled ", " that says ", " saying ", " with the text ", " titled ", " reading ", " that reads ", " showing ", " of ", " with label ", " to show "]
    static let stopWords: Set<String> = ["and", "with", "that", "which", "to", "on", "in", "at", "below", "above", "under", "under", "then", "so", "when", "where", "button", "screen", "page", "the", "please", "too", "also"]

    static func componentRequests(in lower: String, text: String, quoted: [String]) -> [ComponentRequest] {
        var out: [ComponentRequest] = []
        var quotes = quoted
        for (phrase, type) in componentMentions(in: lower) {
            guard let r = lower.range(of: " \(phrase)") else { continue }
            var req = ComponentRequest(type: type, keyword: phrase, label: nil, count: 1, color: nil, size: nil, navigateTo: nil, detail: nil)
            // Preceding words: count, color, size.
            let before = lower[lower.startIndex..<r.lowerBound].split(separator: " ").suffix(4).map(String.init)
            for w in before {
                if let n = Int(w), n > 0, n <= 12 { req.count = n }
                if let n = numberWords[w] { req.count = n }
                if ColorNames.table[w] != nil { req.color = w }
                if ["big", "large", "huge", "small", "tiny", "wide"].contains(w) { req.size = w }
            }
            // Following words: label.
            let afterText = String(lower[r.upperBound...])
            for marker in labelMarkers where afterText.hasPrefix(marker) || afterText.hasPrefix(marker.dropFirst()) {
                let rest = afterText.hasPrefix(marker) ? afterText.dropFirst(marker.count) : afterText.dropFirst(marker.count - 1)
                if let q = quotes.first, rest.trimmingCharacters(in: .whitespaces).hasPrefix("\"") || rest.trimmingCharacters(in: .whitespaces).hasPrefix("“") || rest.trimmingCharacters(in: .whitespaces).hasPrefix("'") {
                    req.label = q
                    quotes.removeFirst()
                } else {
                    var words: [String] = []
                    for w in rest.split(separator: " ") {
                        let clean = w.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?;:"))
                        if stopWords.contains(clean) && !words.isEmpty { break }
                        if clean == "a" || clean == "an" || clean == "the" || clean == "my" { if words.isEmpty { continue } }
                        words.append(clean)
                        if w.hasSuffix(",") || w.hasSuffix(".") || words.count >= 4 { break }
                    }
                    if !words.isEmpty {
                        let l = originalCase(words.joined(separator: " "), in: text)
                        req.label = l.prefix(1).uppercased() + l.dropFirst()
                    }
                }
                break
            }
            if req.label == nil, let q = quotes.first, afterText.trimmingCharacters(in: .whitespaces).hasPrefix("\"") || afterText.trimmingCharacters(in: .whitespaces).hasPrefix("“") {
                req.label = q; quotes.removeFirst()
            }
            // Chart kind words.
            if type == .chart {
                for k in ["bar", "line", "pie", "donut", "area"] where phrase.hasPrefix(k) || lower.contains(" \(k) chart") || lower.contains(" \(k) graph") { req.detail = k }
            }
            if type == .text {
                req.detail = phrase
            }
            // Navigation intent: "button that goes to settings".
            for m in [" goes to ", " go to ", " opens ", " open ", " navigates to ", " links to ", " takes me to ", " leads to "] {
                if let mr = afterText.range(of: m) {
                    let dest = afterText[mr.upperBound...].split(separator: " ").prefix(3).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",.!?")) }
                        .filter { !["the", "a", "screen", "page", "my"].contains($0) }
                    if let first = dest.first, !first.isEmpty {
                        req.navigateTo = originalCase(dest.prefix(2).joined(separator: " "), in: text)
                    }
                    break
                }
            }
            if !out.contains(where: { $0.type == req.type && $0.label == req.label && $0.keyword == req.keyword }) { out.append(req) }
        }
        // "rows"/"buttons" inside a mentioned list are handled by the list itself.
        if out.contains(where: { $0.type == .list }) { out.removeAll { $0.type == .listRow } }
        return out
    }

    /// Restores the user's capitalization for an extracted lowercase phrase.
    static func originalCase(_ phrase: String, in text: String) -> String {
        if let r = text.range(of: phrase, options: .caseInsensitive) { return String(text[r]) }
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    static func topic(in text: String) -> String? {
        let lower = text.lowercased()
        let patterns = [
            #"(?:for|about) (?:a|an|my|our|the)?\s*([a-z][a-z0-9 &'\-]{2,40}?) (?:app|application|website|company|business|startup|brand|shop|store)\b"#,
            #"\b(?:a|an) ([a-z][a-z0-9 &'\-]{2,40}?) (?:app|application)\b"#,
            #"\b(?:app|application) (?:for|about) (?:a|an|my|our|the)?\s*([a-z][a-z0-9 &'\-]{2,40}?)(?:[.,!?]| with | that |$)"#,
            #"\bfor (?:my|our) ([a-z][a-z0-9 &'\-]{2,30}?)(?:[.,!?]| with | that |$)"#,
            #"^\s*(?:create|make|build|design)?\s*(?:a|an)?\s*([a-z][a-z ]{2,30}?) (?:app|application)\b"#,
        ]
        let filler: Set<String> = ["simple", "new", "basic", "cool", "nice", "native", "ios", "iphone", "mobile", "great", "beautiful", "modern", "full", "complete", "little", "small", "the", "my", "our", "an", "a", "me"]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let ns = lower as NSString
            if let m = re.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
                var t = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                var words = t.split(separator: " ").map(String.init)
                while let f = words.first, filler.contains(f) { words.removeFirst() }
                // Drop leading screen words ("dashboard for a ...").
                words.removeAll { ["screen", "page", "dashboard", "login", "settings", "with"].contains($0) }
                t = words.joined(separator: " ")
                if t.count >= 3 { return t }
            }
        }
        return nil
    }

    static func appName(in text: String) -> String? {
        let patterns = [#"(?:called|named) [\"“']?([A-Za-z0-9][A-Za-z0-9 &'\-]{1,30}?)[\"”']?(?:[.,!?]| with | that | for |$)"#, #"app name (?:to |is |as )?[\"“']?([A-Za-z0-9][A-Za-z0-9 &'\-]{1,30}?)[\"”']?(?:[.,!?]|$)"#]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p) else { continue }
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty && name.lowercased() != "app" { return name }
            }
        }
        return nil
    }

    /// "rename the app to Brew", "call my app Brew", "change the app name to Brew".
    static func renamedApp(in text: String) -> String? {
        let p = #"(?:rename (?:the |my |this )?app (?:to |as )?|call (?:the |my |this )?app |app(?:'s)? name (?:to |is |as )?|name (?:the |my |this )?app )[\"“']?([A-Za-z0-9][A-Za-z0-9 &'\-]{0,30}?)[\"”']?(?:[.,!?]|$)"#
        guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    static func screenName(in text: String) -> String? {
        let patterns = [#"(?:screen|page|tab) (?:called|named|titled) [\"“']?([A-Za-z0-9][A-Za-z0-9 &'\-]{1,30}?)[\"”']?(?:[.,!?]| with | that |$)"#,
                        #"[\"“]([A-Za-z0-9][A-Za-z0-9 &'\-]{1,30})[\"”] (?:screen|page|tab)"#]
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) else { continue }
            let ns = text as NSString
            if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    static func screenMention(in lower: String, project: Project) -> String? {
        for s in project.screens.sorted(by: { $0.name.count > $1.name.count }) {
            let n = s.name.lowercased()
            if lower.contains(" \(n) screen") || lower.contains(" \(n) page") || lower.contains(" the \(n) ") || lower.contains(" \(n) tab") || lower.contains(" to \(n)") || lower.contains(" on \(n)") {
                return s.name
            }
        }
        return nil
    }

    static func fillTarget(_ intent: inout Intent, lower: String, context: EditorContext) {
        if has(lower, [" this ", " it ", " it.", " this.", " selected", " selection", " that ", " it,", " them "]) && context.selectedNodeID != nil {
            intent.targetsSelection = true
        }
        // "the continue button", "the title", "the 'Save' button"
        let mentions = componentMentions(in: lower)
        if let m = mentions.first {
            intent.targetType = m.1
            if m.1 == .text && ["title", "heading", "headline"].contains(m.0) { intent.edits["_textStyle"] = "title" }
        }
        if let q = intent.quoted.first {
            intent.targetLabel = q
        } else if let m = mentions.first, let r = lower.range(of: " \(m.0)") {
            // "the continue button" → label before the noun.
            let before = lower[lower.startIndex..<r.lowerBound].split(separator: " ").suffix(2).map(String.init)
            let candidates = before.filter { !["the", "a", "an", "this", "that", "my", "make", "change", "set", "turn", "delete", "remove", "all"].contains($0) && ColorNames.table[$0] == nil }
            if let last = candidates.last, last.count > 2, !["big", "small", "large", "first", "last", "top", "bottom", "primary", "main"].contains(last) {
                intent.targetLabel = last
            }
        }
        if intent.targetsSelection && intent.targetLabel == nil && intent.targetType != nil {
            // "make this button red": the selection is the target.
            intent.targetType = nil
        }
    }

    static func edits(lower: String, text: String, colors: [String], quoted: [String]) -> ([String: String], [String]) {
        var e: [String: String] = [:]
        var flags: [String] = []
        // Text changes.
        let textMarkers = [" text to ", " title to ", " label to ", " rename it to ", " rename to ", " to say ", " say ", " read ", " to read ", " text say ", " change it to ", " wording to "]
        for m in textMarkers {
            if let r = lower.range(of: m) {
                if let q = quoted.last { e["text"] = q } else {
                    let rest = lower[r.upperBound...].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
                    if !rest.isEmpty && rest.count < 60 { e["text"] = originalCase(rest, in: text) }
                }
                break
            }
        }
        if e["text"] == nil, let q = quoted.last, has(lower, [" rename", " retitle", " change the text", " change the title", " change the label"]) { e["text"] = q }
        // Colors: "red background" / "background to blue" → bg; otherwise foreground/tint.
        if let c = colors.first {
            if has(lower, [" background", " bg ", " fill "]) {
                if let bgColor = colorNear(lower, after: ["background", "bg"], colors: colors) { e["bg"] = bgColor } else { e["bg"] = c }
                if colors.count > 1, let other = colors.first(where: { $0 != e["bg"] }) { e["color"] = other }
            } else {
                e["color"] = c
            }
        }
        let sizeMap: [(String, String)] = [(" bigger", "bigger"), (" larger", "bigger"), (" huge", "huge"), (" big", "large"), (" large", "large"), (" smaller", "smaller"), (" tiny", "tiny"), (" small", "small")]
        for (k, v) in sizeMap where lower.contains(k) { e["size"] = v; break }
        if lower.contains(" bold") { flags.append("bold") }
        if lower.contains(" italic") { flags.append("italic") }
        if has(lower, [" center", " centre", " centered"]) { flags.append("center") }
        if has(lower, [" full width", " full-width", " stretch", " wider"]) { flags.append("full") }
        if has(lower, [" rounded", " round the corners", " round corners", " more round"]) { e["radius"] = "20" }
        if has(lower, [" square corners", " sharp corners", " not rounded"]) { e["radius"] = "0" }
        if has(lower, [" shadow"]) { e["shadow"] = lower.contains(" no shadow") || lower.contains("remove the shadow") ? "none" : "medium" }
        if has(lower, [" transparent", " faded", " see-through"]) { e["opacity"] = "0.6" }
        if has(lower, [" destructive", " dangerous"]) { flags.append("destructive") }
        if has(lower, [" outlined", " outline", " bordered"]) { e["style"] = "bordered" }
        if has(lower, [" glass", " liquid glass"]) { e["style"] = "glass" }
        if has(lower, [" prominent", " filled", " solid"]) { e["style"] = "prominent" }
        if has(lower, [" capsule", " pill"]) { e["style"] = "capsule" }
        if has(lower, [" plain", " text only"]) { e["style"] = "plain" }
        for style in ["largeTitle", "title", "headline", "caption", "footnote"] where lower.contains(" a \(style.lowercased())") || lower.contains(" into a \(style.lowercased())") {
            e["style"] = style
        }
        if let iconRange = lower.range(of: " icon to ") ?? lower.range(of: " icon ") ?? lower.range(of: " symbol to ") {
            let rest = lower[iconRange.upperBound...].split(separator: " ").first.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?")) }
            if let r = rest, !r.isEmpty, !["to", "a", "an", "the"].contains(r) { e["icon"] = SymbolResolver.resolve(r, fallback: SymbolResolver.symbol(forConcept: r, fallback: "star.fill")) }
        }
        if let heightRange = lower.range(of: " taller") { _ = heightRange; e["size"] = "bigger" }
        return (e, flags)
    }

    static func colorNear(_ lower: String, after keys: [String], colors: [String]) -> String? {
        for k in keys {
            guard let r = lower.range(of: k) else { continue }
            let window = String(lower[r.upperBound...].prefix(24))
            if let c = colors.first(where: { window.contains($0) }) { return c }
            let beforeWindow = String(lower[..<r.lowerBound].suffix(16))
            if let c = colors.first(where: { beforeWindow.contains($0) }) { return c }
        }
        return nil
    }

    static func themeAttributes(lower: String, text: String, colors: [String], quoted: [String]) -> [String: String] {
        var t: [String: String] = [:]
        if has(lower, [" dark mode", " dark theme", " dark ", " darker", "night mode"]) { t["theme"] = "dark" }
        if has(lower, [" light mode", " light theme", " light ", " lighter"]) && t["theme"] == nil { t["theme"] = "light" }
        if has(lower, [" system appearance", " automatic appearance", " follow the system"]) { t["theme"] = "system" }
        if let c = colorNear(lower, after: ["accent", "primary", "brand", "main color", "tint"], colors: colors) ?? colors.first { t["accent"] = c }
        if colors.count > 1 { t["secondary"] = colors[1] }
        if has(lower, [" rounded font", " round font", " friendly font", " rounded"]) { t["font"] = "rounded" }
        if has(lower, [" serif"]) { t["font"] = "serif" }
        if has(lower, [" monospace", " mono font", " monospaced", " code font"]) { t["font"] = "monospaced" }
        let styles: [(String, String)] = [(" luxury", "luxury"), (" elegant", "luxury"), (" premium", "luxury"), (" playful", "candy"), (" fun", "candy"), (" cute", "candy"),
                                          (" minimal", "mono"), (" monochrome", "mono"), (" black and white", "mono"), (" nature", "forest"), (" eco", "forest"), (" earthy", "forest"),
                                          (" ocean", "ocean"), (" calm", "ocean"), (" neon", "neon"), (" cyber", "neon"), (" hacker", "neon"), (" warm", "coffee"), (" cozy", "coffee"),
                                          (" fresh", "mint"), (" professional", "royal"), (" corporate", "royal"), (" sunset", "sunset"), (" vibrant", "sunset"), (" midnight", "midnight")]
        if t["accent"] == nil { for (k, v) in styles where lower.contains(k) { t["preset"] = v; break } }
        for p in ThemePresets.all where lower.contains(" \(p.name.lowercased()) theme") || lower.contains(" \(p.id) theme") { t["preset"] = p.id; t.removeValue(forKey: "accent") }
        if let name = appName(in: text) ?? renamedApp(in: text) ?? (has(lower, [" rename the app", " app name"]) ? quoted.first : nil) { t["name"] = name }
        if let r = lower.range(of: " app icon ") ?? lower.range(of: " icon to ") {
            let words = lower[r.upperBound...].split(separator: " ").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?")) }.filter { !["to", "a", "an", "the", "be", "with", "use", "of"].contains($0) }
            if let w = words.first { t["icon"] = SymbolResolver.resolve(w, fallback: SymbolResolver.symbol(forConcept: w, fallback: "sparkles")) }
        }
        if has(lower, [" no splash", " remove the splash", " disable the splash"]) { t["splash"] = "none" }
        return t
    }

    struct LogicMatch { var actions: [String]; var type: ComponentType?; var label: String?; var selection: Bool }

    /// Understands "when I tap Continue go to Details", "make the save button show an alert", "add a counter".
    static func logic(in lower: String, text: String, project: Project?, context: EditorContext) -> LogicMatch? {
        let triggers = [" when i tap ", " when i click ", " when i press ", " when tapped", " when you tap ", " when the user taps ", " on tap", " tapping ", " clicking ",
                        " when someone taps ", " once tapped", " after tapping ", " make the ", " make this ", " make it ", " link the ", " link this ", " connect the ", " wire the ", " should "]
        let actionPhrases = [" go to ", " navigate to ", " open ", " show an alert", " show alert", " show a message", " show a toast", " increment", " increase ", " decrease ",
                             " count ", " toggle ", " go back", " navigate back", " share ", " copy ", " vibrate", " haptic", " call ", " email ", " present ", " take me to ", " take the user to ",
                             " show the ", " leads to ", " goes to ", " opens ", " pop up", " popup", " add it to ", " save it", " reset "]
        guard has(lower, triggers) && has(lower, actionPhrases) else { return nil }
        // Element-creation requests ("add a button that goes to settings") are handled as additions.
        if has(lower, [" add ", " create ", " insert "]) && !has(lower, [" when ", " tapping ", " clicking "]) { return nil }
        var actions: [String] = []
        func dest(after marker: String) -> String? {
            guard let r = lower.range(of: marker) else { return nil }
            let words = lower[r.upperBound...].split(separator: " ").map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",.!?")) }
            var picked: [String] = []
            for w in words {
                if ["the", "a", "an", "my", "to"].contains(w) && picked.isEmpty { continue }
                if ["screen", "page", "tab", "view", "and", "then", "when", "with", "after"].contains(w) { break }
                picked.append(w)
                if picked.count >= 3 { break }
            }
            guard !picked.isEmpty else { return nil }
            let phrase = picked.joined(separator: " ")
            if let p = project, let s = p.screen(named: phrase) ?? p.screen(named: picked[0]) { return s.name }
            return originalCase(phrase, in: text).split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        }
        let urlish = text.split(separator: " ").first { $0.contains("://") || $0.hasPrefix("www.") }.map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ",.!?")) }
        if let u = urlish, has(lower, [" open ", " opens ", " go to ", " goes to "]) { actions.append("open \"\(u.hasPrefix("http") ? u : "https://" + u)\"") }
        else if let d = dest(after: " go to ") ?? dest(after: " navigate to ") ?? dest(after: " take me to ") ?? dest(after: " take the user to ") ?? dest(after: " goes to ") ?? dest(after: " leads to ") ?? dest(after: " opens ") ?? dest(after: " open ") ?? dest(after: " present ") ?? dest(after: " show the ") {
            let style = has(lower, [" as a sheet", " in a sheet", " modally", " as a modal", " present "]) ? "sheet" : (has(lower, [" full screen", " fullscreen"]) ? "cover" : "go")
            actions.append("\(style) \"\(d)\"")
        }
        if has(lower, [" go back", " navigate back", " dismiss", " close the screen"]) { actions.append("back") }
        let quoted = quotedStrings(in: text)
        if has(lower, [" show an alert", " show alert", " pop up", " popup", " alert "]) {
            let msg = quoted.first ?? (lower.range(of: " saying ").map { originalCase(String(lower[$0.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " .!?")), in: text) } ?? "Done!")
            actions.append("alert \"\(msg)\"")
        } else if has(lower, [" show a message", " show a toast", " toast"]) {
            actions.append("toast \"\(quoted.first ?? "Done!")\"")
        }
        if has(lower, [" increment", " increase ", " count ", " add one", " +1", " counter"]) {
            let name = lower.range(of: " increment ").flatMap { lower[$0.upperBound...].split(separator: " ").first.map { Variable.sanitize(String($0)) } } ?? "count"
            actions.append("inc \(["the", "a", "it"].contains(name) ? "count" : name)")
        }
        if has(lower, [" decrease ", " decrement"]) { actions.append("dec count") }
        if let r = lower.range(of: " toggle ") {
            let name = lower[r.upperBound...].split(separator: " ").map(String.init).first { !["the", "a"].contains($0) } ?? "isOn"
            actions.append("toggle \(Variable.sanitize(name))")
        }
        if has(lower, [" vibrate", " haptic"]) { actions.append("haptic success") }
        if has(lower, [" share "]) { actions.append("share \"\(quoted.first ?? "Check out this app!")\"") }
        if has(lower, [" copy "]) { actions.append("copy \"\(quoted.first ?? "")\"") }
        if has(lower, [" reset "]) { actions.append("reset") }
        guard !actions.isEmpty else { return nil }
        // Which element triggers it?
        var probe = Intent()
        probe.quoted = quoted
        // Only the part before the action describes the trigger ("when I tap Continue | go to Details").
        var triggerPart = lower
        for marker in [" go to ", " navigate to ", " show ", " open ", " should ", " take me to "] {
            if let r = triggerPart.range(of: marker) { triggerPart = String(triggerPart[..<r.lowerBound]) + " " }
        }
        fillTarget(&probe, lower: triggerPart, context: context)
        if probe.targetType == nil && probe.targetLabel == nil && context.selectedNodeID != nil { probe.targetsSelection = true }
        // A quoted message is not the trigger label.
        if let label = probe.targetLabel, actions.contains(where: { $0.contains("\"\(label)\"") && !$0.hasPrefix("go") && !$0.hasPrefix("sheet") }) {
            probe.targetLabel = nil
            if context.selectedNodeID != nil { probe.targetsSelection = true }
        }
        return LogicMatch(actions: actions, type: probe.targetType, label: probe.targetLabel, selection: probe.targetsSelection)
    }
}

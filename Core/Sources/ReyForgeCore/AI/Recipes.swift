import Foundation

/// Writes ReyForge Script line by line.
public struct RFSWriter {
    public private(set) var lines: [String] = []
    public init() {}
    public mutating func add(_ indent: Int, _ s: String) { lines.append(String(repeating: "  ", count: indent) + s) }
    public mutating func blank() {}
    public var text: String { lines.joined(separator: "\n") }
}

/// Quotes a value for ReyForge Script (inner double quotes become single quotes).
public func rq(_ s: String) -> String {
    "\"" + s.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ") + "\""
}

public struct RecipeOptions {
    public var screenName: String
    public var tab: Bool
    public var appName: String
    /// Where success flows go (e.g. Login → Home).
    public var homeScreen: String
    /// Explicitly requested elements.
    public var requested: [ComponentRequest]
    public init(screenName: String, tab: Bool = false, appName: String = "My App", homeScreen: String = "Home", requested: [ComponentRequest] = []) {
        self.screenName = screenName; self.tab = tab; self.appName = appName; self.homeScreen = homeScreen; self.requested = requested
    }
    func wants(_ t: ComponentType) -> Bool { requested.contains { $0.type == t } }
}

public enum Recipes {
    // MARK: Apps

    public static func blueprint(for domain: Domain) -> [(Archetype, String)] {
        switch domain {
        case .finance: return [(.dashboard, "Home"), (.list, "Activity"), (.settings, "Settings")]
        case .fitness: return [(.dashboard, "Today"), (.workout, "Workout"), (.list, "History"), (.profile, "Profile")]
        case .food: return [(.store, "Menu"), (.cart, "Cart"), (.booking, "Reserve"), (.profile, "Account")]
        case .coffee: return [(.dashboard, "Home"), (.store, "Order"), (.cart, "Cart"), (.profile, "Account")]
        case .travel: return [(.store, "Explore"), (.list, "Trips"), (.map, "Map"), (.profile, "Profile")]
        case .shopping: return [(.store, "Shop"), (.search, "Search"), (.cart, "Cart"), (.profile, "Account")]
        case .social: return [(.feed, "Home"), (.search, "Explore"), (.inbox, "Messages"), (.profile, "Profile")]
        case .music: return [(.list, "Library"), (.player, "Now Playing"), (.search, "Search"), (.settings, "Settings")]
        case .education: return [(.dashboard, "Learn"), (.list, "Courses"), (.quiz, "Quiz"), (.profile, "Profile")]
        case .health: return [(.dashboard, "Today"), (.todo, "Plan"), (.timer, "Breathe"), (.settings, "Settings")]
        case .productivity: return [(.todo, "Tasks"), (.notes, "Notes"), (.calendar, "Calendar"), (.settings, "Settings")]
        case .realEstate: return [(.store, "Explore"), (.map, "Map"), (.list, "Saved"), (.profile, "Profile")]
        case .crypto: return [(.dashboard, "Portfolio"), (.list, "Markets"), (.news, "News"), (.settings, "Settings")]
        case .news: return [(.news, "Today"), (.search, "Search"), (.list, "Saved"), (.settings, "Settings")]
        case .gaming: return [(.dashboard, "Play"), (.quiz, "Challenge"), (.leaderboard, "Ranks"), (.profile, "Profile")]
        case .pets: return [(.dashboard, "Today"), (.todo, "Care"), (.calendar, "Vet"), (.profile, "Pets")]
        case .weather: return [(.weather, "Weather"), (.list, "Forecast"), (.map, "Radar"), (.settings, "Settings")]
        case .events: return [(.feed, "Discover"), (.list, "Tickets"), (.calendar, "Calendar"), (.profile, "Profile")]
        case .beauty: return [(.list, "Services"), (.booking, "Book"), (.gallery, "Looks"), (.profile, "Profile")]
        case .automotive: return [(.dashboard, "Car"), (.map, "Charge"), (.list, "Trips"), (.settings, "Settings")]
        case .generic: return [(.dashboard, "Home"), (.list, "Browse"), (.profile, "Profile"), (.settings, "Settings")]
        }
    }

    /// A complete multi-screen app as ReyForge Script.
    public static func app(pack: ContentPack, name: String? = nil, screens: [(Archetype, String)]? = nil, includeLogin: Bool = false, includeOnboarding: Bool = false) -> String {
        var w = RFSWriter()
        let appName = name ?? pack.appName
        w.add(0, "APP name=\(rq(appName)) preset=\(pack.presetID) icon=\(pack.symbol) tagline=\(rq(pack.tagline))")
        let plan = screens ?? blueprint(for: pack.domain)
        let home = plan.first?.1 ?? "Home"
        if includeOnboarding {
            build(.onboarding, pack: pack, options: RecipeOptions(screenName: "Welcome", appName: appName, homeScreen: includeLogin ? "Login" : home), into: &w)
        }
        if includeLogin {
            build(.login, pack: pack, options: RecipeOptions(screenName: "Login", appName: appName, homeScreen: home), into: &w)
        }
        for (arch, screenName) in plan {
            build(arch, pack: pack, options: RecipeOptions(screenName: screenName, tab: true, appName: appName, homeScreen: home), into: &w)
        }
        return w.text
    }

    // MARK: Screens

    public static func screen(_ archetype: Archetype, pack: ContentPack, options: RecipeOptions) -> String {
        var w = RFSWriter()
        build(archetype, pack: pack, options: options, into: &w)
        return w.text
    }

    static func header(_ w: inout RFSWriter, _ name: String, icon: String, tab: Bool, extra: String = "") {
        w.add(0, "SCREEN \(rq(name)) icon=\(icon)\(tab ? " tab" : "")\(extra.isEmpty ? "" : " " + extra)")
    }

    static func rowTemplate(_ indent: Int, _ w: inout RFSWriter, list: String, tap: String? = nil, deletable: Bool = true) {
        var line = "ROW \"{{item.title}}\" subtitle=\"{{item.subtitle}}\" value=\"{{item.value}}\" icon=\"{{item.icon}}\""
        if deletable { line += " ondelete=\"remove \(list) {{index}}\"" }
        if let tap = tap { line += " -> \(tap)" }
        w.add(indent, line)
    }

    /// Declares the pack's list variable once.
    static func listVar(_ w: inout RFSWriter, _ pack: ContentPack) {
        if !w.lines.contains(where: { $0.hasPrefix("VAR \(pack.listVariable) ") }) {
            w.add(0, "VAR \(pack.listVariable) list \(pack.itemsJSON)")
        }
    }

    static func addForm(_ w: inout RFSWriter, _ pack: ContentPack) {
        let screenName = pack.addScreen
        guard !w.lines.contains(where: { $0.hasPrefix("SCREEN \(rq(screenName))") }) else { return }
        header(&w, screenName, icon: "plus.circle.fill", tab: false)
        w.add(1, "FORM")
        w.add(2, "SECTION \(rq(pack.itemNoun.capitalized))")
        for f in pack.fields {
            w.add(3, "FIELD \(rq(f.label)) bind=new\(f.key.capitalized) keyboard=\(f.keyboard)")
        }
        let obj = "{" + pack.fields.map { "\"\($0.key)\": \"{{new\($0.key.capitalized)}}\"" }.joined(separator: ", ") + ", \"icon\": \"\(pack.symbol)\"}"
        let first = "new\(pack.fields.first?.key.capitalized ?? "Title")"
        w.add(1, "BUTTON \"Save\" icon=checkmark style=prominent full -> validate isNotEmpty(\(first)) \"Please add a \(pack.fields.first?.label.lowercased() ?? "title")\"; add \(pack.listVariable) \(obj); "
              + pack.fields.map { "set new\($0.key.capitalized) = \"\"" }.joined(separator: "; ") + "; haptic success; toast \"\(pack.itemNoun.capitalized) saved\"; back")
        w.add(1, "BUTTON \"Cancel\" style=plain -> back")
    }

    static func detailScreen(_ w: inout RFSWriter, _ pack: ContentPack, name: String = "Details", variable: String = "selectedItem") {
        guard !w.lines.contains(where: { $0.hasPrefix("SCREEN \(rq(name))") }) else { return }
        w.add(0, "VAR \(variable) object \(Value.object(["title": .string(pack.items.first?.title ?? "Item"), "subtitle": .string(pack.items.first?.subtitle ?? ""), "value": .string(pack.items.first?.value ?? ""), "icon": .string(pack.symbol)]).jsonString())")
        header(&w, name, icon: "doc.text.fill", tab: false)
        w.add(1, "CARD")
        w.add(2, "ICON \"{{\(variable).icon}}\" size=44 color=accent")
        w.add(2, "TITLE \"{{\(variable).title}}\"")
        w.add(2, "CAPTION \"{{\(variable).subtitle}}\"")
        w.add(2, "BADGE \"{{\(variable).value}}\"")
        w.add(1, "SECTION \"Details\"")
        w.add(2, "INFO \"Status\" \"Active\"")
        w.add(2, "INFO \"Updated\" \"Today\"")
        w.add(1, "TEXT \(rq(pack.description)) color=secondaryText")
        w.add(1, "HSTACK")
        w.add(2, "SHARE \"Share\" \"{{\(variable).title}}\"")
        w.add(2, "BUTTON \"Favorite\" icon=heart style=bordered -> haptic success; toast \"Saved to favorites\"")
    }

    static func build(_ archetype: Archetype, pack: ContentPack, options o: RecipeOptions, into w: inout RFSWriter) {
        let name = o.screenName
        // Already built earlier in this script (e.g. Cart created by the store flow): just re-open it as a tab.
        if w.lines.contains(where: { $0.hasPrefix("SCREEN \(rq(name))") }) {
            if o.tab { w.add(0, "SCREEN \(rq(name)) tab") }
            return
        }
        switch archetype {
        case .dashboard:
            listVar(&w, pack)
            header(&w, name, icon: pack.symbol, tab: o.tab)
            w.add(1, "TEXT \(rq(pack.greeting)) style=title2 bold")
            w.add(1, "CAPTION \(rq(pack.summary))")
            w.add(1, "GRID columns=2")
            for s in pack.stats.prefix(4) { w.add(2, "STAT \(rq(s.title)) \(rq(s.value)) icon=\(s.icon) delta=\(rq(s.delta))") }
            w.add(1, "CARD")
            w.add(2, "HEADING \(rq(pack.chartTitle))")
            w.add(2, "CHART \(pack.chartKind) \(rq(pack.chartData)) height=180")
            if o.wants(.gauge) || [.fitness, .health, .education, .gaming, .pets, .automotive].contains(pack.domain) {
                w.add(1, "CARD")
                w.add(2, "HSTACK")
                w.add(3, "GAUGE \(rq(pack.gauge.label)) value=\(Value.format(number: pack.gauge.value)) max=\(Value.format(number: pack.gauge.max)) style=circular")
                w.add(3, "VSTACK")
                w.add(4, "HEADING \(rq(pack.gauge.label))")
                w.add(4, "CAPTION \"\(Int(pack.gauge.value))% complete — keep going!\"")
            }
            w.add(1, "HEADING \(rq(pack.listTitle))")
            w.add(1, "LIST source=\(pack.listVariable)")
            rowTemplate(2, &w, list: pack.listVariable, tap: "set selectedItem = {{item}}; go \"Details\"")
            w.add(1, "BUTTON \(rq(pack.addTitle.capitalized)) icon=plus style=prominent full -> sheet \(rq(pack.addScreen))")
            addForm(&w, pack)
            detailScreen(&w, pack)
        case .list:
            listVar(&w, pack)
            w.add(0, "VAR query text")
            header(&w, name, icon: archetype.icon == "list.bullet" ? SymbolResolver.symbol(forConcept: name, fallback: "list.bullet") : archetype.icon, tab: o.tab)
            w.add(1, "SEARCH \"Search \(pack.listTitle.lowercased())\" bind=query")
            w.add(1, "SEGMENTED \(rq(pack.categories.prefix(4).joined(separator: ","))) bind=category")
            w.add(1, "LIST source=\"filter(\(pack.listVariable), query)\"")
            rowTemplate(2, &w, list: pack.listVariable, tap: "set selectedItem = {{item}}; go \"Details\"")
            w.add(1, "EMPTY \"No results\" message=\"Try a different search.\" icon=magnifyingglass visible=\"{{len(filter(\(pack.listVariable), query)) == 0}}\"")
            w.add(1, "BUTTON \(rq(pack.addTitle.capitalized)) icon=plus style=bordered full -> sheet \(rq(pack.addScreen))")
            addForm(&w, pack)
            detailScreen(&w, pack)
        case .detail:
            detailScreen(&w, pack, name: name)
        case .login:
            header(&w, name, icon: "person.crop.circle", tab: o.tab, extra: "nobar")
            w.add(1, "SPACER 24")
            w.add(1, "ICON \(rq(pack.symbol)) size=64 color=accent center")
            w.add(1, "TEXT \"Welcome back\" style=largeTitle bold center")
            w.add(1, "CAPTION \"Sign in to continue to \(o.appName)\" center")
            w.add(1, "FIELD \"Email\" bind=email keyboard=email icon=envelope")
            w.add(1, "SECURE \"Password\" bind=password")
            w.add(1, "BUTTON \"Sign In\" style=prominent full -> validate isEmail(email) \"Enter a valid email address\"; validate len(password) >= 6 \"Password must be at least 6 characters\"; haptic success; root \(rq(o.homeScreen))")
            w.add(1, "APPLE -> haptic success; root \(rq(o.homeScreen))")
            w.add(1, "LINK \"Forgot password?\" \"https://example.com/reset\"")
            w.add(1, "BUTTON \"New here? Create an account\" style=plain -> go \"Sign Up\"")
            if !w.lines.contains(where: { $0.hasPrefix("SCREEN \"Sign Up\"") }) {
                build(.signup, pack: pack, options: RecipeOptions(screenName: "Sign Up", appName: o.appName, homeScreen: o.homeScreen), into: &w)
            }
        case .signup:
            header(&w, name, icon: "person.badge.plus", tab: o.tab)
            w.add(1, "CAPTION \"Create your \(o.appName) account in seconds.\"")
            w.add(1, "FORM")
            w.add(2, "SECTION \"Your details\"")
            w.add(3, "FIELD \"Full name\" bind=fullName")
            w.add(3, "FIELD \"Email\" bind=email keyboard=email")
            w.add(3, "SECURE \"Password\" bind=password")
            w.add(2, "SECTION \"Preferences\"")
            w.add(3, "TOGGLE \"Send me product updates\" bind=marketing off")
            w.add(3, "TOGGLE \"I agree to the Terms\" bind=agreed off")
            w.add(1, "BUTTON \"Create Account\" style=prominent full -> validate isNotEmpty(fullName) \"Please enter your name\"; validate isEmail(email) \"Enter a valid email\"; validate len(password) >= 6 \"Use at least 6 characters\"; validate agreed \"Please accept the Terms\"; haptic success; toast \"Welcome, {{fullName}}!\"; root \(rq(o.homeScreen))")
        case .onboarding:
            header(&w, name, icon: "sparkles", tab: o.tab, extra: "nobar")
            w.add(1, "PAGER height=420")
            let pages: [(String, String, String)] = [
                (pack.symbol, "Welcome to \(o.appName)", pack.tagline),
                ("bolt.fill", "Everything in one place", pack.description),
                ("checkmark.seal.fill", "You're all set", "Personalize your experience and get started in seconds."),
            ]
            for (sym, title, body) in pages {
                w.add(2, "VSTACK align=center spacing=16")
                w.add(3, "ICON \(rq(sym)) size=80 color=accent effect=bounce")
                w.add(3, "TEXT \(rq(title)) style=title bold center")
                w.add(3, "TEXT \(rq(body)) center color=secondaryText")
            }
            w.add(1, "BUTTON \"Get Started\" icon=arrow.right style=prominent full -> haptic success; root \(rq(o.homeScreen))")
            w.add(1, "BUTTON \"I already have an account\" style=plain -> root \(rq(o.homeScreen))")
        case .settings:
            header(&w, name, icon: "gearshape.fill", tab: o.tab)
            w.add(1, "FORM")
            w.add(2, "SECTION \"Account\"")
            w.add(3, "NAVLINK \"Profile\" \"Profile\" icon=person.crop.circle.fill")
            w.add(3, "INFO \"Email\" \"alex@example.com\"")
            w.add(2, "SECTION \"Preferences\"")
            w.add(3, "TOGGLE \"Notifications\" bind=notificationsOn icon=bell.badge.fill")
            w.add(3, "TOGGLE \"Dark mode\" bind=darkMode off icon=moon.fill")
            w.add(3, "PICKER \"Language\" \"English,Español,Français,Filipino\" bind=language style=menu")
            w.add(3, "SLIDER \"Text size\" bind=textSize min=12 max=24 value=17")
            w.add(2, "SECTION \"Privacy & Security\"")
            w.add(3, "TOGGLE \"Face ID\" bind=faceID icon=faceid")
            w.add(3, "TOGGLE \"Share analytics\" bind=analytics off icon=chart.bar.fill")
            w.add(2, "SECTION \"About\"")
            w.add(3, "INFO \"Version\" \"1.0 (1)\"")
            w.add(3, "LINK \"Rate \(o.appName)\" \"https://apps.apple.com\"")
            w.add(3, "SHARE \"Share \(o.appName)\" \"Check out \(o.appName)!\"")
            w.add(1, "BUTTON \"Sign Out\" style=destructive full -> confirm \"Sign out?\" \"You can sign back in anytime.\" { toast \"Signed out\" \"info\" }")
        case .profile:
            header(&w, name, icon: "person.crop.circle.fill", tab: o.tab)
            w.add(1, "VSTACK align=center spacing=8")
            w.add(2, "AVATAR \"Alex Morgan\" size=96 status=online")
            w.add(2, "TEXT \"Alex Morgan\" style=title2 bold center")
            w.add(2, "CAPTION \"@alexm · Product designer in San Francisco\" center")
            w.add(1, "HSTACK")
            for s in pack.stats.prefix(3) { w.add(2, "STAT \(rq(s.title)) \(rq(s.value)) icon=\(s.icon)") }
            w.add(1, "HSTACK")
            w.add(2, "BUTTON \"Edit Profile\" icon=pencil style=bordered -> sheet \"Edit Profile\"")
            w.add(2, "SHARE \"Share\" \"https://example.com/@alexm\"")
            w.add(1, "HEADING \"Highlights\"")
            w.add(1, "GRID columns=3 spacing=6")
            for i in 0..<6 { w.add(2, "IMAGE \"https://picsum.photos/seed/\(pack.domain.rawValue)\(i)/400/400\" height=110 radius=10") }
            w.add(1, "LIST")
            w.add(2, "NAVLINK \"Settings\" \"Settings\" icon=gearshape.fill")
            w.add(2, "NAVLINK \"Help & Support\" \"Help\" icon=questionmark.circle.fill")
            if !w.lines.contains(where: { $0.hasPrefix("SCREEN \"Edit Profile\"") }) {
                header(&w, "Edit Profile", icon: "pencil", tab: false)
                w.add(1, "FORM")
                w.add(2, "SECTION \"Profile\"")
                w.add(3, "PHOTO \"Change photo\" bind=profilePhoto")
                w.add(3, "FIELD \"Name\" bind=profileName")
                w.add(3, "EDITOR \"Bio\" bind=profileBio height=120")
                w.add(1, "BUTTON \"Save\" style=prominent full -> haptic success; toast \"Profile updated\"; back")
            }
        case .feed:
            w.add(0, "VAR posts list \(pack.postsJSON.isEmpty || pack.posts.isEmpty ? ContentPacks.pack(.social).postsJSON : pack.postsJSON)")
            header(&w, name, icon: pack.domain == .social ? "house.fill" : archetype.icon, tab: o.tab)
            w.add(1, "SCROLL horizontal spacing=14")
            for n in ["You", "Maya", "Jon", "Ava", "Leo", "Kim"] { w.add(2, "AVATAR \(rq(n)) size=60 image=https://picsum.photos/seed/\(n.lowercased())face/200/200") }
            w.add(1, "VSTACK source=posts spacing=16")
            w.add(2, "CARD spacing=10")
            w.add(3, "HSTACK")
            w.add(4, "AVATAR \"{{item.author}}\" size=40")
            w.add(4, "VSTACK spacing=2")
            w.add(5, "TEXT \"{{item.author}}\" bold")
            w.add(5, "CAPTION \"{{item.handle}} · {{item.time}}\"")
            w.add(3, "TEXT \"{{item.text}}\"")
            w.add(3, "IMAGE \"{{item.image}}\" height=220")
            w.add(3, "HSTACK")
            w.add(4, "BUTTON \"{{item.likes}}\" icon=heart style=plain -> haptic light; toast \"Liked {{item.author}}'s post\"")
            w.add(4, "BUTTON \"Comment\" icon=bubble.right style=plain -> sheet \"Comments\"")
            w.add(4, "SHARE \"Share\" \"{{item.text}}\"")
            if !w.lines.contains(where: { $0.hasPrefix("SCREEN \"Comments\"") }) {
                header(&w, "Comments", icon: "bubble.right", tab: false)
                w.add(1, "LIST")
                w.add(2, "ROW \"Maya\" subtitle=\"This is amazing! 😍\" icon=person.crop.circle.fill")
                w.add(2, "ROW \"Jon\" subtitle=\"Where is this?\" icon=person.crop.circle.fill")
                w.add(1, "FIELD \"Add a comment…\" bind=comment")
                w.add(1, "BUTTON \"Post\" icon=paperplane.fill style=prominent -> validate isNotEmpty(comment) \"Write something first\"; toast \"Comment posted\"; set comment = \"\"")
            }
        case .cart:
            w.add(0, "VAR cart list \(Value.array(pack.products.prefix(2).map { .object(["title": .string($0.name), "subtitle": "Qty 1", "price": .number(Value.parseNumber($0.price) ?? 0), "icon": .string(pack.symbol)]) }).jsonString())")
            header(&w, name, icon: "cart.fill", tab: o.tab)
            w.add(1, "LIST source=cart")
            w.add(2, "ROW \"{{item.title}}\" subtitle=\"{{item.subtitle}}\" value=\"{{currency(item.price)}}\" icon=\"{{item.icon}}\" ondelete=\"remove cart {{index}}\"")
            w.add(1, "EMPTY \"Your cart is empty\" icon=cart message=\"Add something you love.\" visible=\"{{len(cart) == 0}}\"")
            w.add(1, "CARD visible=\"{{len(cart) > 0}}\"")
            w.add(2, "INFO \"Subtotal\" \"{{currency(sum(cart, 'price'))}}\"")
            w.add(2, "INFO \"Shipping\" \"Free\"")
            w.add(2, "DIVIDER")
            w.add(2, "INFO \"Total\" \"{{currency(sum(cart, 'price'))}}\"")
            w.add(1, "BUTTON \"Checkout\" icon=creditcard.fill style=prominent full visible=\"{{len(cart) > 0}}\" -> go \"Checkout\"")
            if !w.lines.contains(where: { $0.hasPrefix("SCREEN \"Checkout\"") }) {
                build(.checkout, pack: pack, options: RecipeOptions(screenName: "Checkout", appName: o.appName, homeScreen: o.homeScreen), into: &w)
            }
        case .checkout:
            if !w.lines.contains(where: { $0.hasPrefix("VAR cart ") }) { w.add(0, "VAR cart list []") }
            header(&w, name, icon: "creditcard.fill", tab: o.tab)
            w.add(1, "FORM")
            w.add(2, "SECTION \"Shipping\"")
            w.add(3, "FIELD \"Full name\" bind=shipName")
            w.add(3, "FIELD \"Address\" bind=shipAddress")
            w.add(3, "FIELD \"City\" bind=shipCity")
            w.add(2, "SECTION \"Payment\"")
            w.add(3, "PICKER \"Method\" \"Apple Pay,Card,Cash on delivery\" bind=payMethod style=menu")
            w.add(3, "TOGGLE \"Save for next time\" bind=savePayment")
            w.add(2, "SECTION \"Summary\"")
            w.add(3, "INFO \"Items\" \"{{len(cart)}}\"")
            w.add(3, "INFO \"Total\" \"{{currency(sum(cart, 'price'))}}\"")
            w.add(1, "BUTTON \"Place Order\" icon=lock.fill style=prominent full -> validate isNotEmpty(shipName) \"Enter your name\"; validate isNotEmpty(shipAddress) \"Enter your address\"; haptic success; alert \"Order placed!\" \"Thanks {{shipName}} — we'll email your receipt.\"; clear cart; root \(rq(o.homeScreen))")
        case .inbox:
            w.add(0, "VAR chats list \(Value.array([["Maya Chen", "See you at 6!", "2m"], ["Jon Park", "Sent the files 👍", "1h"], ["Design Team", "Ava: Love the new icons", "3h"], ["Leo", "Haha that's great", "Yesterday"]].map { .object(["title": .string($0[0]), "subtitle": .string($0[1]), "value": .string($0[2]), "icon": "person.crop.circle.fill"]) }).jsonString())")
            header(&w, name, icon: "message.fill", tab: o.tab)
            w.add(1, "SEARCH \"Search messages\" bind=chatQuery")
            w.add(1, "LIST source=\"filter(chats, chatQuery)\"")
            w.add(2, "ROW \"{{item.title}}\" subtitle=\"{{item.subtitle}}\" value=\"{{item.value}}\" icon=\"{{item.icon}}\" chevron ondelete=\"remove chats {{index}}\" -> set chatWith = \"{{item.title}}\"; go \"Chat\"")
            if !w.lines.contains(where: { $0.hasPrefix("SCREEN \"Chat\"") }) {
                build(.conversation, pack: pack, options: RecipeOptions(screenName: "Chat", appName: o.appName, homeScreen: o.homeScreen), into: &w)
            }
        case .conversation:
            w.add(0, "VAR messages list [{\"text\": \"Hey! Are we still on for tonight?\", \"me\": false}, {\"text\": \"Yes! 6pm at the usual spot 🙌\", \"me\": true}, {\"text\": \"Perfect, see you there\", \"me\": false}]")
            w.add(0, "VAR chatWith text \"Maya Chen\"")
            header(&w, name, icon: "bubble.left.and.bubble.right.fill", tab: o.tab)
            w.add(1, "CAPTION \"Chatting with {{chatWith}}\" center")
            w.add(1, "VSTACK source=messages spacing=8")
            w.add(2, "CARD bg=accent visible=\"{{item.me}}\" padding=12 align=trailing")
            w.add(3, "TEXT \"{{item.text}}\" color=white")
            w.add(2, "CARD visible=\"{{!item.me}}\" padding=12")
            w.add(3, "TEXT \"{{item.text}}\"")
            w.add(1, "HSTACK")
            w.add(2, "FIELD \"Message\" bind=draft")
            w.add(2, "BUTTON \"Send\" icon=paperplane.fill style=prominent size=regular -> validate isNotEmpty(draft) \"Type a message\"; add messages {\"text\": \"{{draft}}\", \"me\": true}; set draft = \"\"; haptic light")
        case .todo:
            w.add(0, "VAR todos list [{\"title\": \"Plan the week\", \"done\": true}, {\"title\": \"Reply to emails\", \"done\": false}, {\"title\": \"30 min workout\", \"done\": false}]")
            header(&w, name, icon: "checklist", tab: o.tab)
            w.add(1, "CARD")
            w.add(2, "HEADING \"{{countWhere(todos, 'done', true)}} of {{len(todos)}} done\"")
            w.add(2, "PROGRESS \"Progress\" value=\"{{len(todos) == 0 ? 0 : countWhere(todos, 'done', true) / len(todos)}}\"")
            w.add(1, "HSTACK")
            w.add(2, "FIELD \"New task\" bind=newTask icon=plus.circle")
            w.add(2, "BUTTON \"Add\" style=prominent size=regular -> validate isNotEmpty(newTask) \"Type a task first\"; add todos {\"title\": \"{{newTask}}\", \"done\": false}; set newTask = \"\"; haptic success")
            w.add(1, "LIST source=todos")
            w.add(2, "ROW \"{{item.title}}\" icon=\"{{item.done ? 'checkmark.circle.fill' : 'circle'}}\" subtitle=\"{{item.done ? 'Completed' : 'Tap to complete'}}\" ondelete=\"remove todos {{index}}\" -> toggleitem todos done; haptic light")
            w.add(1, "BUTTON \"Clear completed\" style=plain -> set todos = filter(todos, 'done', false); toast \"Cleared\"")
        case .notes:
            w.add(0, "VAR notes list [{\"title\": \"Ideas for the weekend\", \"subtitle\": \"Hike, farmers market, call grandma\", \"value\": \"Today\"}, {\"title\": \"Book list\", \"subtitle\": \"Project Hail Mary, Dune, Atomic Habits\", \"value\": \"Mon\"}]")
            header(&w, name, icon: "note.text", tab: o.tab)
            w.add(1, "SEARCH \"Search notes\" bind=noteQuery")
            w.add(1, "LIST source=\"filter(notes, noteQuery)\"")
            w.add(2, "ROW \"{{item.title}}\" subtitle=\"{{item.subtitle}}\" value=\"{{item.value}}\" icon=note.text ondelete=\"remove notes {{index}}\" -> set selectedNote = {{item}}; go \"Note\"")
            w.add(1, "BUTTON \"New Note\" icon=square.and.pencil style=prominent full -> sheet \"New Note\"")
            if !w.lines.contains(where: { $0.hasPrefix("SCREEN \"New Note\"") }) {
                header(&w, "New Note", icon: "square.and.pencil", tab: false)
                w.add(1, "FIELD \"Title\" bind=noteTitle")
                w.add(1, "EDITOR \"Start writing…\" bind=noteBody height=240")
                w.add(1, "BUTTON \"Save Note\" style=prominent full -> validate isNotEmpty(noteTitle) \"Give your note a title\"; add notes {\"title\": \"{{noteTitle}}\", \"subtitle\": \"{{noteBody}}\", \"value\": \"Now\"}; set noteTitle = \"\"; set noteBody = \"\"; back")
                header(&w, "Note", icon: "doc.text", tab: false)
                w.add(0, "VAR selectedNote object {\"title\": \"Note\", \"subtitle\": \"\"}")
                w.add(1, "TITLE \"{{selectedNote.title}}\"")
                w.add(1, "TEXT \"{{selectedNote.subtitle}}\"")
                w.add(1, "SHARE \"Share note\" \"{{selectedNote.title}}: {{selectedNote.subtitle}}\"")
            }
        case .calendar:
            listVar(&w, pack)
            header(&w, name, icon: "calendar", tab: o.tab)
            w.add(1, "DATE \"Pick a day\" bind=selectedDate style=graphical")
            w.add(1, "HEADING \"Upcoming · {{formatDate(selectedDate, 'MMM d')}}\"")
            w.add(1, "LIST source=\(pack.listVariable)")
            rowTemplate(2, &w, list: pack.listVariable)
            w.add(1, "BUTTON \"Add event\" icon=calendar.badge.plus style=prominent full -> sheet \(rq(pack.addScreen))")
            addForm(&w, pack)
        case .map:
            header(&w, name, icon: "map.fill", tab: o.tab)
            w.add(1, "SEARCH \"Search places\" bind=placeQuery")
            w.add(1, "MAP \(rq(pack.place)) height=300")
            w.add(1, "HEADING \"Nearby\"")
            w.add(1, "LIST")
            let places = [("\(pack.place) Center", "0.3 km", "mappin.circle.fill"), ("Riverside Park", "1.2 km", "tree.fill"), ("Main Street Station", "2.0 km", "tram.fill")]
            for p in places { w.add(2, "ROW \(rq(p.0)) subtitle=\"Open now\" value=\(rq(p.1)) icon=\(p.2) chevron -> open \"maps://?q=\(p.0.replacingOccurrences(of: " ", with: "+"))\"") }
        case .player:
            w.add(0, "VAR isPlaying bool false")
            header(&w, name, icon: "music.note", tab: o.tab)
            w.add(1, "IMAGE \"https://picsum.photos/seed/albumart/800/800\" height=320 radius=24 shadow=large")
            w.add(1, "TEXT \"\(pack.items.first?.title ?? "Midnight City")\" style=title2 bold center")
            w.add(1, "CAPTION \"\(pack.items.first?.subtitle ?? "M83")\" center")
            w.add(1, "AUDIO \"https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3\" \"\(pack.items.first?.title ?? "Midnight City")\"")
            w.add(1, "HSTACK")
            w.add(2, "BUTTON \"\" icon=backward.fill style=plain -> haptic light")
            w.add(2, "BUTTON \"{{isPlaying ? 'Pause' : 'Play'}}\" icon=\"{{isPlaying ? 'pause.fill' : 'play.fill'}}\" style=prominent -> toggle isPlaying; haptic medium")
            w.add(2, "BUTTON \"\" icon=forward.fill style=plain -> haptic light")
            w.add(1, "SLIDER \"Volume\" bind=volume min=0 max=100 value=70")
            w.add(1, "HEADING \"Up next\"")
            listVar(&w, pack)
            w.add(1, "LIST source=\(pack.listVariable)")
            rowTemplate(2, &w, list: pack.listVariable, deletable: false)
        case .video:
            header(&w, name, icon: "play.rectangle.fill", tab: o.tab)
            w.add(1, "VIDEO \"https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8\" height=220")
            w.add(1, "TITLE \"Featured episode\"")
            w.add(1, "CAPTION \"2026 · 24 min · HD\"")
            w.add(1, "HSTACK")
            w.add(2, "BUTTON \"Watchlist\" icon=plus style=bordered -> toast \"Added to watchlist\"")
            w.add(2, "SHARE \"Share\" \"Watch this with me!\"")
            w.add(1, "HEADING \"More like this\"")
            w.add(1, "SCROLL horizontal")
            for i in 0..<5 { w.add(2, "IMAGE \"https://picsum.photos/seed/show\(i)/400/600\" width=120 height=180 radius=12") }
        case .gallery:
            header(&w, name, icon: "photo.on.rectangle", tab: o.tab)
            w.add(1, "PHOTO \"Add photo\" bind=newPhoto icon=photo.badge.plus")
            w.add(1, "IMAGE \"{{newPhoto}}\" height=220 visible=\"{{isNotEmpty(newPhoto)}}\"")
            w.add(1, "GRID columns=3 spacing=4")
            for i in 0..<12 { w.add(2, "IMAGE \"https://picsum.photos/seed/\(pack.domain.rawValue)g\(i)/400/400\" height=118 radius=6") }
        case .search:
            listVar(&w, pack)
            header(&w, name, icon: "magnifyingglass", tab: o.tab)
            w.add(1, "SEARCH \"Search \(o.appName)\" bind=searchQuery")
            w.add(1, "SCROLL horizontal spacing=8")
            for c in pack.categories.prefix(5) { w.add(2, "BADGE \(rq(c)) -> set searchQuery = \(rq(c == "All" ? "" : c))") }
            w.add(1, "LIST source=\"filter(\(pack.listVariable), searchQuery)\"")
            rowTemplate(2, &w, list: pack.listVariable, tap: "set selectedItem = {{item}}; go \"Details\"", deletable: false)
            w.add(1, "EMPTY \"No matches\" icon=magnifyingglass message=\"Try another word.\" visible=\"{{len(filter(\(pack.listVariable), searchQuery)) == 0}}\"")
            detailScreen(&w, pack)
        case .notifications:
            header(&w, name, icon: "bell.fill", tab: o.tab)
            w.add(1, "TOGGLE \"Push notifications\" bind=pushEnabled icon=bell.badge.fill")
            w.add(1, "LIST")
            let notes: [(String, String, String)] = [("Your order has shipped", "2 min ago", "shippingbox.fill"), ("New follower: Jon Park", "1 h ago", "person.badge.plus"),
                                                     ("Weekly summary is ready", "Yesterday", "chart.bar.fill"), ("Reminder: team sync at 3 PM", "Mon", "calendar.badge.clock")]
            for n in notes { w.add(2, "ROW \(rq(n.0)) subtitle=\(rq(n.1)) icon=\(n.2)") }
            w.add(1, "BUTTON \"Send a test notification\" icon=bell style=bordered full -> notify \"\(o.appName)\" \"This is a test notification\" in 5; toast \"Scheduled in 5 seconds\"")
        case .contact:
            header(&w, name, icon: "envelope.fill", tab: o.tab)
            w.add(1, "FORM")
            w.add(2, "SECTION \"Your info\"")
            w.add(3, "FIELD \"Name\" bind=contactName")
            w.add(3, "FIELD \"Email\" bind=contactEmail keyboard=email")
            w.add(2, "SECTION \"Message\"")
            w.add(3, "PICKER \"Topic\" \"Question,Feedback,Bug report,Partnership\" bind=contactTopic style=menu")
            w.add(3, "EDITOR \"How can we help?\" bind=contactMessage height=140")
            w.add(3, "RATING value=5 bind=contactRating")
            w.add(1, "BUTTON \"Send\" icon=paperplane.fill style=prominent full -> validate isEmail(contactEmail) \"Enter a valid email\"; validate isNotEmpty(contactMessage) \"Write a message\"; haptic success; alert \"Thanks, {{contactName}}!\" \"We'll reply within 24 hours.\"")
            w.add(1, "HSTACK")
            w.add(2, "BUTTON \"Call\" icon=phone.fill style=bordered -> call \"+1 555 0100\"")
            w.add(2, "BUTTON \"Email\" icon=envelope.fill style=bordered -> email \"hello@example.com\"")
        case .about:
            header(&w, name, icon: "info.circle.fill", tab: o.tab)
            w.add(1, "VSTACK align=center spacing=10")
            w.add(2, "ICON \(rq(pack.symbol)) size=72 color=accent")
            w.add(2, "TEXT \(rq(o.appName)) style=title bold center")
            w.add(2, "CAPTION \(rq(pack.tagline)) center")
            w.add(1, "TEXT \(rq(pack.description))")
            w.add(1, "LIST")
            w.add(2, "INFO \"Version\" \"1.0 (1)\"")
            w.add(2, "INFO \"Made with\" \"ReyForge\"")
            w.add(1, "LINK \"Visit website\" \"https://example.com\"")
            w.add(1, "QR \"https://example.com\" size=160")
        case .store:
            w.add(0, "VAR products list \(pack.products.isEmpty ? ContentPacks.pack(.shopping).productsJSON : pack.productsJSON)")
            if !w.lines.contains(where: { $0.hasPrefix("VAR cart ") }) { w.add(0, "VAR cart list []") }
            header(&w, name, icon: pack.domain == .shopping || pack.domain == .generic ? "bag.fill" : SymbolResolver.symbol(forConcept: name, fallback: pack.symbol), tab: o.tab)
            w.add(1, "SEARCH \"Search\" bind=shopQuery")
            w.add(1, "SCROLL horizontal spacing=8")
            for c in pack.categories.prefix(5) { w.add(2, "BADGE \(rq(c))") }
            w.add(1, "IMAGE \"https://picsum.photos/seed/\(pack.domain.rawValue)banner/1200/600\" height=170 overlayText=\(rq(pack.tagline))")
            w.add(1, "HEADING \"Featured\"")
            w.add(1, "GRID columns=2 source=\"filter(products, shopQuery)\"")
            w.add(2, "CARD spacing=6 padding=10 -> set selectedProduct = {{item}}; go \"Product\"")
            w.add(3, "IMAGE \"{{item.image}}\" height=130 radius=12")
            w.add(3, "TEXT \"{{item.name}}\" bold lines=1")
            w.add(3, "HSTACK")
            w.add(4, "TEXT \"{{currency(item.price)}}\" color=accent bold")
            w.add(4, "BADGE \"★ {{item.rating}}\"")
            w.add(1, "BUTTON \"View cart ({{len(cart)}})\" icon=cart.fill style=bordered full -> go \"Cart\"")
            if !w.lines.contains(where: { $0.hasPrefix("SCREEN \"Product\"") }) {
                build(.product, pack: pack, options: RecipeOptions(screenName: "Product", appName: o.appName, homeScreen: o.homeScreen), into: &w)
            }
            build(.cart, pack: pack, options: RecipeOptions(screenName: "Cart", appName: o.appName, homeScreen: o.homeScreen), into: &w)
        case .product:
            let p = pack.products.first ?? ContentPacks.pack(.shopping).products[0]
            w.add(0, "VAR selectedProduct object \(Value.object(["name": .string(p.name), "price": .number(Value.parseNumber(p.price) ?? 0), "image": .string(p.image), "detail": .string(p.detail), "rating": .number(p.rating)]).jsonString())")
            if !w.lines.contains(where: { $0.hasPrefix("VAR cart ") }) { w.add(0, "VAR cart list []") }
            header(&w, name, icon: "tag.fill", tab: o.tab)
            w.add(1, "IMAGE \"{{selectedProduct.image}}\" height=300 radius=20")
            w.add(1, "TITLE \"{{selectedProduct.name}}\"")
            w.add(1, "HSTACK")
            w.add(2, "TEXT \"{{currency(selectedProduct.price)}}\" style=title3 bold color=accent")
            w.add(2, "RATING value=\"{{selectedProduct.rating}}\" interactive=false")
            w.add(1, "TEXT \"{{selectedProduct.detail}}\" color=secondaryText")
            w.add(1, "SEGMENTED \"S,M,L,XL\" bind=size")
            w.add(1, "STEPPER \"Quantity\" bind=quantity min=1 max=10 value=1")
            w.add(1, "BUTTON \"Add to Cart\" icon=cart.badge.plus style=prominent full -> add cart {\"title\": \"{{selectedProduct.name}}\", \"subtitle\": \"Size {{size}} · Qty {{quantity}}\", \"price\": \"{{selectedProduct.price * quantity}}\", \"icon\": \"bag.fill\"}; haptic success; toast \"Added to cart\"")
            w.add(1, "SHARE \"Share\" \"{{selectedProduct.name}}\"")
        case .weather:
            w.add(0, "VAR temperature number 31")
            w.add(0, "VAR wind number 12")
            header(&w, name, icon: "cloud.sun.fill", tab: o.tab, extra: "onappear=\"get \\\"https://api.open-meteo.com/v1/forecast?latitude=14.5995&longitude=120.9842&current=temperature_2m,wind_speed_10m\\\" into weather\" onrefresh=\"get \\\"https://api.open-meteo.com/v1/forecast?latitude=14.5995&longitude=120.9842&current=temperature_2m,wind_speed_10m\\\" into weather\"")
            w.add(1, "VSTACK align=center spacing=4")
            w.add(2, "TEXT \(rq(pack.greeting == "Manila" ? "Manila" : pack.place)) style=title2 center")
            w.add(2, "ICON cloud.sun.fill size=90 renderingMode=multicolor")
            w.add(2, "TEXT \"{{round(weather.current.temperature_2m ?? temperature)}}°\" fontsize=76 weight=thin center")
            w.add(2, "CAPTION \"Partly cloudy · Wind {{round(weather.current.wind_speed_10m ?? wind)}} km/h\" center")
            w.add(1, "HSTACK")
            for s in ContentPacks.pack(.weather).stats.prefix(3) { w.add(2, "STAT \(rq(s.title)) \(rq(s.value)) icon=\(s.icon)") }
            w.add(1, "CARD")
            w.add(2, "HEADING \"Hourly\"")
            w.add(2, "CHART line \(rq(ContentPacks.pack(.weather).chartData)) height=150")
            w.add(1, "HEADING \"This week\"")
            w.add(1, "LIST")
            for it in ContentPacks.pack(.weather).items { w.add(2, "ROW \(rq(it.title)) subtitle=\(rq(it.subtitle)) value=\(rq(it.value)) icon=\(it.icon)") }
            w.add(1, "BUTTON \"Refresh\" icon=arrow.clockwise style=bordered full -> get \"https://api.open-meteo.com/v1/forecast?latitude=14.5995&longitude=120.9842&current=temperature_2m,wind_speed_10m\" into weather; toast \"Updated\"")
        case .workout:
            header(&w, name, icon: "figure.run", tab: o.tab)
            w.add(1, "CARD")
            w.add(2, "HSTACK")
            w.add(3, "GAUGE \"Move\" value=79 max=100 style=circular color=red")
            w.add(3, "GAUGE \"Exercise\" value=55 max=100 style=circular color=green")
            w.add(3, "GAUGE \"Stand\" value=92 max=100 style=circular color=cyan")
            w.add(1, "TIMER 1200")
            w.add(1, "PICKER \"Workout\" \"Run,Walk,Cycle,Strength,Yoga\" bind=workoutType style=segmented")
            w.add(1, "STEPPER \"Rounds\" bind=rounds min=1 max=10 value=3")
            w.add(1, "BUTTON \"Log workout\" icon=checkmark.circle.fill style=prominent full -> add workouts {\"title\": \"{{workoutType}}\", \"subtitle\": \"Today · {{rounds}} rounds\", \"value\": \"Done\", \"icon\": \"figure.run\"}; haptic success; toast \"Workout logged 💪\"")
            listVar(&w, ContentPacks.pack(.fitness))
        case .recipe:
            header(&w, name, icon: "frying.pan", tab: o.tab)
            w.add(1, "IMAGE \"https://picsum.photos/seed/recipe/1000/700\" height=240")
            w.add(1, "TITLE \"Creamy Garlic Pasta\"")
            w.add(1, "HSTACK")
            w.add(2, "BADGE \"25 min\" icon=clock")
            w.add(2, "BADGE \"Serves 2\" icon=person.2")
            w.add(2, "BADGE \"540 kcal\" icon=flame")
            w.add(1, "SEGMENTED \"Ingredients,Steps\" bind=recipeTab")
            w.add(1, "LIST visible=\"{{recipeTab == 'Ingredients'}}\"")
            for i in ["200 g spaghetti", "3 cloves garlic", "200 ml cream", "40 g parmesan", "Fresh parsley"] { w.add(2, "ROW \(rq(i)) icon=circle") }
            w.add(1, "LIST visible=\"{{recipeTab == 'Steps'}}\"")
            for (i, s) in ["Boil pasta until al dente.", "Sauté garlic in butter.", "Add cream and parmesan.", "Toss pasta, top with parsley."].enumerated() { w.add(2, "ROW \"Step \(i + 1)\" subtitle=\(rq(s)) icon=\(i + 1).circle.fill") }
            w.add(1, "TIMER 600")
        case .booking:
            header(&w, name, icon: "calendar.badge.plus", tab: o.tab)
            w.add(1, "IMAGE \"https://picsum.photos/seed/\(pack.domain.rawValue)venue/1000/600\" height=180")
            w.add(1, "HEADING \(rq(pack.domain == .beauty ? "Book an appointment" : "Reserve a table"))")
            w.add(1, "MAP \(rq(pack.place)) height=140 interactive=false")
            w.add(1, "FORM")
            w.add(2, "SECTION \"When\"")
            w.add(3, "DATE \"Date\" bind=bookingDate")
            w.add(3, "PICKER \"Time\" \"6:00 PM,7:00 PM,8:00 PM,9:00 PM\" bind=bookingTime style=menu")
            w.add(3, "STEPPER \"Guests\" bind=guests min=1 max=12 value=2")
            w.add(2, "SECTION \"Contact\"")
            w.add(3, "FIELD \"Name\" bind=bookingName")
            w.add(3, "FIELD \"Phone\" bind=bookingPhone keyboard=phone")
            w.add(1, "BUTTON \"Confirm Booking\" icon=checkmark.seal.fill style=prominent full -> validate isNotEmpty(bookingName) \"Please enter your name\"; confirm \"Confirm booking?\" \"{{guests}} guests · {{formatDate(bookingDate)}} at {{bookingTime}}\" { haptic success; notify \"Booking reminder\" \"See you at {{bookingTime}}!\" in 10; toast \"You're booked!\" }")
        case .timer:
            header(&w, name, icon: "timer", tab: o.tab)
            w.add(1, "TIMER 300")
            w.add(1, "PICKER \"Preset\" \"1 min,5 min,10 min,25 min\" bind=timerPreset style=segmented")
            w.add(1, "TOGGLE \"Sound when done\" bind=timerSound")
            w.add(1, "CARD")
            w.add(2, "HEADING \"Breathe in for 4, hold for 4, out for 6\"")
            w.add(2, "ICON lungs.fill size=60 color=mint effect=breathe")
        case .quiz:
            w.add(0, "VAR questions list [{\"q\": \"Which framework builds native iOS UI declaratively?\", \"a\": [\"UIKit\", \"SwiftUI\", \"Flutter\", \"React\"], \"correct\": 1}, {\"q\": \"What does IPA stand for in iOS?\", \"a\": [\"iOS App Store Package\", \"Internet Protocol App\", \"Indie Program Archive\", \"Image Pack\"], \"correct\": 0}, {\"q\": \"Which symbol set ships with iOS?\", \"a\": [\"Font Awesome\", \"Material\", \"SF Symbols\", \"Emoji+\"], \"correct\": 2}]")
            w.add(0, "VAR qIndex number 0")
            w.add(0, "VAR score number 0")
            header(&w, name, icon: "questionmark.circle.fill", tab: o.tab)
            w.add(1, "PROGRESS \"Question {{min(qIndex + 1, len(questions))}} of {{len(questions)}}\" value=\"{{qIndex / len(questions)}}\"")
            w.add(1, "CARD visible=\"{{qIndex < len(questions)}}\"")
            w.add(2, "TEXT \"{{questions[qIndex].q}}\" style=title3 bold")
            for i in 0..<4 {
                w.add(2, "BUTTON \"{{questions[qIndex].a[\(i)]}}\" style=bordered full -> if questions[qIndex].correct == \(i) { inc score; haptic success; toast \"Correct!\" } else { haptic error; toast \"Not quite\" \"error\" }; inc qIndex")
            }
            w.add(1, "CARD visible=\"{{qIndex >= len(questions)}}\" align=center")
            w.add(2, "ICON trophy.fill size=64 color=yellow effect=bounce")
            w.add(2, "TEXT \"You scored {{score}} / {{len(questions)}}\" style=title2 bold center")
            w.add(2, "BUTTON \"Play again\" icon=arrow.counterclockwise style=prominent -> set qIndex = 0; set score = 0")
        case .news:
            listVar(&w, ContentPacks.pack(.news))
            header(&w, name, icon: "newspaper.fill", tab: o.tab)
            w.add(1, "SEGMENTED \(rq(ContentPacks.pack(.news).categories.prefix(4).joined(separator: ","))) bind=newsSection")
            w.add(1, "CARD padding=0 -> go \"Article\"")
            w.add(2, "IMAGE \"https://picsum.photos/seed/headline/1000/600\" height=200")
            w.add(2, "VSTACK padding=14 spacing=4")
            w.add(3, "BADGE \"Top story\"")
            w.add(3, "TEXT \(rq(ContentPacks.pack(.news).items[0].title)) style=title3 bold")
            w.add(3, "CAPTION \(rq(ContentPacks.pack(.news).items[0].subtitle))")
            w.add(1, "LIST source=stories")
            w.add(2, "ROW \"{{item.title}}\" subtitle=\"{{item.subtitle}}\" value=\"{{item.value}}\" icon=\"{{item.icon}}\" chevron -> go \"Article\"")
            if !w.lines.contains(where: { $0.hasPrefix("SCREEN \"Article\"") }) {
                header(&w, "Article", icon: "doc.richtext", tab: false)
                w.add(1, "IMAGE \"https://picsum.photos/seed/headline/1000/600\" height=220")
                w.add(1, "TITLE \(rq(ContentPacks.pack(.news).items[0].title))")
                w.add(1, "CAPTION \"By Jordan Lee · 8 min read\"")
                w.add(1, "TEXT \"Apple today introduced a new lineup with faster chips, brighter displays and all-day battery life. Here's everything you need to know about what's new and whether you should upgrade.\"")
                w.add(1, "HSTACK")
                w.add(2, "BUTTON \"Save\" icon=bookmark style=bordered -> toast \"Saved for later\"")
                w.add(2, "SHARE \"Share\" \"https://example.com/article\"")
            }
        case .leaderboard:
            header(&w, name, icon: "trophy.fill", tab: o.tab)
            w.add(1, "HSTACK")
            for (n, place) in [("PixelPanda", "2nd"), ("NovaStrike", "1st"), ("ByteRider", "3rd")] {
                w.add(2, "VSTACK align=center spacing=4")
                w.add(3, "AVATAR \(rq(n)) size=\(place == "1st" ? 72 : 56)")
                w.add(3, "BADGE \(rq(place))")
            }
            w.add(1, "SEGMENTED \"Daily,Weekly,All time\" bind=boardRange")
            w.add(1, "LIST")
            for it in ContentPacks.pack(.gaming).items { w.add(2, "ROW \(rq(it.title)) subtitle=\(rq(it.subtitle)) value=\(rq(it.value)) icon=\(it.icon)") }
        case .pricing:
            header(&w, name, icon: "crown.fill", tab: o.tab)
            w.add(1, "ICON crown.fill size=60 color=yellow center")
            w.add(1, "TEXT \"Go Pro\" style=largeTitle bold center")
            w.add(1, "CAPTION \"Unlock everything \(o.appName) can do.\" center")
            w.add(1, "LIST")
            for f in ["Unlimited projects", "Advanced insights", "Priority support", "Sync across devices"] { w.add(2, "ROW \(rq(f)) icon=checkmark.circle.fill color=green") }
            w.add(1, "SEGMENTED \"Monthly,Yearly\" bind=plan")
            w.add(1, "CARD")
            w.add(2, "TEXT \"{{plan == 'Yearly' ? '$39.99 / year' : '$4.99 / month'}}\" style=title2 bold")
            w.add(2, "CAPTION \"{{plan == 'Yearly' ? 'Save 33% · 7-day free trial' : 'Cancel anytime'}}\"")
            w.add(1, "BUTTON \"Start Free Trial\" style=prominent full -> haptic success; alert \"Welcome to Pro!\" \"Your trial starts today.\"")
            w.add(1, "BUTTON \"Restore purchases\" style=plain -> toast \"Nothing to restore\" \"info\"")
        case .faq:
            header(&w, name, icon: "questionmark.circle", tab: o.tab)
            let qa = [("How do I get started?", "Create an account, then follow the quick tour on the home screen."),
                      ("Is my data private?", "Yes. Your data stays on your device unless you choose to sync."),
                      ("How do I contact support?", "Use the Contact screen or email hello@example.com."),
                      ("Can I cancel anytime?", "Absolutely — manage your plan in Settings.")]
            for (q, a) in qa {
                w.add(1, "DISCLOSURE \(rq(q))")
                w.add(2, "TEXT \(rq(a)) color=secondaryText")
            }
            w.add(1, "BUTTON \"Still need help?\" style=bordered full -> go \"Contact\"")
        }
    }
}

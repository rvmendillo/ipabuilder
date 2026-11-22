import Foundation

public struct AppTemplate: Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let symbol: String
    public let colors: [String]
    public let category: String
    public let features: [String]
    let script: () -> String

    /// Builds a fresh project from the template (new ids every time).
    public func makeProject(named name: String? = nil) -> Project {
        let projectName = name ?? self.name
        var p = Project(name: projectName, templateID: id)
        let r = RFSCompiler.compile(script(), into: p)
        p = r.project
        p.templateID = id
        if let name = name { p.name = name; p.brand.displayName = name }
        p.bundleID = BundleID.suggest(for: p.brand.displayName)
        p.brand.icon.background = .linear(colors)
        if p.brand.icon.symbol == IconSpec().symbol { p.brand.icon.symbol = symbol }
        p.normalize()
        return p
    }
}

public enum Templates {
    public static let all: [AppTemplate] = [
        AppTemplate(id: "catalog", name: "iOS Component Catalog", summary: "Every native component — controls, inputs, charts, media, maps, layout — in a 5-tab app.",
                    symbol: "square.grid.3x3.fill", colors: ["#6C5CFF", "#FF7A45"], category: "Showcase",
                    features: ["53 components", "All button & picker styles", "Charts, gauges, maps", "Free layout canvas", "Logic examples"], script: { catalogScript }),
        domain("finance", .finance, "Finance Tracker", "Dashboard with KPIs and charts, live transactions, add-transaction form and settings.", ["Charts", "Forms", "Live list", "Onboarding + login"], login: true, onboarding: true),
        domain("fitness", .fitness, "Fitness & Activity", "Activity rings, workout timer, logging, history and profile.", ["Gauges", "Timer", "Logging", "Charts"]),
        domain("shop", .shopping, "Online Store", "Product grid, product detail with size & quantity, cart totals and checkout.", ["Product grid", "Cart math", "Checkout validation"]),
        domain("social", .social, "Social Feed", "Stories, post feed, comments, messaging and profile.", ["Feed", "Chat", "Profile grid"], widget: false),
        domain("tasks", .productivity, "Tasks & Notes", "Todo list with completion, notes with search, calendar and settings.", ["Todo logic", "Search filter", "Calendar"], widget: true),
        domain("weather", .weather, "Live Weather", "Real forecast from the Open-Meteo API with pull-to-refresh.", ["Live API", "Charts", "Map"]),
        domain("food", .food, "Restaurant & Delivery", "Menu grid, cart, checkout and table booking with reminders.", ["Booking", "Notifications", "Cart"]),
        domain("coffee", .coffee, "Coffee Rewards", "Loyalty dashboard, ordering, cart and a Home Screen widget.", ["Loyalty", "Ordering", "Widget"], widget: true),
        domain("music", .music, "Music Player", "Library, now playing with real audio, search and settings.", ["Audio", "Playlists", "Search"]),
        domain("travel", .travel, "Travel Planner", "Explore stays, trips, map and profile.", ["Grid", "Map", "Trips"]),
        domain("learning", .education, "Learning & Quiz", "Progress dashboard, courses and a scored quiz.", ["Quiz logic", "Progress", "Streaks"]),
        AppTemplate(id: "auth", name: "Onboarding & Login", summary: "Swipeable onboarding, validated login, sign up and a home screen.",
                    symbol: "person.badge.key.fill", colors: ["#4338CA", "#DB2777"], category: "Starters",
                    features: ["Page view", "Validation", "Sign in with Apple"], script: {
                        let pack = ContentPacks.pack(.generic)
                        var w = RFSWriter()
                        w.add(0, "APP name=\"Auth Starter\" preset=royal icon=person.badge.key.fill")
                        Recipes.build(.onboarding, pack: pack, options: RecipeOptions(screenName: "Welcome", appName: "Auth Starter", homeScreen: "Login"), into: &w)
                        Recipes.build(.login, pack: pack, options: RecipeOptions(screenName: "Login", appName: "Auth Starter", homeScreen: "Home"), into: &w)
                        Recipes.build(.dashboard, pack: pack, options: RecipeOptions(screenName: "Home", tab: true, appName: "Auth Starter"), into: &w)
                        Recipes.build(.settings, pack: pack, options: RecipeOptions(screenName: "Settings", tab: true, appName: "Auth Starter"), into: &w)
                        w.add(0, "SCREEN \"Welcome\" home")
                        return w.text
                    }),
        AppTemplate(id: "settings", name: "Settings & Profile", summary: "iOS Settings-style grouped form, profile with edit sheet, help center.",
                    symbol: "gearshape.2.fill", colors: ["#8E8E93", "#3A3A3C"], category: "Starters",
                    features: ["Grouped form", "Pickers", "Confirm dialogs"], script: {
                        let pack = ContentPacks.pack(.generic)
                        var w = RFSWriter()
                        w.add(0, "APP name=\"Preferences\" preset=mono icon=gearshape.2.fill")
                        Recipes.build(.settings, pack: pack, options: RecipeOptions(screenName: "Settings", tab: true, appName: "Preferences"), into: &w)
                        Recipes.build(.profile, pack: pack, options: RecipeOptions(screenName: "Profile", tab: true, appName: "Preferences"), into: &w)
                        Recipes.build(.faq, pack: pack, options: RecipeOptions(screenName: "Help", tab: true, appName: "Preferences"), into: &w)
                        Recipes.build(.contact, pack: pack, options: RecipeOptions(screenName: "Contact", appName: "Preferences"), into: &w)
                        return w.text
                    }),
        AppTemplate(id: "widget", name: "Widget Starter", summary: "A simple app with a counter and a Home Screen widget.",
                    symbol: "rectangle.3.group.fill", colors: ["#00B894", "#00CEC9"], category: "Starters",
                    features: ["WidgetKit", "Counter logic", "Persistence"], script: {
                        """
                        APP name="Glance" preset=mint icon=rectangle.3.group.fill
                        VAR count number 0 persist
                        SCREEN "Home" icon=house.fill
                          CARD align=center
                            ICON "sparkles" size=56 color=accent effect=bounce
                            TEXT "{{count}}" fontsize=64 bold center
                            CAPTION "Taps saved on this device" center
                          HSTACK
                            BUTTON "−" style=bordered -> dec count; haptic light
                            BUTTON "+" style=prominent -> inc count; haptic light
                          BUTTON "Reset" style=plain -> set count = 0
                          CARD
                            HEADING "Add the widget"
                            TEXT "Install the app, then long-press your Home Screen, tap + and search for Glance."
                        WIDGET name="Glance" title="Glance" value="42" subtitle="Taps today" symbol=sparkles family=small layout=stat
                        """
                    }),
        AppTemplate(id: "blank", name: "Blank App", summary: "An empty screen — build it with the AI or the component library.",
                    symbol: "plus.app.fill", colors: ["#6C5CFF", "#A855F7"], category: "Starters", features: ["Start from scratch"], script: {
                        "SCREEN \"Home\" icon=house.fill\n  TITLE \"Hello!\"\n  TEXT \"Tap + to add components, or ask ReyForge AI to build something.\" color=secondaryText"
                    }),
    ]

    static func domain(_ id: String, _ d: Domain, _ name: String, _ summary: String, _ features: [String], login: Bool = false, onboarding: Bool = false, widget: Bool = false) -> AppTemplate {
        let pack = ContentPacks.pack(d)
        let preset = ThemePresets.named(pack.presetID)
        return AppTemplate(id: id, name: name, summary: summary, symbol: pack.symbol, colors: preset?.iconBackground ?? ["#6C5CFF", "#FF7A45"],
                           category: "Apps", features: features, script: {
            var s = Recipes.app(pack: pack, includeLogin: login, includeOnboarding: onboarding)
            if onboarding { s += "\nSCREEN \"Welcome\" home" }
            if widget {
                let stat = pack.stats.first
                s += "\nWIDGET name=\(rq(pack.appName)) title=\(rq(stat?.title ?? pack.appName)) value=\(rq(stat?.value ?? "")) subtitle=\(rq(pack.summary)) symbol=\(stat?.icon ?? pack.symbol) family=small layout=stat"
            }
            return s
        })
    }

    public static func template(_ id: String) -> AppTemplate? { all.first { $0.id == id } }

    // MARK: Component catalog

    static let catalogScript = #"""
    APP name="Catalog" preset=forge icon=square.grid.3x3.fill tagline="Every native iOS component"
    VAR taps number 0
    VAR volume number 60
    VAR brightness number 0.4
    VAR guests number 2
    VAR wifi bool true
    VAR rating number 4
    VAR plan text "Pro"
    VAR size text "M"
    VAR flavor text "Vanilla"
    VAR day date
    VAR tint color "#6C5CFF"
    VAR photo image
    VAR name text
    VAR email text
    VAR password text
    VAR notes text
    VAR query text
    VAR fruits list ["Apple", "Banana", "Cherry", "Mango", "Peach"]
    VAR progress number 0.65
    SCREEN "Controls" icon=switch.2 tab
      TOOLBAR icon=plus.circle.fill -> toast "Toolbar button tapped"
      HEADING "Buttons"
      BUTTON "Prominent" icon=star.fill style=prominent -> inc taps; haptic success; toast "Tapped {{taps}} times"
      HSTACK
        BUTTON "Bordered" style=bordered size=regular -> toast "Bordered"
        BUTTON "Capsule" style=capsule size=regular -> toast "Capsule"
      HSTACK
        BUTTON "Plain" style=plain size=regular -> toast "Plain"
        BUTTON "Borderless" icon=link style=borderless size=regular -> toast "Borderless"
      BUTTON "Liquid Glass" icon=drop.fill style=glass -> haptic light
      BUTTON "Delete" icon=trash style=destructive -> confirm "Delete everything?" "This can't be undone." { toast "Deleted" "warning" }
      BUTTON "Show alert" icon=exclamationmark.bubble style=bordered -> alert "Hello from ReyForge" "Alerts, confirmations and toasts are built in."
      MENU "Menu" icon=ellipsis.circle
        BUTTON "Copy" icon=doc.on.doc -> copy "Copied from ReyForge"
        BUTTON "Share" icon=square.and.arrow.up -> share "Made with ReyForge"
        BUTTON "Remove" icon=trash style=destructive -> toast "Removed" "warning"
      SHARE "Share Link" "https://github.com/rvmendillo/ipabuilder"
      APPLE -> haptic success; toast "Signed in with Apple"
      HEADING "Toggles & sliders"
      TOGGLE "Wi-Fi" bind=wifi icon=wifi
      TOGGLE "Checkbox style" bind=agree variant=checkbox off
      TOGGLE "Button style" bind=bold variant=button off
      SLIDER "Volume" bind=volume min=0 max=100
      SLIDER "Brightness" bind=brightness min=0 max=1 step=0 minSymbol=sun.min maxSymbol=sun.max.fill
      STEPPER "Guests" bind=guests min=1 max=10 format="{{value}} guests"
      TEXT "Wi-Fi is {{wifi ? 'on' : 'off'}} · volume {{volume}} · {{guests}} guests" color=secondaryText
    SCREEN "Inputs" icon=character.cursor.ibeam tab
      FORM
        SECTION "Text" footer="Fields bind to variables you can use anywhere with {{name}}."
          FIELD "Name" bind=name icon=person
          FIELD "Email" bind=email keyboard=email variant=rounded
          SECURE "Password" bind=password
          EDITOR "Notes" bind=notes height=100
        SECTION "Pickers"
          PICKER "Plan" "Free,Pro,Team" bind=plan style=segmented
          PICKER "Size" "S,M,L,XL" bind=size style=menu
          PICKER "Flavor" "Vanilla,Chocolate,Strawberry,Mint" bind=flavor style=wheel
          PICKER "Inline" "One,Two,Three" bind=inlineChoice style=inline
        SECTION "Dates & colors"
          DATE "Date" bind=day
          DATE "Time" bind=meeting mode=time
          COLOR "Tint" bind=tint
          PHOTO "Pick a photo" bind=photo
      SEARCH "Search fruits" bind=query
      LIST source="filter(fruits, query)"
        ROW "{{item}}" icon=leaf.fill
      DATE "Calendar" bind=day style=graphical
      BUTTON "Submit" icon=paperplane.fill style=prominent full -> validate isNotEmpty(name) "Enter your name"; validate isEmail(email) "Enter a valid email"; haptic success; alert "Thanks, {{name}}!" "We'll write to {{email}}."
    SCREEN "Data" icon=chart.bar.xaxis tab
      GRID columns=2
        STAT "Revenue" "$48.2K" icon=chart.line.uptrend.xyaxis delta="+12%"
        STAT "Users" "12,840" icon=person.2.fill delta="+5.4%" color=green
        STAT "Churn" "2.1%" icon=arrow.down.right delta="-0.3%" color=orange
        STAT "Rating" "4.9" icon=star.fill delta="+0.1" color=yellow
      CARD
        HEADING "Bar chart"
        CHART bar "Mon:4,Tue:7,Wed:5,Thu:9,Fri:6,Sat:11,Sun:8" height=160
      CARD
        HEADING "Line & area"
        CHART line "Jan:12,Feb:18,Mar:15,Apr:24,May:30,Jun:28" height=140 color=pink
        CHART area "Q1:20,Q2:35,Q3:28,Q4:44" height=120 color=teal
      HSTACK
        CARD
          HEADING "Pie"
          CHART pie "Rent:45,Food:25,Fun:15,Other:15" height=140
        CARD
          HEADING "Donut"
          CHART donut "iOS:62,Android:30,Web:8" height=140
      CARD
        HEADING "Points"
        CHART point "1:3,2:5,3:4,4:8,5:7,6:10" height=120 color=indigo
      HEADING "Gauges"
      HSTACK
        GAUGE "Battery" value=72 max=100 variant=circularCapacity
        GAUGE "Speed" value=45 max=120 variant=circular color=orange
        GAUGE "Temp" value=21 min=-10 max=40 variant=circular color=red symbol=thermometer.medium
      GAUGE "Storage" value=0.7 max=1 variant=linearCapacity color=purple
      GAUGE "Signal" value=3 max=5 variant=linear color=green
      HEADING "Progress"
      PROGRESS "Download" value="{{progress}}"
      PROGRESS "Uploading" value=0.35 circular
      PROGRESS "Loading" value=""
      BUTTON "Advance progress" style=bordered -> set progress = progress >= 1 ? 0 : round(progress + 0.1, 2)
      RATING value=4 bind=rating
      TEXT "You rated {{rating}} / 5" color=secondaryText
      TIMER 90
      HSTACK
        BADGE "New" variant=filled
        BADGE "Beta" color=orange
        BADGE "Sale" color=red variant=outlined
        BADGE "Pro" icon=crown.fill color=purple
      EMPTY "No Messages" icon=tray message="New messages will appear here." actionTitle="Refresh"
    SCREEN "Media" icon=photo.on.rectangle tab
      IMAGE "https://picsum.photos/seed/catalog/1000/600" height=200 overlayText="Remote image"
      HSTACK
        IMAGE "symbol:mountain.2.fill" height=90 fit
        AVATAR "Rey Mendillo" size=64 status=online
        AVATAR "Ana Cruz" image=https://picsum.photos/seed/ana/200/200 size=64 status=away
      HEADING "SF Symbols"
      HSTACK
        ICON "heart.fill" size=36 color=red effect=pulse
        ICON "wifi" size=36 effect=variableColor
        ICON "cloud.sun.rain.fill" size=36 renderingMode=multicolor
        ICON "bell.badge.fill" size=36 effect=bounce renderingMode=palette secondaryColor=orange
        ICON "gearshape.fill" size=36 color=gray effect=wiggle
      LABEL "Favorites" "star.fill" color=yellow
      LABEL "Downloads" "arrow.down.circle.fill"
      VIDEO "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8" height=210
      AUDIO "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3" "Sample Song" artist="SoundHelix"
      MAP "Apple Park" height=200 markers="Apple Park:37.3349,-122.009;Infinite Loop:37.3318,-122.0312"
      WEB "https://www.apple.com/ios/" height=320
      QR "https://github.com/rvmendillo/ipabuilder" size=160
      LINK "Open apple.com" "https://www.apple.com" icon=safari
    SCREEN "Layout" icon=square.split.2x2 tab
      TITLE "Text styles"
      TEXT "Large Title" style=largeTitle
      TEXT "Title 2" style=title2
      TEXT "Headline" style=headline
      TEXT "Body with **Markdown** and _italics_"
      TEXT "Footnote" style=footnote color=secondaryText
      TEXT "Rounded monospaced 123" design=monospaced
      DIVIDER
      HEADING "Stacks"
      HSTACK
        CARD
          ICON "leaf.fill" size=24 color=green
          TEXT "HStack" bold
        CARD
          ICON "drop.fill" size=24 color=blue
          TEXT "Cards" bold
      HEADING "Free layout (drag children anywhere)"
      ZSTACK height=220
        GRADIENT "#6C5CFF,#FF7A45" width=360 height=220 radius=20
        CIRCLE color=white opacity=0.3 width=120 height=120 x=230 y=-20
        TEXT "Positioned" style=title2 bold color=white x=20 y=30
        BADGE "x: 20 · y: 150" x=20 y=150
      HEADING "Carousel"
      SCROLL horizontal paging
        IMAGE "https://picsum.photos/seed/c1/600/400" width=260 height=160
        IMAGE "https://picsum.photos/seed/c2/600/400" width=260 height=160
        IMAGE "https://picsum.photos/seed/c3/600/400" width=260 height=160
      HEADING "Grid"
      GRID columns=3
        SHAPE circle color=pink width=80 height=80
        SHAPE capsule color=orange width=100 height=44
        SHAPE rounded color=teal width=90 height=70
        SHAPE rectangle color=indigo width=80 height=80
        SHAPE ellipse color=yellow width=100 height=60
        SHAPE rounded color=clear stroke=accent width=90 height=70
      GRADIENT "pink,purple" kind=radial height=100
      GRADIENT "cyan,blue,indigo,purple" kind=angular height=100
      HEADING "Page view"
      PAGER height=200
        VSTACK align=center
          ICON "1.circle.fill" size=48 color=accent
          TEXT "Swipe" bold
        VSTACK align=center
          ICON "2.circle.fill" size=48 color=accent
          TEXT "through" bold
        VSTACK align=center
          ICON "3.circle.fill" size=48 color=accent
          TEXT "pages" bold
      GROUP "Group Box" icon=shippingbox
        TEXT "Native GroupBox container."
      DISCLOSURE "Disclosure group"
        TEXT "Tap the header to collapse me again." color=secondaryText
      LIST header="List" footer="Rows support swipe actions and navigation."
        ROW "Wi-Fi" value="Home" icon=wifi chevron
        ROW "Bluetooth" value="On" icon=antenna.radiowaves.left.and.right color=blue
        ROW "Swipe to delete" subtitle="Try it in Preview" icon=trash color=red ondelete="toast \"Deleted\" \"warning\""
        NAVLINK "About this catalog" "About" icon=info.circle.fill
        INFO "Version" "3.0"
      SECTION "Section" footer="Sections also work outside forms."
        INFO "Components" "53"
        INFO "Made with" "ReyForge"
      SPACER 24
    SCREEN "About" icon=info.circle.fill
      ICON "square.grid.3x3.fill" size=64 color=accent center
      TITLE "Component Catalog" center
      TEXT "Every element here is a real native SwiftUI view rendered from ReyForge's project model. Select anything in the editor to change its properties, style, layout and logic." center color=secondaryText
      BUTTON "Back to the catalog" style=bordered -> back
    """#
}

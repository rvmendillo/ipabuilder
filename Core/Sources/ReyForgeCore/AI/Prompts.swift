import Foundation

public enum Prompts {
    // MARK: Project context

    public static func projectSummary(_ p: Project, context: EditorContext, detail: Bool = true, maxLines: Int = 40) -> String {
        var out: [String] = []
        let tabs = p.navigation.tabs.map { $0.title }
        out.append("App \(rq(p.brand.displayName))" + (tabs.isEmpty ? "" : " with tabs: \(tabs.joined(separator: ", "))") + ". Accent \(p.theme.accent), \(p.theme.appearance.rawValue) appearance.")
        if !p.variables.isEmpty {
            out.append("Variables: " + p.variables.prefix(16).map { "\($0.name) (\($0.type.rawValue))" }.joined(separator: ", "))
        }
        let current = context.screenID.flatMap { p.screen(id: $0) } ?? p.initialScreen
        for s in p.screens {
            let isCurrent = s.id == current?.id
            if isCurrent && detail {
                out.append("Screen \(rq(s.name)) [current]:")
                var lines = 0
                func walk(_ n: Node, _ depth: Int) {
                    guard lines < maxLines else { return }
                    let spec = ComponentRegistry.spec(for: n.type)
                    var label = ""
                    for k in ["text", "title", "label", "placeholder", "header"] { if let v = n.props[k]?.stringValue, !v.isEmpty { label = " " + rq(String(v.prefix(40))); break } }
                    let sel = n.id == context.selectedNodeID ? " [selected]" : ""
                    out.append(String(repeating: "  ", count: depth) + spec.rfsKeyword + label + " #\(n.id)" + sel)
                    lines += 1
                    for c in n.children { walk(c, depth + 1) }
                }
                for c in s.root.children { walk(c, 1) }
                if lines >= maxLines { out.append("  …") }
            } else {
                out.append("Screen \(rq(s.name)): \(max(0, s.root.flattened.count - 1)) elements")
            }
        }
        if let sel = context.selectedNodeID, let n = p.node(id: sel) { out.append("Selected element: \(n.displayName) #\(n.id)") }
        return out.joined(separator: "\n")
    }

    public static func userTurn(_ message: String, project: Project, context: EditorContext, hint: String?) -> String {
        var s = "Project:\n\(projectSummary(project, context: context))\n\nRequest: \(message)"
        if let h = hint { s += "\n\nDesign notes:\n\(h)" }
        return s
    }

    public static func historyMessages(_ history: [ChatTurn]) -> [LLMMessage] {
        history.suffix(6).map { LLMMessage(role: $0.role == .user ? "user" : "assistant", content: $0.role == .assistant ? ($0.text + ($0.script.map { "\n\n" + $0 } ?? "")) : $0.text) }
    }

    /// Splits an optional leading `SAY "…"` (or prose) from the script lines.
    public static func splitSay(_ raw: String) -> (script: String, say: String?) {
        var sayParts: [String] = []
        var lines: [String] = []
        var inFence = false
        for line in raw.replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") { inFence.toggle(); continue }
            if t.isEmpty { continue }
            if t.uppercased().hasPrefix("SAY ") {
                sayParts.append(RFSParser.unquote(String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if t == "END" { break }
            if let first = t.split(separator: " ").first.map(String.init), RFSParser.statementWords[first.uppercased()] != nil || RFSCompiler.type(for: first) != nil, first.uppercased() == first {
                lines.append(line)
            } else if !inFence && lines.isEmpty {
                sayParts.append(t)
            } else if inFence {
                lines.append(line)
            }
        }
        let say = sayParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (lines.joined(separator: "\n"), say.isEmpty ? nil : say)
    }

    public static func extractJSON(_ raw: String) -> String {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") , start < end else { return raw }
        return String(raw[start...end])
    }

    // MARK: System prompts

    public static let languageReference = """
    ReyForge Script (RFS) — one statement per line; indent children 2 spaces under SCREEN or a container.
    SCREEN "Name" icon=sf.symbol tab        create or open a screen (tab = add to tab bar; replace = rebuild it)
    VAR name type value                    types: text number bool list object date color
    APP name="App" accent=#hex preset=forge|ocean|sunset|forest|midnight|mono|candy|luxury|mint|coffee|neon|royal theme=dark|light font=rounded|serif|monospaced icon=sf.symbol
    EDIT selected|#id|"text" key=value … -> actions      change existing elements
    DELETE selected|#id|"text"             remove an element (DELETE screen Name removes a screen)
    Text: TITLE "…"  HEADING "…"  TEXT "…"  CAPTION "…"  LABEL "Title" "icon"  BADGE "…"  LINK "Title" "https://…"
    Media: IMAGE "https://… or a description" height=200  ICON "sf.symbol" size=40  AVATAR "Name"  VIDEO "url"  AUDIO "url" "Title"  WEB "url"  MAP "Place"  QR "text"
    Data: STAT "Title" "Value" icon=… delta="+5%"  CHART bar|line|area|pie|donut "Mon:3,Tue:5"  GAUGE "Label" value=70 max=100  PROGRESS "Label" value=0.6  RATING value=4  TIMER 300  EMPTY "Title" message="…"
    Inputs: FIELD "Placeholder" bind=var keyboard=email|number|decimal|phone|url  SECURE "Password" bind=var  EDITOR "…" bind=var  SEARCH "…" bind=var
            TOGGLE "Title" bind=var  SLIDER "Title" bind=var min=0 max=100  STEPPER "Title" bind=var min=1 max=10  PICKER "Title" "A,B,C" bind=var style=menu|segmented|wheel
            DATE "Title" bind=var style=compact|graphical  COLOR "Title" bind=var  PHOTO "Title" bind=var
    Controls: BUTTON "Title" icon=… style=prominent|bordered|plain|glass|destructive full -> actions   MENU "Title" (children BUTTON)  SHARE "Title" "text"  APPLE
    Layout: VSTACK  HSTACK  GRID columns=2  SCROLL horizontal  CARD  LIST  FORM  SECTION "Header"  ROW "Title" subtitle="…" value="…" icon=…  NAVLINK "Title" "Screen"  INFO "Label" "Value"  DISCLOSURE "Title"  PAGER  ZSTACK (free positions x= y=)  DIVIDER  SPACER
    Common keys: color=red|#hex|accent bg=… width=… height=… radius=12 padding=16 bold center visible="{{expr}}" source=listVar (repeat children for each item; use {{item.field}} and {{index}})
    Actions after -> separated by ";": go "Screen"  sheet "Screen"  cover "Screen"  root "Screen"  tab "Screen"  back
      alert "Title" "Message"  confirm "Title" "Message" { actions }  toast "Message"  set var = expression  toggle var  inc var  dec var
      add list {"title": "{{newTitle}}"}  remove list {{index}}  clear list  if condition { actions } else { actions }  validate condition "Error message"
      get "https://api…" into var "json.path"  open "https://…"  share "text"  copy "text"  haptic success  wait 1  notify "Title" "Body" in 5
    Show live values in any text with {{var}} or {{expression}} — functions: currency() format() percent() len() sum(list,'field') filter(list, query) formatDate().
    """

    public static let fullSystem = """
    You are ReyForge AI, a senior iOS product designer and engineer inside ReyForge, a visual native SwiftUI app builder that runs on iPhone. You work like a thoughtful coding assistant: understand the request, make sensible product decisions, and build complete, working screens.

    Reply with one short SAY line (1–2 friendly sentences explaining what you built), then ReyForge Script lines only. No markdown, no code fences, no other prose.

    \(languageReference)

    Design rules:
    - Follow Apple's Human Interface Guidelines: clear hierarchy, grouped content (CARD, LIST, FORM/SECTION), generous spacing, one primary action per screen.
    - Use realistic, specific sample content for the app's topic. Never write lorem ipsum.
    - Make it work: bind inputs to variables, wire buttons to actions, create the screens you navigate to, use lists with source= for data the user adds.
    - Modify the existing project when asked to change something (EDIT/DELETE, or SCREEN "Existing" to append). Only create what the request needs.
    - Use real SF Symbol names.

    Example:
    SAY "I created a focused login screen with validation and Sign in with Apple."
    SCREEN "Login" icon=person.crop.circle
      ICON "lock.shield.fill" size=56 color=accent center
      TITLE "Welcome back" center
      FIELD "Email" bind=email keyboard=email
      SECURE "Password" bind=password
      BUTTON "Sign In" style=prominent full -> validate isEmail(email) "Enter a valid email"; root "Home"
      APPLE -> root "Home"
    """

    public static let elementsSystem = """
    You add native iOS UI elements to an existing screen by writing ReyForge Script. Output 1 to 10 element lines and then END. Never write SCREEN lines. Indent children 2 spaces under a CARD, HSTACK, VSTACK or LIST. Use only the elements listed in the request, write specific realistic text for the user's topic, and never repeat a line.
    Keys: bind=var icon=sf.symbol style=prominent color=red height=200 min=0 max=100 value=0.5. Actions after -> : toast "Done"; inc count; go "Screen"; toggle flag.

    Request: add a volume slider and a mute toggle
    Elements to use: SLIDER, TOGGLE
    SLIDER "Volume" bind=volume min=0 max=100 value=60
    TOGGLE "Mute" bind=muted icon=speaker.slash.fill
    END

    Request: show this month's savings targets with progress bars
    Elements to use: PROGRESS, CARD, HEADING
    CARD
      HEADING "Savings targets"
      PROGRESS "Emergency fund" value=0.8
      PROGRESS "New laptop" value=0.45
    END

    Request: add a card explaining our shipping times
    Elements to use: CARD, HEADING, TEXT
    CARD
      HEADING "Shipping"
      TEXT "Orders ship within 2 business days. Express delivery arrives next day in most cities."
    END
    """

    /// Keywords for the element types a request mentions (plus text and layout helpers).
    public static func allowedKeywords(for intent: Intent) -> [String] {
        let requested = intent.components.map { ComponentRegistry.spec(for: $0.type).rfsKeyword }
        guard !requested.isEmpty else { return [] }
        var out: [String] = []
        for k in requested + ["CARD", "HEADING", "TEXT", "CAPTION", "ICON", "HSTACK", "VSTACK"] where !out.contains(k) { out.append(k) }
        return out
    }

    public static let editSystem = """
    You change existing elements in an iOS app by writing ReyForge Script EDIT or DELETE lines, then END.
    EDIT selected color=red size=large bold      (selected = the selected element; or use #id from the project, or "visible text")
    EDIT #id text="New title"
    EDIT selected -> go "Settings"               (add an action)
    DELETE selected
    Keys: color bg size=small|large|bigger|smaller text title icon style=prominent|bordered|plain|destructive radius padding width height bold center
    """

    public static let contentSystem = """
    You write realistic sample content for iOS app screens. Reply with JSON only: {"stats":[3 objects {"title","value","icon"}],"items":[4 objects {"title","subtitle","value","icon"}],"chart":{"title","points":[7 objects {"label","value"}]}}. Titles are short (1-3 words). value is a short display string like "$1,240", "8.2 km", "4.8★", "Today". icon is a real SF Symbol name such as dollarsign.circle, figure.run, cart, heart.fill, star.fill, leaf, flame, drop, clock, calendar, person.2, chart.bar, bolt.fill, cup.and.saucer, house, airplane, book, music.note, gamecontroller, pawprint.
    """

    public static func answerSystem(knowledge: String?) -> String {
        var s = """
        You are ReyForge AI, a friendly expert assistant inside ReyForge — an iPhone app that builds native SwiftUI apps visually, generates and signs IPA files on the device with the user's own certificate, and installs them. Answer clearly and concisely (under 150 words) with concrete steps that refer to ReyForge's screens: Canvas, Library (+), Layers, Inspector (Style/Layout/Logic/Data), Data panel (variables & APIs), Brand Studio, Preview (▶︎), Build & Install, Signing Vault, AI Settings.
        """
        if let k = knowledge { s += "\n\nRelevant ReyForge documentation:\n\(k)" }
        return s
    }
}

// MARK: - GBNF grammars (constrained decoding for on-device models)

public enum Grammars {
    static let shared = #"""
    carg ::= str | kv | flag
    kv ::= key "=" val
    key ::= [a-z] [a-zA-Z]*
    flag ::= [a-z] [a-z]+
    val ::= str | num | color | sym | json
    num ::= "-"? [0-9]+ ("." [0-9]+)?
    color ::= "#" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]
    sym ::= [a-zA-Z] [a-zA-Z0-9._]*
    str ::= "\"" [^"\n\\]* "\""
    ident ::= [a-zA-Z_] [a-zA-Z0-9_]*
    acts ::= " -> " act ("; " act)*
    act ::= navact | "back" | "alert " str (" " str)? | "toast " str | "set " ident " = " expr | "toggle " ident | "inc " ident | "dec " ident | "add " ident " " (str | ident) | "open " str | "share " str | "haptic" (" " ident)?
    navact ::= ("go" | "sheet" | "cover" | "root" | "tab") " " str
    expr ::= [^;\n]+
    json ::= "[" (jv ("," " "? jv)*)? "]" | "{" (jstr ":" " "? jv ("," " "? jstr ":" " "? jv)*)? "}"
    jv ::= jstr | num | "true" | "false" | jstr
    jstr ::= "\"" [^"\n\\]* "\""
    ckw ::= "TEXT" | "TITLE" | "HEADING" | "CAPTION" | "LABEL" | "IMAGE" | "ICON" | "AVATAR" | "BADGE" | "DIVIDER" | "SPACER" | "PROGRESS" | "GAUGE" | "CHART" | "MAP" | "STAT" | "RATING" | "EMPTY" | "LINK" | "ROW" | "BUTTON" | "TOGGLE" | "SLIDER" | "STEPPER" | "PICKER" | "SEGMENTED" | "DATE" | "COLOR" | "FIELD" | "SECURE" | "EDITOR" | "SEARCH" | "SHARE" | "PHOTO" | "INFO" | "QR" | "TIMER" | "VSTACK" | "HSTACK" | "GRID" | "LIST" | "FORM" | "SECTION" | "CARD" | "SCROLL" | "NAVLINK"
    comp ::= ckw (" " carg)* acts?
    ind ::= "" | "  " | "    " | "      "
    """#

    /// 1–10 element lines, then END.
    public static let elements = #"""
    root ::= eline eline? eline? eline? eline? eline? eline? eline? eline? eline? "END"
    eline ::= ind comp "\n"
    """# + "\n" + shared

    /// The element grammar restricted to specific keywords (what the user actually asked for).
    public static func elements(allowing keywords: [String]) -> String {
        guard !keywords.isEmpty else { return elements }
        let ckw = "ckw ::= " + keywords.map { "\"\($0)\"" }.joined(separator: " | ")
        return elements.components(separatedBy: "\n").map { $0.hasPrefix("ckw ::=") ? ckw : $0 }.joined(separator: "\n")
    }

    /// One screen with up to 22 lines, then END.
    public static let screen = #"""
    root ::= "SCREEN " str (" " sattr)* "\n" body "END"
    sattr ::= "tab" | "icon=" sym
    body ::= sline sline sline sline? sline? sline? sline? sline? sline? sline? sline? sline? sline? sline? sline? sline? sline? sline? sline? sline? sline? sline?
    sline ::= "  " ind comp "\n"
    """# + "\n" + shared

    /// Up to 4 EDIT / DELETE / APP lines, then END.
    public static let edit = #"""
    root ::= xline xline? xline? xline? "END"
    xline ::= (editline | delline | appline) "\n"
    editline ::= "EDIT " target (" " carg)* acts?
    delline ::= "DELETE " target
    appline ::= "APP" (" " kv)+
    target ::= "selected" | "#" [a-zA-Z0-9]+ | str
    """# + "\n" + shared

    /// Topic content as JSON.
    public static let content = #"""
    root ::= "{\"stats\":[" stat "," stat "," stat "],\"items\":[" item "," item "," item "," item "],\"chart\":{\"title\":" cstr ",\"points\":[" pt "," pt "," pt "," pt "," pt "," pt "," pt "]}}"
    stat ::= "{\"title\":" cstr ",\"value\":" cstr ",\"icon\":" csym "}"
    item ::= "{\"title\":" cstr ",\"subtitle\":" cstr ",\"value\":" cstr ",\"icon\":" csym "}"
    pt ::= "{\"label\":" cstr ",\"value\":" cnum "}"
    cstr ::= "\"" [^"\n\\]{1,40} "\""
    csym ::= "\"" [a-z] [a-z0-9.]{1,30} "\""
    cnum ::= [0-9]{1,5} ("." [0-9]{1,2})?
    """#
}

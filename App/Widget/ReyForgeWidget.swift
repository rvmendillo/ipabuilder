import WidgetKit
import SwiftUI
import ReyForgeCore

struct WidgetEntry: TimelineEntry {
    let date: Date
    let project: Project
}

enum WidgetProject {
    static func load() -> Project {
        if let url = Bundle.main.url(forResource: "ReyForgeProject", withExtension: "json"), let data = try? Data(contentsOf: url), let p = try? Project.decode(data) {
            return p
        }
        var p = Project(name: "ReyForge")
        p.widget.enabled = true
        p.widget.title = "ReyForge"
        p.widget.value = "3.0"
        p.widget.subtitle = "Build apps on iPhone"
        return p
    }
}

struct WidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry { WidgetEntry(date: Date(), project: WidgetProject.load()) }
    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) { completion(WidgetEntry(date: Date(), project: WidgetProject.load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = WidgetEntry(date: Date(), project: WidgetProject.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct ReyForgeWidgetView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let w = entry.project.widget
        let palette = ThemePalette(theme: entry.project.theme, dark: false)
        let fg = palette.color(w.foreground, fallback: .white)
        let scheme = "rf" + BundleID.slug(entry.project.bundleID).prefix(24)
        Group {
            switch w.layout {
            case .list:
                VStack(alignment: .leading, spacing: 6) {
                    Label(w.title, systemImage: w.symbol).font(.headline)
                    ForEach(Array((w.items.isEmpty ? ["First item", "Second item", "Third item"] : w.items).prefix(family == .systemLarge ? 8 : 3).enumerated()), id: \.offset) { _, item in
                        HStack { Circle().frame(width: 6, height: 6); Text(item).font(.subheadline).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                }
            case .quote:
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "quote.opening").font(.title2)
                    Text(w.value).font(.system(.title3, design: .serif)).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                    Text(w.subtitle).font(.caption).opacity(0.8)
                }
            case .progress:
                VStack(alignment: .leading, spacing: 10) {
                    Label(w.title, systemImage: w.symbol).font(.headline)
                    Gauge(value: min(max(w.progress, 0), 1)) { Text(w.title) } currentValueLabel: { Text("\(Int(w.progress * 100))%") }
                        .gaugeStyle(.accessoryCircularCapacity).tint(fg)
                    Text(w.subtitle).font(.caption).opacity(0.85)
                }
            case .stat:
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: w.symbol).font(.title2.weight(.semibold))
                    Spacer(minLength: 0)
                    Text(w.value).font(.system(size: family == .systemSmall ? 34 : 44, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                    Text(w.title).font(.headline).lineLimit(1)
                    Text(w.subtitle).font(.caption).opacity(0.8).lineLimit(2)
                }
            }
        }
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { palette.fill(w.background) }
        .widgetURL(URL(string: "\(scheme)://screen/\(w.deepLinkScreenID ?? entry.project.initialScreen?.id ?? "home")"))
    }
}

struct ReyForgeWidget: Widget {
    let kind = "ReyForgeWidget"
    var body: some WidgetConfiguration {
        let project = WidgetProject.load()
        let families: [WidgetFamily] = {
            switch project.widget.family {
            case .small: return [.systemSmall, .systemMedium]
            case .medium: return [.systemMedium, .systemSmall]
            case .large: return [.systemLarge, .systemMedium]
            }
        }()
        return StaticConfiguration(kind: kind, provider: WidgetProvider()) { entry in
            ReyForgeWidgetView(entry: entry)
        }
        .configurationDisplayName(project.widget.name)
        .description(project.widget.summary)
        .supportedFamilies(families)
    }
}

@main
struct ReyForgeWidgetBundle: WidgetBundle {
    var body: some Widget { ReyForgeWidget() }
}

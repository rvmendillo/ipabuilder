import SwiftUI
import ReyForgeCore

/// All native components. Tap to add next to the selection, or press-and-drag onto the canvas.
struct LibraryPanel: View {
    @ObservedObject var editor: EditorModel
    @State private var query = ""
    @State private var category: ComponentCategory?

    var specs: [ComponentSpec] {
        let base = query.isEmpty ? ComponentRegistry.all : ComponentRegistry.search(query)
        guard let c = category else { return base }
        return base.filter { $0.category == c }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search 53 components", text: $query)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("library.search")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(nil, "All", "square.grid.2x2")
                    ForEach(ComponentCategory.allCases, id: \.self) { c in chip(c, c.rawValue, c.symbol) }
                }
                .padding(.horizontal, 12)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                    ForEach(specs, id: \.type) { spec in
                        LibraryTile(spec: spec, editor: editor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            Text(editor.selectedNode.map { "Adds \(ComponentRegistry.spec(for: $0.type).isContainer ? "inside" : "after") “\($0.displayName)” · press and drag to place" } ?? "Tap to add · press and drag onto the canvas")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                .padding(.bottom, 6)
        }
        .padding(.top, 8)
    }

    func chip(_ c: ComponentCategory?, _ title: String, _ symbol: String) -> some View {
        Button { withAnimation(.snappy) { category = c } } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(category == c ? Color.accentColor : Color(.secondarySystemBackground)))
                .foregroundStyle(category == c ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct LibraryTile: View {
    let spec: ComponentSpec
    @ObservedObject var editor: EditorModel
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: spec.symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(height: 26)
            Text(spec.title)
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.accentColor.opacity(dragging ? 0.8 : 0), lineWidth: 2))
        .opacity(dragging ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { editor.addComponent(spec.type) }
        .gesture(
            LongPressGesture(minimumDuration: 0.2)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                .onChanged { value in
                    switch value {
                    case .second(true, let drag):
                        if !dragging { dragging = true; Haptics.selection() }
                        if let d = drag { editor.libraryDragChanged(spec.type, location: d.location) }
                    default: break
                    }
                }
                .onEnded { value in
                    if case .second(true, let drag?) = value { editor.libraryDragEnded(spec.type, location: drag.location) }
                    dragging = false
                    editor.dragGhost = nil
                    editor.dropIndicator = nil
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Add \(spec.title)")
        .accessibilityIdentifier("library.\(spec.type.rawValue)")
    }
}

import SwiftUI
import MapKit
import WebKit
import AVKit
import CoreImage.CIFilterBuiltins
import ReyForgeCore

struct MapNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @State private var position: MapCameraPosition = .automatic
    @State private var geocoded: CLLocationCoordinate2D?

    struct Pin: Identifiable { let id = UUID(); let name: String; let coordinate: CLLocationCoordinate2D }

    var pins: [Pin] {
        let raw = store.resolve(node.prop("markers"), scope: scope)
        var out: [Pin] = []
        switch raw {
        case .array(let items):
            for m in items {
                if let lat = m["latitude"].numberValue ?? m["lat"].numberValue, let lon = m["longitude"].numberValue ?? m["lon"].numberValue ?? m["lng"].numberValue {
                    out.append(Pin(name: m["title"].stringValue.isEmpty ? m["name"].stringValue : m["title"].stringValue, coordinate: .init(latitude: lat, longitude: lon)))
                }
            }
        default:
            for entry in raw.stringValue.split(separator: ";") {
                let parts = entry.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                let c = parts[1].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if c.count == 2 { out.append(Pin(name: parts[0], coordinate: .init(latitude: c[0], longitude: c[1]))) }
            }
        }
        if out.isEmpty, let g = geocoded { out.append(Pin(name: store.string(node, "title", scope), coordinate: g)) }
        return out
    }

    var center: CLLocationCoordinate2D {
        if let g = geocoded { return g }
        return CLLocationCoordinate2D(latitude: store.number(node, "latitude", scope) ?? 37.3349, longitude: store.number(node, "longitude", scope) ?? -122.009)
    }

    var body: some View {
        let span = store.number(node, "span", scope) ?? 0.03
        let region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
        let interactive = node.bool("interactive") && store.mode == .run
        Map(position: $position, interactionModes: interactive ? .all : []) {
            ForEach(pins) { p in Marker(p.name, coordinate: p.coordinate) }
        }
        .mapStyle(mapStyle)
        .onAppear { position = .region(region) }
        .onChange(of: "\(center.latitude),\(center.longitude),\(span)") { _, _ in position = .region(region) }
        .task(id: store.string(node, "title", scope)) {
            guard node.bool("geocode") else { return }
            let query = store.string(node, "title", scope)
            guard !query.isEmpty, let placemark = try? await CLGeocoder().geocodeAddressString(query).first, let loc = placemark.location else { return }
            geocoded = loc.coordinate
            position = .region(MKCoordinateRegion(center: loc.coordinate, span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)))
        }
    }

    var mapStyle: MapStyle {
        switch node.string("variant") {
        case "imagery": return .imagery(elevation: .realistic)
        case "hybrid": return .hybrid(elevation: .realistic)
        default: return .standard(elevation: .realistic)
        }
    }
}

struct WebNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        let s = store.string(node, "url", scope)
        if let url = URL(string: s.hasPrefix("http") ? s : "https://" + s) {
            WebViewRepresentable(url: url)
        } else {
            Text("Invalid URL").foregroundStyle(.secondary)
        }
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let v = WKWebView(frame: .zero, configuration: config)
        v.allowsBackForwardNavigationGestures = true
        v.load(URLRequest(url: url))
        context.coordinator.loaded = url
        return v
    }
    func updateUIView(_ v: WKWebView, context: Context) {
        if context.coordinator.loaded != url { v.load(URLRequest(url: url)); context.coordinator.loaded = url }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loaded: URL? }
}

struct VideoNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @State private var player: AVPlayer?
    @State private var loadedURL = ""

    var body: some View {
        let s = store.string(node, "url", scope)
        VideoPlayer(player: player)
            .onAppear { load(s) }
            .onChange(of: s) { _, new in load(new) }
            .onDisappear { player?.pause() }
    }

    func load(_ s: String) {
        guard s != loadedURL, let url = URL(string: s) else { return }
        loadedURL = s
        let p = AVPlayer(url: url)
        player = p
        if node.bool("loops") {
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
                p.seek(to: .zero); p.play()
            }
        }
        if node.bool("autoplay") && store.mode == .run { p.play() }
    }
}

struct AudioNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    @Environment(\.palette) var palette
    @StateObject private var model = AudioModel()

    var body: some View {
        let url = store.string(node, "url", scope)
        HStack(spacing: 14) {
            SourceImage(source: store.string(node, "artwork", scope), fill: true)
                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(store.string(node, "title", scope)).font(.headline).lineLimit(1)
                Text(store.string(node, "artist", scope)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                ProgressView(value: model.progress).tint(palette.accent)
                HStack {
                    Text(TimerNode.format(model.elapsed)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    Spacer()
                    Text(TimerNode.format(model.duration)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Button { model.toggle(url: url) } label: {
                Image(systemName: model.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 42)).foregroundStyle(palette.accent)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(store.mode == .run)
        }
        .padding(12)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: palette.theme.cornerRadius, style: .continuous))
        .onDisappear { model.stop() }
    }
}

@MainActor
final class AudioModel: ObservableObject {
    @Published var playing = false
    @Published var progress: Double = 0
    @Published var elapsed: Double = 0
    @Published var duration: Double = 0
    private var player: AVPlayer?
    private var observer: Any?
    private var url = ""

    func toggle(url: String) {
        if player == nil || self.url != url {
            stop()
            guard let u = URL(string: url) else { return }
            self.url = url
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            let p = AVPlayer(url: u)
            observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
                Task { @MainActor in
                    guard let self, let item = self.player?.currentItem else { return }
                    let d = item.duration.seconds
                    self.elapsed = t.seconds
                    self.duration = d.isFinite ? d : 0
                    self.progress = d.isFinite && d > 0 ? t.seconds / d : 0
                }
            }
            player = p
        }
        if playing { player?.pause() } else { player?.play() }
        playing.toggle()
    }

    func stop() {
        player?.pause()
        if let o = observer { player?.removeTimeObserver(o) }
        observer = nil
        player = nil
        playing = false
    }
}

struct QRNode: View {
    let node: Node
    let scope: Scope
    @EnvironmentObject var store: RuntimeStore
    var body: some View {
        let content = store.string(node, "content", scope)
        let size = CGFloat(store.number(node, "size", scope) ?? 180)
        Group {
            if let img = QRNode.make(content) {
                Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
            } else {
                Image(systemName: "qrcode").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    static let context = CIContext()
    static func make(_ s: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(s.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)), let cg = context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

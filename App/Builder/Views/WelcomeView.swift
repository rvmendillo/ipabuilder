import SwiftUI

/// First-launch welcome (ReyForge branding and what you can do).
struct WelcomeView: View {
    @ObservedObject var settings = AppSettings.shared

    struct Feature: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let text: String
    }

    let features: [Feature] = [
        Feature(symbol: "hand.draw.fill", title: "Design visually", text: "Drag, resize and edit every native component on a live canvas."),
        Feature(symbol: "sparkles", title: "Vibe-code with AI", text: "Describe screens and features — ReyForge AI builds them, even offline."),
        Feature(symbol: "bolt.horizontal.fill", title: "Add real logic", text: "Variables, navigation, forms, lists, APIs and notifications."),
        Feature(symbol: "hammer.fill", title: "Build & install here", text: "Sign with your certificate and install the IPA right on this iPhone."),
    ]

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            Image("BrandMark")
                .resizable().frame(width: 104, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: RF.violet.opacity(0.45), radius: 16, y: 8)
            VStack(spacing: 6) {
                Text("Welcome to ReyForge").font(.largeTitle.weight(.heavy)).multilineTextAlignment(.center)
                Text("Build native iOS apps on your iPhone").font(.headline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(features) { f in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: f.symbol)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(RF.gradient))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title).font(.headline)
                            Text(f.text).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 10)
            Button {
                settings.showOnboarding = false
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(RF.gradient))
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("welcome.start")
        }
        .padding(24)
    }
}

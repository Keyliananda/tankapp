import SwiftUI

@main
struct TankappApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Tankapp")
                .font(.largeTitle.bold())
            Text("MVP — Phase 0/1 in Arbeit")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    RootView()
}

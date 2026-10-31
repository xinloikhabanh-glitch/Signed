import SwiftUI

enum Config {
    /// Địa chỉ server Vercel của bạn (không có dấu "/" ở cuối)
    static let apiBase = "https://api-rust-alpha-49.vercel.app"
}

@main
struct TouchStudioApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(red: 0.02, green: 0.03, blue: 0.05).ignoresSafeArea()
                TabView {
                    WebTab(page: "keys")
                        .tabItem { Label("Tạo key", systemImage: "key.fill") }
                    WebTab(page: "signer")
                        .tabItem { Label("Cert & Ký", systemImage: "checkmark.seal.fill") }
                }
                .accentColor(Color(red: 0.39, green: 0.82, blue: 1.0))
            }
            .preferredColorScheme(.dark)
        }
    }
}

import SwiftUI

enum Config {
    /// Địa chỉ server Vercel của bạn (không có dấu "/" ở cuối)
    static let apiBase = "https://api-rust-alpha-49.vercel.app"
    /// Phiên bản app (gửi lên server để bật "bắt buộc cập nhật")
    static let version = "1.1.0"
}

private let bgColor = Color(red: 0.02, green: 0.03, blue: 0.05)
private let accent = Color(red: 0.39, green: 0.82, blue: 1.0)

@main
struct TouchStudioApp: App {
    @StateObject private var lock = AppLock()
    @StateObject private var player = Player.shared
    @Environment(\.scenePhase) private var phase
    @State private var splash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                bgColor.ignoresSafeArea()
                VStack(spacing: 0) {
                    MiniPlayer(player: player)
                    TabView {
                        WebTab(page: "keys")
                            .tabItem { Label("Tạo key", systemImage: "key.fill") }
                        WebTab(page: "studio")
                            .tabItem { Label("Cert Studio", systemImage: "checkmark.seal.fill") }
                        WebTab(page: "signer")
                            .tabItem { Label("Ký bplist", systemImage: "square.and.pencil") }
                        SettingsView(lock: lock)
                            .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
                    }
                    .accentColor(accent)
                }
                if lock.locked { LockView(lock: lock) }
                if splash { SplashView() }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                if lock.locked { lock.unlock() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    withAnimation(.easeOut(duration: 0.4)) { splash = false }
                }
            }
            .onChange(of: phase) { p in
                if p == .background { lock.lockIfEnabled() }
                if p == .active && lock.locked { lock.unlock() }
            }
        }
    }
}

struct SplashView: View {
    @State private var appear = false
    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.45, blue: 1.0), accent],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 104, height: 104)
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundColor(.white)
                }
                .scaleEffect(appear ? 1 : 0.7)
                Text("Touch Studio")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Key · Cert · Signer")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            .opacity(appear ? 1 : 0)
        }
        .transition(.opacity)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appear = true } }
    }
}

struct LockView: View {
    @ObservedObject var lock: AppLock
    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundColor(accent)
                Text("Touch Studio đang khoá")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Button("Mở khoá") { lock.unlock() }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(accent)
                    .foregroundColor(.black)
                    .cornerRadius(12)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var lock: AppLock
    @State private var msg = ""

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Bảo mật")) {
                    Toggle("Khoá bằng Face ID / Touch ID", isOn: Binding(
                        get: { lock.enabled },
                        set: { on in
                            lock.setEnabled(on) { ok in
                                if !ok { msg = "Không bật được: máy cần đặt mật mã / Face ID trước." }
                            }
                        }))
                    Button("Xoá mật khẩu admin đã lưu trong Keychain") {
                        Keychain.delete("admin")
                        msg = "Đã xoá mật khẩu admin đã lưu."
                    }
                    .foregroundColor(.red)
                    if !msg.isEmpty {
                        Text(msg).font(.footnote).foregroundColor(.gray)
                    }
                }
                Section(header: Text("Thông tin")) {
                    HStack { Text("Phiên bản"); Spacer(); Text(Config.version).foregroundColor(.gray) }
                    HStack { Text("Server"); Spacer(); Text(Config.apiBase.replacingOccurrences(of: "https://", with: ""))
                        .font(.footnote).foregroundColor(.gray) }
                }
            }
            .navigationTitle("Cài đặt")
        }
        .navigationViewStyle(.stack)
    }
}

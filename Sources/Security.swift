import Foundation
import Security
import LocalAuthentication

/// Lưu mật khẩu admin trong Keychain (được iOS mã hoá, không nằm trong UserDefaults)
enum Keychain {
    private static let service = "com.leviz.touchstudio"

    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    static func set(_ key: String, _ value: String) {
        SecItemDelete(base(key) as CFDictionary)
        var q = base(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete(base(key) as CFDictionary)
    }
}

/// Khoá app bằng Face ID / Touch ID (tự dùng mật mã máy nếu sinh trắc học lỗi)
final class AppLock: ObservableObject {
    @Published var locked: Bool
    @Published private(set) var enabled: Bool
    private var busy = false
    private let key = "tt_lock"

    init() {
        let on = UserDefaults.standard.bool(forKey: "tt_lock")
        enabled = on
        locked = on
    }

    func lockIfEnabled() {
        if enabled { locked = true }
    }

    /// Hiện hộp thoại Face ID / Touch ID để mở khoá
    func unlock() {
        guard locked, !busy else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // máy chưa đặt mật mã => không thể khoá, tránh bị kẹt ngoài app
            locked = false
            return
        }
        busy = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Mở Touch Studio") { ok, _ in
            DispatchQueue.main.async {
                self.busy = false
                if ok { self.locked = false }
            }
        }
    }

    /// Bật cần xác thực thành công trước (để chắc chắn không tự khoá mình ra ngoài)
    func setEnabled(_ on: Bool, completion: @escaping (Bool) -> Void) {
        if !on {
            enabled = false
            UserDefaults.standard.set(false, forKey: key)
            completion(true)
            return
        }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            completion(false)
            return
        }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Bật khoá Touch Studio") { ok, _ in
            DispatchQueue.main.async {
                if ok {
                    self.enabled = true
                    UserDefaults.standard.set(true, forKey: self.key)
                }
                completion(ok)
            }
        }
    }
}

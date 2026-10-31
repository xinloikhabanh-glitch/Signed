# Touch Studio (iOS)
2 tab: **Tạo key** (quản trị key trên server Vercel) và **Cert & Ký** (tạo chứng chỉ, ký bplist/plist/mobileconfig).
Build: upload `ios-src.zip` (không giải nén) + `.github/workflows/build-ipa.yml` lên repo → Actions → Run workflow → tải TouchStudio-ipa.
IPA chưa ký: cài bằng Sideloadly / AltStore / eSign / TrollStore.
Đổi server: sửa `Config.apiBase` trong Sources/App.swift.

import SwiftUI
import UIKit
import WebKit

/// Một tab hiển thị trang HTML nằm trong app (Resources/<page>.html).
struct WebTab: UIViewRepresentable {
    let page: String

    func makeCoordinator() -> Bridge { Bridge() }

    func makeUIView(context: Context) -> WKWebView {
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: Bridge.userScript(),
                                       injectionTime: .atDocumentStart,
                                       forMainFrameOnly: true))
        ucc.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "api")
        ucc.add(context.coordinator, name: "save")
        ucc.add(context.coordinator, name: "store")

        let cfg = WKWebViewConfiguration()
        cfg.userContentController = ucc

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1)
        web.scrollView.backgroundColor = web.backgroundColor
        context.coordinator.web = web

        if let url = Bundle.main.url(forResource: page, withExtension: "html"),
           let html = try? String(contentsOf: url, encoding: .utf8) {
            // baseURL kiểu https để trang là "secure context" (cần cho crypto.subtle)
            web.loadHTMLString(html, baseURL: URL(string: "https://studio.invalid/"))
        } else {
            web.loadHTMLString("<h3 style='color:#fff;font-family:-apple-system'>Không tìm thấy \(page).html trong app</h3>",
                               baseURL: nil)
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Cầu nối giữa trang web và iOS:
///  - api:   gọi server bằng URLSession (không dính CORS)
///  - save:  mở bảng chia sẻ để lưu file tạo ra (.mobileconfig, .crt, .pem, .txt, .csv)
///  - store: lưu localStorage vào UserDefaults để không mất khi tắt app
///  - alert / confirm / prompt của JavaScript
final class Bridge: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKUIDelegate {
    weak var web: WKWebView?

    private static let storeKey = "tt_localstorage"

    // MARK: - script chèn vào mỗi trang

    static func userScript() -> String {
        let saved = (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String]) ?? [:]
        let json: String
        if let d = try? JSONSerialization.data(withJSONObject: saved, options: []),
           let s = String(data: d, encoding: .utf8) {
            json = s
        } else {
            json = "{}"
        }
        let base = Config.apiBase

        return """
        (function () {
          var BASE = '\(base)';
          var post = function (name, msg) {
            try { window.webkit.messageHandlers[name].postMessage(msg); } catch (e) {}
          };

          // ---- localStorage lưu bền qua UserDefaults ----
          var data = \(json);
          var st = {
            getItem: function (k) { return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null; },
            setItem: function (k, v) { k = String(k); v = String(v); data[k] = v; post('store', { op: 'set', k: k, v: v }); },
            removeItem: function (k) { k = String(k); delete data[k]; post('store', { op: 'del', k: k }); },
            clear: function () { data = {}; post('store', { op: 'clear' }); },
            key: function (i) { return Object.keys(data)[i] || null; }
          };
          Object.defineProperty(st, 'length', { get: function () { return Object.keys(data).length; } });
          try { Object.defineProperty(window, 'localStorage', { configurable: true, get: function () { return st; } }); } catch (e) {}

          // ---- fetch tới server đi qua iOS (tránh CORS) ----
          var origFetch = window.fetch.bind(window);
          window.fetch = function (input, init) {
            var url = (typeof input === 'string') ? input : ((input && input.url) || String(input));
            if (url.indexOf('/api/') === 0 || url.indexOf(BASE + '/') === 0) {
              init = init || {};
              var headers = {};
              var h = init.headers;
              if (h) {
                if (typeof h.forEach === 'function' && !Array.isArray(h)) { h.forEach(function (v, k) { headers[k] = v; }); }
                else if (Array.isArray(h)) { h.forEach(function (p) { headers[p[0]] = p[1]; }); }
                else { for (var k in h) { headers[k] = h[k]; } }
              }
              return window.webkit.messageHandlers.api.postMessage({
                url: url,
                method: init.method || 'GET',
                headers: headers,
                body: (typeof init.body === 'string') ? init.body : null
              }).then(function (r) {
                return new Response(r.body, { status: r.status, headers: { 'content-type': 'application/json' } });
              });
            }
            return origFetch(input, init);
          };

          // ---- tải file: chuyển sang bảng chia sẻ của iOS ----
          var origClick = HTMLAnchorElement.prototype.click;
          HTMLAnchorElement.prototype.click = function () {
            var a = this;
            var href = a.href || '';
            if (a.hasAttribute('download') && (href.indexOf('blob:') === 0 || href.indexOf('data:') === 0)) {
              var name = a.getAttribute('download') || 'file';
              origFetch(href).then(function (r) { return r.blob(); }).then(function (b) {
                var fr = new FileReader();
                fr.onload = function () {
                  var s = String(fr.result);
                  post('save', { name: name, data: s.substring(s.indexOf(',') + 1) });
                };
                fr.readAsDataURL(b);
              });
              return;
            }
            return origClick.apply(a, arguments);
          };
        })();
        """
    }

    // MARK: - api (có trả lời)

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let d = message.body as? [String: Any],
              let raw = d["url"] as? String else {
            replyHandler(nil, "Yêu cầu không hợp lệ")
            return
        }
        let full = raw.hasPrefix("/") ? Config.apiBase + raw : raw
        guard let url = URL(string: full),
              url.scheme == "https",
              url.host == URL(string: Config.apiBase)?.host else {
            replyHandler(nil, "Địa chỉ không được phép")
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = ((d["method"] as? String) ?? "GET").uppercased()
        if let hs = d["headers"] as? [String: Any] {
            for (k, v) in hs {
                if let s = v as? String { req.setValue(s, forHTTPHeaderField: k) }
            }
        }
        if let b = d["body"] as? String { req.httpBody = Data(b.utf8) }

        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                if let http = resp as? HTTPURLResponse {
                    let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                    replyHandler(["status": http.statusCode, "body": body], nil)
                } else {
                    replyHandler(nil, err?.localizedDescription ?? "Lỗi mạng")
                }
            }
        }.resume()
    }

    // MARK: - save / store (không trả lời)

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any] else { return }

        if message.name == "save" {
            guard let name = d["name"] as? String,
                  let b64 = d["data"] as? String,
                  let bytes = Data(base64Encoded: b64) else { return }
            share(name: name, data: bytes)
        } else if message.name == "store" {
            var all = (UserDefaults.standard.dictionary(forKey: Bridge.storeKey) as? [String: String]) ?? [:]
            switch d["op"] as? String {
            case "set":
                if let k = d["k"] as? String, let v = d["v"] as? String { all[k] = v }
            case "del":
                if let k = d["k"] as? String { all.removeValue(forKey: k) }
            case "clear":
                all = [:]
            default:
                return
            }
            UserDefaults.standard.set(all, forKey: Bridge.storeKey)
        }
    }

    private func share(name: String, data: Data) {
        let clean = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(clean.isEmpty ? "file" : clean)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
        DispatchQueue.main.async {
            guard let top = Bridge.topController() else { return }
            let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let pop = vc.popoverPresentationController {
                pop.sourceView = top.view
                pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                pop.permittedArrowDirections = []
            }
            top.present(vc, animated: true)
        }
    }

    // MARK: - hộp thoại JavaScript

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        guard let top = Bridge.topController() else { completionHandler(); return }
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        top.present(a, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        guard let top = Bridge.topController() else { completionHandler(false); return }
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        top.present(a, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard let top = Bridge.topController() else { completionHandler(nil); return }
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Huỷ", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(a.textFields?.first?.text ?? "")
        })
        top.present(a, animated: true)
    }

    // MARK: - tiện ích

    static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene?.windows.first?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

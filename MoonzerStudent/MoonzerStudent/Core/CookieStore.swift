import Foundation
import WebKit

enum CookieStore {
    private static let key = "moonzer.ios.cookie.header"
    private static let savedAtKey = "moonzer.ios.cookie.header.at"
    private static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    static func persist(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let sims = cookies.filter {
                $0.domain.lowercased().hasSuffix("emoonzer.com") &&
                !$0.name.uppercased().contains("CSRF") &&
                $0.name != "XSRF-TOKEN"
            }
            let header = sims.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            UserDefaults.standard.set(header, forKey: key)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: savedAtKey)
        }
    }

    static func restore(into webView: WKWebView, completion: @escaping () -> Void = {}) {
        guard let header = UserDefaults.standard.string(forKey: key), !header.isEmpty else {
            completion()
            return
        }

        let savedAt = UserDefaults.standard.double(forKey: savedAtKey)
        if savedAt > 0, Date().timeIntervalSince1970 - savedAt > maxAge {
            clear()
            completion()
            return
        }

        guard let base = URL(string: AppUrls.base) else {
            completion()
            return
        }

        let pairs: [(String, String)] = header.split(separator: ";").compactMap { part in
            let item = part.trimmingCharacters(in: .whitespaces)
            let pieces = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2, !pieces[0].isEmpty else { return nil }
            return (pieces[0], pieces[1])
        }

        guard !pairs.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for (name, value) in pairs {
            guard let cookie = HTTPCookie(properties: [
                .domain: AppUrls.host,
                .path: "/",
                .name: name,
                .value: value,
                .secure: "TRUE",
                .originURL: base
            ]) else { continue }
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }

        group.notify(queue: .main) { completion() }
    }

    static func hasSession() -> Bool {
        guard let header = UserDefaults.standard.string(forKey: key), !header.isEmpty else { return false }
        let savedAt = UserDefaults.standard.double(forKey: savedAtKey)
        if savedAt > 0, Date().timeIntervalSince1970 - savedAt > maxAge {
            clear()
            return false
        }
        return true
    }

    static func clear(completion: @escaping () -> Void = {}) {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: savedAtKey)

        let store = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) {
            HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
            DispatchQueue.main.async { completion() }
        }
    }
}

import Foundation

enum AppUrls {
    static let host = "sims.emoonzer.com"
    static let base = "https://sims.emoonzer.com/"
    static let portal = base
    static let presensi = base + "presensi"
    static let tryout = base + "tryout/"
    static let qrExitVerify = base + "mobile/qr-exit-token/verify"
    static let safeId = #"^[A-Za-z0-9_-]{1,160}$"#

    static func isTrustedHost(_ host: String?) -> Bool {
        host?.lowercased() == Self.host
    }

    static func isTrusted(_ urlString: String?) -> Bool {
        guard let urlString, let url = URL(string: urlString) else { return false }
        return isTrusted(url)
    }

    static func isTrusted(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https" else { return false }
        return isTrustedHost(url.host)
    }

    static func parseScannedHttpUrl(_ raw: String?) -> String? {
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .components(separatedBy: .newlines).first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return nil }
        let candidate: String
        if text.lowercased().hasPrefix("https://") || text.lowercased().hasPrefix("http://") {
            candidate = text
        } else if text.lowercased().hasPrefix("www.") {
            candidate = "https://\(text)"
        } else {
            return nil
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(),
              host.contains("."), !host.hasSuffix(".") else { return nil }
        if scheme == "http", var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.scheme = "https"
            return comps.url?.absoluteString
        }
        return url.absoluteString
    }

    static func isAllowedQrHost(_ url: URL?, allowedHost: String?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        if isTrustedHost(host) { return true }
        let allowed = allowedHost?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !allowed.isEmpty else { return false }
        return host == allowed || host.hasSuffix(".\(allowed)")
    }

    static func isTryoutExamStartUrl(_ urlString: String?) -> Bool {
        guard isTrusted(urlString), let url = URL(string: urlString ?? "") else { return false }
        let segments = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        return segments.count >= 4 && segments[0] == "tryout" && segments[1] == "paket" && !segments[2].isEmpty && segments[3] == "mulai"
    }

    static func tryoutId(fromStart urlString: String?) -> String? {
        guard isTryoutExamStartUrl(urlString), let url = URL(string: urlString ?? "") else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }
        return segments.count > 2 ? segments[2] : nil
    }

    static func isTryoutResultUrl(_ urlString: String?) -> Bool {
        guard isTrusted(urlString), let url = URL(string: urlString ?? "") else { return false }
        let segments = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        return segments.count >= 3 && segments[0] == "tryout" && segments[1] == "hasil" && !segments[2].isEmpty
    }

    static func isExamLikeUrl(_ urlString: String?) -> Bool {
        guard isTrusted(urlString), let url = URL(string: urlString ?? "") else { return false }
        if isTryoutExamStartUrl(urlString) { return true }
        let path = url.path.lowercased()
        return path.contains("/ujian/") || path.contains("/siswa/quiz/") || path.contains("/quiz/")
    }

    static func isAttemptUrl(_ urlString: String?) -> Bool {
        guard isExamLikeUrl(urlString) else { return false }
        if isTryoutExamStartUrl(urlString) { return true }
        return (URL(string: urlString ?? "")?.path.lowercased().contains("/attempt") ?? false)
    }

    static func matchesSafeId(_ value: String) -> Bool {
        value.range(of: safeId, options: .regularExpression) != nil
    }
}

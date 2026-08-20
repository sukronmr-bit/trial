import Foundation

enum TokenVerifier {
    private static let timeout: TimeInterval = 20

    static func verifyQuizExit(token: String,
                               quizId: String,
                               uuid: String,
                               cookie: String,
                               userAgent: String,
                               completion: @escaping (Bool) -> Void) {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let exitId = quizId.isEmpty ? uuid : quizId
        guard !normalizedToken.isEmpty,
              normalizedToken.count <= 128,
              AppUrls.matchesSafeId(exitId),
              let url = URL(string: "\(AppUrls.base)siswa/quiz/\(exitId)/exittoken") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if !quizId.isEmpty, AppUrls.matchesSafeId(uuid) {
            request.setValue("\(AppUrls.base)siswa/quiz/\(quizId)/\(uuid)", forHTTPHeaderField: "Referer")
        }

        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = parseQuizToken(data: data, http: response as? HTTPURLResponse, input: normalizedToken)
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    static func verifyQrExit(token: String,
                             userAgent: String,
                             completion: @escaping (Bool) -> Void) {
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedToken.isEmpty,
              normalizedToken.count <= 128,
              let url = URL(string: AppUrls.qrExitVerify) else {
            completion(false)
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": normalizedToken])

        URLSession.shared.dataTask(with: request) { data, response, _ in
            var valid = false
            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                valid = json["valid"] as? Bool ?? false
            }
            DispatchQueue.main.async { completion(valid) }
        }.resume()
    }

    private static func parseQuizToken(data: Data?, http: HTTPURLResponse?, input: String) -> Bool {
        guard let http,
              http.statusCode == 200,
              let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let server = ((json["exittoken"] as? String) ?? (json["token"] as? String) ?? "").uppercased()
        return !server.isEmpty && constantTimeEquals(server, input.uppercased())
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aa = Array(a.utf8)
        let bb = Array(b.utf8)
        var diff = aa.count ^ bb.count
        let maxCount = max(aa.count, bb.count)
        for i in 0..<maxCount {
            let x = i < aa.count ? Int(aa[i]) : 0
            let y = i < bb.count ? Int(bb[i]) : 0
            diff |= x ^ y
        }
        return diff == 0
    }
}

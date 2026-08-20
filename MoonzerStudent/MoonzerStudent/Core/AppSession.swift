import Foundation
import Combine
import UIKit

final class AppSession: ObservableObject {
    enum Screen {
        case splash
        case menu
        case web
        case qr
    }

    @Published var screen: Screen = .splash
    @Published var currentURL: URL = URL(string: AppUrls.portal)!
    @Published var pageURL: String = AppUrls.portal
    @Published var isLocked = false
    @Published var isQrSession = false
    @Published var qrAllowedHost: String?
    @Published var currentUuid = ""
    @Published var currentQuizId = ""
    @Published var isOnResultPage = false
    @Published var showError = false
    @Published var errorMessage = "Periksa koneksi internet lalu coba kembali."
    @Published var toast: String?
    @Published var screenshotWarning = false
    @Published var isOnline = true
    @Published var guidedAccessEnabled = UIAccessibility.isGuidedAccessEnabled
    @Published var privacyShieldActive = false
    @Published var backgroundViolationCount = 0

    var webController: PortalWebView.Coordinator?

    init() {
        NetworkMonitor.shared.onStatusChange = { [weak self] online in
            self?.isOnline = online
            if online, self?.showError == true {
                self?.showError = false
            }
        }
        NetworkMonitor.shared.start()
        refreshGuidedAccessStatus()
    }

    func openPortal() { open(AppUrls.portal, qr: false) }
    func openPresensi() { open(AppUrls.presensi, qr: false) }
    func openTryout() { open(AppUrls.tryout, qr: false) }

    func open(_ urlString: String, qr: Bool) {
        guard let url = URL(string: urlString) else {
            toast = "Alamat layanan tidak valid."
            return
        }
        if !qr && !AppUrls.isTrusted(url) {
            toast = "Alamat layanan tidak valid."
            return
        }

        currentURL = url
        pageURL = urlString
        isQrSession = qr
        showError = false
        screen = .web
        webController?.load(url)
    }

    func showMenu() {
        guard !isLocked else { return }
        isQrSession = false
        qrAllowedHost = nil
        showError = false
        screen = .menu
    }

    func beginQrSession(urlString: String, host: String) {
        qrAllowedHost = host.lowercased()
        isQrSession = true
        currentUuid = "qr_session"
        open(urlString, qr: true)
        startLock(reason: "qr_session_enter")
    }

    func inspect(url: String) {
        pageURL = url
        if isQrSession { return }
        detectExam(from: url)

        if AppUrls.isTryoutExamStartUrl(url) {
            if let id = AppUrls.tryoutId(fromStart: url), AppUrls.matchesSafeId(id) {
                currentQuizId = id
                currentUuid = "tryout_\(id)"
                if !isLocked { startLock(reason: "exam_enter") }
            }
        } else if AppUrls.isTryoutResultUrl(url), isLocked, currentUuid.hasPrefix("tryout_") {
            releaseLock(toMenu: false, message: "Tryout selesai. Mode ujian dinonaktifkan.")
            currentQuizId = ""
            currentUuid = ""
        }
    }

    func detectExam(from urlString: String) {
        guard AppUrls.isTrusted(urlString), let url = URL(string: urlString) else { return }
        let segments = url.pathComponents.filter { $0 != "/" }
        let lower = segments.map { $0.lowercased() }
        let quizIndex = lower.lastIndex(of: "quiz")
        let attemptIndex = lower.lastIndex(of: "attempt")
        let resultIndex = lower.lastIndex(of: "result")
        let ujianIndex = lower.lastIndex(of: "ujian")

        let onResult = quizIndex != nil && resultIndex != nil && resultIndex! > quizIndex!
        isOnResultPage = onResult

        if let q = quizIndex {
            if onResult, let r = resultIndex, r > 0 {
                updateUuid(segments[r - 1])
                if r - q >= 3 { updateQuizId(segments[q + 1]) }
            } else if segments.count > q + 2, attemptIndex == nil {
                updateQuizId(segments[q + 1])
                updateUuid(segments[q + 2])
            } else if segments.count > q + 1, attemptIndex == nil {
                updateUuid(segments[q + 1])
            }
        }

        if let u = ujianIndex, attemptIndex != nil, segments.count > u + 1 {
            updateQuizId(segments[u + 1])
            updateUuid(segments[u + 1])
        }

        if let a = attemptIndex {
            if a > 0 { updateUuid(segments[a - 1]) }
            if let q = quizIndex, q + 1 < a { updateQuizId(segments[q + 1]) }
            if !isLocked { startLock(reason: "exam_enter") }
        }
    }

    func startExamFromBridge(uuid: String) {
        guard AppUrls.matchesSafeId(uuid), AppUrls.isExamLikeUrl(pageURL) else { return }
        let segments = URL(string: pageURL)?.pathComponents ?? []
        guard segments.contains(uuid) else { return }
        currentUuid = uuid
        startLock(reason: "exam_enter")
    }

    func startLock(reason: String) {
        guard !isLocked else { return }
        if !isQrSession && !AppUrls.isExamLikeUrl(pageURL) { return }

        isLocked = true
        screenshotWarning = false
        privacyShieldActive = false
        backgroundViolationCount = 0
        UIApplication.shared.isIdleTimerDisabled = true
        webController?.setCopyPasteBlocked(true)
        refreshGuidedAccessStatus()

        if guidedAccessEnabled {
            toast = "Mode ujian aktif. Guided Access terdeteksi aktif."
        } else {
            toast = "Mode ujian aktif. Aktifkan Guided Access dengan klik 3x tombol samping."
        }
        _ = reason
    }

    func releaseLock(toMenu: Bool, message: String) {
        isLocked = false
        isQrSession = false
        qrAllowedHost = nil
        isOnResultPage = false
        UIApplication.shared.isIdleTimerDisabled = false
        webController?.setCopyPasteBlocked(false)
        toast = message
        screenshotWarning = false
        privacyShieldActive = false
        backgroundViolationCount = 0
        if toMenu { screen = .menu }
    }

    func updateUuid(_ value: String) {
        if AppUrls.matchesSafeId(value) { currentUuid = value }
    }

    func updateQuizId(_ value: String) {
        if AppUrls.matchesSafeId(value) { currentQuizId = value }
    }

    func handleScreenshot() {
        guard isLocked else { return }
        screenshotWarning = true
        toast = "Screenshot terdeteksi selama ujian."
    }

    func handleCaptureChange(_ captured: Bool) {
        guard isLocked else { return }
        if captured {
            screenshotWarning = true
            privacyShieldActive = true
            toast = "Perekaman layar terdeteksi selama ujian."
        } else {
            privacyShieldActive = false
        }
    }

    func handleWillResignActive() {
        guard isLocked else {
            privacyShieldActive = false
            return
        }
        privacyShieldActive = true
    }

    func handleDidEnterBackground() {
        guard isLocked else { return }
        privacyShieldActive = true
        backgroundViolationCount += 1
    }

    func handleBecameActive() {
        refreshGuidedAccessStatus()
        guard isLocked else {
            privacyShieldActive = false
            return
        }
        privacyShieldActive = UIScreen.main.isCaptured
        if backgroundViolationCount > 0 {
            screenshotWarning = true
            toast = "Aplikasi sempat berpindah dari layar ujian."
        }
    }

    func refreshGuidedAccessStatus() {
        guidedAccessEnabled = UIAccessibility.isGuidedAccessEnabled
    }

    func resetSession() {
        guard !isLocked else {
            toast = "Sesi tidak dapat direset saat mode ujian aktif."
            return
        }
        CookieStore.clear()
        webController?.clearWebViewState()
        currentUuid = ""
        currentQuizId = ""
        currentURL = URL(string: AppUrls.portal)!
        pageURL = AppUrls.portal
        toast = "Sesi berhasil direset."
        screen = .menu
    }
}

import SwiftUI
import UIKit

struct WebSessionView: View {
    @ObservedObject var session: AppSession
    @State private var tokenInput = ""
    @State private var showExitToken = false
    @State private var verifying = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack {
                PortalWebView(session: session)

                if session.showError {
                    errorOverlay
                }

                if session.screenshotWarning && !session.privacyShieldActive {
                    warningOverlay
                }

                if verifying {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView("Memverifikasi token…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .navigationBarHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            session.handleScreenshot()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
            session.handleCaptureChange(UIScreen.main.isCaptured)
        }
        .alert(session.isQrSession ? "Keluar Mode Ujian QR" : "Keluar Mode Ujian", isPresented: $showExitToken) {
            TextField("Masukkan token", text: $tokenInput)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Verifikasi") { submitToken() }
                .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || verifying)
            Button("Batal", role: .cancel) { tokenInput = "" }
        } message: {
            Text(session.isQrSession
                 ? "Masukkan token keluar dari pengawas. Token sistem berubah setiap 10 menit."
                 : "Masukkan token keluar yang diberikan pengawas.")
        }
    }

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 12) {
            if session.isLocked {
                HStack(spacing: 5) {
                    Circle()
                        .fill(session.isOnline ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(session.isOnline ? "Online" : "Offline")
                }
                .font(.caption.bold())

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: session.guidedAccessEnabled ? "lock.shield.fill" : "exclamationmark.shield.fill")
                    Text(session.guidedAccessEnabled ? "Guided Access" : "Belum Dikunci")
                }
                .font(.caption.bold())
                .foregroundStyle(session.guidedAccessEnabled ? .white : .yellow)
                .onTapGesture {
                    session.refreshGuidedAccessStatus()
                    if !session.guidedAccessEnabled {
                        session.toast = "Klik 3x tombol samping lalu mulai Guided Access."
                    }
                }

                Spacer()

                Button { session.webController?.zoom(in: false) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .accessibilityLabel("Perkecil tampilan")

                Button { session.webController?.zoom(in: true) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .accessibilityLabel("Perbesar tampilan")

                Button { requestExit() } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityLabel("Keluar mode ujian")
            } else {
                Button {
                    if session.webController?.goBack() != true {
                        session.showMenu()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Kembali")

                Button { session.openPortal() } label: {
                    Image(systemName: "house.fill")
                }
                .accessibilityLabel("Portal siswa")

                Spacer()

                Text(session.isOnline ? "Online" : "Offline")
                    .font(.caption.bold())
                    .foregroundStyle(session.isOnline ? .white : .yellow)

                Spacer()

                Button { session.webController?.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Muat ulang")

                Button { session.showMenu() } label: {
                    Image(systemName: "square.grid.2x2.fill")
                }
                .accessibilityLabel("Kembali ke menu")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.12, green: 0.25, blue: 0.69))
    }

    private var errorOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: session.isOnline ? "exclamationmark.icloud.fill" : "wifi.slash")
                .font(.system(size: 34))
            Text("Halaman belum dapat dibuka").bold()
            Text(session.errorMessage)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Coba Lagi") {
                session.webController?.reload()
            }
            .buttonStyle(.borderedProminent)

            Button("Kembali ke Menu") {
                if session.isLocked { requestExit() } else { session.showMenu() }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var warningOverlay: some View {
        Color.black.opacity(0.62).ignoresSafeArea()
            .overlay {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 40))
                    Text("Aktivitas di luar mode ujian terdeteksi")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Screenshot, perekaman layar, atau perpindahan aplikasi dapat tercatat selama ujian.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.85))
                    Button("Kembali ke Ujian") {
                        session.screenshotWarning = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .foregroundStyle(.white)
                .padding(28)
            }
    }

    private func requestExit() {
        guard !verifying else { return }
        if session.isLocked && session.isOnResultPage && !session.isQrSession {
            session.releaseLock(toMenu: false, message: "Mode ujian selesai.")
            session.openPortal()
            return
        }
        tokenInput = ""
        showExitToken = true
    }

    private func submitToken() {
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !token.isEmpty, !verifying else { return }
        verifying = true
        showExitToken = false

        let userAgent = "MoonzerStudent-iOS/1.1"
        if session.isQrSession {
            TokenVerifier.verifyQrExit(token: token, userAgent: userAgent) { ok in
                verifying = false
                tokenInput = ""
                if ok {
                    session.releaseLock(toMenu: true, message: "Sesi QR selesai.")
                } else {
                    session.toast = session.isOnline ? "Token tidak valid." : "Verifikasi gagal karena perangkat offline."
                }
            }
        } else {
            session.webController?.cookieHeader { cookie in
                TokenVerifier.verifyQuizExit(
                    token: token,
                    quizId: session.currentQuizId,
                    uuid: session.currentUuid,
                    cookie: cookie,
                    userAgent: userAgent
                ) { ok in
                    verifying = false
                    tokenInput = ""
                    if ok {
                        session.releaseLock(toMenu: false, message: "Mode ujian selesai.")
                        session.openPortal()
                    } else {
                        session.toast = session.isOnline ? "Token tidak valid." : "Verifikasi gagal karena perangkat offline."
                    }
                }
            }
        }
    }
}

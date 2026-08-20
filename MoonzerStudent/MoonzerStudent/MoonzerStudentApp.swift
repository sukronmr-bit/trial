import SwiftUI
import UIKit

@main
struct MoonzerStudentApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var session: AppSession

    var body: some View {
        ZStack {
            switch session.screen {
            case .splash:
                SplashView()
            case .menu:
                MenuView(session: session)
            case .web:
                WebSessionView(session: session)
            case .qr:
                QRScannerView(session: session)
            }

            if session.privacyShieldActive {
                PrivacyShieldView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = session.toast, !session.privacyShieldActive {
                Text(toast)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.84), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                            if session.toast == toast { session.toast = nil }
                        }
                    }
            }
        }
        .onAppear {
            session.refreshGuidedAccessStatus()
            if session.screen == .splash {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if session.screen == .splash { session.screen = .menu }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            session.handleWillResignActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            session.handleDidEnterBackground()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            session.handleBecameActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.guidedAccessStatusDidChangeNotification)) { _ in
            session.refreshGuidedAccessStatus()
        }
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
            Text("Moonzer Student")
                .font(.title2.bold())
            ProgressView()
            Text("Menyiapkan layanan siswa…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.97, green: 0.98, blue: 0.99))
    }
}

struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.10, blue: 0.25).ignoresSafeArea()
            VStack(spacing: 14) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 38))
                Text("Mode Ujian Dilindungi")
                    .font(.title3.bold())
                Text("Kembali ke aplikasi untuk melanjutkan.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
        }
    }
}

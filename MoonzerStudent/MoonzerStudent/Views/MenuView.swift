import SwiftUI

struct MenuView: View {
    @ObservedObject var session: AppSession
    @State private var confirmReset = false
    @State private var showIOSGuide = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 72)
                    .padding(.top, 24)

                Text("MOONZER STUDENT")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text("Satu aplikasi untuk layanan siswa")
                    .foregroundStyle(.white.opacity(0.85))
                    .font(.subheadline)

                Text("SMAN 2 Kota Tangerang Selatan")
                    .foregroundStyle(.white.opacity(0.7))
                    .font(.caption)

                HStack(spacing: 8) {
                    Label(session.isOnline ? "Online" : "Offline",
                          systemImage: session.isOnline ? "wifi" : "wifi.slash")
                    Divider().frame(height: 14).overlay(.white.opacity(0.35))
                    Label(session.guidedAccessEnabled ? "Guided Access Aktif" : "Guided Access Belum Aktif",
                          systemImage: session.guidedAccessEnabled ? "lock.shield.fill" : "shield")
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.12), in: Capsule())

                VStack(alignment: .leading, spacing: 12) {
                    Text("Layanan utama")
                        .font(.headline)

                    serviceButton("Portal Siswa", "Tugas, quiz, nilai, jadwal dan layanan siswa", "graduationcap.fill") {
                        session.openPortal()
                    }
                    serviceButton("Presensi", "Presensi masuk, pulang dan riwayat kehadiran", "checkmark.circle.fill") {
                        session.openPresensi()
                    }
                    serviceButton("Tryout", "Latihan dan simulasi dengan Mode Ujian", "pencil.and.list.clipboard") {
                        session.openTryout()
                    }

                    Text("Akun & perangkat")
                        .font(.headline)
                        .padding(.top, 8)

                    outlineButton("Scan QR Code", icon: "qrcode.viewfinder") {
                        session.screen = .qr
                    }
                    outlineButton("Panduan Mode Ujian iPhone", icon: "iphone.gen3") {
                        showIOSGuide = true
                    }
                    outlineButton("Reset sesi login", icon: "arrow.counterclockwise") {
                        confirmReset = true
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))

                Text("Versi 1.1.0 iOS")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                Text("© 2026 E-MOONZER • SMAN 2 Kota Tangerang Selatan")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(red: 0.11, green: 0.31, blue: 0.85).ignoresSafeArea())
        .alert("Reset sesi login?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { session.resetSession() }
            Button("Batal", role: .cancel) {}
        } message: {
            Text("Cookie, cache, dan sesi WebView akan dihapus. Anda perlu login kembali.")
        }
        .sheet(isPresented: $showIOSGuide) {
            IOSExamGuideView(session: session)
        }
    }

    private func serviceButton(_ title: String,
                               _ desc: String,
                               _ icon: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 30)
                    .foregroundStyle(Color(red: 0.11, green: 0.31, blue: 0.85))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    private func outlineButton(_ title: String,
                               icon: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3)))
            .foregroundStyle(Color(red: 0.11, green: 0.31, blue: 0.85))
            .font(.headline)
        }
        .buttonStyle(.plain)
    }
}

struct IOSExamGuideView: View {
    @ObservedObject var session: AppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Status perangkat") {
                    Label(session.guidedAccessEnabled ? "Guided Access aktif" : "Guided Access belum aktif",
                          systemImage: session.guidedAccessEnabled ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .foregroundStyle(session.guidedAccessEnabled ? Color.green : Color.orange)

                    Button("Periksa ulang status") {
                        session.refreshGuidedAccessStatus()
                    }
                }

                Section("Sebelum ujian") {
                    guideRow(1, "Buka Pengaturan → Aksesibilitas → Guided Access dan aktifkan.")
                    guideRow(2, "Atur kode sandi Guided Access yang dikuasai pengawas.")
                    guideRow(3, "Kembali ke Moonzer Student lalu mulai ujian/scan QR.")
                    guideRow(4, "Klik 3x tombol samping iPhone, lalu pilih Mulai.")
                }

                Section("Perlindungan aplikasi") {
                    Label("Copy/paste dan context menu diblokir saat ujian", systemImage: "doc.on.clipboard")
                    Label("Screenshot dan screen recording dideteksi", systemImage: "camera.badge.ellipsis")
                    Label("Isi ujian disembunyikan saat app masuk background", systemImage: "eye.slash.fill")
                    Label("Tautan di luar domain ujian diblokir", systemImage: "link.badge.plus")
                }

                Section {
                    Text("iOS tidak menyediakan Lock Task seperti Android untuk aplikasi biasa. Guided Access adalah mekanisme Apple yang digunakan untuk mengunci perangkat pada satu aplikasi.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Mode Ujian iPhone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Selesai") { dismiss() }
                }
            }
        }
    }

    private func guideRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 24, height: 24)
                .background(Color.blue.opacity(0.12), in: Circle())
            Text(text)
        }
    }
}

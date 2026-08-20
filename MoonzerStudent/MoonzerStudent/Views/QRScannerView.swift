import SwiftUI
import AVFoundation
import UIKit

struct QRScannerView: View {
    @ObservedObject var session: AppSession
    @State private var confirmURL: String?
    @State private var confirmHost: String?
    @State private var notURL = false
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var torchOn = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch permission {
            case .authorized:
                QRCameraRepresentable(torchOn: torchOn) { value in
                    handle(value)
                }
                scannerOverlay
            case .notDetermined:
                ProgressView("Meminta izin kamera…")
                    .tint(.white)
                    .foregroundStyle(.white)
            case .denied, .restricted:
                permissionDeniedView
            @unknown default:
                permissionDeniedView
            }
        }
        .onAppear { requestCameraIfNeeded() }
        .onDisappear { torchOn = false }
        .alert("Alihkan ke mode ujian?", isPresented: Binding(
            get: { confirmURL != nil },
            set: { if !$0 { confirmURL = nil; confirmHost = nil } }
        )) {
            Button("Setuju") {
                if let url = confirmURL, let host = confirmHost {
                    session.beginQrSession(urlString: url, host: host)
                }
                confirmURL = nil
                confirmHost = nil
            }
            Button("Batal", role: .cancel) {
                confirmURL = nil
                confirmHost = nil
            }
        } message: {
            Text("Domain: \(confirmHost ?? "-")\n\nAplikasi akan masuk mode ujian. Copy-paste dan tautan keluar dibatasi. Di iPhone, gunakan Guided Access untuk mengunci tombol Home/gesture keluar.")
        }
        .alert("QR tidak valid", isPresented: $notURL) {
            Button("Pindai Lagi", role: .cancel) {}
        } message: {
            Text("QR code tidak berisi tautan HTTP/HTTPS yang dapat dibuka.")
        }
    }

    private var scannerOverlay: some View {
        VStack {
            HStack {
                Button {
                    torchOn = false
                    session.screen = .menu
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.45), in: Circle())
                }

                Spacer()

                Button {
                    torchOn.toggle()
                } label: {
                    Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.45), in: Circle())
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)

            Spacer()

            RoundedRectangle(cornerRadius: 22)
                .stroke(.white, lineWidth: 3)
                .frame(width: 250, height: 250)
                .overlay {
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(.white.opacity(0.25), lineWidth: 12)
                }

            Spacer()

            VStack(spacing: 8) {
                Text("Pindai QR Code")
                    .font(.headline)
                Text("Arahkan kamera ke QR yang berisi tautan ujian.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 24)
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white)
            Text("Akses kamera diperlukan")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Izinkan kamera agar Moonzer Student dapat memindai QR Code ujian.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 30)

            Button("Buka Pengaturan") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)

            Button("Kembali ke Menu") {
                session.screen = .menu
            }
            .foregroundStyle(.white)
        }
    }

    private func requestCameraIfNeeded() {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        permission = current
        guard current == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                permission = granted ? .authorized : .denied
            }
        }
    }

    private func handle(_ raw: String) {
        guard confirmURL == nil else { return }
        guard let url = AppUrls.parseScannedHttpUrl(raw),
              let host = URL(string: url)?.host,
              !host.isEmpty else {
            notURL = true
            return
        }
        confirmURL = url
        confirmHost = host
    }
}

struct QRCameraRepresentable: UIViewControllerRepresentable {
    var torchOn: Bool
    var onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {
        uiViewController.onCode = onCode
        uiViewController.setTorch(enabled: torchOn)
    }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var videoDevice: AVCaptureDevice?
    private var handled = false
    private var configured = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCaptureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSessionIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setTorch(enabled: false)
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    func setTorch(enabled: Bool) {
        guard let device = videoDevice, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            if enabled {
                try device.setTorchModeOn(level: min(AVCaptureDevice.maxAvailableTorchLevel, 0.7))
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            // Torch is optional; scanning continues if it cannot be enabled.
        }
    }

    private func configureCaptureSession() {
        guard !configured else { return }

        guard let device = AVCaptureDevice.default(for: .video) else { return }
        videoDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { return }
            session.addInput(input)
        } catch {
            return
        }

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
        configured = true

        startSessionIfNeeded()
    }

    private func startSessionIfNeeded() {
        guard configured, !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !handled,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              !value.isEmpty else { return }

        handled = true
        onCode?(value)

        // Keep the camera session alive so cancel/invalid QR can be scanned again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.handled = false
        }
    }
}

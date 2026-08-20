import Foundation
import Network

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.emoonzer.student.network-monitor")
    private var started = false

    var onStatusChange: ((Bool) -> Void)?

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            DispatchQueue.main.async {
                self?.onStatusChange?(online)
            }
        }
        monitor.start(queue: queue)
    }
}

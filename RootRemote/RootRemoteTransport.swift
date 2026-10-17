import Foundation
import Combine
import Network

final class RootRemoteTransport: ObservableObject {
    @Published private(set) var status = "Chưa kết nối"
    @Published private(set) var isAuthenticated = false
    @Published private(set) var messages: [String] = []
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "RootRemote.transport")
    private var buffer = Data()
    private var token = ""

    func setStatus(_ value: String) { DispatchQueue.main.async { self.status = value } }

    func connect(host: String, port: UInt16, token: String) {
        disconnect()
        self.token = token
        buffer.removeAll()
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { setStatus("Cổng không hợp lệ"); return }
        let conn = NWConnection(to: .hostPort(host: .init(host), port: nwPort), using: .tcp)
        connection = conn
        setStatus("Đang kết nối…")
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.setStatus("Kết nối được, chờ xác thực…"); self.receiveNext()
            case .failed(let error): self.setStatus("Lỗi: \(error.localizedDescription)"); self.append("Kết nối thất bại: \(error)")
            case .cancelled: self.setStatus("Đã ngắt kết nối")
            default: break
            }
        }
        conn.start(queue: queue)
    }

    func send(_ object: [String: Any]) {
        guard let connection,
              let data = try? JSONSerialization.data(withJSONObject: object),
              var line = String(data: data, encoding: .utf8) else {
            append("Chưa kết nối hoặc JSON không hợp lệ"); return
        }
        line += "\n"
        connection.send(content: Data(line.utf8), completion: .contentProcessed { [weak self] error in
            if let error { self?.append("Lỗi gửi: \(error.localizedDescription)") }
        })
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async { self.isAuthenticated = false; self.status = "Đã ngắt kết nối" }
    }

    func clearMessages() { DispatchQueue.main.async { self.messages.removeAll() } }

    private func receiveNext() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { self.buffer.append(data); self.consumeLines() }
            if let error { self.append("Lỗi nhận: \(error.localizedDescription)"); return }
            if complete { self.disconnect() } else { self.receiveNext() }
        }
    }

    private func consumeLines() {
        while let newline = buffer.firstIndex(of: 10) {
            let data = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let obj = try? JSONSerialization.jsonObject(with: data),
                  let response = obj as? [String: Any] else { append("Phản hồi lỗi"); continue }
            if response["type"] as? String == "hello" { send(["token": token]) }
            if response["type"] as? String == "authenticated" {
                DispatchQueue.main.async { self.isAuthenticated = true; self.status = "Đã xác thực" }
            }
            if response["type"] as? String == "error" {
                DispatchQueue.main.async { self.isAuthenticated = false; self.status = "Agent báo lỗi" }
            }
            if let encoded = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]),
               let line = String(data: encoded, encoding: .utf8) { append(line) }
        }
    }

    private func append(_ line: String) {
        DispatchQueue.main.async {
            self.messages.append(line)
            if self.messages.count > 100 { self.messages.removeFirst(self.messages.count - 100) }
        }
    }
}

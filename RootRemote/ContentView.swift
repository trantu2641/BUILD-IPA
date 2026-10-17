import SwiftUI

struct ContentView: View {
    @StateObject private var transport = RootRemoteTransport()
    @State private var host = "127.0.0.1"
    @State private var port = "28741"
    @State private var token = ""
    @State private var x = "500"
    @State private var y = "800"

    var body: some View {
        NavigationView {
            Form {
                Section("Kết nối Android") {
                    TextField("IP / hostname", text: $host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Cổng", text: $port).keyboardType(.numberPad)
                    SecureField("Token", text: $token).textInputAutocapitalization(.never)
                    Button("Kết nối") {
                        guard let p = UInt16(port), !host.isEmpty, !token.isEmpty else {
                            transport.setStatus("Hãy nhập IP, cổng và token."); return
                        }
                        transport.connect(host: host, port: p, token: token)
                    }
                    Button("Ngắt kết nối") { transport.disconnect() }
                    Text(transport.status).font(.footnote)
                }
                Section("Kiểm tra") {
                    Button("Ping") { transport.send(["type":"ping", "seq":Int(Date().timeIntervalSince1970)]) }
                    Button("Trạng thái agent") { transport.send(["type":"status"]) }
                }
                Section("Điều khiển") {
                    HStack {
                        TextField("X pixel", text: $x).keyboardType(.numberPad)
                        TextField("Y pixel", text: $y).keyboardType(.numberPad)
                    }
                    Button("Chạm") {
                        if let px = Int(x), let py = Int(y) {
                            transport.send(["type":"input", "action":"tap", "x":px, "y":py])
                        }
                    }.disabled(!transport.isAuthenticated)
                    Button("Back") {
                        transport.send(["type":"input", "action":"key", "key":"BACK"])
                    }.disabled(!transport.isAuthenticated)
                    Button("Home") {
                        transport.send(["type":"input", "action":"key", "key":"HOME"])
                    }.disabled(!transport.isAuthenticated)
                }
                Section("Nhật ký") {
                    ForEach(Array(transport.messages.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    Button("Xóa nhật ký") { transport.clearMessages() }
                }
                Section {
                    Text("Bản thử nghiệm chưa có truyền màn hình Android, H.264 hoặc WebRTC.")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }.navigationTitle("RootRemote")
        }
    }
}

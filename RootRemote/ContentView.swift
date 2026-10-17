
import SwiftUI

struct ContentView: View {
    @StateObject private var transport = RootRemoteTransport()
    @StateObject private var video = VideoStreamClient()

    @State private var host = "192.168.1.10"
    @State private var port = "28741"
    @State private var videoPort = "28742"
    @State private var token = ""
    @State private var x = "500"
    @State private var y = "800"

    var body: some View {
        NavigationView {
            Form {
                Section("Kết nối Android") {
                    TextField("IP / hostname", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Cổng điều khiển", text: $port)
                        .keyboardType(.numberPad)

                    SecureField("Token", text: $token)
                        .textInputAutocapitalization(.never)

                    Button("Kết nối điều khiển") {
                        guard let p = UInt16(port),
                              !host.isEmpty,
                              !token.isEmpty else {
                            transport.setStatus(
                                "Hãy nhập IP, cổng và token."
                            )
                            return
                        }

                        transport.connect(
                            host: host,
                            port: p,
                            token: token
                        )
                    }

                    Button("Ngắt kết nối điều khiển") {
                        transport.disconnect()
                    }

                    Text(transport.status)
                        .font(.footnote)
                }

                Section("Màn hình Android") {
                    TextField("Cổng video", text: $videoPort)
                        .keyboardType(.numberPad)

                    Button("Kết nối xem màn hình") {
                        guard let p = UInt16(videoPort),
                              !host.isEmpty,
                              !token.isEmpty else {
                            return
                        }

                        video.connect(
                            host: host,
                            port: p,
                            token: token
                        )
                    }

                    Button("Ngắt video") {
                        video.disconnect()
                    }

                    Text(video.status)
                        .font(.footnote)

                    if let image = video.image {
                        GeometryReader { geometry in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(
                                    width: geometry.size.width,
                                    height: geometry.size.height
                                )
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onEnded { value in
                                            guard transport.isAuthenticated,
                                                  let start = androidPoint(
                                                    value.startLocation,
                                                    in: geometry.size
                                                  ),
                                                  let end = androidPoint(
                                                    value.location,
                                                    in: geometry.size
                                                  ) else {
                                                return
                                            }

                                            let dx = abs(
                                                value.location.x -
                                                value.startLocation.x
                                            )
                                            let dy = abs(
                                                value.location.y -
                                                value.startLocation.y
                                            )

                                            if dx < 8 && dy < 8 {
                                                transport.send([
                                                    "type": "input",
                                                    "action": "tap",
                                                    "x": end.x,
                                                    "y": end.y
                                                ])
                                            } else {
                                                transport.send([
                                                    "type": "input",
                                                    "action": "swipe",
                                                    "x1": start.x,
                                                    "y1": start.y,
                                                    "x2": end.x,
                                                    "y2": end.y,
                                                    "duration_ms": 250
                                                ])
                                            }
                                        }
                                )
                        }
                        .frame(height: 360)
                        .frame(maxWidth: .infinity)
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(height: 180)
                            .overlay {
                                Text("Chưa có hình ảnh Android")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                    }
                }

                Section("Kiểm tra") {
                    Button("Ping") {
                        transport.send([
                            "type": "ping",
                            "seq": Int(Date().timeIntervalSince1970)
                        ])
                    }

                    Button("Trạng thái agent") {
                        transport.send(["type": "status"])
                    }
                }

                Section("Điều khiển thủ công") {
                    HStack {
                        TextField("X pixel", text: $x)
                            .keyboardType(.numberPad)

                        TextField("Y pixel", text: $y)
                            .keyboardType(.numberPad)
                    }

                    Button("Chạm") {
                        if let px = Int(x), let py = Int(y) {
                            transport.send([
                                "type": "input",
                                "action": "tap",
                                "x": px,
                                "y": py
                            ])
                        }
                    }
                    .disabled(!transport.isAuthenticated)

                    Button("Back") {
                        transport.send([
                            "type": "input",
                            "action": "key",
                            "key": "BACK"
                        ])
                    }
                    .disabled(!transport.isAuthenticated)

                    Button("Home") {
                        transport.send([
                            "type": "input",
                            "action": "key",
                            "key": "HOME"
                        ])
                    }
                    .disabled(!transport.isAuthenticated)
                }

                Section("Nhật ký") {
                    ForEach(
                        Array(transport.messages.enumerated()),
                        id: \.offset
                    ) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    Button("Xóa nhật ký") {
                        transport.clearMessages()
                    }
                }
            }
            .navigationTitle("RootRemote")
        }
    }

    private func androidPoint(
        _ point: CGPoint,
        in size: CGSize
    ) -> (x: Int, y: Int)? {
        guard video.width > 0,
              video.height > 0,
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        let sourceWidth = CGFloat(video.width)
        let sourceHeight = CGFloat(video.height)
        let scale = min(
            size.width / sourceWidth,
            size.height / sourceHeight
        )

        let renderedWidth = sourceWidth * scale
        let renderedHeight = sourceHeight * scale
        let offsetX = (size.width - renderedWidth) / 2
        let offsetY = (size.height - renderedHeight) / 2

        let px = (point.x - offsetX) / scale
        let py = (point.y - offsetY) / scale

        guard px >= 0,
              py >= 0,
              px < sourceWidth,
              py < sourceHeight else {
            return nil
        }

        return (Int(px), Int(py))
    }
}

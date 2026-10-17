
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
    @State private var showFullScreen = false
    @State private var videoInputError = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    connectionPanel
                    videoPanel
                    checkPanel
                    manualPanel
                    logPanel
                }
                .padding()
            }
            .navigationTitle("RootRemote")
        }
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenAndroidView(
                video: video,
                transport: transport,
                onClose: { showFullScreen = false }
            )
        }
    }

    private var connectionPanel: some View {
        panel("Kết nối Android") {
            TextField("IP / hostname", text: $host)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            TextField("Cổng điều khiển", text: $port)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            SecureField("Token", text: $token)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)

            Button("Kết nối điều khiển") {
                guard let p = UInt16(port),
                      !host.isEmpty,
                      !token.isEmpty else {
                    transport.setStatus("Hãy nhập IP, cổng và token.")
                    return
                }

                transport.connect(host: host, port: p, token: token)
            }
            .buttonStyle(.borderedProminent)

            Button("Ngắt kết nối điều khiển") {
                transport.disconnect()
            }
            .buttonStyle(.bordered)

            Text("Trạng thái: \(transport.status)")
                .font(.footnote)
                .textSelection(.enabled)
        }
    }

    private var videoPanel: some View {
        panel("Màn hình Android") {
            TextField("Cổng video", text: $videoPort)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            Button("Kết nối xem màn hình") {
                guard let p = UInt16(videoPort),
                      p > 0,
                      !host.isEmpty,
                      !token.isEmpty else {
                    videoInputError = "IP, cổng video hoặc token không hợp lệ."
                    return
                }

                videoInputError = ""
                video.connect(host: host, port: p, token: token)
            }
            .buttonStyle(.borderedProminent)

            Button("Ngắt video") {
                video.disconnect()
            }
            .buttonStyle(.bordered)

            Text(videoInputError.isEmpty ? video.status : videoInputError)
                .font(.footnote)
                .textSelection(.enabled)

            if let image = video.image {
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    sendGesture(
                                        value,
                                        size: geometry.size,
                                        fill: false
                                    )
                                }
                        )
                }
                .frame(height: 240)
                .frame(maxWidth: .infinity)

                Button {
                    showFullScreen = true
                } label: {
                    Label(
                        "Toàn màn hình",
                        systemImage: "arrow.up.left.and.arrow.down.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 150)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "display")
                                .font(.largeTitle)

                            Text("Chưa có hình ảnh Android")
                                .font(.footnote)
                        }
                        .foregroundColor(.secondary)
                    }
            }
        }
    }

    private var checkPanel: some View {
        panel("Kiểm tra kết nối") {
            Button("Ping") {
                transport.send([
                    "type": "ping",
                    "seq": Int(Date().timeIntervalSince1970)
                ])
            }
            .buttonStyle(.bordered)
            .disabled(!transport.isAuthenticated)

            Button("Trạng thái agent") {
                transport.send(["type": "status"])
            }
            .buttonStyle(.bordered)
            .disabled(!transport.isAuthenticated)
        }
    }

    private var manualPanel: some View {
        panel("Điều khiển thủ công") {
            HStack {
                TextField("X pixel", text: $x)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)

                TextField("Y pixel", text: $y)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }

            Button("Chạm tại tọa độ") {
                guard let px = Int(x), let py = Int(y) else {
                    return
                }

                transport.send([
                    "type": "input",
                    "action": "tap",
                    "x": px,
                    "y": py
                ])
            }
            .buttonStyle(.borderedProminent)
            .disabled(!transport.isAuthenticated)

            HStack {
                Button {
                    sendKey("BACK")
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!transport.isAuthenticated)

                Button {
                    sendKey("HOME")
                } label: {
                    Label("Home", systemImage: "house")
                }
                .buttonStyle(.bordered)
                .disabled(!transport.isAuthenticated)
            }
        }
    }

    private var logPanel: some View {
        panel("Nhật ký") {
            if transport.messages.isEmpty {
                Text("Chưa có nhật ký.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(
                    Array(transport.messages.enumerated()),
                    id: \.offset
                ) { _, line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                        .padding(.vertical, 3)
                }
            }

            Button("Xóa nhật ký") {
                transport.clearMessages()
            }
            .buttonStyle(.bordered)
        }
    }

    private func panel<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func sendKey(_ key: String) {
        transport.send([
            "type": "input",
            "action": "key",
            "key": key
        ])
    }

    private func sendGesture(
        _ value: DragGesture.Value,
        size: CGSize,
        fill: Bool
    ) {
        guard transport.isAuthenticated,
              let start = androidPoint(
                value.startLocation,
                size: size,
                fill: fill
              ),
              let end = androidPoint(
                value.location,
                size: size,
                fill: fill
              ) else {
            return
        }

        let dx = abs(value.location.x - value.startLocation.x)
        let dy = abs(value.location.y - value.startLocation.y)

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

    private func androidPoint(
        _ point: CGPoint,
        size: CGSize,
        fill: Bool
    ) -> (x: Int, y: Int)? {
        guard video.width > 0,
              video.height > 0,
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        let sourceWidth = CGFloat(video.width)
        let sourceHeight = CGFloat(video.height)

        let widthScale = size.width / sourceWidth
        let heightScale = size.height / sourceHeight
        let scale = fill
            ? max(widthScale, heightScale)
            : min(widthScale, heightScale)

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

private struct FullScreenAndroidView: View {
    @ObservedObject var video: VideoStreamClient
    @ObservedObject var transport: RootRemoteTransport

    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                // Phóng video lấp đầy toàn bộ màn hình.
                // Nếu tỷ lệ Android và iPhone khác nhau,
                // phần dư sẽ bị cắt thay vì để video nhỏ ở giữa.
                if let image = video.image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: geometry.size.width,
                            height: geometry.size.height
                        )
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    sendGesture(
                                        value,
                                        size: geometry.size
                                    )
                                }
                        )
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)

                        Text("Đang chờ hình ảnh Android...")
                            .foregroundColor(.white)
                    }
                }

                // Thanh điều khiển nằm phía trên video.
                VStack {
                    HStack {
                        Button(action: onClose) {
                            Label("Đóng", systemImage: "xmark")
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(Color.black.opacity(0.8))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        Text(video.status)
                            .font(.caption)
                            .lineLimit(2)
                            .padding(8)
                            .background(Color.black.opacity(0.8))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    HStack(spacing: 28) {
                        Button {
                            sendKey("BACK")
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(!transport.isAuthenticated)

                        Button {
                            sendKey("HOME")
                        } label: {
                            Label("Home", systemImage: "house")
                        }
                        .disabled(!transport.isAuthenticated)
                    }
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray.opacity(0.7))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
            .background(Color.black)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
    }

    private func sendKey(_ key: String) {
        transport.send([
            "type": "input",
            "action": "key",
            "key": key
        ])
    }

    private func sendGesture(
        _ value: DragGesture.Value,
        size: CGSize
    ) {
        guard transport.isAuthenticated,
              let start = androidPoint(
                value.startLocation,
                size: size
              ),
              let end = androidPoint(
                value.location,
                size: size
              ) else {
            return
        }

        let dx = abs(value.location.x - value.startLocation.x)
        let dy = abs(value.location.y - value.startLocation.y)

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

    // Ánh xạ tọa độ theo chế độ fill, có tính cả phần ảnh bị cắt.
    private func androidPoint(
        _ point: CGPoint,
        size: CGSize
    ) -> (x: Int, y: Int)? {
        guard video.width > 0,
              video.height > 0,
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        let sourceWidth = CGFloat(video.width)
        let sourceHeight = CGFloat(video.height)

        let scale = max(
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

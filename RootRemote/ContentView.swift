
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
                            video.statusMessageInvalidInput()
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
                                            sendGesture(
                                                value,
                                                size: geometry.size
                                            )
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

                    Button {
                        showFullScreen = true
                    } label: {
                        Label(
                            "Toàn màn hình",
                            systemImage:
                                "arrow.up.left.and.arrow.down.right"
                        )
                    }
                    .disabled(video.image == nil)
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
                        sendKey("BACK")
                    }
                    .disabled(!transport.isAuthenticated)

                    Button("Home") {
                        sendKey("HOME")
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
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenAndroidView(
                video: video,
                transport: transport,
                onClose: {
                    showFullScreen = false
                }
            )
        }
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
              let start = androidPoint(value.startLocation, size: size),
              let end = androidPoint(value.location, size: size) else {
            return
        }

        let dx = abs(
            value.location.x - value.startLocation.x
        )
        let dy = abs(
            value.location.y - value.startLocation.y
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

private struct FullScreenAndroidView: View {
    @ObservedObject var video: VideoStreamClient
    @ObservedObject var transport: RootRemoteTransport

    let onClose: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if let image = video.image {
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

                        Text("Đang chờ hình ảnh Android…")
                            .foregroundColor(.white)
                    }
                }

                VStack {
                    HStack {
                        Button(action: onClose) {
                            Label(
                                "Đóng",
                                systemImage: "xmark"
                            )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Capsule())
                        }

                        Spacer()

                        Text(video.status)
                            .font(.caption)
                            .lineLimit(2)
                            .padding(8)
                            .background(Color.black.opacity(0.75))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    HStack(spacing: 28) {
                        Button {
                            sendKey("BACK")
                        } label: {
                            Label(
                                "Back",
                                systemImage: "chevron.left"
                            )
                        }
                        .disabled(!transport.isAuthenticated)

                        Button {
                            sendKey("HOME")
                        } label: {
                            Label(
                                "Home",
                                systemImage: "house"
                            )
                        }
                        .disabled(!transport.isAuthenticated)
                    }
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                    .background(Color.black.opacity(0.8))
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

        let dx = abs(
            value.location.x - value.startLocation.x
        )
        let dy = abs(
            value.location.y - value.startLocation.y
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

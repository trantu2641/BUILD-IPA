
import SwiftUI
import Security

struct ContentView: View {
    @StateObject private var transport = RootRemoteTransport()
    @StateObject private var video = VideoStreamClient()

    @AppStorage("rootremote.host")
    private var savedHost = "192.168.1.10"

    @AppStorage("rootremote.controlPort")
    private var savedControlPort = "28741"

    @AppStorage("rootremote.videoPort")
    private var savedVideoPort = "28742"

    @AppStorage("rootremote.resolution")
    private var selectedResolution = "1280x720"

    @AppStorage("rootremote.fps")
    private var selectedFPS = 60

    @AppStorage("rootremote.audioEnabled")
    private var audioEnabled = true

    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if transport.isAuthenticated {
                RemoteScreen(
                    video: video,
                    transport: transport,
                    onDisconnect: disconnect,
                    onApplySettings: applyRemoteSettings
                )
            } else {
                connectionScreen
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            password = PasswordStore.load()
        }
        .onChange(of: transport.isAuthenticated) { authenticated in
            if authenticated {
                isConnecting = false
                applyRemoteSettings(
                    resolution: selectedResolution,
                    fps: selectedFPS,
                    audioEnabled: audioEnabled
                )
            }
        }
        .onChange(of: video.image != nil) { hasImage in
            if hasImage {
                isConnecting = false
            }
        }
    }

    private var connectionScreen: some View {
        ZStack {
            Color(red: 0.035, green: 0.045, blue: 0.075)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 35)

                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.system(size: 54, weight: .light))
                        .foregroundStyle(.cyan)

                    VStack(spacing: 8) {
                        Text("RootRemote")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)

                        Text("Điều khiển Android từ xa")
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    VStack(spacing: 16) {
                        field(
                            "Địa chỉ Android",
                            text: $savedHost,
                            icon: "network"
                        )
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                        HStack(spacing: 12) {
                            field(
                                "Cổng điều khiển",
                                text: $savedControlPort,
                                icon: "slider.horizontal.3"
                            )
                            .keyboardType(.numberPad)

                            field(
                                "Cổng video",
                                text: $savedVideoPort,
                                icon: "video"
                            )
                            .keyboardType(.numberPad)
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.cyan)

                            SecureField("Mật khẩu kết nối", text: $password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding(15)
                        .background(.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(20)
                    .background(.white.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 22))

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if isConnecting {
                        ProgressView()
                            .tint(.cyan)

                        Text(transport.status + "\n" + video.status)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }

                    Button(action: connect) {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill")
                            Text(isConnecting ? "Đang kết nối..." : "Kết nối Android")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(17)
                        .background(.cyan)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                    }
                    .disabled(isConnecting)
                    .opacity(isConnecting ? 0.65 : 1)

                    Text("Địa chỉ và cổng được lưu trên thiết bị. Mật khẩu được lưu trong Keychain.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)

                    Spacer(minLength: 30)
                }
                .padding(22)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.cyan)
                    .frame(width: 20)

                TextField(title, text: text)
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(12)
            .background(.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connect() {
        let host = savedHost.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !host.isEmpty,
              !password.isEmpty,
              let control = UInt16(savedControlPort),
              control > 0,
              let videoPort = UInt16(savedVideoPort),
              videoPort > 0 else {
            errorMessage = "Hãy kiểm tra địa chỉ, hai cổng và mật khẩu."
            return
        }

        errorMessage = ""
        isConnecting = true

        PasswordStore.save(password)

        transport.connect(
            host: host,
            port: control,
            token: password
        )

        video.connect(
            host: host,
            port: videoPort,
            token: password
        )
    }

    private func applyRemoteSettings(
        resolution: String,
        fps: Int,
        audioEnabled: Bool
    ) {
        let dimensions = resolution.split(separator: "x")

        guard dimensions.count == 2,
              let width = Int(dimensions[0]),
              let height = Int(dimensions[1]) else {
            return
        }

        // Gửi cấu hình video tới agent Android.
        transport.send([
            "type": "settings",
            "action": "video",
            "width": width,
            "height": height,
            "fps": fps
        ])

        // Gửi lệnh bật/tắt âm thanh tới agent Android.
        transport.send([
            "type": "audio",
            "action": audioEnabled ? "start" : "stop"
        ])
    }

    private func disconnect() {
        video.disconnect()
        transport.disconnect()
        isConnecting = false
    }
}

private struct RemoteScreen: View {
    @ObservedObject var video: VideoStreamClient
    @ObservedObject var transport: RootRemoteTransport

    let onDisconnect: () -> Void
    let onApplySettings: (
        _ resolution: String,
        _ fps: Int,
        _ audioEnabled: Bool
    ) -> Void

    @AppStorage("rootremote.resolution")
    private var selectedResolution = "1280x720"

    @AppStorage("rootremote.fps")
    private var selectedFPS = 60

    @AppStorage("rootremote.audioEnabled")
    private var audioEnabled = true

    @State private var showSettings = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                if let image = video.image {
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
                                        size: geometry.size
                                    )
                                }
                        )
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(.cyan)

                        Text("Đang nhận màn hình Android...")
                            .foregroundStyle(.white)

                        Text(video.status)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }

                VStack {
                    HStack {
                        Circle()
                            .fill(
                                video.image == nil
                                    ? Color.orange
                                    : Color.green
                            )
                            .frame(width: 8, height: 8)

                        Text(
                            video.image == nil
                                ? "Đang kết nối"
                                : "Đang điều khiển"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)

                        Spacer()

                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.black.opacity(0.65))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Cài đặt truyền hình ảnh và âm thanh")

                        Button(action: onDisconnect) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(.black.opacity(0.65))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Ngắt kết nối")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height
            )
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("Độ phân giải màn hình") {
                        Picker(
                            "Độ phân giải",
                            selection: $selectedResolution
                        ) {
                            Text("1280 × 720").tag("1280x720")
                            Text("1920 × 1080").tag("1920x1080")
                        }
                        .pickerStyle(.inline)
                    }

                    Section("Tốc độ khung hình") {
                        Picker("FPS", selection: $selectedFPS) {
                            Text("30 FPS").tag(30)
                            Text("45 FPS").tag(45)
                            Text("60 FPS").tag(60)
                        }
                        .pickerStyle(.segmented)
                    }

                    Section("Âm thanh") {
                        Toggle(
                            "Nghe âm thanh Android",
                            isOn: $audioEnabled
                        )

                        Text(
                            "Lựa chọn được lưu trên iPhone. Agent Android cần hỗ trợ giao thức âm thanh để truyền tiếng thực tế."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    Section {
                        LabeledContent(
                            "Đang chọn",
                            value: "\(selectedResolution.replacingOccurrences(of: "x", with: " × ")) · \(selectedFPS) FPS"
                        )
                    }
                }
                .navigationTitle("Cài đặt truyền")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Hủy") {
                            showSettings = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Áp dụng") {
                            onApplySettings(
                                selectedResolution,
                                selectedFPS,
                                audioEnabled
                            )
                            showSettings = false
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private func sendGesture(
        _ value: DragGesture.Value,
        size: CGSize
    ) {
        guard transport.isAuthenticated,
              video.width > 0,
              video.height > 0,
              size.width > 0,
              size.height > 0 else {
            return
        }

        // Ánh xạ tọa độ theo vùng ảnh thực tế, không tính viền đen.
        let sourceWidth = CGFloat(video.width)
        let sourceHeight = CGFloat(video.height)

        let scale = min(
            size.width / sourceWidth,
            size.height / sourceHeight
        )

        let displayedWidth = sourceWidth * scale
        let displayedHeight = sourceHeight * scale
        let offsetX = (size.width - displayedWidth) / 2
        let offsetY = (size.height - displayedHeight) / 2

        func mapPoint(_ point: CGPoint) -> (x: Int, y: Int)? {
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

        guard let start = mapPoint(value.startLocation),
              let end = mapPoint(value.location) else {
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
}

private enum PasswordStore {
    private static let service = "RootRemote.Connection"
    private static let account = "android-password"

    static func save(_ password: String) {
        guard let data = password.data(using: .utf8) else {
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemAdd(item as CFDictionary, nil)
    }

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return ""
        }

        return password
    }
}

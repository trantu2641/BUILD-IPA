
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

    @AppStorage("rootremote.audioEnabled")
    private var audioEnabled = false

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
                    onAudioChanged: sendAudioSetting
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
                            "Địa chỉ ZeroTier của Android",
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
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
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
                            Text(
                                isConnecting
                                    ? "Đang kết nối..."
                                    : "Kết nối Android"
                            )
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

                    Text(
                        "Nhập Managed IP của Android trong ZeroTier. " +
                        "Mật khẩu được lưu trong Keychain."
                    )
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

    private func sendAudioSetting(_ enabled: Bool) {
        // Android Agent hiện tại chưa triển khai truyền âm thanh thực tế.
        transport.send([
            "type": "audio",
            "action": enabled ? "start" : "stop"
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
    let onAudioChanged: (Bool) -> Void

    @AppStorage("rootremote.audioEnabled")
    private var audioEnabled = false

    @State private var showSettings = false

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size

            ZStack {
                Color.black
                    .ignoresSafeArea()

                if let image = video.image {
                    let sourceW = CGFloat(max(video.width, 1))
                    let sourceH = CGFloat(max(video.height, 1))

                    let scale = min(
                        viewport.width / sourceW,
                        viewport.height / sourceH
                    )

                    let drawnW = sourceW * scale
                    let drawnH = sourceH * scale

                    let imageRect = CGRect(
                        x: (viewport.width - drawnW) / 2,
                        y: (viewport.height - drawnH) / 2,
                        width: drawnW,
                        height: drawnH
                    )

                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(
                            contentMode: .fit
                        )
                        .frame(
                            width: drawnW,
                            height: drawnH
                        )
                        .position(
                            x: viewport.width / 2,
                            y: viewport.height / 2
                        )

                    Color.clear
                        .contentShape(Rectangle())
                        .frame(
                            width: viewport.width,
                            height: viewport.height
                        )
                        .gesture(
                            DragGesture(
                                minimumDistance: 0,
                                coordinateSpace: .local
                            )
                            .onEnded { value in
                                sendGesture(
                                    value,
                                    imageRect: imageRect
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
                    HStack(spacing: 8) {
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
                                .font(
                                    .system(
                                        size: 16,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(.black.opacity(0.65))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Cài đặt")

                        Button(action: onDisconnect) {
                            Image(systemName: "xmark")
                                .font(
                                    .system(
                                        size: 16,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(.black.opacity(0.65))
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("Ngắt kết nối")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                    Spacer()
                }
            }
            .frame(
                width: viewport.width,
                height: viewport.height
            )
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("Luồng video") {
                        LabeledContent(
                            "Kích thước từ Android",
                            value: "\(video.width) × \(video.height)"
                        )

                        Text(
                            "Ứng dụng không tự thay đổi độ phân giải " +
                            "Android khi kết nối."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    Section("Âm thanh") {
                        Toggle(
                            "Yêu cầu âm thanh Android",
                            isOn: $audioEnabled
                        )
                        .onChange(of: audioEnabled) { enabled in
                            onAudioChanged(enabled)
                        }

                        Text(
                            "Tùy chọn này chỉ gửi yêu cầu. Agent Android " +
                            "cần có bộ thu và truyền âm thanh thực tế."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    Section("Trạng thái") {
                        Text(transport.status)
                        Text(video.status)
                    }
                }
                .navigationTitle("Cài đặt RootRemote")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Đóng") {
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
        imageRect: CGRect
    ) {
        guard transport.isAuthenticated,
              video.width > 0,
              video.height > 0,
              imageRect.width > 0,
              imageRect.height > 0 else {
            return
        }

        func map(_ point: CGPoint) -> (x: Int, y: Int)? {
            let px = point.x - imageRect.minX
            let py = point.y - imageRect.minY

            guard px >= 0,
                  py >= 0,
                  px < imageRect.width,
                  py < imageRect.height else {
                return nil
            }

            return (
                x: min(
                    video.width - 1,
                    max(
                        0,
                        Int(
                            px / imageRect.width *
                            CGFloat(video.width)
                        )
                    )
                ),
                y: min(
                    video.height - 1,
                    max(
                        0,
                        Int(
                            py / imageRect.height *
                            CGFloat(video.height)
                        )
                    )
                )
            )
        }

        guard let start = map(value.startLocation),
              let end = map(value.location) else {
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
              let password = String(
                data: data,
                encoding: .utf8
              ) else {
            return ""
        }

        return password
    }
}

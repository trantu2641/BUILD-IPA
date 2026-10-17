
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

    @AppStorage("rootremote.videoQuality")
    private var videoQuality = "720p"

    @AppStorage("rootremote.displayMode")
    private var displayMode = "fit"

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
                    onAudioChanged: sendAudioSetting,
                    videoQuality: $videoQuality,
                    displayMode: $displayMode
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

                            SecureField(
                                "Mật khẩu kết nối",
                                text: $password
                            )
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

    @Binding var videoQuality: String
    @Binding var displayMode: String

    @AppStorage("rootremote.audioEnabled")
    private var audioEnabled = false

    @State private var showSettings = false
    @State private var showFloatingMenu = false
    @State private var isApplyingResolution = false
    @State private var resolutionMessage = ""

    @State private var bubblePosition = CGPoint.zero
    @State private var bubbleDragStart: CGPoint?
    @State private var hasInitialBubblePosition = false

    private let bubbleSize: CGFloat = 42
    private let dragThreshold: CGFloat = 10

    private var targetResolution: (width: Int, height: Int) {
        let portrait = video.height >= video.width

        switch videoQuality {
        case "480p":
            return portrait ? (480, 854) : (854, 480)
        case "1080p":
            return portrait ? (1080, 1920) : (1920, 1080)
        default:
            return portrait ? (720, 1280) : (1280, 720)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.size

            ZStack(alignment: .topLeading) {
                Color.black
                    .ignoresSafeArea()

                if let image = video.image {
                    let sourceW = CGFloat(max(video.width, 1))
                    let sourceH = CGFloat(max(video.height, 1))

                    let scale: CGFloat = {
                        switch displayMode {
                        case "stretch":
                            return 1
                        case "fillCrop":
                            return max(
                                viewport.width / sourceW,
                                viewport.height / sourceH
                            )
                        default:
                            return viewport.width / sourceW
                        }
                    }()

                    let drawnW: CGFloat =
                        displayMode == "stretch"
                        ? viewport.width
                        : sourceW * scale

                    let drawnH: CGFloat =
                        displayMode == "stretch"
                        ? viewport.height
                        : sourceH * scale

                    let imageRect = CGRect(
                        x: (viewport.width - drawnW) / 2,
                        y: (viewport.height - drawnH) / 2,
                        width: drawnW,
                        height: drawnH
                    )

                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: drawnW, height: drawnH)
                        .position(
                            x: viewport.width / 2,
                            y: viewport.height / 2
                        )
                        .frame(
                            width: viewport.width,
                            height: viewport.height
                        )
                        .clipped()

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
                    ProgressView()
                        .tint(.cyan)
                        .frame(
                            width: viewport.width,
                            height: viewport.height
                        )
                }

                floatingBubble(in: viewport)
                    .zIndex(10)
            }
            .frame(width: viewport.width, height: viewport.height)
            .coordinateSpace(name: "remoteScreen")
            .clipped()
            .onAppear {
                setInitialBubblePosition(in: viewport)
            }
            .onChange(of: viewport) { newSize in
                clampBubblePosition(in: newSize)
            }
            .confirmationDialog(
                "RootRemote",
                isPresented: $showFloatingMenu,
                titleVisibility: .visible
            ) {
                Button {
                    showSettings = true
                } label: {
                    Label("Cài đặt", systemImage: "gearshape.fill")
                }

                Button(role: .destructive) {
                    onDisconnect()
                } label: {
                    Label(
                        "Thoát kết nối",
                        systemImage: "xmark.circle.fill"
                    )
                }

                Button("Hủy", role: .cancel) {}
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    // Chạm nhanh mở menu. Kéo chỉ di chuyển bong bóng.
    // Không dùng Button kết hợp simultaneousGesture để tránh
    // việc thả tay sau khi kéo vẫn kích hoạt nút.
    private func floatingBubble(in viewport: CGSize) -> some View {
        let x = hasInitialBubblePosition
            ? bubblePosition.x
            : viewport.width - bubbleSize / 2 - 16

        let y = hasInitialBubblePosition
            ? bubblePosition.y
            : viewport.height * 0.55

        return Image(systemName: "gearshape.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: bubbleSize, height: bubbleSize)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(Color.cyan.opacity(0.28))
                    }
                    .overlay {
                        Circle()
                            .stroke(
                                .white.opacity(0.55),
                                lineWidth: 1
                            )
                    }
            }
            .shadow(
                color: .black.opacity(0.35),
                radius: 6,
                y: 2
            )
            .contentShape(Circle())
            .position(x: x, y: y)
            .gesture(
                DragGesture(
                    minimumDistance: dragThreshold,
                    coordinateSpace: .named("remoteScreen")
                )
                .onChanged { value in
                    if !hasInitialBubblePosition {
                        setInitialBubblePosition(in: viewport)
                    }

                    if bubbleDragStart == nil {
                        bubbleDragStart = bubblePosition
                    }

                    guard let start = bubbleDragStart else {
                        return
                    }

                    bubblePosition = clamp(
                        CGPoint(
                            x: start.x + value.translation.width,
                            y: start.y + value.translation.height
                        ),
                        in: viewport
                    )
                }
                .onEnded { value in
                    let distance = hypot(
                        value.translation.width,
                        value.translation.height
                    )

                    if distance >= dragThreshold {
                        // Kéo xong, dạt về cạnh gần nhất.
                        snapBubbleToNearestSide(in: viewport)
                    } else {
                        // Không kéo đáng kể: coi là chạm.
                        showFloatingMenu = true
                    }

                    bubbleDragStart = nil
                }
            )
            .accessibilityElement()
            .accessibilityLabel("Mở menu RootRemote")
    }

    private func setInitialBubblePosition(in size: CGSize) {
        guard !hasInitialBubblePosition else { return }

        bubblePosition = CGPoint(
            x: size.width - bubbleSize / 2 - 16,
            y: size.height * 0.55
        )

        hasInitialBubblePosition = true
    }

    private func clampBubblePosition(in size: CGSize) {
        guard hasInitialBubblePosition else { return }
        bubblePosition = clamp(bubblePosition, in: size)
    }

    private func clamp(
        _ point: CGPoint,
        in size: CGSize
    ) -> CGPoint {
        CGPoint(
            x: min(
                max(point.x, bubbleSize / 2 + 4),
                size.width - bubbleSize / 2 - 4
            ),
            y: min(
                max(point.y, bubbleSize / 2 + 8),
                size.height - bubbleSize / 2 - 8
            )
        )
    }

    private func snapBubbleToNearestSide(in size: CGSize) {
        let current = clamp(bubblePosition, in: size)

        let leftX = bubbleSize / 2 + 8
        let rightX = size.width - bubbleSize / 2 - 8

        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            bubblePosition = CGPoint(
                x: abs(current.x - leftX) < abs(current.x - rightX)
                    ? leftX
                    : rightX,
                y: current.y
            )
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Chất lượng hình ảnh") {
                    Picker("Độ phân giải", selection: $videoQuality) {
                        Text("480p • Nhẹ").tag("480p")
                        Text("720p • Cân bằng").tag("720p")
                        Text("1080p • Nét cao").tag("1080p")
                    }
                    .pickerStyle(.inline)

                    LabeledContent(
                        "Độ phân giải yêu cầu",
                        value: "\(targetResolution.width) × \(targetResolution.height)"
                    )

                    LabeledContent(
                        "Độ phân giải đang nhận",
                        value: "\(video.width) × \(video.height)"
                    )

                    Button {
                        applyVideoResolution()
                    } label: {
                        HStack {
                            if isApplyingResolution {
                                ProgressView()
                            }

                            Text("Áp dụng độ phân giải")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(
                        isApplyingResolution ||
                        !transport.isAuthenticated
                    )

                    if !resolutionMessage.isEmpty {
                        Text(resolutionMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Text(
                        "Android cần hỗ trợ yêu cầu này và phát lại luồng " +
                        "video ở kích thước mới."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Hiển thị màn hình") {
                    Picker("Chế độ hiển thị", selection: $displayMode) {
                        Text("Lấp đầy, cắt mép").tag("fillCrop")
                        Text("Kéo giãn toàn màn hình").tag("stretch")
                        Text("Giữ tỉ lệ, vừa chiều rộng").tag("fit")
                    }
                    .pickerStyle(.inline)

                    Text(displayModeDescription)
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
                        "Chức năng này cần module Android hỗ trợ thu và " +
                        "truyền âm thanh."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Kết nối") {
                    LabeledContent("Điều khiển", value: transport.status)
                    LabeledContent("Video", value: video.status)
                }
            }
            .navigationTitle("Cài đặt")
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

    private var displayModeDescription: String {
        switch displayMode {
        case "stretch":
            return "Video phủ kín màn hình nhưng hình ảnh có thể bị méo."
        case "fillCrop":
            return "Video phủ kín màn hình; phần vượt khỏi mép bị cắt."
        default:
            return "Video vừa chiều rộng iPhone, giữ tỉ lệ gốc. " +
                   "Có thể có khoảng trống phía trên và dưới."
        }
    }

    private func applyVideoResolution() {
        let resolution = targetResolution

        isApplyingResolution = true
        resolutionMessage =
            "Đã gửi yêu cầu \(resolution.width) × \(resolution.height)."

        transport.send([
            "type": "settings",
            "action": "video",
            "width": resolution.width,
            "height": resolution.height
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isApplyingResolution = false

            if video.width == resolution.width &&
               video.height == resolution.height {
                resolutionMessage = "Luồng video đã dùng độ phân giải mới."
            } else {
                resolutionMessage =
                    "Chưa thấy độ phân giải mới. Cần kiểm tra module Android."
            }
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

            let x = Int(
                px / imageRect.width * CGFloat(video.width)
            )

            let y = Int(
                py / imageRect.height * CGFloat(video.height)
            )

            return (
                x: min(video.width - 1, max(0, x)),
                y: min(video.height - 1, max(0, y))
            )
        }

        guard let start = map(value.startLocation),
              let end = map(value.location) else {
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
              let password = String(
                data: data,
                encoding: .utf8
              ) else {
            return ""
        }

        return password
    }
}

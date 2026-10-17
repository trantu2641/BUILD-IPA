import SwiftUI
import Security

struct ContentView: View {
    @StateObject private var transport = RootRemoteTransport()
    @StateObject private var video = VideoStreamClient()

    @AppStorage("rootremote.host") private var savedHost = "192.168.1.10"
    @AppStorage("rootremote.controlPort") private var savedControlPort = "28741"
    @AppStorage("rootremote.videoPort") private var savedVideoPort = "28742"
    @AppStorage("rootremote.audioEnabled") private var audioEnabled = false
    @AppStorage("rootremote.videoQuality") private var videoQuality = "720p"
    @AppStorage("rootremote.displayMode") private var displayMode = "fillCrop"

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

                    Text("Nhập Managed IP của Android trong ZeroTier. Mật khẩu được lưu trong Keychain.")
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
        let host = savedHost.trimmingCharacters(in: .whitespacesAndNewlines)

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

        transport.connect(host: host, port: control, token: password)
        video.connect(host: host, port: videoPort, token: password)
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

    @AppStorage("rootremote.audioEnabled") private var audioEnabled = false

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
                    let sourceW = CGFloat(
                        max(image.cgImage?.width ?? video.width, 1)
                    )
                    let sourceH = CGFloat(
                        max(image.cgImage?.height ?? video.height, 1)
                    )

                    let fitScale = viewport.width / sourceW

                    let fillScale = max(
                        viewport.width / sourceW,
                        viewport.height / sourceH
                    )

                    let drawnW: CGFloat
                    let drawnH: CGFloat

                    switch displayMode {
                    case "fit":
                        // Khớp toàn bộ chiều rộng, giữ nguyên tỷ lệ.
                        drawnW = viewport.width
                        drawnH = sourceH * fitScale

                    case "stretch":
                        // Giữ chế độ kéo giãn toàn màn hình.
                        drawnW = viewport.width
                        drawnH = viewport.height

                    default:
                        // Giữ chế độ lấp đầy và cắt hình cũ.
                        drawnW = sourceW * fillScale
                        drawnH = sourceH * fillScale
                    }

                    let imageRect = CGRect(
                        x: (viewport.width - drawnW) / 2,
                        y: (viewport.height - drawnH) / 2,
                        width: drawnW,
                        height: drawnH
                    )

                    ZStack {
                        Color.black

                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: drawnW,
                                height: drawnH
                            )
                            .position(
                                x: viewport.width / 2,
                                y: viewport.height / 2
                            )
                    }
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

                // Giữ nguyên bong bóng thao tác.
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
                    Label("Thoát kết nối", systemImage: "xmark.circle.fill")
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

    // Chạm nhanh mở menu; kéo chỉ di chuyển bong bóng.
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
                        Circle().fill(Color.cyan.opacity(0.28))
                    }
                    .overlay {
                        Circle().stroke(.white.opacity(0.55), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            .contentShape(Circle())
            .position(x: x, y: y)
            .highPriorityGesture(
                DragGesture(
                    minimumDistance: 0,
                    coordinateSpace: .named("remoteScreen")
                )
                .onChanged { value in
                    if !hasInitialBubblePosition {
                        setInitialBubblePosition(in: viewport)
                    }

                    if bubbleDragStart == nil {
                        bubbleDragStart = bubblePosition
                    }

                    guard let start = bubbleDragStart else { return }

                    let distance = hypot(
                        value.translation.width,
                        value.translation.height
                    )

                    if distance >= dragThreshold {
                        bubblePosition = clamp(
                            CGPoint(
                                x: start.x + value.translation.width,
                                y: start.y + value.translation.height
                            ),
                            in: viewport
                        )
                    }
                }
                .onEnded { value in
                    let distance = hypot(
                        value.translation.width,
                        value.translation.height
                    )

                    if distance >= dragThreshold {
                        snapBubbleToNearestSide(in: viewport)
                    } else {
                        showFloatingMenu = true
                    }

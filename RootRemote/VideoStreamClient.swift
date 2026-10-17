
import Foundation
import Network
import Combine
import VideoToolbox
import CoreMedia
import CoreVideo
import CoreImage
import UIKit

final class VideoStreamClient: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var status = "Video chưa kết nối"
    @Published private(set) var width = 1280
    @Published private(set) var height = 720

    private let queue = DispatchQueue(
        label: "RootRemote.video",
        qos: .userInteractive
    )

    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var headerReceived = false
    private var token = ""

    private let decoder = H264StreamDecoder()

    init() {
        decoder.onImage = { [weak self] image in
            DispatchQueue.main.async {
                self?.image = image
            }
        }
    }

    func connect(host: String, port: UInt16, token: String) {
        disconnect()

        guard let nwPort = NWEndpoint.Port(rawValue: port),
              !host.isEmpty,
              !token.isEmpty else {
            setStatus("IP, cổng hoặc token không hợp lệ")
            return
        }

        self.token = token
        receiveBuffer.removeAll()
        headerReceived = false

        DispatchQueue.main.async {
            self.image = nil
            self.width = 1280
            self.height = 720
        }

        let conn = NWConnection(
            to: .hostPort(host: NWEndpoint.Host(host), port: nwPort),
            using: .tcp
        )
        connection = conn

        setStatus("Đang kết nối máy chủ video…")

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn else { return }

            switch state {
            case .ready:
                self.setStatus("Đã kết nối TCP video, đang xác thực…")
                self.sendAuthentication(on: conn)
                self.receiveNext(on: conn)

            case .failed(let error):
                self.setStatus("Lỗi video: \(error.localizedDescription)")

            case .cancelled:
                self.setStatus("Video đã ngắt kết nối")

            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil

        receiveBuffer.removeAll()
        headerReceived = false

        queue.async {
            self.decoder.reset()
        }

        DispatchQueue.main.async {
            self.image = nil
            self.status = "Video đã ngắt kết nối"
        }
    }

    private func sendAuthentication(on conn: NWConnection) {
        let object: [String: String] = ["token": token]

        guard let data = try? JSONSerialization.data(
            withJSONObject: object
        ) else {
            setStatus("Không tạo được thông tin xác thực")
            return
        }

        var line = data
        line.append(10)

        conn.send(content: line, completion: .contentProcessed {
            [weak self] error in

            if let error {
                self?.setStatus(
                    "Gửi token video thất bại: \(error.localizedDescription)"
                )
            }
        })
    }

    private func receiveNext(on conn: NWConnection) {
        conn.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self, weak conn] data, _, complete, error in
            guard let self, let conn else { return }

            if let data, !data.isEmpty {
                self.consume(data)
            }

            if let error {
                self.setStatus("Lỗi nhận video: \(error.localizedDescription)")
                return
            }

            if complete {
                self.setStatus("Máy chủ đã đóng luồng video")
                return
            }

            self.receiveNext(on: conn)
        }
    }

    private func consume(_ data: Data) {
        if headerReceived {
            decoder.append(data)
            return
        }

        receiveBuffer.append(data)

        guard let newline = receiveBuffer.firstIndex(of: 10) else {
            if receiveBuffer.count > 8192 {
                setStatus("Header video quá dài hoặc không hợp lệ")
                connection?.cancel()
            }
            return
        }

        let headerData = Data(receiveBuffer[..<newline])
        receiveBuffer.removeSubrange(...newline)

        guard let object = try? JSONSerialization.jsonObject(
            with: headerData
        ) as? [String: Any],
        object["type"] as? String == "video",
        object["codec"] as? String == "h264" else {
            setStatus("Header video không hợp lệ")
            connection?.cancel()
            return
        }

        let w = object["width"] as? Int ?? 1280
        let h = object["height"] as? Int ?? 720

        guard w > 0, h > 0, w <= 8192, h <= 8192 else {
            setStatus("Kích thước video không hợp lệ")
            connection?.cancel()
            return
        }

        headerReceived = true

        DispatchQueue.main.async {
            self.width = w
            self.height = h
            self.status = "Đang nhận H.264 (\(w) × \(h))…"
        }

        // Sau dòng JSON, dữ liệu còn lại là H.264 nhị phân.
        // Tuyệt đối không chuyển phần này thành chuỗi UTF-8.
        if !receiveBuffer.isEmpty {
            decoder.append(receiveBuffer)
            receiveBuffer.removeAll()
        }
    }

    private func setStatus(_ value: String) {
        DispatchQueue.main.async {
            self.status = value
        }
    }
}

private final class H264StreamDecoder {
    var onImage: ((UIImage) -> Void)?

    private var streamBuffer = Data()
    private var pendingPrefixNALs: [Data] = []
    private var accessUnit: [Data] = []

    private var sps: Data?
    private var pps: Data?
    private var formatDescription: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private var frameNumber: Int64 = 0

    private let ciContext = CIContext()

    func reset() {
        streamBuffer.removeAll()
        pendingPrefixNALs.removeAll()
        accessUnit.removeAll()
        sps = nil
        pps = nil
        formatDescription = nil
        frameNumber = 0

        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
    }

    func append(_ data: Data) {
        streamBuffer.append(data)
        extractNALUnits()
    }

    private func extractNALUnits() {
        let bytes = [UInt8](streamBuffer)
        let starts = findStartCodes(bytes)

        guard starts.count >= 2 else { return }

        for index in 0..<(starts.count - 1) {
            let current = starts[index]
            let next = starts[index + 1]

            let payloadStart = current.offset + current.length
            var payloadEnd = next.offset

            while payloadEnd > payloadStart && bytes[payloadEnd - 1] == 0 {
                payloadEnd -= 1
            }

            if payloadEnd > payloadStart {
                processNAL(Data(bytes[payloadStart..<payloadEnd]))
            }
        }

        // Giữ lại NAL cuối vì có thể mới chỉ nhận được một phần qua TCP.
        let lastStart = starts[starts.count - 1].offset
        streamBuffer = Data(bytes[lastStart...])
    }

    private func findStartCodes(
        _ bytes: [UInt8]
    ) -> [(offset: Int, length: Int)] {
        var result: [(offset: Int, length: Int)] = []
        var i = 0

        while i + 2 < bytes.count {
            if i + 3 < bytes.count,
               bytes[i] == 0,
               bytes[i + 1] == 0,
               bytes[i + 2] == 0,
               bytes[i + 3] == 1 {
                result.append((i, 4))
                i += 4
            } else if bytes[i] == 0,
                      bytes[i + 1] == 0,
                      bytes[i + 2] == 1 {
                result.append((i, 3))
                i += 3
            } else {
                i += 1
            }
        }

        return result
    }

    private func processNAL(_ nal: Data) {
        guard let first = nal.first else { return }
        let type = Int(first & 0x1F)

        switch type {
        case 7:
            sps = nal
            rebuildFormat()

        case 8:
            pps = nal
            rebuildFormat()

        case 9:
            // Access Unit Delimiter
            flushAccessUnit()

        case 1, 2, 3, 4, 5:
            let firstMacroblock = readFirstUnsignedExpGolomb(nal)

            if firstMacroblock == 0 && containsSlice(accessUnit) {
                flushAccessUnit()
            }

            if accessUnit.isEmpty && !pendingPrefixNALs.isEmpty {
                accessUnit.append(contentsOf: pendingPrefixNALs)
                pendingPrefixNALs.removeAll()
            }

            accessUnit.append(nal)

        case 10, 11:
            flushAccessUnit()

        default:
            if containsSlice(accessUnit) {
                pendingPrefixNALs.append(nal)
            } else {
                pendingPrefixNALs.append(nal)
            }
        }
    }

    private func containsSlice(_ nals: [Data]) -> Bool {
        nals.contains {
            guard let first = $0.first else { return false }
            let type = Int(first & 0x1F)
            return (1...5).contains(type)
        }
    }

    private func readFirstUnsignedExpGolomb(_ nal: Data) -> Int? {
        guard nal.count > 1 else { return nil }

        // Remove emulation-prevention bytes (00 00 03).
        var rbsp: [UInt8] = []
        let input = Array(nal.dropFirst())
        var zeroCount = 0

        for byte in input {
            if zeroCount >= 2 && byte == 3 {
                zeroCount = 0
                continue
            }

            rbsp.append(byte)

            if byte == 0 {
                zeroCount += 1
            } else {
                zeroCount = 0
            }
        }

        var bitIndex = 0

        func readBit() -> Int? {
            guard bitIndex < rbsp.count * 8 else { return nil }
            let byte = rbsp[bitIndex / 8]
            let shift = 7 - (bitIndex % 8)
            bitIndex += 1
            return Int((byte >> shift) & 1)
        }

        var leadingZeros = 0

        while true {
            guard let bit = readBit() else { return nil }
            if bit == 1 { break }
            leadingZeros += 1
            if leadingZeros > 30 { return nil }
        }

        var suffix = 0
        if leadingZeros > 0 {
            for _ in 0..<leadingZeros {
                guard let bit = readBit() else { return nil }
                suffix = (suffix << 1) | bit
            }
        }

        return ((1 << leadingZeros) - 1) + suffix
    }

    private func rebuildFormat() {
        guard let sps, let pps else { return }

        var description: CMFormatDescription?

        let status: OSStatus = sps.withUnsafeBytes { spsRaw in
            pps.withUnsafeBytes { ppsRaw in
                guard let spsPointer = spsRaw.bindMemory(
                    to: UInt8.self
                ).baseAddress,
                let ppsPointer = ppsRaw.bindMemory(
                    to: UInt8.self
                ).baseAddress else {
                    return kCMFormatDescriptionError_InvalidParameter
                }

                let pointers: [UnsafePointer<UInt8>] = [
                    spsPointer, ppsPointer
                ]
                let sizes = [sps.count, pps.count]

                return pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &description
                        )
                    }
                }
            }
        }

        guard status == noErr,
              let description,
              let videoDescription = description as? CMVideoFormatDescription
        else {
            return
        }

        formatDescription = videoDescription

        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
    }

    private func flushAccessUnit() {
        defer { accessUnit.removeAll() }

        guard containsSlice(accessUnit),
              let formatDescription,
              ensureSession(formatDescription) else {
            return
        }

        // VideoToolbox expects each NAL to have a 4-byte length prefix.
        var bytes = Data()

        for nal in accessUnit {
            let count = UInt32(nal.count)
            bytes.append(contentsOf: [
                UInt8((count >> 24) & 0xFF),
                UInt8((count >> 16) & 0xFF),
                UInt8((count >> 8) & 0xFF),
                UInt8(count & 0xFF)
            ])
            bytes.append(nal)
        }

        guard !bytes.isEmpty else { return }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: bytes.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: bytes.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard blockStatus == kCMBlockBufferNoErr,
              let blockBuffer else {
            return
        }

        let copyStatus = bytes.withUnsafeBytes { rawBuffer -> OSStatus in
            guard let baseAddress = rawBuffer.baseAddress else {
                return kCMBlockBufferBadPointerParameterErr
            }

            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: bytes.count
            )
        }

        guard copyStatus == kCMBlockBufferNoErr else { return }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60),
            presentationTimeStamp: CMTime(
                value: frameNumber,
                timescale: 60
            ),
            decodeTimeStamp: .invalid
        )
        frameNumber += 1

        var sampleSize = bytes.count
        var sampleBuffer: CMSampleBuffer?

        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr,
              let sampleBuffer,
              let session else {
            return
        }

        var flagsOut = VTDecodeInfoFlags()
        VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [],
            frameRefcon: nil,
            infoFlagsOut: &flagsOut
        )
    }

    private func ensureSession(
        _ format: CMVideoFormatDescription
    ) -> Bool {
        if session != nil { return true }

        let callback: VTDecompressionOutputCallback = {
            refCon, _, status, _, imageBuffer, _, _ in

            guard status == noErr,
                  let refCon,
                  let imageBuffer else {
                return
            }

            let decoder = Unmanaged<H264StreamDecoder>
                .fromOpaque(refCon)
                .takeUnretainedValue()

            let pixelBuffer = imageBuffer
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

            if let cgImage = decoder.ciContext.createCGImage(
                ciImage,
                from: ciImage.extent
            ) {
                decoder.onImage?(UIImage(cgImage: cgImage))
            }
        }

        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: callback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self)
                .toOpaque()
        )

        var newSession: VTDecompressionSession?

        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: nil,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &newSession
        )

        guard status == noErr, let newSession else {
            return false
        }

        session = newSession
        return true
    }
}

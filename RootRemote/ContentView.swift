            } else {
                resolutionMessage = "Chưa thấy độ phân giải mới. Cần kiểm tra module Android."
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

            // Không gửi thao tác khi chạm vào vùng viền đen.
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
        guard let data = password.data(using: .utf8) else { return }

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
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return ""
        }

        return password
    }
}

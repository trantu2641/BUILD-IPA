
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

                // Chỉ di chuyển khi ngón tay thực sự kéo.
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

                bubbleDragStart = nil
            }
        )
        .accessibilityLabel("Mở menu RootRemote")
}

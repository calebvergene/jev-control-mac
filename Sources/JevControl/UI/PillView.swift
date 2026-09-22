import SwiftUI

/// The contents of the floating pill: a status dot and one line of text.
struct PillView: View {
    let state: PillState
    let text: String
    let isLatched: Bool

    @State private var pulse = false

    static let height: CGFloat = 34
    static let minWidth: CGFloat = 150
    static let maxWidth: CGFloat = 720

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(state.color)
                .frame(width: 10, height: 10)
                .opacity(pulse && state.isAnimated ? 0.35 : 1)
                .animation(
                    state.isAnimated
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )

            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: true, vertical: false)

            if isLatched {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .frame(minWidth: Self.minWidth)
        .background(
            Capsule().fill(Color.black.opacity(0.86))
        )
        .onAppear { pulse = true }
    }
}

import SwiftUI

/// The contents of the floating pill: a status dot and one line of text.
///
/// Always a single line. A transcript is anchored to its end, so new words
/// arrive on the right and older ones fall off the left — the pill is a window
/// onto the last few seconds of speech, not a transcript you scroll back
/// through.
struct PillView: View {
    let state: PillState
    let text: String
    let isLatched: Bool
    /// Truncate from the front, keeping the newest words visible.
    let anchorToEnd: Bool
    /// Laid out at exactly this width; `PillController` has already measured it.
    let width: CGFloat

    @State private var pulse = false

    static let height: CGFloat = 34
    static let minWidth: CGFloat = 150
    /// Never wider than this, nor than 70% of the screen — see `PillController`.
    static let maxWidth: CGFloat = 720

    static let horizontalPadding: CGFloat = 14
    static let dotWidth: CGFloat = 10
    static let dotSpacing: CGFloat = 9
    static let lockWidth: CGFloat = 16

    /// Width left for the text itself at a given pill width.
    static func textWidth(in total: CGFloat, isLatched: Bool) -> CGFloat {
        total - horizontalPadding * 2 - dotWidth - dotSpacing - (isLatched ? lockWidth : 0)
    }

    var body: some View {
        HStack(spacing: Self.dotSpacing) {
            Circle()
                .fill(state.color)
                .frame(width: Self.dotWidth, height: Self.dotWidth)
                .opacity(pulse && state.isAnimated ? 0.35 : 1)
                .animation(
                    state.isAnimated
                        ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )

            // No fixedSize here: it pins the text to its ideal width, which
            // stops truncation applying at all and clips the end instead.
            Text(text)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(anchorToEnd ? .head : .tail)
                .frame(
                    width: Self.textWidth(in: width, isLatched: isLatched),
                    alignment: anchorToEnd ? .trailing : .leading
                )

            if isLatched {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .frame(width: width, height: Self.height)
        .background(Capsule().fill(Color.black.opacity(0.86)))
        .onAppear { pulse = true }
    }
}

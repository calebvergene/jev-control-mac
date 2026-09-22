import SwiftUI

/// The contents of the floating pill: a status dot and the transcript.
///
/// Short text sits on one line in a capsule. Longer text wraps and the pill
/// grows downward, because a single clipped line hides the newest words —
/// which during a live transcript are the only ones worth reading.
struct PillView: View {
    let state: PillState
    let text: String
    let isLatched: Bool
    /// A transcript still being spoken.
    let isLive: Bool
    /// Laid out at exactly this width; `PillController` has already measured it.
    let width: CGFloat
    let isMultiline: Bool

    @State private var pulse = false

    static let lineHeight: CGFloat = 34
    static let minWidth: CGFloat = 150
    /// Never wider than this, nor than 70% of the screen — see `PillController`.
    static let maxWidth: CGFloat = 720
    /// Beyond this the oldest words are dropped rather than the newest.
    static let maxLines = 5

    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 8
    static let dotWidth: CGFloat = 10
    static let dotSpacing: CGFloat = 9
    static let lockWidth: CGFloat = 16

    /// Width left for the text itself at a given pill width.
    static func textWidth(in total: CGFloat, isLatched: Bool) -> CGFloat {
        total - horizontalPadding * 2 - dotWidth - dotSpacing - (isLatched ? lockWidth : 0)
    }

    var body: some View {
        HStack(alignment: isMultiline ? .top : .center, spacing: Self.dotSpacing) {
            Circle()
                .fill(state.color)
                .frame(width: Self.dotWidth, height: Self.dotWidth)
                .padding(.top, isMultiline ? 4 : 0)
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
                .lineLimit(Self.maxLines)
                .multilineTextAlignment(.leading)
                .frame(
                    width: Self.textWidth(in: width, isLatched: isLatched),
                    alignment: .leading
                )

            if isLatched {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, isMultiline ? 4 : 0)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, isMultiline ? Self.verticalPadding : 0)
        .frame(width: width, alignment: .leading)
        .frame(minHeight: isMultiline ? 0 : Self.lineHeight)
        .background(
            RoundedRectangle(cornerRadius: isMultiline ? 14 : Self.lineHeight / 2)
                .fill(Color.black.opacity(0.86))
        )
        .onAppear { pulse = true }
    }
}

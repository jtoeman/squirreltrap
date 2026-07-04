import AppKit
import SwiftUI

/// Native equivalent of the Ko-fi web widget (which is JS meant for a browser
/// page) — same brand color, opens the same Ko-fi page directly.
struct KofiButton: View {
    var onOpened: () -> Void = {}

    var body: some View {
        Button {
            if let url = URL(string: "https://ko-fi.com/B0B31XCPZQ") {
                NSWorkspace.shared.open(url)
            }
            onOpened()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cup.and.saucer.fill")
                Text("Support me on Ko-fi")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Color(red: 0x72 / 255, green: 0xA4 / 255, blue: 0xF2 / 255),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }
}

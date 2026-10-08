import SwiftUI

/// Controls for the expanded state. HomeView owns the single persistent preview.
struct ExpandedCameraView: View {
    let onClose: () -> Void

    var body: some View {
        VStack {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.black.opacity(0.45), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close camera")
                .accessibilityIdentifier("closeCamera")

                Spacer()
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .accessibilityAction(.escape, onClose)
    }
}

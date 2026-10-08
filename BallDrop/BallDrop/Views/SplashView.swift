import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color(red: 0.87, green: 0.97, blue: 0.40)
                .ignoresSafeArea()

            Text("Let's Play")
                .font(.system(size: 54, weight: .heavy, design: .rounded))
                .tracking(-2)
                .foregroundStyle(Color.black)
                .minimumScaleFactor(0.7)
                .padding(24)
                .scaleEffect(hasAppeared || reduceMotion ? 1 : 0.95)
                .opacity(hasAppeared ? 1 : 0)
                .accessibilityIdentifier("splashTitle")
        }
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.5)) {
                hasAppeared = true
            }
        }
    }
}

#Preview {
    SplashView()
}

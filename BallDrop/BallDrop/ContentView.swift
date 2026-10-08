//
//  ContentView.swift
//  BallDrop
//
//  Created by Abraham May on 10/4/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsSplash = true
    @State private var homeIsActive = false

    var body: some View {
        ZStack {
            HomeView(isPresented: homeIsActive)
                .opacity(showsSplash ? 0 : 1)
                .allowsHitTesting(!showsSplash)
                .accessibilityHidden(showsSplash)

            if showsSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task {
            guard showsSplash else { return }
            do {
                try await Task.sleep(for: .seconds(1.35))
            } catch {
                return
            }

            withAnimation(.easeInOut(duration: reduceMotion ? 0.2 : 0.45)) {
                showsSplash = false
            } completion: {
                // Let the crossfade finish before presenting system permissions.
                homeIsActive = true
            }
        }
    }
}

#Preview {
    ContentView()
}

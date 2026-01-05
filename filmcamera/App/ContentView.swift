//
//  ContentView.swift
//  iOS Vibe Film Camera
//
//  Root view that displays the camera interface
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        CameraView()
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}

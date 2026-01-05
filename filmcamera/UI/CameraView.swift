//
//  CameraView.swift
//  iOS Vibe Film Camera
//
//  Main camera interface with minimal UI
//

import SwiftUI

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            if viewModel.permissionGranted {
                // Full-screen camera preview
                CameraPreviewView(session: viewModel.session)
                    .ignoresSafeArea()

                // Camera controls overlay
                VStack {
                    Spacer()

                    controlsOverlay
                        .padding(.bottom, 40)
                }
            } else {
                // Permission denied or not granted yet
                permissionView
            }

            // Error message overlay
            if let errorMessage = viewModel.errorMessage {
                VStack {
                    Text(errorMessage)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .padding()

                    Spacer()
                }
                .onAppear {
                    // Auto-dismiss error after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        viewModel.errorMessage = nil
                    }
                }
            }
        }
        .onAppear {
            viewModel.checkPermissions()
            viewModel.startSession()
        }
        .onDisappear {
            viewModel.stopSession()
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack(spacing: 20) {
            // EV indicator
            Text("EV: \(viewModel.exposureBias, specifier: "%+.1f")")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

            // Exposure slider
            Slider(
                value: $viewModel.exposureBias,
                in: viewModel.exposureBiasRange.min...viewModel.exposureBiasRange.max,
                step: 0.1
            )
            .padding(.horizontal, 40)
            .tint(.white)

            // Shutter button
            Button(action: {
                viewModel.capturePhoto()
            }) {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 70, height: 70)

                    Circle()
                        .fill(viewModel.isCapturing ? Color.gray : Color.white)
                        .frame(width: 60, height: 60)
                }
            }
            .disabled(viewModel.isCapturing)
            .padding(.vertical, 10)

            // Resolution indicator
            Text(viewModel.resolutionLabel)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
        }
    }

    // MARK: - Permission View

    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("Camera Access Required")
                .font(.headline)

            Text("Please grant camera and photo library access to use this app.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)

            Button("Retry") {
                viewModel.checkPermissions()
            }
            .padding()
        }
    }
}

#Preview {
    CameraView()
}

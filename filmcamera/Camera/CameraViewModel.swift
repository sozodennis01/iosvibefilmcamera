//
//  CameraViewModel.swift
//  iOS Vibe Film Camera
//
//  SwiftUI state management for camera interface
//

import SwiftUI
import AVFoundation
import Photos

class CameraViewModel: ObservableObject {
    @Published var exposureBias: Float = 0.0 {
        didSet {
            cameraSession.setExposureBias(exposureBias)
        }
    }

    @Published var isCapturing = false
    @Published var permissionGranted = false
    @Published var errorMessage: String?

    let cameraSession = CameraSession()
    private let pipeline = FilmPipeline()
    private let storage = PhotoLibraryManager()
    private var captureController: CaptureController?

    var session: AVCaptureSession {
        cameraSession.captureSession
    }

    var resolutionLabel: String {
        let dims = cameraSession.maxPhotoDimensions
        let megapixels = Float(dims.width * dims.height) / 1_000_000
        return String(format: "%.0fMP", megapixels)
    }

    var exposureBiasRange: (min: Float, max: Float) {
        cameraSession.getExposureBiasRange()
    }

    // MARK: - Initialization

    init() {
        captureController = CaptureController(
            session: cameraSession,
            pipeline: pipeline,
            storage: storage
        )
        captureController?.delegate = self
    }

    // MARK: - Permissions

    func checkPermissions() {
        Task {
            let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            let photosStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)

            let cameraGranted: Bool
            let photosGranted: Bool

            // Request camera permission
            if cameraStatus == .notDetermined {
                cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
            } else {
                cameraGranted = cameraStatus == .authorized
            }

            // Request photos permission
            if photosStatus == .notDetermined {
                photosGranted = await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
            } else {
                photosGranted = photosStatus == .authorized || photosStatus == .limited
            }

            await MainActor.run {
                self.permissionGranted = cameraGranted && photosGranted

                if !cameraGranted {
                    self.errorMessage = "Camera access denied. Please enable in Settings."
                } else if !photosGranted {
                    self.errorMessage = "Photos access denied. Please enable in Settings."
                }
            }
        }
    }

    // MARK: - Session Control

    func startSession() {
        guard permissionGranted else {
            checkPermissions()
            return
        }

        do {
            try cameraSession.configure()
            cameraSession.startRunning()
        } catch {
            errorMessage = "Failed to start camera: \(error.localizedDescription)"
        }
    }

    func stopSession() {
        cameraSession.stopRunning()
    }

    // MARK: - Capture

    func capturePhoto() {
        guard !isCapturing else { return }
        captureController?.capturePhoto()
    }
}

// MARK: - CaptureControllerDelegate

extension CameraViewModel: CaptureControllerDelegate {
    func captureDidStart() {
        isCapturing = true
    }

    func captureDidFinish(success: Bool) {
        isCapturing = false

        if !success {
            errorMessage = "Capture failed"
        }
    }

    func captureDidFail(error: Error) {
        errorMessage = "Capture error: \(error.localizedDescription)"
    }
}

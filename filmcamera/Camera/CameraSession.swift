//
//  CameraSession.swift
//  iOS Vibe Film Camera
//
//  Manages AVCaptureSession and device configuration for maximum resolution capture
//

import AVFoundation
import UIKit

class CameraSession: NSObject {
    let captureSession = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()

    private var currentDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?

    var maxPhotoDimensions: CMVideoDimensions {
        if #available(iOS 16.0, *) {
            return photoOutput.maxPhotoDimensions
        } else {
            // Fallback for iOS 15
            return CMVideoDimensions(width: 4032, height: 3024)
        }
    }

    // MARK: - Configuration

    func configure() throws {
        // 1. Select primary wide camera
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            throw CameraError.deviceNotFound
        }

        currentDevice = device

        // 2. Configure session
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo  // Required for max resolution

        // 3. Add input
        do {
            let input = try AVCaptureDeviceInput(device: device)

            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                videoInput = input
            } else {
                throw CameraError.cannotAddInput
            }
        } catch {
            captureSession.commitConfiguration()
            throw CameraError.inputCreationFailed(error)
        }

        // 4. Configure photo output for max resolution
        photoOutput.isHighResolutionCaptureEnabled = true
        photoOutput.maxPhotoQualityPrioritization = .speed  // Reduce computational stacking

        // 5. Set max photo dimensions (iOS 16+)
        if #available(iOS 16.0, *) {
            let maxDimensions = device.activeFormat.supportedMaxPhotoDimensions.max { dim1, dim2 in
                dim1.width * dim1.height < dim2.width * dim2.height
            } ?? CMVideoDimensions(width: 4032, height: 3024)

            photoOutput.maxPhotoDimensions = maxDimensions
        }

        // 6. Add output
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        } else {
            captureSession.commitConfiguration()
            throw CameraError.cannotAddOutput
        }

        captureSession.commitConfiguration()
    }

    // MARK: - Session Control

    func startRunning() {
        if !captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.startRunning()
            }
        }
    }

    func stopRunning() {
        if captureSession.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession.stopRunning()
            }
        }
    }

    // MARK: - Exposure Control

    func setExposureBias(_ ev: Float) {
        guard let device = currentDevice else { return }

        do {
            try device.lockForConfiguration()

            // Clamp to device limits
            let clampedEV = max(device.minExposureTargetBias,
                               min(device.maxExposureTargetBias, ev))

            device.setExposureTargetBias(clampedEV, completionHandler: nil)

            device.unlockForConfiguration()
        } catch {
            print("Error setting exposure bias: \(error)")
        }
    }

    func getExposureBiasRange() -> (min: Float, max: Float) {
        guard let device = currentDevice else {
            return (-3.0, 3.0)
        }

        return (device.minExposureTargetBias, device.maxExposureTargetBias)
    }
}

// MARK: - Errors

enum CameraError: Error {
    case deviceNotFound
    case cannotAddInput
    case cannotAddOutput
    case inputCreationFailed(Error)

    var localizedDescription: String {
        switch self {
        case .deviceNotFound:
            return "Camera device not found"
        case .cannotAddInput:
            return "Cannot add camera input to session"
        case .cannotAddOutput:
            return "Cannot add photo output to session"
        case .inputCreationFailed(let error):
            return "Failed to create camera input: \(error.localizedDescription)"
        }
    }
}

//
//  CaptureController.swift
//  iOS Vibe Film Camera
//
//  Coordinates the photo capture flow and delegates processing
//

import AVFoundation
import UIKit

protocol CaptureControllerDelegate: AnyObject {
    func captureDidStart()
    func captureDidFinish(success: Bool)
    func captureDidFail(error: Error)
}

class CaptureController: NSObject {
    weak var delegate: CaptureControllerDelegate?

    private let session: CameraSession
    private let pipeline: FilmPipeline
    private let storage: PhotoLibraryManager

    private var isCapturing = false

    init(session: CameraSession, pipeline: FilmPipeline, storage: PhotoLibraryManager) {
        self.session = session
        self.pipeline = pipeline
        self.storage = storage
    }

    // MARK: - Capture

    func capturePhoto() {
        guard !isCapturing else { return }

        isCapturing = true
        delegate?.captureDidStart()

        var settings = AVCapturePhotoSettings()

        // Request max resolution
        if #available(iOS 16.0, *) {
            settings.maxPhotoDimensions = session.photoOutput.maxPhotoDimensions
        }

        // Disable auxiliary outputs (depth, semantic segmentation)
        settings.isDepthDataDeliveryEnabled = false

        // Speed over quality - reduce computational processing
        settings.photoQualityPrioritization = .speed

        session.photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CaptureController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        defer {
            isCapturing = false
        }

        if let error = error {
            delegate?.captureDidFail(error: error)
            delegate?.captureDidFinish(success: false)
            return
        }

        // Validate capture
        let dimensions = photo.resolvedSettings.photoDimensions
        let megapixels = Float(dimensions.width * dimensions.height) / 1_000_000
        print("✓ Captured: \(dimensions.width) × \(dimensions.height) (\(String(format: "%.1f", megapixels))MP)")

        // Process and save on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            do {
                // Get image data
                guard let imageData = photo.fileDataRepresentation() else {
                    throw CaptureError.noImageData
                }

                // Create CIImage from photo data (lazy evaluation)
                guard let ciImage = CIImage(data: imageData) else {
                    throw CaptureError.cannotCreateCIImage
                }

                // Process through film pipeline
                let processed = self.pipeline.process(ciImage)

                // Convert to CGImage
                guard let cgImage = self.pipeline.context.createCGImage(
                    processed,
                    from: processed.extent,
                    format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
                ) else {
                    throw CaptureError.cannotCreateCGImage
                }

                // Get metadata from original photo
                var metadata: [String: Any] = [:]
                if let metadataDict = photo.metadata as? [String: Any] {
                    metadata = metadataDict
                }

                // Save to Photos library
                try self.storage.savePhoto(cgImage: cgImage, metadata: metadata)

                print("✓ Saved to Photos library")

                DispatchQueue.main.async {
                    self.delegate?.captureDidFinish(success: true)
                }

            } catch {
                print("✗ Capture failed: \(error)")
                DispatchQueue.main.async {
                    self.delegate?.captureDidFail(error: error)
                    self.delegate?.captureDidFinish(success: false)
                }
            }
        }
    }
}

// MARK: - Errors

enum CaptureError: Error {
    case noImageData
    case cannotCreateCIImage
    case cannotCreateCGImage

    var localizedDescription: String {
        switch self {
        case .noImageData:
            return "No image data available from capture"
        case .cannotCreateCIImage:
            return "Cannot create CIImage from captured data"
        case .cannotCreateCGImage:
            return "Cannot create CGImage from processed image"
        }
    }
}

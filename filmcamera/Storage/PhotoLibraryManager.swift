//
//  PhotoLibraryManager.swift
//  iOS Vibe Film Camera
//
//  Handles HEIF encoding and saving to Photos library
//

import UIKit
import Photos
import ImageIO
import AVFoundation

class PhotoLibraryManager {
    // MARK: - HEIF Encoding Configuration

    private let heifQuality: Float = 0.45  // Balance between size and quality

    // MARK: - Save Photo

    func savePhoto(cgImage: CGImage, metadata: [String: Any]) throws {
        // 1. Create temporary file URL
        let tempURL = temporaryFileURL()

        // 2. Encode to HEIF
        try encodeAsHEIF(cgImage: cgImage, to: tempURL, metadata: metadata)

        // 3. Save to Photos library
        try saveToPhotosLibrary(fileURL: tempURL)

        // 4. Clean up temporary file
        try? FileManager.default.removeItem(at: tempURL)
    }

    // MARK: - HEIF Encoding

    private func encodeAsHEIF(cgImage: CGImage, to url: URL, metadata: [String: Any]) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            AVFileType.heic as CFString,
            1,
            nil
        ) else {
            throw PhotoLibraryError.cannotCreateDestination
        }

        // Build metadata dictionary
        var metadataDict = metadata

        // Add/override with our own metadata
        var exifDict = (metadata[kCGImagePropertyExifDictionary as String] as? [String: Any]) ?? [:]
        exifDict[kCGImagePropertyExifDateTimeOriginal as String] = ISO8601DateFormatter().string(from: Date())
        exifDict[kCGImagePropertyExifLensMake as String] = "Apple"
        exifDict[kCGImagePropertyExifSoftware as String] = "FilmCamera 1.0"

        var tiffDict = (metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any]) ?? [:]
        tiffDict[kCGImagePropertyTIFFMake as String] = "Apple"
        tiffDict[kCGImagePropertyTIFFModel as String] = UIDevice.current.model
        tiffDict[kCGImagePropertyTIFFSoftware as String] = "FilmCamera 1.0"

        metadataDict[kCGImagePropertyExifDictionary as String] = exifDict
        metadataDict[kCGImagePropertyTIFFDictionary as String] = tiffDict

        // Configure compression and metadata
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: heifQuality,
            kCGImagePropertyOrientation: CGImagePropertyOrientation.up.rawValue,
            kCGImageDestinationMetadata: metadataDict
        ]

        // Add image to destination
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        // Finalize and write
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoLibraryError.encodingFailed
        }

        // Log file size
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            let sizeMB = Double(fileSize) / 1_000_000
            print("✓ HEIF encoded: \(String(format: "%.2f", sizeMB))MB at quality \(heifQuality)")
        }
    }

    // MARK: - Photos Library

    private func saveToPhotosLibrary(fileURL: URL) throws {
        var saveError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        PHPhotoLibrary.shared().performChanges({
            PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
        }) { success, error in
            if !success {
                saveError = error ?? PhotoLibraryError.saveFailed
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = saveError {
            throw error
        }
    }

    // MARK: - Utilities

    private func temporaryFileURL() -> URL {
        let filename = "filmcamera_\(UUID().uuidString).heic"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}

// MARK: - Errors

enum PhotoLibraryError: Error {
    case cannotCreateDestination
    case encodingFailed
    case saveFailed

    var localizedDescription: String {
        switch self {
        case .cannotCreateDestination:
            return "Cannot create image destination for HEIF encoding"
        case .encodingFailed:
            return "Failed to encode image as HEIF"
        case .saveFailed:
            return "Failed to save image to Photos library"
        }
    }
}

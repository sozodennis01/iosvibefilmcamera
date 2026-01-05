//
//  ToneCurve.swift
//  iOS Vibe Film Camera
//
//  Filmic tone curve for Portra 400 aesthetic
//  Characteristics: lifted shadows, soft highlight rolloff, reduced contrast
//

import CoreImage

class ToneCurve {
    // MARK: - Filmic Curve

    func applyFilmicCurve(to image: CIImage) -> CIImage {
        // Use CIToneCurve with key points for Portra-like response:
        //
        // Toe (shadows): Lift blacks, add detail retention
        // Midtones: Slightly reduced contrast
        // Shoulder (highlights): Smooth rolloff to prevent clipping

        guard let toneCurve = CIFilter(name: "CIToneCurve") else {
            return image
        }

        toneCurve.setValue(image, forKey: kCIInputImageKey)

        // Point 0: Lifted blacks (0.0 -> 0.03)
        // Instead of pure black, we start at a slight gray
        toneCurve.setValue(CIVector(x: 0.0, y: 0.03), forKey: "inputPoint0")

        // Point 1: Soft toe transition (0.15 -> 0.12)
        // Gentle transition from shadows to mids
        toneCurve.setValue(CIVector(x: 0.15, y: 0.12), forKey: "inputPoint1")

        // Point 2: Midtones (0.5 -> 0.48)
        // Slightly reduced contrast in the middle
        toneCurve.setValue(CIVector(x: 0.5, y: 0.48), forKey: "inputPoint2")

        // Point 3: Start shoulder (0.85 -> 0.82)
        // Begin highlight rolloff
        toneCurve.setValue(CIVector(x: 0.85, y: 0.82), forKey: "inputPoint3")

        // Point 4: Soft clip (1.0 -> 0.97)
        // Prevent harsh white clipping
        toneCurve.setValue(CIVector(x: 1.0, y: 0.97), forKey: "inputPoint4")

        return toneCurve.outputImage ?? image
    }
}

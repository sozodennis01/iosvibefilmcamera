//
//  FilmPipeline.swift
//  iOS Vibe Film Camera
//
//  Main film emulation processing pipeline
//  Applies Kodak Portra 400 look to captured images
//

import CoreImage
import CoreGraphics
import UIKit

class FilmPipeline {
    let context: CIContext
    private let lutFilter: CIFilter?
    private let toneCurve: ToneCurve
    private let grainGenerator: GrainGenerator

    init() {
        // Metal-backed context for GPU processing
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

        context = CIContext(options: [
            .workingColorSpace: colorSpace,
            .outputColorSpace: colorSpace,
            .useSoftwareRenderer: false,
            .cacheIntermediates: false  // Reduce memory pressure
        ])

        // Load Portra 400 LUT
        lutFilter = LUTLoader.loadLUT(named: "portra400")

        toneCurve = ToneCurve()
        grainGenerator = GrainGenerator()
    }

    // MARK: - Processing Pipeline

    func process(_ image: CIImage) -> CIImage {
        var output = image

        // 1. Apply filmic tone curve (lifted shadows, soft highlights)
        output = toneCurve.applyFilmicCurve(to: output)

        // 2. Apply 3D LUT (Kodak Portra 400 color science)
        if let lut = lutFilter {
            lut.setValue(output, forKey: kCIInputImageKey)
            output = lut.outputImage ?? output
        }

        // 3. Highlight desaturation (reduce saturation in bright areas)
        output = desaturateHighlights(output)

        // 4. Film grain (luma noise, stronger in shadows/mids)
        output = grainGenerator.addFilmGrain(to: output, extent: image.extent)

        return output
    }

    // MARK: - Highlight Desaturation

    private func desaturateHighlights(_ image: CIImage) -> CIImage {
        // Create luminance mask for highlights
        let luminanceMask = CIFilter(name: "CIColorMatrix")!
        luminanceMask.setValue(image, forKey: kCIInputImageKey)

        // Convert to luminance (Rec. 709 weights)
        luminanceMask.setValue(CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0), forKey: "inputRVector")
        luminanceMask.setValue(CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0), forKey: "inputGVector")
        luminanceMask.setValue(CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0), forKey: "inputBVector")
        luminanceMask.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")

        guard let mask = luminanceMask.outputImage else { return image }

        // Threshold to isolate highlights (values above 0.7)
        let highlightMask = CIFilter(name: "CIColorClamp")!
        highlightMask.setValue(mask, forKey: kCIInputImageKey)
        highlightMask.setValue(CIVector(x: 0.7, y: 0.7, z: 0.7, w: 1.0), forKey: "inputMinComponents")
        highlightMask.setValue(CIVector(x: 1.0, y: 1.0, z: 1.0, w: 1.0), forKey: "inputMaxComponents")

        guard let clampedMask = highlightMask.outputImage else { return image }

        // Desaturate the image
        let desaturate = CIFilter(name: "CIColorControls")!
        desaturate.setValue(image, forKey: kCIInputImageKey)
        desaturate.setValue(0.7, forKey: kCIInputSaturationKey)  // Reduce saturation to 70%

        guard let desaturatedImage = desaturate.outputImage else { return image }

        // Blend original with desaturated based on highlight mask
        let blend = CIFilter(name: "CIBlendWithMask")!
        blend.setValue(desaturatedImage, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(clampedMask, forKey: kCIInputMaskImageKey)

        return blend.outputImage ?? image
    }
}

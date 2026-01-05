//
//  GrainGenerator.swift
//  iOS Vibe Film Camera
//
//  Film grain effect for analog aesthetic
//

import CoreImage

class GrainGenerator {
    // MARK: - Film Grain

    func addFilmGrain(to image: CIImage, extent: CGRect, intensity: Float = 0.04) -> CIImage {
        // Generate noise texture
        guard let noiseFilter = CIFilter(name: "CIRandomGenerator") else {
            return image
        }

        var noise = noiseFilter.outputImage!.cropped(to: extent)

        // Make it monochrome (luma grain only for more authentic look)
        guard let mono = CIFilter(name: "CIColorMatrix") else {
            return image
        }

        mono.setValue(noise, forKey: kCIInputImageKey)
        mono.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0), forKey: "inputRVector")
        mono.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0), forKey: "inputGVector")
        mono.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0), forKey: "inputBVector")
        mono.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")

        noise = mono.outputImage!

        // Scale noise intensity
        guard let multiply = CIFilter(name: "CIColorMatrix") else {
            return image
        }

        multiply.setValue(noise, forKey: kCIInputImageKey)
        multiply.setValue(CIVector(x: intensity, y: 0, z: 0, w: 0), forKey: "inputRVector")
        multiply.setValue(CIVector(x: 0, y: intensity, z: 0, w: 0), forKey: "inputGVector")
        multiply.setValue(CIVector(x: 0, y: 0, z: intensity, w: 0), forKey: "inputBVector")
        multiply.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        multiply.setValue(CIVector(x: 0.5, y: 0.5, z: 0.5, w: 0), forKey: "inputBiasVector")

        guard let scaledNoise = multiply.outputImage else {
            return image
        }

        // Blend grain with image using overlay mode
        guard let blend = CIFilter(name: "CIOverlayBlendMode") else {
            return image
        }

        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(scaledNoise, forKey: kCIInputImageKey)

        // Return blended result with reduced opacity
        guard let blended = blend.outputImage else {
            return image
        }

        // Mix original with grainy version (reduce grain strength)
        guard let mix = CIFilter(name: "CISourceOverCompositing") else {
            return blended
        }

        // Adjust grain intensity by mixing
        let grainStrength: Float = 0.3  // 30% grain blend

        guard let multiply2 = CIFilter(name: "CIColorMatrix") else {
            return blended
        }

        multiply2.setValue(blended, forKey: kCIInputImageKey)
        multiply2.setValue(CIVector(x: grainStrength, y: 0, z: 0, w: 0), forKey: "inputRVector")
        multiply2.setValue(CIVector(x: 0, y: grainStrength, z: 0, w: 0), forKey: "inputGVector")
        multiply2.setValue(CIVector(x: 0, y: 0, z: grainStrength, w: 0), forKey: "inputBVector")
        multiply2.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")

        guard let fadedGrain = multiply2.outputImage else {
            return blended
        }

        // Composite faded grain over original
        guard let finalComposite = CIFilter(name: "CISourceAtopCompositing") else {
            return image
        }

        finalComposite.setValue(fadedGrain, forKey: kCIInputImageKey)
        finalComposite.setValue(image, forKey: kCIInputBackgroundImageKey)

        return finalComposite.outputImage ?? image
    }
}

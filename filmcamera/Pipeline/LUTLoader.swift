//
//  LUTLoader.swift
//  iOS Vibe Film Camera
//
//  Utilities for loading and applying 3D LUTs
//

import CoreImage
import UIKit

class LUTLoader {
    // MARK: - LUT Loading

    static func loadLUT(named name: String) -> CIFilter? {
        // For MVP, create a synthetic Portra 400-inspired LUT
        // In production, this would load from a .cube file or PNG
        return createSyntheticPortra400LUT()
    }

    // MARK: - Synthetic Portra 400 LUT

    private static func createSyntheticPortra400LUT() -> CIFilter? {
        // Create a 64x64x64 color cube that approximates Portra 400 characteristics:
        // - Warm skin tones (peachy/golden shift in mids)
        // - Lifted shadows with blue/cyan cast
        // - Subtle desaturation in highlights
        // - Overall warmth

        let dimension = 64
        let cubeDataSize = dimension * dimension * dimension * 4 // RGBA
        var cubeData = [Float](repeating: 0, count: cubeDataSize)

        var index = 0
        for blue in 0..<dimension {
            for green in 0..<dimension {
                for red in 0..<dimension {
                    // Normalize to 0-1
                    let r = Float(red) / Float(dimension - 1)
                    let g = Float(green) / Float(dimension - 1)
                    let b = Float(blue) / Float(dimension - 1)

                    // Calculate luminance
                    let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b

                    // Apply Portra 400 characteristics
                    var outR = r
                    var outG = g
                    var outB = b

                    // 1. Add warmth in midtones (boost reds, slightly reduce blues)
                    if luma > 0.2 && luma < 0.8 {
                        let midtoneStrength = 1.0 - abs(luma - 0.5) * 2.0
                        outR += 0.05 * midtoneStrength
                        outB -= 0.02 * midtoneStrength
                    }

                    // 2. Lift shadows with cyan/blue cast
                    if luma < 0.3 {
                        let shadowStrength = (0.3 - luma) / 0.3
                        outB += 0.04 * shadowStrength
                        outG += 0.02 * shadowStrength
                    }

                    // 3. Add peachy/golden tint to skin tone range (warm mids)
                    // Detect skin-like colors (higher red, moderate green, lower blue)
                    if r > 0.4 && r > g && g > b && luma > 0.3 && luma < 0.7 {
                        outR += 0.03
                        outG += 0.01
                    }

                    // 4. Slight overall warmth
                    outR += 0.02
                    outG += 0.01

                    // Clamp values
                    outR = min(max(outR, 0.0), 1.0)
                    outG = min(max(outG, 0.0), 1.0)
                    outB = min(max(outB, 0.0), 1.0)

                    cubeData[index] = outR
                    cubeData[index + 1] = outG
                    cubeData[index + 2] = outB
                    cubeData[index + 3] = 1.0  // Alpha

                    index += 4
                }
            }
        }

        // Create CIColorCube filter
        guard let filter = CIFilter(name: "CIColorCube") else {
            return nil
        }

        let cubeDataNS = NSData(bytes: cubeData, length: cubeDataSize * MemoryLayout<Float>.size)
        filter.setValue(dimension, forKey: "inputCubeDimension")
        filter.setValue(cubeDataNS, forKey: "inputCubeData")

        return filter
    }
}

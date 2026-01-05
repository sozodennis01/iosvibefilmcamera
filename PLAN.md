# iOS Vibe Film Camera - Prototype Plan

## BLUF (Bottom Line Up Front)

Build a minimal iOS camera prototype around AVFoundation still capture at max resolution, a single exposure-bias slider, and a single Kodak 400 look transform applied post-ISP to the captured image. Save the result as HEIF with high compression via CGImageDestination/ImageIO and Photos/PhotoKit.

**Core Philosophy**: Skip Apple's stock camera pipeline. Pull directly from the sensor with minimal processing, then apply our own film emulation post-capture.

---

## 0. Scope Definition

### In Scope (MVP)

| Feature | Description |
|---------|-------------|
| Full-screen viewfinder | Unfiltered live preview via `AVCaptureVideoPreviewLayer` |
| Exposure slider | Single EV bias control (-3 to +3 range typically) |
| Shutter button | Single press capture |
| Max resolution capture | Target 48MP where device supports |
| Kodak 400 emulation | Applied post-capture to still image |
| HEIF output | High compression for small file sizes |

### Out of Scope (Future Iterations)

- Manual shutter speed / ISO controls
- RAW/DNG capture
- Live LUT preview (expensive at 48MP)
- Portrait mode / Live Photos
- Multi-lens switching UI
- Film stock selector (start with one look, nail it)

---

## 1. Technical Architecture

### Module Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         UI Layer                            │
│  ┌─────────────┐  ┌──────────────┐  ┌───────────────────┐  │
│  │ PreviewView │  │ ExposureSlider│  │  ShutterButton   │  │
│  └─────────────┘  └──────────────┘  └───────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    CaptureController                        │
│         Coordinates capture flow, handles state             │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
┌─────────────────┐  ┌────────────────┐  ┌─────────────────┐
│  CameraSession  │  │  FilmPipeline  │  │    Storage      │
│                 │  │                │  │                 │
│ • AVCaptureSession│ • Tone curve   │  │ • HEIF encode   │
│ • Device config │  │ • 3D LUT      │  │ • PhotoKit save │
│ • Photo output  │  │ • Grain       │  │ • Metadata      │
└─────────────────┘  └────────────────┘  └─────────────────┘
```

### Key Design Decisions

1. **Live view stays unfiltered** - Fast, simple, stable. No thermal issues.
2. **Film emulation applies only to captured photo** - Process once, not 30fps.
3. **Single Core Image render pass** - Chain filters as graph, render once at end.
4. **Modular separation** - Camera, pipeline, storage are independent. Swap CI for Metal later if needed.

---

## 2. Camera Capture Implementation

### Device & Session Configuration

```swift
// Target configuration
class CameraSession {
    let captureSession = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()

    func configure() {
        // 1. Select primary wide camera
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else { return }

        // 2. Configure session
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo  // Required for max res

        // 3. Add input
        let input = try AVCaptureDeviceInput(device: device)
        captureSession.addInput(input)

        // 4. Configure photo output for max resolution
        photoOutput.isHighResolutionCaptureEnabled = true
        photoOutput.maxPhotoQualityPrioritization = .speed  // Reduce computational stacking

        // 5. Set max photo dimensions (iOS 16+)
        if #available(iOS 16.0, *) {
            photoOutput.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
                $0.width * $0.height < $1.width * $1.height
            }) ?? CMVideoDimensions(width: 4032, height: 3024)
        }

        captureSession.addOutput(photoOutput)
        captureSession.commitConfiguration()
    }
}
```

### Exposure Slider Behavior

```swift
// EV bias range: device.minExposureTargetBias ... device.maxExposureTargetBias
// Typical: -8.0 to +8.0, but clamp to useful range (-3 to +3)

func setExposureBias(_ ev: Float) {
    guard let device = currentDevice else { return }

    let clampedEV = max(device.minExposureTargetBias,
                        min(device.maxExposureTargetBias, ev))

    try? device.lockForConfiguration()
    device.setExposureTargetBias(clampedEV, completionHandler: nil)
    device.unlockForConfiguration()
}
```

### Capture Settings

```swift
func capturePhoto() {
    var settings = AVCapturePhotoSettings()

    // Request max resolution
    if #available(iOS 16.0, *) {
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
    }

    // Disable auxiliary outputs (depth, semantic segmentation)
    settings.isDepthDataDeliveryEnabled = false

    // Speed over quality - reduce computational processing
    settings.photoQualityPrioritization = .speed

    photoOutput.capturePhoto(with: settings, delegate: captureDelegate)
}
```

### Validation Checklist

- [ ] Captured image reports expected pixel dimensions (8064x6048 for 48MP)
- [ ] Wide lens confirmed via device.deviceType
- [ ] Image orientation matches device orientation

---

## 3. Kodak 400 Film Emulation Pipeline

### Target Aesthetic: Kodak Portra 400

Portra 400 characteristics:
- Warm skin tones (slightly peachy/golden)
- Lifted shadows with blue/cyan cast
- Soft shoulder rolloff in highlights
- Subtle desaturation in highlights
- Fine grain structure, more visible in shadows/mids
- Overall slightly lower contrast than digital

### Pipeline Order of Operations

```
┌─────────────────────────────────────────────────────────────┐
│                    Input Image (sRGB/P3)                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              1. Working Space Normalization                 │
│                    (Convert to linear P3)                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              2. Exposure Adjustment (if needed)             │
│                    (Linear multiply)                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   3. Filmic Tone Curve                      │
│            (Soft toe + shoulder, reduce contrast)           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      4. 3D LUT Apply                        │
│              (Kodak Portra 400 color science)               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              5. Highlight Desaturation                      │
│          (Mask by luma, reduce sat in bright areas)         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        6. Grain                             │
│      (Band-limited luma noise, stronger in shadows/mids)    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Output Image (sRGB/P3)                   │
└─────────────────────────────────────────────────────────────┘
```

### Core Image Implementation Sketch

```swift
class FilmPipeline {
    let context: CIContext
    let lutFilter: CIFilter?

    init() {
        // Metal-backed context for GPU processing
        context = CIContext(options: [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
            .useSoftwareRenderer: false
        ])

        // Load Portra 400 LUT (64x64x64 recommended)
        lutFilter = loadLUT(named: "portra400")
    }

    func process(_ image: CIImage) -> CIImage {
        var output = image

        // 1. Filmic tone curve
        output = applyFilmicCurve(output)

        // 2. Apply 3D LUT
        if let lut = lutFilter {
            lut.setValue(output, forKey: kCIInputImageKey)
            output = lut.outputImage ?? output
        }

        // 3. Highlight desaturation
        output = desaturateHighlights(output)

        // 4. Film grain (last)
        output = addFilmGrain(output)

        return output
    }
}
```

### Filmic Tone Curve Parameters

```swift
func applyFilmicCurve(_ image: CIImage) -> CIImage {
    // Use CIToneCurve or custom cubic spline
    // Key points for Portra-like response:

    // Toe (shadows): Lift blacks, add slight blue cast
    // point0: (0.0, 0.03)   // Lifted blacks
    // point1: (0.15, 0.12)  // Soft toe transition

    // Midtones: Slightly reduced contrast
    // point2: (0.5, 0.48)   // Neutral mid

    // Shoulder (highlights): Smooth rolloff
    // point3: (0.85, 0.82)  // Start shoulder
    // point4: (1.0, 0.97)   // Soft clip

    let toneCurve = CIFilter(name: "CIToneCurve")!
    toneCurve.setValue(image, forKey: kCIInputImageKey)
    toneCurve.setValue(CIVector(x: 0.0, y: 0.03), forKey: "inputPoint0")
    toneCurve.setValue(CIVector(x: 0.15, y: 0.12), forKey: "inputPoint1")
    toneCurve.setValue(CIVector(x: 0.5, y: 0.48), forKey: "inputPoint2")
    toneCurve.setValue(CIVector(x: 0.85, y: 0.82), forKey: "inputPoint3")
    toneCurve.setValue(CIVector(x: 1.0, y: 0.97), forKey: "inputPoint4")

    return toneCurve.outputImage ?? image
}
```

### Film Grain Implementation

```swift
func addFilmGrain(_ image: CIImage, intensity: Float = 0.04) -> CIImage {
    // Generate noise texture
    let noiseFilter = CIFilter(name: "CIRandomGenerator")!
    var noise = noiseFilter.outputImage!.cropped(to: image.extent)

    // Make it monochrome (luma grain only)
    let mono = CIFilter(name: "CIColorMatrix")!
    mono.setValue(noise, forKey: kCIInputImageKey)
    mono.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0), forKey: "inputRVector")
    mono.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0), forKey: "inputGVector")
    mono.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0), forKey: "inputBVector")
    noise = mono.outputImage!

    // Blend with image (soft light works well for grain)
    let blend = CIFilter(name: "CISoftLightBlendMode")!
    blend.setValue(image, forKey: kCIInputBackgroundImageKey)
    blend.setValue(noise, forKey: kCIInputImageKey)

    // Reduce intensity
    let mix = CIFilter(name: "CISourceOverCompositing")!
    // ... adjust opacity

    return blend.outputImage ?? image
}
```

### LUT Format & Loading

```swift
// Recommended: 64x64x64 3D LUT as .cube file or embedded PNG
// For MVP: Use a proven Portra 400 LUT from reputable source

func loadLUT(named name: String) -> CIFilter? {
    guard let lutImage = UIImage(named: name)?.cgImage else { return nil }

    let colorCube = CIFilter(name: "CIColorCubeWithColorSpace")!

    // Extract cube data from image...
    // (Implementation depends on LUT format)

    return colorCube
}
```

---

## 4. Performance Strategy

### 48MP Processing Constraints

| Constraint | Value |
|------------|-------|
| Image size | ~48 megapixels (8064 x 6048) |
| Memory per image | ~550MB uncompressed (RGBA float) |
| Processing target | < 3 seconds capture-to-saved |
| Thermal budget | Sustainable for 10+ shots |

### Implementation Strategy

```swift
func processAndSave(_ photoData: AVCapturePhoto) {
    // 1. Move to background queue immediately
    DispatchQueue.global(qos: .userInitiated).async {

        // 2. Create CIImage from photo data (lazy evaluation)
        guard let ciImage = CIImage(data: photoData.fileDataRepresentation()!) else { return }

        // 3. Build filter chain (no intermediate renders)
        let pipeline = FilmPipeline()
        let processed = pipeline.process(ciImage)

        // 4. Single render pass to CGImage
        let cgImage = context.createCGImage(
            processed,
            from: processed.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!
        )

        // 5. Encode to HEIF
        self.saveAsHEIF(cgImage)
    }
}
```

### Memory Pressure Fallback

```swift
// If processing fails due to memory, fall back to scaled processing
func processWithFallback(_ image: CIImage) -> CIImage {
    let maxDimension: CGFloat = 8064
    let currentMax = max(image.extent.width, image.extent.height)

    if currentMax > maxDimension {
        // Scale down to 75% if needed
        let scale = (maxDimension * 0.75) / currentMax
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        return image.transformed(by: transform)
    }

    return image
}
```

---

## 5. HEIF Output Configuration

### Encoding Strategy

Goal: Smaller files than stock camera at similar resolution.

```swift
func saveAsHEIF(_ cgImage: CGImage, quality: Float = 0.45) {
    let url = temporaryFileURL(extension: "heic")

    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        AVFileType.heic as CFString,
        1,
        nil
    ) else { return }

    // Configure compression
    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: quality,  // 0.35-0.55 range
        kCGImagePropertyOrientation: CGImagePropertyOrientation.up.rawValue
    ]

    CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
    CGImageDestinationFinalize(destination)

    // Save to Photos library
    saveToPhotosLibrary(url)
}
```

### Quality vs Size Tradeoffs

| Quality | Approx File Size (48MP) | Notes |
|---------|------------------------|-------|
| 0.35 | ~3-4 MB | Aggressive, may show banding |
| 0.45 | ~5-6 MB | Good balance (recommended) |
| 0.55 | ~7-9 MB | Higher quality, still smaller than JPEG |
| 0.70 | ~12-15 MB | Near-reference quality |

### Metadata Preservation

```swift
// Preserve essential EXIF
let metadata: [CFString: Any] = [
    kCGImagePropertyExifDictionary: [
        kCGImagePropertyExifDateTimeOriginal: ISO8601DateFormatter().string(from: Date()),
        kCGImagePropertyExifLensMake: "Apple",
        kCGImagePropertyExifFocalLength: 26  // Wide lens equiv
    ],
    kCGImagePropertyTIFFDictionary: [
        kCGImagePropertyTIFFMake: "Apple",
        kCGImagePropertyTIFFModel: UIDevice.current.model,
        kCGImagePropertyTIFFSoftware: "FilmCamera 1.0"
    ]
]
```

---

## 6. UI Specification

### Layout (Super Minimal)

```
┌─────────────────────────────────────────┐
│                                         │
│                                         │
│                                         │
│           Full-screen Preview           │
│        (AVCaptureVideoPreviewLayer)     │
│                                         │
│                                         │
│                                         │
├─────────────────────────────────────────┤
│                                         │
│    EV: -0.7                             │
│    ←────────●─────────────────────→     │
│                                         │
│              [ ◉ ]                      │  ← Shutter button
│                                         │
│    48MP                                 │  ← Resolution indicator
│                                         │
└─────────────────────────────────────────┘
```

### SwiftUI Structure

```swift
struct CameraView: View {
    @StateObject var viewModel = CameraViewModel()

    var body: some View {
        ZStack {
            // Full-screen preview
            CameraPreviewView(session: viewModel.session)
                .ignoresSafeArea()

            VStack {
                Spacer()

                // EV indicator
                Text("EV: \(viewModel.exposureBias, specifier: "%.1f")")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white)

                // Exposure slider
                Slider(value: $viewModel.exposureBias, in: -3...3, step: 0.1)
                    .padding(.horizontal, 40)
                    .tint(.white)

                // Shutter button
                Button(action: viewModel.capturePhoto) {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .fill(Color.white)
                                .frame(width: 60, height: 60)
                        )
                }
                .disabled(viewModel.isCapturing)
                .padding(.vertical, 20)

                // Resolution indicator
                Text(viewModel.resolutionLabel)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.bottom, 20)
            }
        }
    }
}
```

### No Settings Screen

For MVP, hardcode:
- Film look: Kodak Portra 400
- HEIF quality: 0.45
- Output color space: Display P3

---

## 7. Validation Plan

### Capture Validation

```swift
// After each capture, log:
func validateCapture(_ photo: AVCapturePhoto) {
    let dimensions = photo.resolvedSettings.photoDimensions
    print("Captured: \(dimensions.width) x \(dimensions.height)")

    // Verify 48MP: should be ~8064 x 6048 or similar
    let megapixels = Float(dimensions.width * dimensions.height) / 1_000_000
    print("Resolution: \(megapixels)MP")

    // Verify lens
    // (check device configuration)
}
```

### Look Validation Test Set

Shoot these scenarios and compare against Portra 400 reference images:

| Scene | What to Check |
|-------|---------------|
| Daylight skin tones | Warm but not orange, smooth gradation |
| Shade/greenery | Not too green, slight blue in shadows |
| Tungsten indoor | Warm overall, lifted shadows |
| Specular highlights | Smooth rolloff, no clipping |
| Deep shadows | Blue/cyan cast, visible detail |
| High contrast | Reduced contrast, film-like dynamic range |

### Output Validation

| Metric | Target |
|--------|--------|
| File size (48MP) | 4-8 MB at quality 0.45 |
| Banding | None visible at 100% zoom |
| Color accuracy | P3 preserved |
| Metadata | Orientation, date, lens info present |

---

## 8. Development Milestones

Each milestone produces a working, testable build.

### M1: Camera MVP
**Goal**: Viewfinder + shutter saves unprocessed max-res image

- [ ] Set up AVCaptureSession with wide camera
- [ ] Display full-screen preview layer
- [ ] Configure AVCapturePhotoOutput for max resolution
- [ ] Implement shutter button that triggers capture
- [ ] Save unprocessed capture as HEIF to Photos
- [ ] Verify 48MP capture in image metadata

**Validation**: Take 10 photos, confirm all are 48MP, saved correctly.

### M2: Exposure Slider
**Goal**: EV bias controls capture exposure reliably

- [ ] Add slider UI (-3 to +3 EV range)
- [ ] Connect slider to device.setExposureTargetBias()
- [ ] Display current EV value
- [ ] Verify exposure changes in captured images

**Validation**: Shoot same scene at -2, 0, +2 EV. Confirm clear exposure difference.

### M3: Kodak 400 Pipeline
**Goal**: Film emulation applied post-capture

- [ ] Implement filmic tone curve
- [ ] Integrate Portra 400 LUT
- [ ] Add highlight desaturation
- [ ] Add film grain
- [ ] Process captured image through pipeline
- [ ] Save processed result

**Validation**: Run test set (Section 7), compare to Portra 400 references.

### M4: HEIF High Compression
**Goal**: Small file sizes with acceptable quality

- [ ] Configure CGImageDestination with quality 0.45
- [ ] Preserve essential metadata
- [ ] Measure file sizes across test set
- [ ] Check for banding artifacts
- [ ] Adjust quality if needed

**Validation**: Average file size < 7MB for 48MP. No visible banding.

### M5: Hardening
**Goal**: Production-ready stability

- [ ] Handle camera permission denial gracefully
- [ ] Add memory pressure handling
- [ ] Test thermal behavior (20 rapid shots)
- [ ] Handle orientation changes
- [ ] Add capture-in-progress state to prevent double-tap
- [ ] Error states and user feedback

**Validation**: App survives abuse testing, doesn't crash, handles errors gracefully.

---

## 9. Expert Tradeoff Analysis

### Imaging Engineer Perspective
> "Prioritize tone curve + highlight behavior. LUT alone often looks 'preset-y' or Instagram-filter-cheap. The filmic response curve is what sells the analog feel. Spend time on the shoulder rolloff."

**Action**: Tune tone curve before LUT. May need multiple curve iterations.

### Performance Engineer Perspective
> "Don't do live LUT preview at 48MP. That's 30fps of 550MB image processing. Keep preview unfiltered until the core flow is stable and you've profiled memory. Add preview later as optimization."

**Action**: Live preview stays raw. Process only captured stills.

### iOS Architect Perspective
> "Separate camera, pipeline, and storage modules from day one. You'll want to swap Core Image for Metal shaders eventually. Clean interfaces now save painful refactors later."

**Action**: Define clear protocols between modules. FilmPipeline is a protocol.

### Product/UX Perspective
> "One look + one slider is the perfect MVP. Resist the urge to add film stock options, presets, or toggles until you prove users actually like the Portra output. Ship and learn."

**Action**: No settings. No options. One look. One slider. Ship.

---

## 10. Future Considerations (Post-MVP)

Not for now, but documenting for later:

1. **Live LUT preview** - Requires downscaled processing or Metal optimization
2. **Multiple film stocks** - Portra 160, Ektar 100, CineStill 800T
3. **RAW capture option** - For users who want to process elsewhere
4. **Manual controls** - Shutter speed, ISO, focus
5. **Halation effect** - Warm glow around bright highlights
6. **Lens switching** - Ultra-wide, telephoto
7. **Export formats** - JPEG, TIFF options
8. **iCloud sync** - For cross-device access

---

## File Structure (Proposed)

```
filmcamera/
├── App/
│   ├── filmcameraApp.swift
│   └── ContentView.swift
├── Camera/
│   ├── CameraSession.swift        # AVCaptureSession management
│   ├── CaptureController.swift    # Capture flow coordination
│   └── CameraPreviewView.swift    # UIViewRepresentable for preview
├── Pipeline/
│   ├── FilmPipeline.swift         # Main processing pipeline
│   ├── ToneCurve.swift            # Filmic curve implementation
│   ├── LUTLoader.swift            # 3D LUT loading utilities
│   └── GrainGenerator.swift       # Film grain effect
├── Storage/
│   ├── HEIFEncoder.swift          # HEIF compression & metadata
│   └── PhotoLibrary.swift         # PhotoKit integration
├── UI/
│   ├── CameraView.swift           # Main camera interface
│   ├── ExposureSlider.swift       # EV control
│   └── ShutterButton.swift        # Capture button
└── Resources/
    └── LUTs/
        └── portra400.cube         # Kodak Portra 400 LUT
```

---

## Notes on "No Fusion" Reference

The user references the "No Fusion" camera app as proof-of-concept that bypassing Apple's computational pipeline is possible. Key takeaways:

1. **It's possible** - AVFoundation allows access to minimally-processed sensor data
2. **Quality settings matter** - `.speed` prioritization reduces computational stacking
3. **Max resolution is achievable** - 48MP capture works on supported devices
4. **Post-processing is viable** - Apply your own look after ISP, not before

This prototype follows the same philosophy: minimal capture, custom post-processing.

---

## Quick Reference: Key APIs

| Task | API |
|------|-----|
| Camera session | `AVCaptureSession` |
| Photo capture | `AVCapturePhotoOutput` |
| Preview layer | `AVCaptureVideoPreviewLayer` |
| Exposure control | `AVCaptureDevice.setExposureTargetBias()` |
| Max resolution | `AVCapturePhotoOutput.maxPhotoDimensions` |
| Image processing | `CIContext`, `CIFilter` |
| HEIF encoding | `CGImageDestinationCreateWithURL` with `AVFileType.heic` |
| Photo saving | `PHPhotoLibrary.shared().performChanges()` |

---

*Last updated: January 2026*
*Status: Planning Phase*

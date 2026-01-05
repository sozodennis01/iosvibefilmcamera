# Claude Implementation Notes - iOS Vibe Film Camera

## Implementation Summary

Building a minimal iOS camera app that bypasses Apple's computational photography pipeline to create authentic film-like images with Kodak Portra 400 emulation.

## Core Approach

1. **Direct Sensor Access**: Use AVFoundation with `.speed` prioritization to minimize computational stacking
2. **Post-Capture Processing**: Apply film emulation to captured stills (not live preview)
3. **Modular Architecture**: Separate Camera, Pipeline, Storage layers for maintainability
4. **Performance First**: Single Core Image render pass, background processing, memory-aware

## Implementation Phases

### Phase 1: Camera Foundation (M1)
- Set up AVCaptureSession with max resolution (48MP)
- Full-screen preview with AVCaptureVideoPreviewLayer
- Basic capture and HEIF save to Photos library
- Validation: Confirm 48MP captures

### Phase 2: Exposure Control (M2)
- Add EV bias slider (-3 to +3)
- Wire to AVCaptureDevice.setExposureTargetBias()
- Display current EV value
- Validation: Verify exposure changes in output

### Phase 3: Film Emulation Pipeline (M3)
- Implement filmic tone curve (lifted shadows, soft highlights)
- Load and apply Kodak Portra 400 3D LUT
- Add highlight desaturation
- Add film grain (luma noise)
- Validation: Compare against Portra 400 reference images

### Phase 4: HEIF Compression (M4)
- Configure CGImageDestination with quality 0.45
- Preserve EXIF metadata
- Target: 4-8MB per 48MP image
- Validation: Check for banding, measure file sizes

### Phase 5: Hardening (M5)
- Camera permissions handling
- Memory pressure fallbacks
- Thermal management
- Orientation handling
- Error states and user feedback
- Validation: Stress testing (20+ rapid captures)

## Key Technical Decisions

### Why No Live Preview Filter?
- 48MP at 30fps = 550MB/frame processing
- Causes thermal throttling and battery drain
- Live preview stays unfiltered for MVP stability

### Why Start with One Film Look?
- Easier to perfect one aesthetic than ship mediocre multiple options
- Reduces scope, accelerates learning
- Can add Portra 160, Ektar 100, etc. based on user feedback

### Why Core Image Not Metal?
- Faster to implement for MVP
- Sufficient performance for post-capture processing
- Can optimize to Metal shaders later if needed
- Clean FilmPipeline protocol enables easy swap

### Why HEIF Over JPEG?
- Better compression at same quality (40-50% smaller)
- Wide color gamut (P3) support
- Native iOS format, excellent Photos app integration

## File Structure

```
filmcamera/
├── App/
│   ├── filmcameraApp.swift         # App entry point
│   └── ContentView.swift            # Root view
├── Camera/
│   ├── CameraSession.swift          # AVCaptureSession wrapper
│   ├── CaptureController.swift      # Capture coordination
│   ├── CameraPreviewView.swift      # Preview layer UIViewRepresentable
│   └── CameraViewModel.swift        # SwiftUI state management
├── Pipeline/
│   ├── FilmPipeline.swift           # Main processing protocol + impl
│   ├── ToneCurve.swift              # Filmic curve algorithms
│   ├── LUTLoader.swift              # 3D LUT loading
│   └── GrainGenerator.swift         # Film grain effect
├── Storage/
│   ├── HEIFEncoder.swift            # HEIF compression
│   └── PhotoLibraryManager.swift    # PhotoKit integration
├── UI/
│   └── CameraView.swift             # Main camera UI
└── Resources/
    └── LUTs/
        └── portra400.cube           # Kodak Portra 400 LUT
```

## Critical Performance Optimizations

1. **Background Processing**: Move all image processing to `.userInitiated` queue
2. **Single Render Pass**: Build filter chain, render once (not per-filter)
3. **Lazy Evaluation**: CIImage operations are lazy until `createCGImage()`
4. **Color Space Consistency**: Use Display P3 throughout pipeline
5. **Memory Fallback**: Scale to 75% if memory pressure detected

## Testing Strategy

### Validation Scenes
- Daylight portraits (skin tone warmth)
- Shade/greenery (shadow blue cast)
- Indoor tungsten (overall warmth)
- Specular highlights (rolloff smoothness)
- Deep shadows (cyan cast, detail retention)
- High contrast (dynamic range compression)

### Success Metrics
- Capture resolution: 48MP (8064x6048)
- File size: 4-8MB per image
- Processing time: < 3 seconds capture-to-saved
- Thermal: Sustained 10+ shots without throttling
- No visible banding at 100% zoom
- Accurate P3 color preservation

## Development Order

1. ✅ Read and understand PLAN.md
2. ✅ Create claude.md implementation notes
3. ⬜ Set up Xcode project structure
4. ⬜ Implement M1: Camera MVP (capture + save)
5. ⬜ Implement M2: Exposure slider
6. ⬜ Implement M3: Film pipeline (tone + LUT + grain)
7. ⬜ Implement M4: HEIF compression
8. ⬜ Implement M5: Hardening and error handling
9. ⬜ Test with validation scene set
10. ⬜ Commit and push to branch

## References

- PLAN.md: Complete technical specification
- "No Fusion" app: Proof of concept for minimal processing approach
- AVFoundation docs: Camera session and photo output configuration
- Core Image docs: Filter chains and color management

---

**Status**: Implementation in progress
**Target**: Working prototype with Kodak Portra 400 look
**Branch**: claude/read-plan-implement-Q1zOP

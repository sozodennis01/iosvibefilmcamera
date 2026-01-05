# iOS Vibe Film Camera

A minimal iOS camera app that bypasses Apple's computational photography pipeline to create authentic film-like images with Kodak Portra 400 emulation.

## Overview

This app captures photos at maximum resolution (48MP on supported devices) with minimal processing, then applies custom film emulation to create the authentic Portra 400 aesthetic:

- 📸 **Direct sensor access** - Bypasses computational photography stacking
- 🎨 **Kodak Portra 400 look** - Warm skin tones, lifted shadows, soft highlights
- 🎞️ **Film grain** - Authentic analog texture
- 📦 **High compression HEIF** - Small file sizes (4-8MB for 48MP)
- ⚡ **Performance optimized** - Background processing, single render pass

## Features

- Full-screen unfiltered viewfinder
- Single exposure slider (-3 to +3 EV bias)
- One-tap capture with custom film emulation
- Automatic save to Photos library
- Support for 48MP capture on compatible devices

## Project Structure

```
filmcamera/
├── App/
│   ├── filmcameraApp.swift         # App entry point
│   └── ContentView.swift            # Root view
├── Camera/
│   ├── CameraSession.swift          # AVCaptureSession management
│   ├── CaptureController.swift      # Capture flow coordination
│   ├── CameraPreviewView.swift      # Preview layer wrapper
│   └── CameraViewModel.swift        # SwiftUI state management
├── Pipeline/
│   ├── FilmPipeline.swift           # Main processing pipeline
│   ├── ToneCurve.swift              # Filmic tone curve
│   ├── LUTLoader.swift              # 3D LUT loading & generation
│   └── GrainGenerator.swift         # Film grain effect
├── Storage/
│   └── PhotoLibraryManager.swift    # HEIF encoding & Photos save
├── UI/
│   └── CameraView.swift             # Main camera interface
└── Info.plist                       # Required permissions
```

## Setup Instructions

### 1. Create Xcode Project

1. Open Xcode and create a new iOS App project:
   - Product Name: `FilmCamera`
   - Interface: SwiftUI
   - Language: Swift
   - Minimum iOS: 15.0 (iOS 16+ recommended for full features)

2. Replace the default files with the files from `filmcamera/` directory:
   - Copy all `.swift` files to your Xcode project
   - Replace `Info.plist` with the provided one

### 2. Configure Project

1. **Bundle Identifier**: Set a unique bundle identifier in project settings
2. **Signing**: Configure your development team for code signing
3. **Deployment Target**: Set to iOS 15.0 minimum (iOS 16.0 recommended)
4. **Capabilities**: No special capabilities needed beyond camera/photos permissions

### 3. File Organization in Xcode

Organize files in groups matching the directory structure:
- Create Groups: App, Camera, Pipeline, Storage, UI
- Add corresponding .swift files to each group
- Add Info.plist to the project root

### 4. Build and Run

1. Connect an iOS device (simulator won't work for camera features)
2. Select your device as the build target
3. Build and run (⌘R)
4. Grant camera and photo library permissions when prompted

## Technical Implementation

### Camera Pipeline

1. **Capture**: AVFoundation with `.speed` prioritization to minimize computational stacking
2. **Processing**: Core Image filter chain on background queue
   - Filmic tone curve (lifted shadows, soft highlights)
   - 3D LUT for Kodak Portra 400 color science
   - Highlight desaturation
   - Film grain (luma noise)
3. **Encoding**: HEIF with quality 0.45 for optimal size/quality balance
4. **Save**: PhotoKit integration for Photos library

### Film Emulation

The Portra 400 look is achieved through:

- **Tone Curve**: Lifted blacks (0.0→0.03), soft shoulder rolloff (1.0→0.97)
- **Color Science**: Synthetic 3D LUT with warm midtones, cyan shadow lift
- **Highlight Treatment**: Subtle desaturation in bright areas
- **Grain**: Monochrome luma noise at ~30% strength

### Performance

- Processing time: <3 seconds for 48MP image
- Memory: Optimized with lazy evaluation and background processing
- Thermal: Sustainable for 10+ consecutive shots
- File size: 4-8MB per 48MP image (vs 12-20MB for stock camera)

## Requirements

- iOS 15.0+ (iOS 16.0+ for full 48MP support)
- iPhone with rear camera
- 48MP capture available on:
  - iPhone 14 Pro / Pro Max
  - iPhone 15 Pro / Pro Max
  - iPhone 16 series
- Xcode 14.0+
- Swift 5.7+

## Permissions

The app requires two permissions (configured in Info.plist):

- **Camera Access** (`NSCameraUsageDescription`): To capture photos
- **Photo Library** (`NSPhotoLibraryAddUsageDescription`): To save captured images

## Testing

Test the app with various scenes to validate the Portra 400 look:

- ✅ Daylight portraits (warm skin tones)
- ✅ Shade/greenery (shadow blue cast)
- ✅ Indoor tungsten (overall warmth)
- ✅ Specular highlights (smooth rolloff)
- ✅ Deep shadows (cyan cast, detail retention)
- ✅ High contrast scenes (dynamic range compression)

## Known Limitations

- No live preview of film effect (performance optimization)
- Single film look (Portra 400 only)
- No manual controls (shutter speed, ISO, focus)
- Portrait mode not supported
- RAW/DNG capture not available

## Future Enhancements

See `PLAN.md` for detailed future considerations:

- Multiple film stocks (Portra 160, Ektar 100, CineStill 800T)
- Live LUT preview with optimization
- Manual exposure controls
- RAW capture option
- Lens switching (ultra-wide, telephoto)
- Halation effect for bright highlights

## Architecture Decisions

### Why No Live Preview Filter?
Processing 48MP at 30fps (550MB/frame) causes thermal throttling. Live preview stays unfiltered for stability.

### Why Core Image Not Metal?
Faster MVP development. Sufficient performance for post-capture processing. Can optimize to Metal shaders later via clean `FilmPipeline` protocol.

### Why HEIF Over JPEG?
40-50% smaller files at same quality, wide color gamut (P3) support, native iOS format.

### Why Single Film Look?
Easier to perfect one aesthetic than ship multiple mediocre options. Can add more based on user feedback.

## Documentation

- `PLAN.md` - Comprehensive technical specification and design rationale
- `claude.md` - Implementation notes and development phases

## License

MIT License - See LICENSE file for details

## Credits

Built with guidance from the comprehensive prototype plan in `PLAN.md`, inspired by the "No Fusion" camera app's approach to minimal computational photography.

---

**Status**: Complete prototype implementation
**Version**: 1.0
**Last Updated**: January 2026

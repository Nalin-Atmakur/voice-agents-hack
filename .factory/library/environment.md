# Environment

**What belongs here:** Required env vars, external dependencies, platform notes.
**What does NOT belong here:** Service ports/commands (use `.factory/services.yaml`).

---

## Platform

- macOS (darwin 25.4.0), Apple Silicon, 24 GB RAM, 10 cores
- Xcode with iOS 18.6 SDK, iPhone 17 Pro simulator
- Branch: `image-detection`

## Dependencies

- Cactus xcframework: vendored at `Frameworks/cactus-ios.xcframework` (arm64 only, no x86_64)
- ZIPFoundation SPM package (existing, do not add new packages)
- Apple frameworks: ARKit, AVFoundation, CoreLocation, CoreBluetooth, SwiftData

## Notes

- Cactus model (Gemma 4 E4B INT4, ~6.44 GB) downloads on first app launch. Never trigger this in unit tests — always stub `completeFunction`.
- `CODE_SIGNING_ALLOWED=NO` required for CI/headless builds.

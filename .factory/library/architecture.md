# Architecture

## Overview

TacNet is an iOS app (SwiftUI, iOS 18.6+) for decentralized tactical communication over Bluetooth mesh. The Recon tab adds on-device battlefield object detection using Gemma 4 E4B via the vendored Cactus xcframework.

## Key Components

- **ContentView.swift** — Root view with onboarding flow + `TacNetTabShellView` (5 tabs: Main, Recon, Tree View, Data Flow, Settings)
- **AppNetworkCoordinator** — DI container owning all view models and services. Created as `@StateObject` in ContentView.
- **CactusModelInitializationService** — Singleton actor managing the Gemma 4 E4B model handle. Downloads the 6.44 GB INT4 model on first launch, then reuses the handle.
- **BattlefieldVisionService** — Actor wrapping `cactusComplete` for object detection. Accepts a `completeFunction` closure for test injection.
- **TargetFusion** — Pure stateless math enum: bearing, pinhole distance, class-to-height mapping, sensor fusion.
- **ReconViewModel** — @MainActor VM orchestrating camera, heading, range, and vision services into the scan pipeline.

## Data Flow (Recon Tab)

1. User taps Scan -> `ReconViewModel.performScan()`
2. `CameraCaptureService.capture()` -> `CameraShot` (UIImage + FoV)
3. `HeadingProvider.snapshot()` -> optional true-north heading
4. `BattlefieldVisionService.scan()` -> `[RawDetection]` (Gemma JSON output)
5. For each detection: `RangeProvider.sampleDepthMeters()` (LiDAR) or nil
6. `TargetFusion.fuse()` -> `TargetSighting` (description + bearing + range)
7. Results displayed as sighting cards with bounding box overlay

## Test Architecture

- **TacNetTests** — Unit tests using `@testable import TacNet`. Test files in `TacNetTests/Recon/` subfolder.
- **TacNetUITests** — UI smoke tests using `XCUIApplication`. Single `TacNetUISmokeTests` class with `--ui-test-skip-download` to bypass model download gate.
- **Xcode project**: Separate targets for TacNet, TacNetTests, TacNetUITests.

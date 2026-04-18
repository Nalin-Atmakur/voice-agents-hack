# User Testing

## Validation Surface

**Primary surface:** Native iOS app on physical iPhones

This is a native iOS app with no web UI, no API endpoints, and no CLI. All user-facing behavior happens on-device.

## Testing Tools

- **xcodebuild test**: XCTest unit/integration tests run on iOS Simulator. Covers all pure logic (models, routing, compaction triggers, tree helpers, deduplication, version convergence).
- **Manual: physical device**: BLE mesh, on-device AI (Cactus/Gemma 4), audio recording, multi-device flows. Requires 4+ iPhones.

## Validation Concurrency

Since all automated tests run via a single `xcodebuild test` invocation targeting the iOS Simulator, there is no parallelization concern for automated tests. Manual device testing is inherently sequential (one tester with physical devices).

Max concurrent validators: 1 (single xcodebuild process)

## Known Limitations

- iOS Simulator has no Bluetooth support. All BLE-dependent assertions require physical devices and manual testing.
- Cactus model inference (cactusInit, cactusComplete, cactusTranscribe) requires actual model weights and may only work on physical devices or Apple Silicon Macs. Mock/stub the Cactus calls for simulator-based tests.
- Audio recording (AVAudioEngine) may not work reliably in simulator. Mock audio input for unit tests.

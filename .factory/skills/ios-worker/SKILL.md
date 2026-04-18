---
name: ios-worker
description: Native iOS (Swift/SwiftUI) implementation worker for TacNet app features
---

# iOS Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

All TacNet iOS implementation features: data models, services, view models, views, BLE mesh, Cactus AI integration, SwiftUI screens, and XCTest unit tests.

## Required Skills

None. All work is done via Xcode toolchain (xcodebuild).

## Work Procedure

1. **Read the feature description** thoroughly. Check preconditions -- if a dependency doesn't exist yet, return to orchestrator.

2. **Write tests FIRST (TDD)**:
   - Create or update XCTest files in `TacNetTests/` targeting the feature's logic.
   - Tests must compile but FAIL (red) before implementation.
   - Cover: normal path, edge cases from expectedBehavior, and at least one boundary condition.
   - Run: `xcodebuild test -project TacNet.xcodeproj -scheme TacNet -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:TacNetTests 2>&1 | tail -30` -- confirm tests fail.

3. **Implement the feature**:
   - Follow the project's Swift style: Swift Concurrency (async/await, actors), SwiftUI for views, Codable for models.
   - Place files in the correct directory per the project structure (Models/, Services/, ViewModels/, Views/).
   - Reference `.factory/library/architecture.md` for component relationships and `.factory/library/cactus-api.md` for Cactus SDK usage.

4. **Make tests pass (green)**:
   - Run the same xcodebuild test command. All tests must pass.
   - If tests fail, fix implementation (not tests) until green.

5. **Run full project build**:
   - `xcodebuild build -project TacNet.xcodeproj -scheme TacNet -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' 2>&1 | tail -20`
   - Fix any compiler errors or warnings.

6. **Run all tests** (not just yours):
   - `xcodebuild test -project TacNet.xcodeproj -scheme TacNet -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' 2>&1 | tail -40`
   - All tests must pass. If a pre-existing test breaks, investigate and fix if it's related to your change, or report it.

7. **Verify manually** where applicable:
   - For UI features: describe what you'd verify on device (since simulator can't do BLE).
   - For logic features: verify via test output.

## Example Handoff

```json
{
  "salientSummary": "Implemented TreeNode, NetworkConfig, Message, and NodeIdentity Codable models with full encode/decode support, version-based convergence logic, and tree helper utilities. Wrote 24 XCTests covering round-trip encoding, malformed JSON rejection, version monotonicity, and parent/sibling/children lookups. All tests pass.",
  "whatWasImplemented": "Data models (TreeNode, NetworkConfig, Message, NodeIdentity) in Models/ directory. TreeHelpers utility with parent(), siblings(), children(), level() functions. Message deduplicator with bounded seen-set. All models conform to Codable with explicit CodingKeys. NetworkConfig includes version-based convergence logic.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {
        "command": "xcodebuild test -project TacNet.xcodeproj -scheme TacNet -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' -only-testing:TacNetTests/ModelTests 2>&1 | tail -30",
        "exitCode": 0,
        "observation": "24 tests passed, 0 failed. TreeNode round-trip, malformed JSON rejection, version monotonicity, message type enum coverage, tree helpers all green."
      },
      {
        "command": "xcodebuild build -project TacNet.xcodeproj -scheme TacNet -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' 2>&1 | tail -10",
        "exitCode": 0,
        "observation": "BUILD SUCCEEDED. No warnings."
      }
    ],
    "interactiveChecks": []
  },
  "tests": {
    "added": [
      {
        "file": "TacNetTests/ModelTests/TreeNodeTests.swift",
        "cases": [
          { "name": "testRoundTripEncoding", "verifies": "VAL-FOUND-001" },
          { "name": "testMalformedJSONRejection", "verifies": "VAL-FOUND-002" },
          { "name": "testDeepTreeRoundTrip", "verifies": "VAL-FOUND-001" }
        ]
      }
    ]
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- Feature depends on a model, service, or view that doesn't exist yet and isn't part of this feature
- Xcode project structure needs changes (adding targets, build phases, entitlements)
- Cactus SDK integration issues (framework not loading, API mismatch)
- BLE entitlements or Info.plist changes needed
- Requirements are ambiguous or contradictory

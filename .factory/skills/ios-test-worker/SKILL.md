---
name: ios-test-worker
description: Writes XCTest unit and UI tests for iOS/Swift, registers them in pbxproj, and verifies builds stay green.
---

# iOS Test Worker

NOTE: Startup and cleanup are handled by `worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Features that require writing XCTest unit tests, XCUITest UI smoke tests, updating Xcode project.pbxproj to register new test files, or updating documentation files.

## Required Skills

None. All work uses standard file tools, xcodebuild CLI, and git.

## Work Procedure

1. **Read the feature description thoroughly.** Understand exactly which test cases are required, what files to create, and what pbxproj changes are needed.

2. **Read the source files under test.** Before writing any test, read the implementation files you're testing to understand the exact API surface, method signatures, parameter types, and return types. For `@testable import TacNet`, internal methods are accessible.

3. **Read existing test files for patterns.** Check `TacNetTests/TacNetTests.swift` and `TacNetUITests/TacNetUITests.swift` for conventions: imports, class structure, helper methods, assertion style, setUp/tearDown patterns.

4. **Write test files (RED).** Create the test Swift files with all required test methods. Each test should be self-contained with clear arrange/act/assert. For BattlefieldVisionService tests, always inject a stub `completeFunction` — NEVER reference `CactusModelInitializationService.shared`.

5. **Register test files in project.pbxproj.** Add new files to the appropriate PBXGroup, PBXFileReference entries, and the test target's PBXSourcesBuildPhase. Use reserved IDs from AGENTS.md if available. If creating a subfolder group (e.g., Recon/), create a new PBXGroup and add it as a child of the parent test group.

6. **Create test file directories on disk.** Ensure the directory structure (e.g., `TacNetTests/Recon/`) exists before creating files.

7. **Build and run tests.** Execute the test command from `.factory/services.yaml`:
   ```
   xcrun xcodebuild -project TacNet.xcodeproj -scheme TacNet -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test CODE_SIGNING_ALLOWED=NO
   ```
   Capture the last 80 lines of output. If tests fail, read the error output, fix the test code, and re-run. Iterate until all tests pass.

8. **Verify device build stays green.**
   ```
   xcrun xcodebuild -project TacNet.xcodeproj -scheme TacNet -configuration Debug -destination 'generic/platform=iOS' -sdk iphoneos build CODE_SIGNING_ALLOWED=NO
   ```

9. **For documentation features:** Read the existing file, make targeted edits to the specified sections, and verify with a final read-back.

10. **Commit with Conventional Commits.** Run `git status` and `git diff --cached` before committing. Use the commit message format specified in the feature description. Always include the co-author footer.

11. **If the simulator returns "Busy" errors:** Kill any running xcodebuild processes with `pkill -f xcodebuild` and retry once.

## Example Handoff

```json
{
  "salientSummary": "Wrote 11 TargetFusion unit tests covering bearing math, pinhole distance, label heights, LiDAR preference, and invalid box rejection. All pass on iPhone 17 Pro simulator. Committed as feat(recon): add unit tests for TargetFusion.",
  "whatWasImplemented": "Created TacNetTests/Recon/TargetFusionTests.swift with 11 test methods. Registered in project.pbxproj under TacNetTests target with new Recon PBXGroup. Added PBXBuildFile and PBXFileReference entries using reserved IDs.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      {
        "command": "xcrun xcodebuild -project TacNet.xcodeproj -scheme TacNet -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test CODE_SIGNING_ALLOWED=NO",
        "exitCode": 0,
        "observation": "All tests passed: 11 TargetFusionTests + 14 TacNetUISmokeTests + existing TacNetTests. 0 failures."
      },
      {
        "command": "xcrun xcodebuild -project TacNet.xcodeproj -scheme TacNet -configuration Debug -destination 'generic/platform=iOS' -sdk iphoneos build CODE_SIGNING_ALLOWED=NO",
        "exitCode": 0,
        "observation": "BUILD SUCCEEDED for arm64 device."
      }
    ],
    "interactiveChecks": []
  },
  "tests": {
    "added": [
      {
        "file": "TacNetTests/Recon/TargetFusionTests.swift",
        "cases": [
          {"name": "testBearingAtCenter_returnsHeading", "verifies": "Centroid at x=500 yields heading-aligned bearing"},
          {"name": "testBearingAtLeftEdge_subtractsHalfFoV", "verifies": "Left-edge centroid subtracts half FoV from heading"},
          {"name": "testFuse_rejectsInvalidBox", "verifies": "Degenerate bounding box returns nil"}
        ]
      }
    ]
  },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- pbxproj structure is unexpected (missing groups, changed UUIDs)
- Tests require access to types/methods not visible via `@testable import TacNet`
- Simulator consistently fails with "Busy" after retry
- Existing 14 UI tests start failing for reasons unrelated to changes

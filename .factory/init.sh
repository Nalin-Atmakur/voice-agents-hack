#!/bin/bash
# Idempotent environment setup for the Recon tab test mission.
# No services to start — this is a pure Xcode build+test mission.

set -euo pipefail

cd "$(dirname "$0")/.."

# Resolve SPM packages (idempotent)
xcrun xcodebuild -project TacNet.xcodeproj -scheme TacNet -resolvePackageDependencies 2>/dev/null || true

echo "[init.sh] Environment ready."

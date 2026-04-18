#!/bin/bash
set -e

cd /Users/yifuzuo/Desktop/yifu/startup/projects/hackathon/YC-hack

# Verify Xcode is available
if ! command -v xcodebuild &> /dev/null; then
    echo "ERROR: xcodebuild not found. Ensure Xcode is installed."
    exit 1
fi

# Verify Xcode developer tools are pointing to Xcode.app (not CommandLineTools)
XCODE_PATH=$(xcode-select -p)
if [[ "$XCODE_PATH" != *"Xcode.app"* ]]; then
    echo "WARNING: xcode-select points to $XCODE_PATH, not Xcode.app"
    echo "Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi

# Verify Cactus SDK artifacts exist
CACTUS_XCFRAMEWORK="/Users/yifuzuo/Desktop/yifu/startup/projects/hackathon/cactus/apple/cactus-ios.xcframework"
if [ ! -d "$CACTUS_XCFRAMEWORK" ]; then
    echo "WARNING: Cactus XCFramework not found at $CACTUS_XCFRAMEWORK"
    echo "Build it: cd /Users/yifuzuo/Desktop/yifu/startup/projects/hackathon/cactus && bash apple/build.sh"
fi

echo "Init complete."

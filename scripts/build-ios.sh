#!/usr/bin/env bash
# Build script for iOS targets
# Usage: ./scripts/build-ios.sh [device|simulator|all]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_DIR/mobile/ios/libs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    error "iOS builds require macOS"
    exit 1
fi

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    error "Rust is not installed. Install from https://rustup.rs"
    exit 1
fi

# Determine what to build
BUILD_TARGET="${1:-all}"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to check and add target if needed
add_target_if_missing() {
    local target=$1
    if ! rustup target list | grep -q "^$target (installed)"; then
        info "Adding target: $target"
        rustup target add "$target"
    else
        info "Target already installed: $target"
    fi
}

# Function to build for a specific target
build_target() {
    local target=$1
    local output_name=$2
    
    info "Building for $target..."
    cargo build --release \
        --target "$target" \
        --no-default-features \
        --features mobile-ios \
        --manifest-path "$PROJECT_DIR/Cargo.toml"
    
    if [ $? -eq 0 ]; then
        info "✓ Successfully built for $target"
        cp "$PROJECT_DIR/target/$target/release/libzeroclaw.a" "$OUTPUT_DIR/$output_name"
        info "✓ Copied to $OUTPUT_DIR/$output_name"
    else
        error "Failed to build for $target"
        return 1
    fi
}

# Build device target (ARM64)
build_device() {
    info "Building for iOS devices (ARM64)..."
    add_target_if_missing "aarch64-apple-ios"
    build_target "aarch64-apple-ios" "libzeroclaw_device.a"
}

# Build simulator targets
build_simulator() {
    info "Building for iOS Simulator..."
    
    # Check host architecture
    HOST_ARCH=$(uname -m)
    
    if [ "$HOST_ARCH" = "arm64" ]; then
        info "Detected Apple Silicon Mac"
        add_target_if_missing "aarch64-apple-ios-sim"
        build_target "aarch64-apple-ios-sim" "libzeroclaw_sim_arm64.a"
    else
        info "Detected Intel Mac"
        add_target_if_missing "x86_64-apple-ios"
        build_target "x86_64-apple-ios" "libzeroclaw_sim_x86_64.a"
    fi
}

# Build universal simulator library
build_universal_simulator() {
    info "Building universal simulator library..."
    
    add_target_if_missing "aarch64-apple-ios-sim"
    add_target_if_missing "x86_64-apple-ios"
    
    build_target "aarch64-apple-ios-sim" "libzeroclaw_sim_arm64.a"
    build_target "x86_64-apple-ios" "libzeroclaw_sim_x86_64.a"
    
    info "Creating universal library with lipo..."
    lipo -create \
        "$OUTPUT_DIR/libzeroclaw_sim_arm64.a" \
        "$OUTPUT_DIR/libzeroclaw_sim_x86_64.a" \
        -output "$OUTPUT_DIR/libzeroclaw_sim.a"
    
    if [ $? -eq 0 ]; then
        info "✓ Created universal simulator library"
        # Clean up individual arch libraries
        rm -f "$OUTPUT_DIR/libzeroclaw_sim_arm64.a" "$OUTPUT_DIR/libzeroclaw_sim_x86_64.a"
    else
        error "Failed to create universal library"
        return 1
    fi
}

# Create XCFramework
create_xcframework() {
    info "Creating XCFramework..."
    
    local XCFRAMEWORK_PATH="$PROJECT_DIR/mobile/ios/ZeroClaw.xcframework"
    
    # Remove existing XCFramework if it exists
    if [ -d "$XCFRAMEWORK_PATH" ]; then
        warn "Removing existing XCFramework"
        rm -rf "$XCFRAMEWORK_PATH"
    fi
    
    # Build all targets first
    build_device
    build_universal_simulator
    
    # Create XCFramework
    xcodebuild -create-xcframework \
        -library "$OUTPUT_DIR/libzeroclaw_device.a" \
        -library "$OUTPUT_DIR/libzeroclaw_sim.a" \
        -output "$XCFRAMEWORK_PATH"
    
    if [ $? -eq 0 ]; then
        info "✓ Successfully created XCFramework at $XCFRAMEWORK_PATH"
        
        # Print size
        local SIZE=$(du -sh "$XCFRAMEWORK_PATH" | cut -f1)
        info "XCFramework size: $SIZE"
    else
        error "Failed to create XCFramework"
        return 1
    fi
}

# Main build logic
case "$BUILD_TARGET" in
    device)
        build_device
        ;;
    simulator)
        build_simulator
        ;;
    universal-sim)
        build_universal_simulator
        ;;
    xcframework)
        create_xcframework
        ;;
    all)
        build_device
        build_universal_simulator
        create_xcframework
        ;;
    *)
        error "Unknown build target: $BUILD_TARGET"
        echo "Usage: $0 [device|simulator|universal-sim|xcframework|all]"
        exit 1
        ;;
esac

info "Build complete! 🎉"
info "Output directory: $OUTPUT_DIR"

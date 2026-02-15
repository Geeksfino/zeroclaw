#!/usr/bin/env bash
# Build script for Android targets
# Usage: ./scripts/build-android.sh [arm64|armv7|x86_64|all]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ANDROID_PROJECT_DIR="$PROJECT_DIR/mobile/android"
JNI_LIBS_DIR="$ANDROID_PROJECT_DIR/app/src/main/jniLibs"

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

# Check if Rust is installed
if ! command -v cargo &> /dev/null; then
    error "Rust is not installed. Install from https://rustup.rs"
    exit 1
fi

# Check for Android NDK
if [ -z "$ANDROID_NDK_HOME" ]; then
    error "ANDROID_NDK_HOME is not set"
    error "Please set ANDROID_NDK_HOME to your Android NDK installation"
    echo ""
    echo "Example:"
    echo "  export ANDROID_NDK_HOME=\$HOME/Android/Sdk/ndk/25.2.9519653"
    exit 1
fi

if [ ! -d "$ANDROID_NDK_HOME" ]; then
    error "ANDROID_NDK_HOME directory does not exist: $ANDROID_NDK_HOME"
    exit 1
fi

info "Using Android NDK: $ANDROID_NDK_HOME"

# Detect host OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    HOST_TAG="darwin-x86_64"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    HOST_TAG="linux-x86_64"
else
    error "Unsupported host OS: $OSTYPE"
    exit 1
fi

TOOLCHAIN_DIR="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"

if [ ! -d "$TOOLCHAIN_DIR" ]; then
    error "Toolchain directory not found: $TOOLCHAIN_DIR"
    exit 1
fi

info "Using toolchain: $TOOLCHAIN_DIR"

# Set up linker environment variables
export PATH="$TOOLCHAIN_DIR/bin:$PATH"

export CC_aarch64_linux_android="$TOOLCHAIN_DIR/bin/aarch64-linux-android21-clang"
export CXX_aarch64_linux_android="$TOOLCHAIN_DIR/bin/aarch64-linux-android21-clang++"
export AR_aarch64_linux_android="$TOOLCHAIN_DIR/bin/llvm-ar"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$TOOLCHAIN_DIR/bin/aarch64-linux-android21-clang"

export CC_armv7_linux_androideabi="$TOOLCHAIN_DIR/bin/armv7a-linux-androideabi21-clang"
export CXX_armv7_linux_androideabi="$TOOLCHAIN_DIR/bin/armv7a-linux-androideabi21-clang++"
export AR_armv7_linux_androideabi="$TOOLCHAIN_DIR/bin/llvm-ar"
export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$TOOLCHAIN_DIR/bin/armv7a-linux-androideabi21-clang"

export CC_x86_64_linux_android="$TOOLCHAIN_DIR/bin/x86_64-linux-android21-clang"
export CXX_x86_64_linux_android="$TOOLCHAIN_DIR/bin/x86_64-linux-android21-clang++"
export AR_x86_64_linux_android="$TOOLCHAIN_DIR/bin/llvm-ar"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$TOOLCHAIN_DIR/bin/x86_64-linux-android21-clang"

# Determine what to build
BUILD_TARGET="${1:-all}"

# Create JNI libs directory structure
mkdir -p "$JNI_LIBS_DIR"/{arm64-v8a,armeabi-v7a,x86_64,x86}

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
    local rust_target=$1
    local android_abi=$2
    
    info "Building for $rust_target ($android_abi)..."
    
    cargo build --release \
        --target "$rust_target" \
        --no-default-features \
        --features mobile-android \
        --manifest-path "$PROJECT_DIR/Cargo.toml"
    
    if [ $? -eq 0 ]; then
        info "✓ Successfully built for $rust_target"
        
        # Copy to JNI libs directory
        cp "$PROJECT_DIR/target/$rust_target/release/libzeroclaw.so" \
           "$JNI_LIBS_DIR/$android_abi/"
        
        if [ $? -eq 0 ]; then
            info "✓ Copied to $JNI_LIBS_DIR/$android_abi/"
            
            # Print size
            local SIZE=$(du -h "$JNI_LIBS_DIR/$android_abi/libzeroclaw.so" | cut -f1)
            info "Library size: $SIZE"
        else
            error "Failed to copy library"
            return 1
        fi
    else
        error "Failed to build for $rust_target"
        return 1
    fi
}

# Build for ARM64 (most modern devices)
build_arm64() {
    info "Building for ARM64 (arm64-v8a)..."
    add_target_if_missing "aarch64-linux-android"
    build_target "aarch64-linux-android" "arm64-v8a"
}

# Build for ARMv7 (older devices)
build_armv7() {
    info "Building for ARMv7 (armeabi-v7a)..."
    add_target_if_missing "armv7-linux-androideabi"
    build_target "armv7-linux-androideabi" "armeabi-v7a"
}

# Build for x86_64 (emulator)
build_x86_64() {
    info "Building for x86_64 emulator..."
    add_target_if_missing "x86_64-linux-android"
    build_target "x86_64-linux-android" "x86_64"
}

# Build for x86 (older emulator)
build_x86() {
    info "Building for x86 emulator..."
    add_target_if_missing "i686-linux-android"
    build_target "i686-linux-android" "x86"
}

# Print summary
print_summary() {
    info "Build summary:"
    echo ""
    
    for abi in arm64-v8a armeabi-v7a x86_64 x86; do
        local LIB="$JNI_LIBS_DIR/$abi/libzeroclaw.so"
        if [ -f "$LIB" ]; then
            local SIZE=$(du -h "$LIB" | cut -f1)
            echo "  ✓ $abi: $SIZE"
        else
            echo "  ✗ $abi: not built"
        fi
    done
    
    echo ""
    local TOTAL_SIZE=$(du -sh "$JNI_LIBS_DIR" | cut -f1)
    info "Total JNI libs size: $TOTAL_SIZE"
}

# Main build logic
case "$BUILD_TARGET" in
    arm64)
        build_arm64
        ;;
    armv7)
        build_armv7
        ;;
    x86_64)
        build_x86_64
        ;;
    x86)
        build_x86
        ;;
    all)
        build_arm64
        build_armv7
        build_x86_64
        ;;
    *)
        error "Unknown build target: $BUILD_TARGET"
        echo "Usage: $0 [arm64|armv7|x86_64|x86|all]"
        exit 1
        ;;
esac

print_summary
info "Build complete! 🎉"
info "JNI libraries directory: $JNI_LIBS_DIR"

# ZeroClaw Mobile Quick Start Guide

This guide provides practical steps to get started with ZeroClaw on mobile platforms.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [iOS Setup](#ios-setup)
3. [Android Setup](#android-setup)
4. [Common Issues](#common-issues)
5. [FAQ](#faq)

---

## Prerequisites

### General Requirements

- Rust 1.75 or later
- macOS (for iOS builds) or Linux/macOS (for Android builds)
- 10GB+ free disk space
- Git

### iOS-Specific Requirements

- Xcode 15.0+
- macOS 13.0+ (Ventura)
- Apple Developer Account (for device deployment)
- CocoaPods (optional, for dependency management)

### Android-Specific Requirements

- Android Studio 2023.1.1+
- Android NDK r25c or later
- Android SDK API 26+ (Android 8.0)
- JDK 17 or later

---

## iOS Setup

### Step 1: Install Rust Targets

```bash
# Add iOS targets
rustup target add aarch64-apple-ios          # iOS devices (ARM64)
rustup target add aarch64-apple-ios-sim      # iOS Simulator (ARM64 Mac)
rustup target add x86_64-apple-ios           # iOS Simulator (Intel Mac)

# Verify installation
rustup target list | grep apple-ios
```

### Step 2: Configure Cargo for iOS

Create or update `.cargo/config.toml`:

```toml
[target.aarch64-apple-ios]
rustflags = [
    "-C", "link-arg=-Wl,-all_load",
    "-C", "link-arg=-fembed-bitcode=no"
]

[target.aarch64-apple-ios-sim]
rustflags = [
    "-C", "link-arg=-Wl,-all_load"
]

[target.x86_64-apple-ios]
rustflags = [
    "-C", "link-arg=-Wl,-all_load"
]
```

### Step 3: Build for iOS

```bash
# Build for iOS devices (ARM64)
cargo build --release --target aarch64-apple-ios --no-default-features --features mobile-ios

# Build for iOS Simulator (ARM64 Mac)
cargo build --release --target aarch64-apple-ios-sim --no-default-features --features mobile-ios

# Build for iOS Simulator (Intel Mac)
cargo build --release --target x86_64-apple-ios --no-default-features --features mobile-ios
```

### Step 4: Create Universal Library (Optional)

If you need to support both device and simulator in a single library:

```bash
# Create output directory
mkdir -p mobile/ios/libs

# Create universal library for simulator
lipo -create \
    target/aarch64-apple-ios-sim/release/libzeroclaw.a \
    target/x86_64-apple-ios/release/libzeroclaw.a \
    -output mobile/ios/libs/libzeroclaw_sim.a

# Copy device library
cp target/aarch64-apple-ios/release/libzeroclaw.a \
   mobile/ios/libs/libzeroclaw_device.a

# Create XCFramework (recommended for distribution)
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libzeroclaw.a \
    -library target/aarch64-apple-ios-sim/release/libzeroclaw.a \
    -library target/x86_64-apple-ios/release/libzeroclaw.a \
    -output mobile/ios/ZeroClaw.xcframework
```

### Step 5: Create Swift Package

Create `mobile/ios/Package.swift`:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZeroClaw",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "ZeroClaw",
            targets: ["ZeroClaw"]
        ),
    ],
    targets: [
        .target(
            name: "ZeroClaw",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "ZeroClawTests",
            dependencies: ["ZeroClaw"],
            path: "Tests"
        ),
    ]
)
```

### Step 6: Integrate with Xcode Project

1. Open your Xcode project
2. Add the `ZeroClaw.xcframework` to your project
3. In Build Settings, add to "Other Linker Flags":
   - `-lc++`
   - `-framework Foundation`
   - `-framework Security`

### Step 7: Use in Swift

```swift
import ZeroClaw

class ChatViewModel: ObservableObject {
    @Published var messages: [String] = []
    private var zeroclaw: ZeroClaw?
    
    func initialize(apiKey: String) {
        do {
            zeroclaw = try ZeroClaw(
                apiKey: apiKey,
                provider: "openrouter"
            )
            print("ZeroClaw initialized successfully")
        } catch {
            print("Failed to initialize ZeroClaw: \(error)")
        }
    }
    
    func sendMessage(_ text: String) async {
        guard let zeroclaw = zeroclaw else { return }
        
        do {
            let response = try await zeroclaw.sendMessage(text)
            await MainActor.run {
                messages.append("You: \(text)")
                messages.append("AI: \(response)")
            }
        } catch {
            print("Error sending message: \(error)")
        }
    }
}
```

---

## Android Setup

### Step 1: Install Android NDK

#### Via Android Studio
1. Open Android Studio
2. Go to Preferences → Appearance & Behavior → System Settings → Android SDK
3. Click "SDK Tools" tab
4. Check "NDK (Side by side)" and "CMake"
5. Click "Apply" to install

#### Via Command Line
```bash
# macOS/Linux
export ANDROID_HOME=$HOME/Android/Sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/25.2.9519653

# Add to PATH
export PATH=$PATH:$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin

# Verify
ls $ANDROID_NDK_HOME
```

### Step 2: Install Rust Targets

```bash
# Add Android targets
rustup target add aarch64-linux-android      # ARM64 (most modern devices)
rustup target add armv7-linux-androideabi    # ARMv7 (older devices)
rustup target add x86_64-linux-android       # x86_64 emulator
rustup target add i686-linux-android         # x86 emulator

# Verify installation
rustup target list | grep android
```

### Step 3: Configure Cargo for Android

Create or update `.cargo/config.toml`:

```toml
[target.aarch64-linux-android]
linker = "aarch64-linux-android21-clang"

[target.armv7-linux-androideabi]
linker = "armv7a-linux-androideabi21-clang"

[target.x86_64-linux-android]
linker = "x86_64-linux-android21-clang"

[target.i686-linux-android]
linker = "i686-linux-android21-clang"
```

Set environment variables (add to `~/.zshrc` or `~/.bashrc`):

```bash
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/25.2.9519653

export CC_aarch64_linux_android=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android21-clang
export CXX_aarch64_linux_android=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android21-clang++
export AR_aarch64_linux_android=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-ar

export CC_armv7_linux_androideabi=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/armv7a-linux-androideabi21-clang
export CXX_armv7_linux_androideabi=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/armv7a-linux-androideabi21-clang++
export AR_armv7_linux_androideabi=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin/llvm-ar
```

### Step 4: Build for Android

```bash
# Build for ARM64 (most modern devices)
cargo build --release --target aarch64-linux-android --no-default-features --features mobile-android

# Build for ARMv7 (older devices)
cargo build --release --target armv7-linux-androideabi --no-default-features --features mobile-android

# Build for x86_64 emulator (testing)
cargo build --release --target x86_64-linux-android --no-default-features --features mobile-android
```

### Step 5: Set Up Android Project Structure

```bash
# Create Android project directories
mkdir -p mobile/android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}
mkdir -p mobile/android/app/src/main/kotlin/com/zeroclaw/sdk

# Copy compiled libraries
cp target/aarch64-linux-android/release/libzeroclaw.so \
   mobile/android/app/src/main/jniLibs/arm64-v8a/

cp target/armv7-linux-androideabi/release/libzeroclaw.so \
   mobile/android/app/src/main/jniLibs/armeabi-v7a/

cp target/x86_64-linux-android/release/libzeroclaw.so \
   mobile/android/app/src/main/jniLibs/x86_64/
```

### Step 6: Create Gradle Build Configuration

Create `mobile/android/app/build.gradle.kts`:

```kotlin
plugins {
    id("com.android.library")
    kotlin("android")
}

android {
    namespace = "com.zeroclaw.sdk"
    compileSdk = 34
    
    defaultConfig {
        minSdk = 26
        targetSdk = 34
        
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }
    
    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    
    kotlinOptions {
        jvmTarget = "17"
    }
    
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test:runner:1.5.2")
}
```

### Step 7: Use in Kotlin

```kotlin
import com.zeroclaw.sdk.ZeroClaw
import kotlinx.coroutines.launch
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers

class ChatViewModel {
    private var zeroclaw: ZeroClaw? = null
    private val scope = CoroutineScope(Dispatchers.Main)
    
    fun initialize(context: Context, apiKey: String) {
        val storageDir = context.filesDir.absolutePath
        
        try {
            zeroclaw = ZeroClaw(
                apiKey = apiKey,
                provider = "openrouter",
                storageDir = storageDir
            )
            println("ZeroClaw initialized successfully")
        } catch (e: Exception) {
            println("Failed to initialize ZeroClaw: ${e.message}")
        }
    }
    
    fun sendMessage(text: String, onResponse: (String) -> Unit) {
        scope.launch {
            try {
                val response = zeroclaw?.sendMessage(text) ?: return@launch
                onResponse(response)
            } catch (e: Exception) {
                println("Error sending message: ${e.message}")
            }
        }
    }
    
    fun cleanup() {
        zeroclaw?.cleanup()
    }
}
```

---

## Common Issues

### iOS Issues

#### Issue: "Library not found" error in Xcode

**Solution:**
1. Verify the library path in Xcode Build Settings → Library Search Paths
2. Ensure the library is added to "Link Binary With Libraries" in Build Phases
3. Check that the target architecture matches your build

#### Issue: "Undefined symbols" linker error

**Solution:**
```bash
# Add these to "Other Linker Flags" in Xcode:
-lc++
-lresolv
-framework Foundation
-framework Security
```

#### Issue: App crashes on startup with "dyld: Library not loaded"

**Solution:**
- Make sure you're using a static library (`.a`) not a dynamic library (`.dylib`)
- Verify code signing is correct
- Check that all dependencies are properly linked

### Android Issues

#### Issue: "UnsatisfiedLinkError: dlopen failed"

**Solution:**
1. Verify `.so` files are in correct directories:
   - `arm64-v8a/` for ARM64
   - `armeabi-v7a/` for ARMv7
2. Check that `System.loadLibrary("zeroclaw")` is called before any native methods
3. Verify ABI filters in `build.gradle.kts` match your build targets

#### Issue: NDK build fails with "clang: error: linker command failed"

**Solution:**
1. Verify `ANDROID_NDK_HOME` is set correctly
2. Check that linker paths in `.cargo/config.toml` are correct
3. Ensure you're using NDK r25c or later

#### Issue: App crashes with "SIGSEGV" on startup

**Solution:**
- Check that API level matches (minSdk = 26)
- Verify all native symbols are properly exported with `#[no_mangle]`
- Use `adb logcat` to see detailed crash logs

---

## FAQ

### Q: What's the minimum iOS version supported?

**A:** iOS 14.0+. This covers 95%+ of active devices as of 2026.

### Q: What's the minimum Android version supported?

**A:** Android 8.0 (API 26)+. This covers 95%+ of active devices.

### Q: How large is the binary?

**A:** 
- iOS: ~4-5MB (static library)
- Android: ~3-4MB per architecture (ARM64 is most important)

### Q: Can I use ZeroClaw in React Native or Flutter?

**A:** Yes! You can create platform-specific modules that call the native iOS/Android wrappers. Example plugins could be created for:
- React Native: Native Modules
- Flutter: Platform Channels
- Capacitor: Native Plugins

### Q: Does ZeroClaw work offline?

**A:** No, ZeroClaw requires internet connectivity to communicate with AI providers. Local memory/history is stored on device, but inference requires network access.

### Q: How do I handle API keys securely?

**A:** 
- Never hardcode API keys in your app
- Use iOS Keychain or Android KeyStore to store API keys
- Consider implementing a backend proxy that manages API keys server-side
- For testing, use environment variables or configuration files that are .gitignored

### Q: Can I run multiple instances?

**A:** Currently, the FFI layer supports a single global instance. For multiple instances, you would need to extend the FFI to support instance handles.

### Q: What about background execution?

**A:** 
- iOS: Use Background Tasks framework for periodic updates
- Android: Use WorkManager for periodic tasks or Foreground Service for active sessions
- Note: Mobile OSes aggressively limit background execution to save battery

### Q: How do I debug native crashes?

**iOS:**
```bash
# View crash logs
lldb path/to/YourApp.app
```

**Android:**
```bash
# View detailed logs
adb logcat -s ZeroClaw

# Attach debugger
adb shell am attach-agent <package-name>
```

### Q: What tools are available on mobile?

**Available:**
- ✅ Message send/receive to AI providers
- ✅ Memory store/recall (SQLite)
- ✅ File read/write (sandboxed)
- ✅ HTTP requests (with platform networking)

**Not Available:**
- ❌ Shell command execution
- ❌ Arbitrary file system access
- ❌ Browser automation
- ⚠️ Gateway server (limited usefulness on mobile)

### Q: How do I update ZeroClaw in my app?

**A:** 
1. Rebuild Rust libraries with `cargo build --release --target <target>`
2. Copy new `.a` (iOS) or `.so` (Android) files to your project
3. Rebuild your mobile app
4. Test thoroughly before releasing

For automated updates, integrate the build process into your CI/CD pipeline.

---

## Next Steps

1. Read the [Mobile Feasibility Assessment](./mobile-feasibility.md) for architecture details
2. Check the main [README](../README.md) for general ZeroClaw information
3. Review [CONTRIBUTING.md](../CONTRIBUTING.md) if you want to contribute mobile support
4. Join the community discussions for mobile-specific questions

---

**Note:** Mobile support is currently in planning/development phase. This guide reflects the planned implementation. Check the project's GitHub issues and discussions for current status.

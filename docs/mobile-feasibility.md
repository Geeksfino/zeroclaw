# Mobile Feasibility Assessment: ZeroClaw on iOS and Android

**Version:** 1.0  
**Date:** February 2026  
**Status:** Feasibility Assessment

## Executive Summary

This document assesses the feasibility of running ZeroClaw on mobile devices (iOS and Android) by wrapping the Rust core with Swift and Kotlin bindings. 

**Verdict: FEASIBLE** with the following constraints and recommendations:

- ✅ Technical feasibility: HIGH - Rust FFI support is mature
- ✅ Architecture compatibility: HIGH - Trait-based design is well-suited for mobile
- ⚠️ Implementation complexity: MEDIUM-HIGH - Requires careful dependency management
- ⚠️ Performance considerations: MEDIUM - Some features require adaptation
- ⚠️ Maintenance overhead: MEDIUM - Requires CI/CD for multiple platforms

## Table of Contents

1. [Current Architecture Analysis](#1-current-architecture-analysis)
2. [Mobile Platform Requirements](#2-mobile-platform-requirements)
3. [FFI Integration Strategy](#3-ffi-integration-strategy)
4. [Dependency Compatibility Analysis](#4-dependency-compatibility-analysis)
5. [Technical Challenges](#5-technical-challenges)
6. [Recommended Approach](#6-recommended-approach)
7. [Implementation Roadmap](#7-implementation-roadmap)
8. [Code Examples](#8-code-examples)
9. [Testing Strategy](#9-testing-strategy)
10. [Maintenance Considerations](#10-maintenance-considerations)

---

## 1. Current Architecture Analysis

### 1.1 Strengths for Mobile

ZeroClaw's architecture has several features that make it well-suited for mobile:

#### Trait-Based Modularity
```rust
pub trait RuntimeAdapter: Send + Sync {
    fn name(&self) -> &str;
    fn has_shell_access(&self) -> bool;
    fn has_filesystem_access(&self) -> bool;
    fn storage_path(&self) -> PathBuf;
    fn supports_long_running(&self) -> bool;
    fn memory_budget(&self) -> u64;
}
```

The trait-based architecture allows for easy adaptation to mobile constraints by implementing mobile-specific runtime adapters.

#### Small Binary Size
- Current binary: ~3.4MB
- Release profile optimized for size (`opt-level = "z"`)
- Minimal dependencies with feature flags
- No heavy runtime dependencies (no Node.js, Python, etc.)

#### Low Resource Footprint
- <5MB RAM usage
- Fast startup (<10ms)
- Efficient async runtime (Tokio with minimal features)

#### Modular Feature Set
All major subsystems are swappable:
- Providers (22+ LLM providers)
- Channels (CLI, Telegram, Discord, etc.)
- Memory (SQLite, Markdown)
- Tools (shell, file operations, browser)
- Observability (logging, metrics)

### 1.2 Current Platform Support

```toml
[dependencies]
# Core async runtime - already platform-agnostic
tokio = { version = "1.42", default-features = false, features = [...] }

# HTTP client with TLS
reqwest = { version = "0.12", default-features = false, features = ["rustls-tls"] }

# Storage
rusqlite = { version = "0.32", features = ["bundled"] }
```

Current support:
- ✅ macOS (native Darwin support)
- ✅ Linux (x86_64, ARM, RISC-V)
- ✅ Raspberry Pi (ARM)
- ⚠️ iOS: Not yet implemented (but architecture supports it)
- ⚠️ Android: Not yet implemented (but architecture supports it)

---

## 2. Mobile Platform Requirements

### 2.1 iOS (Swift Wrapper)

**Platform Characteristics:**
- Language: Swift (primary), Objective-C (legacy)
- Runtime: iOS 14.0+ recommended
- Architecture: ARM64 (aarch64-apple-ios)
- Sandbox: Strict app sandboxing
- Background execution: Limited
- Network: NSURLSession or URLSession
- Storage: App-specific directories only

**Key Constraints:**
1. **No Shell Access**: `has_shell_access() = false`
2. **Limited Background**: Long-running tasks restricted
3. **Sandboxed Filesystem**: Limited to app container
4. **Code Signing**: All binaries must be signed
5. **App Store Review**: Additional restrictions

### 2.2 Android (Kotlin Wrapper)

**Platform Characteristics:**
- Language: Kotlin (primary), Java (legacy)
- Runtime: Android 8.0+ (API 26+) recommended
- Architecture: ARM64 (aarch64-linux-android), ARM (armv7-linux-androideabi)
- Sandbox: SELinux-enforced app sandboxing
- Background execution: Foreground service or WorkManager
- Network: OkHttp or HttpURLConnection
- Storage: App-specific internal/external storage

**Key Constraints:**
1. **Limited Shell Access**: Restricted by SELinux
2. **Background Restrictions**: Battery optimization limits
3. **Permissions Model**: Runtime permissions required
4. **APK Size**: Should stay under 50MB for optimal distribution
5. **JNI Overhead**: Small performance cost for FFI calls

---

## 3. FFI Integration Strategy

### 3.1 Rust-to-C FFI Layer

Create a C-compatible API layer that both Swift and Kotlin can call:

```rust
// src/mobile/ffi.rs

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Initialize ZeroClaw with config
#[no_mangle]
pub extern "C" fn zeroclaw_init(config_path: *const c_char) -> i32 {
    if config_path.is_null() {
        return -1;
    }
    
    let c_str = unsafe { CStr::from_ptr(config_path) };
    let config_path = match c_str.to_str() {
        Ok(s) => s,
        Err(_) => return -1,
    };
    
    // Initialize runtime with mobile adapter
    match init_mobile_runtime(config_path) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// Send message to agent
#[no_mangle]
pub extern "C" fn zeroclaw_send_message(
    message: *const c_char,
    callback: extern "C" fn(*const c_char),
) -> i32 {
    // Implementation
    0
}

/// Clean up resources
#[no_mangle]
pub extern "C" fn zeroclaw_cleanup() {
    // Cleanup implementation
}
```

### 3.2 iOS Swift Bridge

```swift
// ZeroClaw.swift

import Foundation

public class ZeroClaw {
    private var isInitialized = false
    
    // Load the Rust library
    private static let library = loadLibrary()
    
    private static func loadLibrary() {
        // Library is statically linked or loaded via dlopen
    }
    
    public init(configPath: String) throws {
        let result = zeroclaw_init(configPath)
        guard result == 0 else {
            throw ZeroClawError.initializationFailed
        }
        isInitialized = true
    }
    
    public func sendMessage(_ message: String, completion: @escaping (String) -> Void) {
        let callback: @convention(c) (UnsafePointer<CChar>?) -> Void = { response in
            guard let response = response else { return }
            let str = String(cString: response)
            completion(str)
        }
        
        zeroclaw_send_message(message, callback)
    }
    
    deinit {
        if isInitialized {
            zeroclaw_cleanup()
        }
    }
}

enum ZeroClawError: Error {
    case initializationFailed
    case messageError
}
```

### 3.3 Android Kotlin Bridge

```kotlin
// ZeroClaw.kt

package com.zeroclaw.sdk

class ZeroClaw(configPath: String) {
    companion object {
        init {
            System.loadLibrary("zeroclaw")
        }
        
        @JvmStatic
        private external fun nativeInit(configPath: String): Int
        
        @JvmStatic
        private external fun nativeSendMessage(message: String, callback: (String) -> Unit): Int
        
        @JvmStatic
        private external fun nativeCleanup()
    }
    
    private var isInitialized: Boolean = false
    
    init {
        val result = nativeInit(configPath)
        if (result != 0) {
            throw ZeroClawException("Failed to initialize ZeroClaw")
        }
        isInitialized = true
    }
    
    fun sendMessage(message: String, callback: (String) -> Unit) {
        if (!isInitialized) {
            throw IllegalStateException("ZeroClaw not initialized")
        }
        nativeSendMessage(message, callback)
    }
    
    protected fun finalize() {
        if (isInitialized) {
            nativeCleanup()
        }
    }
}

class ZeroClawException(message: String) : Exception(message)
```

---

## 4. Dependency Compatibility Analysis

### 4.1 Core Dependencies

| Dependency | iOS Support | Android Support | Notes |
|------------|-------------|-----------------|-------|
| `tokio` | ✅ Full | ✅ Full | Works on all mobile targets |
| `reqwest` | ✅ Full | ✅ Full | Use `rustls-tls` feature |
| `serde`/`serde_json` | ✅ Full | ✅ Full | Pure Rust, no issues |
| `rusqlite` | ✅ Full | ✅ Full | Bundled SQLite works on mobile |
| `clap` | ⚠️ Limited | ⚠️ Limited | CLI parsing not needed on mobile |
| `dialoguer` | ❌ No | ❌ No | Interactive prompts not supported |

### 4.2 Platform-Specific Issues

#### Network Stack
- **Current**: `reqwest` with `rustls-tls`
- **Mobile**: Works but may want to use platform native networking for better integration
- **Recommendation**: Keep `rustls` for consistency, but add option for platform networking

#### Shell Execution
- **Current**: Direct shell command execution via `tokio::process::Command`
- **Mobile**: Extremely limited or not available
- **Solution**: Implement `MobileRuntime` with `has_shell_access() = false`

#### Filesystem Access
- **Current**: Full filesystem access
- **Mobile**: Sandboxed to app container
- **Solution**: Override `storage_path()` to use app-specific directories

#### Background Tasks
- **Current**: `daemon` mode runs indefinitely
- **Mobile**: Background restrictions apply
- **Solution**: Use foreground services (Android) or background app refresh (iOS)

### 4.3 Feature Flags for Mobile

Add mobile-specific feature flags to reduce binary size:

```toml
[features]
default = ["full"]
full = ["cli", "gateway", "all-channels", "all-providers"]
mobile = ["core-providers", "core-channels"]
mobile-ios = ["mobile"]
mobile-android = ["mobile"]

core-providers = ["openai", "anthropic", "openrouter"]
core-channels = ["webhook"]
all-channels = ["telegram", "discord", "slack", "whatsapp", "irc"]
all-providers = [...]

cli = ["clap", "dialoguer"]
gateway = ["axum", "tower"]
```

---

## 5. Technical Challenges

### 5.1 Critical Challenges

#### 1. Shell Tool Restrictions
**Challenge**: Mobile platforms don't allow arbitrary shell execution.

**Impact**: HIGH - The `shell` tool is a core feature.

**Solution**:
- Implement `MobileRuntime` that returns `has_shell_access() = false`
- Disable shell tool on mobile
- Provide alternative tools: `http_request`, `file_operations`, `app_integration`
- Create mobile-specific tool plugins

#### 2. Background Processing
**Challenge**: Mobile OSes aggressively limit background execution.

**Impact**: MEDIUM - Affects `daemon` mode and long-running tasks.

**Solution**:
- iOS: Use Background Tasks framework with scheduled refresh
- Android: Use WorkManager for periodic tasks, Foreground Service for active sessions
- Implement `MobileRuntime::supports_long_running() = false` variant
- Add "interactive mode" where app must be in foreground

#### 3. Memory Constraints
**Challenge**: Mobile devices have limited memory and aggressive memory management.

**Impact**: MEDIUM - Must be more conservative with memory usage.

**Solution**:
- Implement `memory_budget()` in `MobileRuntime` (e.g., 50MB)
- Add memory pressure handling
- Reduce model context length on mobile
- Stream responses to avoid buffering large outputs

#### 4. Code Signing and Distribution
**Challenge**: iOS requires code signing; Android requires APK signing.

**Impact**: MEDIUM - CI/CD complexity.

**Solution**:
- Set up automated builds for mobile targets
- Integrate with Xcode build system (iOS)
- Integrate with Gradle build system (Android)
- Automate code signing in CI

### 5.2 Minor Challenges

#### 5. Network Permissions
**Solution**: Request at runtime, handle gracefully if denied.

#### 6. Storage Permissions
**Solution**: Use app-internal storage by default; request external storage if needed.

#### 7. Battery Optimization
**Solution**: Implement efficient polling, use push notifications where possible.

#### 8. Cross-Compilation
**Solution**: Use `cross` tool or set up proper toolchains for iOS/Android targets.

---

## 6. Recommended Approach

### 6.1 Phased Implementation

#### Phase 1: Foundation (Weeks 1-2)
- Create `MobileRuntime` trait implementation
- Implement iOS runtime adapter
- Implement Android runtime adapter
- Set up cross-compilation for iOS/Android targets
- Create basic FFI layer

#### Phase 2: Platform Wrappers (Weeks 3-4)
- Implement Swift wrapper for iOS
- Implement Kotlin wrapper for Android
- Create sample iOS app
- Create sample Android app
- Test basic message send/receive

#### Phase 3: Feature Adaptation (Weeks 5-6)
- Disable incompatible features (shell, gateway)
- Implement mobile-specific tools
- Add background task support
- Implement push notification integration
- Test memory usage under constraints

#### Phase 4: Polish (Weeks 7-8)
- CI/CD for mobile builds
- Documentation and examples
- Performance optimization
- Security hardening
- App Store / Play Store preparation

### 6.2 Minimum Viable Product (MVP)

**Core Features for Mobile:**
1. ✅ Message send/receive to AI providers
2. ✅ Memory persistence (SQLite)
3. ✅ File read/write (sandboxed)
4. ✅ Basic configuration
5. ❌ Shell execution (not possible)
6. ⚠️ Gateway server (limited usefulness on mobile)
7. ⚠️ Background daemon (with restrictions)

**MVP Scope:**
- Single provider support (OpenRouter or Anthropic)
- Single channel support (direct API)
- File operations in app sandbox
- Memory recall/store
- Basic configuration management

---

## 7. Implementation Roadmap

### 7.1 Project Structure

```
zeroclaw/
├── src/
│   ├── mobile/
│   │   ├── mod.rs           # Mobile module
│   │   ├── ffi.rs           # C FFI exports
│   │   ├── ios.rs           # iOS-specific runtime
│   │   ├── android.rs       # Android-specific runtime
│   │   └── runtime.rs       # Mobile runtime adapter
│   └── runtime/
│       ├── native.rs        # Existing native runtime
│       ├── docker.rs        # Existing docker runtime
│       └── mobile.rs        # Import mobile runtime
├── mobile/
│   ├── ios/
│   │   ├── ZeroClaw.xcodeproj/
│   │   ├── ZeroClaw/
│   │   │   ├── ZeroClaw.swift
│   │   │   └── ZeroClawBridge.h
│   │   └── ZeroClawTests/
│   └── android/
│       ├── app/
│       │   ├── src/main/
│       │   │   ├── kotlin/com/zeroclaw/sdk/
│       │   │   │   └── ZeroClaw.kt
│       │   │   └── jniLibs/
│       │   └── build.gradle.kts
│       └── settings.gradle.kts
└── Cargo.toml
```

### 7.2 Build Configuration

#### iOS Target

```toml
# .cargo/config.toml
[target.aarch64-apple-ios]
rustflags = ["-C", "link-arg=-Wl,-all_load"]

[target.aarch64-apple-ios-sim]
rustflags = ["-C", "link-arg=-Wl,-all_load"]
```

Build commands:
```bash
# iOS Device (ARM64)
cargo build --release --target aarch64-apple-ios --features mobile-ios

# iOS Simulator (ARM64 Mac)
cargo build --release --target aarch64-apple-ios-sim --features mobile-ios

# iOS Simulator (Intel Mac)
cargo build --release --target x86_64-apple-ios --features mobile-ios

# Create universal library
lipo -create \
  target/aarch64-apple-ios/release/libzeroclaw.a \
  target/x86_64-apple-ios/release/libzeroclaw.a \
  -output mobile/ios/libzeroclaw.a
```

#### Android Target

```toml
# .cargo/config.toml
[target.aarch64-linux-android]
linker = "aarch64-linux-android-clang"

[target.armv7-linux-androideabi]
linker = "armv7a-linux-androideabi-clang"
```

Build commands:
```bash
# Install NDK and set up
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/25.2.9519653

# Build for Android ARM64
cargo build --release --target aarch64-linux-android --features mobile-android

# Build for Android ARMv7
cargo build --release --target armv7-linux-androideabi --features mobile-android

# Copy to Android project
cp target/aarch64-linux-android/release/libzeroclaw.so \
   mobile/android/app/src/main/jniLibs/arm64-v8a/

cp target/armv7-linux-androideabi/release/libzeroclaw.so \
   mobile/android/app/src/main/jniLibs/armeabi-v7a/
```

### 7.3 CI/CD Integration

```yaml
# .github/workflows/mobile.yml
name: Mobile Builds

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  build-ios:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: dtolnay/rust-toolchain@stable
      - name: Add iOS targets
        run: |
          rustup target add aarch64-apple-ios
          rustup target add aarch64-apple-ios-sim
          rustup target add x86_64-apple-ios
      - name: Build iOS
        run: |
          cargo build --release --target aarch64-apple-ios --features mobile-ios
          cargo build --release --target aarch64-apple-ios-sim --features mobile-ios
      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: ios-libs
          path: target/*/release/libzeroclaw.a

  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: dtolnay/rust-toolchain@stable
      - name: Set up Android NDK
        uses: nttld/setup-ndk@v1
        with:
          ndk-version: r25c
      - name: Add Android targets
        run: |
          rustup target add aarch64-linux-android
          rustup target add armv7-linux-androideabi
      - name: Build Android
        run: |
          cargo build --release --target aarch64-linux-android --features mobile-android
          cargo build --release --target armv7-linux-androideabi --features mobile-android
      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: android-libs
          path: target/*/release/libzeroclaw.so
```

---

## 8. Code Examples

### 8.1 Mobile Runtime Implementation

```rust
// src/mobile/runtime.rs

use crate::runtime::RuntimeAdapter;
use std::path::{Path, PathBuf};

pub struct MobileRuntime {
    platform: MobilePlatform,
    storage_base: PathBuf,
    memory_limit: u64,
}

pub enum MobilePlatform {
    IOS,
    Android,
}

impl MobileRuntime {
    pub fn new(platform: MobilePlatform, storage_base: PathBuf) -> Self {
        let memory_limit = match platform {
            MobilePlatform::IOS => 50 * 1024 * 1024,      // 50MB
            MobilePlatform::Android => 100 * 1024 * 1024, // 100MB
        };
        
        Self {
            platform,
            storage_base,
            memory_limit,
        }
    }
}

impl RuntimeAdapter for MobileRuntime {
    fn name(&self) -> &str {
        match self.platform {
            MobilePlatform::IOS => "ios",
            MobilePlatform::Android => "android",
        }
    }

    fn has_shell_access(&self) -> bool {
        false // Mobile platforms don't allow shell execution
    }

    fn has_filesystem_access(&self) -> bool {
        true // Limited to app sandbox
    }

    fn storage_path(&self) -> PathBuf {
        self.storage_base.clone()
    }

    fn supports_long_running(&self) -> bool {
        false // Background execution is restricted
    }

    fn memory_budget(&self) -> u64 {
        self.memory_limit
    }

    fn build_shell_command(
        &self,
        _command: &str,
        _workspace_dir: &Path,
    ) -> anyhow::Result<tokio::process::Command> {
        anyhow::bail!("Shell execution not supported on mobile platforms")
    }
}
```

### 8.2 FFI Interface

```rust
// src/mobile/ffi.rs

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Mutex;
use once_cell::sync::Lazy;

static RUNTIME: Lazy<Mutex<Option<MobileRuntimeHandle>>> = Lazy::new(|| Mutex::new(None));

struct MobileRuntimeHandle {
    config: Config,
    runtime: Box<dyn RuntimeAdapter>,
}

/// Initialize the ZeroClaw runtime
/// Returns 0 on success, -1 on error
#[no_mangle]
pub extern "C" fn zeroclaw_init(
    config_json: *const c_char,
    storage_path: *const c_char,
) -> i32 {
    if config_json.is_null() || storage_path.is_null() {
        return -1;
    }

    let config_str = unsafe {
        match CStr::from_ptr(config_json).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };

    let storage_str = unsafe {
        match CStr::from_ptr(storage_path).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };

    // Parse config and initialize runtime
    let config: Config = match serde_json::from_str(config_str) {
        Ok(c) => c,
        Err(_) => return -1,
    };

    let platform = if cfg!(target_os = "ios") {
        MobilePlatform::IOS
    } else if cfg!(target_os = "android") {
        MobilePlatform::Android
    } else {
        return -1;
    };

    let runtime = MobileRuntime::new(platform, PathBuf::from(storage_str));
    
    let mut handle = RUNTIME.lock().unwrap();
    *handle = Some(MobileRuntimeHandle {
        config,
        runtime: Box::new(runtime),
    });

    0
}

/// Send a message and receive async response via callback
/// Returns 0 on success, -1 on error
#[no_mangle]
pub extern "C" fn zeroclaw_send_message(
    message: *const c_char,
    callback: extern "C" fn(*const c_char, *mut std::ffi::c_void),
    user_data: *mut std::ffi::c_void,
) -> i32 {
    if message.is_null() {
        return -1;
    }

    let message_str = unsafe {
        match CStr::from_ptr(message).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return -1,
        }
    };

    // Spawn async task to process message
    tokio::spawn(async move {
        let response = process_message(&message_str).await;
        
        let response_cstr = match CString::new(response) {
            Ok(s) => s,
            Err(_) => return,
        };

        callback(response_cstr.as_ptr(), user_data);
    });

    0
}

/// Get the current status as JSON string
/// Caller must free the returned string with zeroclaw_free_string
#[no_mangle]
pub extern "C" fn zeroclaw_get_status() -> *mut c_char {
    let handle = RUNTIME.lock().unwrap();
    
    if handle.is_none() {
        return std::ptr::null_mut();
    }

    let status = serde_json::json!({
        "initialized": true,
        "runtime": handle.as_ref().unwrap().runtime.name(),
        "version": env!("CARGO_PKG_VERSION"),
    });

    match CString::new(status.to_string()) {
        Ok(s) => s.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a string returned by ZeroClaw
#[no_mangle]
pub extern "C" fn zeroclaw_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

/// Clean up and shut down ZeroClaw
#[no_mangle]
pub extern "C" fn zeroclaw_cleanup() {
    let mut handle = RUNTIME.lock().unwrap();
    *handle = None;
}

async fn process_message(message: &str) -> String {
    // Actual implementation would go here
    format!("Echo: {}", message)
}
```

### 8.3 iOS Swift Wrapper (Complete Example)

```swift
// mobile/ios/ZeroClaw/ZeroClaw.swift

import Foundation

public class ZeroClaw {
    private var isInitialized = false
    
    public enum ZeroClawError: Error {
        case initializationFailed
        case notInitialized
        case invalidResponse
        case messageSendFailed
    }
    
    public init(apiKey: String, provider: String = "openrouter") throws {
        // Get app documents directory for storage
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].path
        
        // Create config JSON
        let config: [String: Any] = [
            "api_key": apiKey,
            "default_provider": provider,
            "memory": [
                "backend": "sqlite",
                "auto_save": true
            ],
            "runtime": [
                "kind": "ios"
            ]
        ]
        
        guard let configData = try? JSONSerialization.data(withJSONObject: config),
              let configString = String(data: configData, encoding: .utf8) else {
            throw ZeroClawError.initializationFailed
        }
        
        // Initialize native library
        let result = configString.withCString { configPtr in
            documentsPath.withCString { storagePtr in
                zeroclaw_init(configPtr, storagePtr)
            }
        }
        
        guard result == 0 else {
            throw ZeroClawError.initializationFailed
        }
        
        isInitialized = true
    }
    
    public func sendMessage(_ message: String) async throws -> String {
        guard isInitialized else {
            throw ZeroClawError.notInitialized
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            // Create context for callback
            let context = CallbackContext(continuation: continuation)
            let contextPtr = Unmanaged.passRetained(context).toOpaque()
            
            // C callback function
            let callback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = {
                responsePtr, userDataPtr in
                
                guard let userDataPtr = userDataPtr else { return }
                let context = Unmanaged<CallbackContext>.fromOpaque(userDataPtr).takeRetainedValue()
                
                if let responsePtr = responsePtr {
                    let response = String(cString: responsePtr)
                    zeroclaw_free_string(UnsafeMutablePointer(mutating: responsePtr))
                    context.continuation.resume(returning: response)
                } else {
                    context.continuation.resume(throwing: ZeroClawError.invalidResponse)
                }
            }
            
            // Send message
            let result = message.withCString { messagePtr in
                zeroclaw_send_message(messagePtr, callback, contextPtr)
            }
            
            if result != 0 {
                Unmanaged<CallbackContext>.fromOpaque(contextPtr).release()
                continuation.resume(throwing: ZeroClawError.messageSendFailed)
            }
        }
    }
    
    public func getStatus() throws -> [String: Any] {
        guard isInitialized else {
            throw ZeroClawError.notInitialized
        }
        
        guard let statusPtr = zeroclaw_get_status() else {
            throw ZeroClawError.invalidResponse
        }
        
        let statusString = String(cString: statusPtr)
        zeroclaw_free_string(statusPtr)
        
        guard let data = statusString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ZeroClawError.invalidResponse
        }
        
        return json
    }
    
    deinit {
        if isInitialized {
            zeroclaw_cleanup()
        }
    }
}

private class CallbackContext {
    let continuation: CheckedContinuation<String, Error>
    
    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }
}

// C function declarations
@_silgen_name("zeroclaw_init")
func zeroclaw_init(_ config: UnsafePointer<CChar>, _ storage: UnsafePointer<CChar>) -> Int32

@_silgen_name("zeroclaw_send_message")
func zeroclaw_send_message(
    _ message: UnsafePointer<CChar>,
    _ callback: @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void,
    _ userData: UnsafeMutableRawPointer?
) -> Int32

@_silgen_name("zeroclaw_get_status")
func zeroclaw_get_status() -> UnsafeMutablePointer<CChar>?

@_silgen_name("zeroclaw_free_string")
func zeroclaw_free_string(_ string: UnsafeMutablePointer<CChar>)

@_silgen_name("zeroclaw_cleanup")
func zeroclaw_cleanup()
```

### 8.4 Android Kotlin Wrapper (Complete Example)

```kotlin
// mobile/android/app/src/main/kotlin/com/zeroclaw/sdk/ZeroClaw.kt

package com.zeroclaw.sdk

import kotlinx.coroutines.*
import org.json.JSONObject
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

class ZeroClaw(apiKey: String, provider: String = "openrouter", storageDir: String) {
    
    companion object {
        init {
            System.loadLibrary("zeroclaw")
        }
        
        @JvmStatic
        private external fun nativeInit(config: String, storage: String): Int
        
        @JvmStatic
        private external fun nativeSendMessage(
            message: String,
            callback: (String) -> Unit
        ): Int
        
        @JvmStatic
        private external fun nativeGetStatus(): String?
        
        @JvmStatic
        private external fun nativeCleanup()
    }
    
    private var isInitialized: Boolean = false
    
    init {
        // Create config JSON
        val config = JSONObject().apply {
            put("api_key", apiKey)
            put("default_provider", provider)
            put("memory", JSONObject().apply {
                put("backend", "sqlite")
                put("auto_save", true)
            })
            put("runtime", JSONObject().apply {
                put("kind", "android")
            })
        }
        
        val result = nativeInit(config.toString(), storageDir)
        if (result != 0) {
            throw ZeroClawException("Failed to initialize ZeroClaw (error code: $result)")
        }
        
        isInitialized = true
    }
    
    suspend fun sendMessage(message: String): String = suspendCoroutine { continuation ->
        if (!isInitialized) {
            continuation.resumeWithException(IllegalStateException("ZeroClaw not initialized"))
            return@suspendCoroutine
        }
        
        val result = nativeSendMessage(message) { response ->
            continuation.resume(response)
        }
        
        if (result != 0) {
            continuation.resumeWithException(
                ZeroClawException("Failed to send message (error code: $result)")
            )
        }
    }
    
    fun getStatus(): JSONObject {
        if (!isInitialized) {
            throw IllegalStateException("ZeroClaw not initialized")
        }
        
        val statusString = nativeGetStatus()
            ?: throw ZeroClawException("Failed to get status")
        
        return JSONObject(statusString)
    }
    
    fun cleanup() {
        if (isInitialized) {
            nativeCleanup()
            isInitialized = false
        }
    }
    
    protected fun finalize() {
        cleanup()
    }
}

class ZeroClawException(message: String) : Exception(message)
```

---

## 9. Testing Strategy

### 9.1 Unit Tests

```rust
// src/mobile/tests.rs

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mobile_runtime_no_shell() {
        let runtime = MobileRuntime::new(
            MobilePlatform::IOS,
            PathBuf::from("/tmp/test"),
        );
        assert!(!runtime.has_shell_access());
    }

    #[test]
    fn mobile_runtime_has_filesystem() {
        let runtime = MobileRuntime::new(
            MobilePlatform::Android,
            PathBuf::from("/tmp/test"),
        );
        assert!(runtime.has_filesystem_access());
    }

    #[test]
    fn mobile_runtime_memory_budget() {
        let runtime = MobileRuntime::new(
            MobilePlatform::IOS,
            PathBuf::from("/tmp/test"),
        );
        assert!(runtime.memory_budget() > 0);
        assert!(runtime.memory_budget() < 200 * 1024 * 1024); // < 200MB
    }

    #[test]
    fn shell_command_fails_on_mobile() {
        let runtime = MobileRuntime::new(
            MobilePlatform::IOS,
            PathBuf::from("/tmp/test"),
        );
        let result = runtime.build_shell_command("echo test", Path::new("/tmp"));
        assert!(result.is_err());
    }
}
```

### 9.2 Integration Tests

#### iOS XCTest

```swift
// mobile/ios/ZeroClawTests/ZeroClawTests.swift

import XCTest
@testable import ZeroClaw

class ZeroClawTests: XCTestCase {
    
    func testInitialization() throws {
        let zeroclaw = try ZeroClaw(
            apiKey: "test-key",
            provider: "openrouter"
        )
        
        let status = try zeroclaw.getStatus()
        XCTAssertEqual(status["initialized"] as? Bool, true)
        XCTAssertEqual(status["runtime"] as? String, "ios")
    }
    
    func testSendMessage() async throws {
        let zeroclaw = try ZeroClaw(
            apiKey: "test-key",
            provider: "openrouter"
        )
        
        let response = try await zeroclaw.sendMessage("Hello, ZeroClaw!")
        XCTAssertFalse(response.isEmpty)
    }
    
    func testMultipleMessages() async throws {
        let zeroclaw = try ZeroClaw(
            apiKey: "test-key",
            provider: "openrouter"
        )
        
        for i in 1...5 {
            let response = try await zeroclaw.sendMessage("Message \(i)")
            XCTAssertFalse(response.isEmpty)
        }
    }
}
```

#### Android JUnit

```kotlin
// mobile/android/app/src/androidTest/kotlin/com/zeroclaw/sdk/ZeroClawTest.kt

package com.zeroclaw.sdk

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ZeroClawTest {
    
    private lateinit var zeroclaw: ZeroClaw
    
    @Before
    fun setUp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val storageDir = context.filesDir.absolutePath
        
        zeroclaw = ZeroClaw(
            apiKey = "test-key",
            provider = "openrouter",
            storageDir = storageDir
        )
    }
    
    @After
    fun tearDown() {
        zeroclaw.cleanup()
    }
    
    @Test
    fun testInitialization() {
        val status = zeroclaw.getStatus()
        assertEquals(true, status.getBoolean("initialized"))
        assertEquals("android", status.getString("runtime"))
    }
    
    @Test
    fun testSendMessage() = runBlocking {
        val response = zeroclaw.sendMessage("Hello, ZeroClaw!")
        assertNotNull(response)
        assertFalse(response.isEmpty())
    }
    
    @Test
    fun testMultipleMessages() = runBlocking {
        repeat(5) { i ->
            val response = zeroclaw.sendMessage("Message ${i + 1}")
            assertNotNull(response)
            assertFalse(response.isEmpty())
        }
    }
}
```

### 9.3 Performance Tests

```rust
#[cfg(test)]
mod perf_tests {
    use super::*;
    use std::time::Instant;

    #[test]
    fn mobile_runtime_startup_time() {
        let start = Instant::now();
        let _runtime = MobileRuntime::new(
            MobilePlatform::IOS,
            PathBuf::from("/tmp/test"),
        );
        let elapsed = start.elapsed();
        
        // Should initialize in under 10ms
        assert!(elapsed.as_millis() < 10);
    }

    #[test]
    fn mobile_memory_footprint() {
        // Measure memory before and after
        let before = get_memory_usage();
        let _runtime = MobileRuntime::new(
            MobilePlatform::Android,
            PathBuf::from("/tmp/test"),
        );
        let after = get_memory_usage();
        
        // Should use less than 5MB for initialization
        assert!(after - before < 5 * 1024 * 1024);
    }
}
```

---

## 10. Maintenance Considerations

### 10.1 Documentation Requirements

1. **Mobile-specific README**: Create `docs/mobile-quickstart.md`
2. **API Reference**: Document all FFI functions
3. **Integration Guides**: Step-by-step for iOS and Android
4. **Troubleshooting Guide**: Common mobile issues

### 10.2 Version Compatibility

- **Minimum iOS**: 14.0+ (supports 95%+ of devices as of 2026)
- **Minimum Android**: API 26 (Android 8.0+, supports 95%+ of devices)
- **Rust**: 1.75+ for stable mobile support
- **NDK**: r25c or later for Android builds

### 10.3 Ongoing Maintenance Tasks

1. **Update Dependencies**: Keep mobile targets compatible
2. **Test New OS Versions**: Beta test on iOS/Android betas
3. **Performance Monitoring**: Track mobile-specific metrics
4. **Security Updates**: Monitor for mobile-specific vulnerabilities
5. **User Feedback**: Collect and address mobile-specific issues

### 10.4 Breaking Change Policy

- Mobile FFI should be stable once v1.0 is released
- Version FFI interface to allow backward compatibility
- Use feature flags to maintain old behavior during transitions

---

## Conclusion

Running ZeroClaw on mobile devices via Swift and Kotlin wrappers is **technically feasible** and aligns well with the project's trait-based architecture. The main challenges are:

1. **Adapting to mobile constraints** (no shell, limited background execution)
2. **Setting up cross-compilation** and CI/CD for mobile targets
3. **Creating robust FFI** layer and native wrappers

**Recommended Next Steps:**

1. ✅ Create this feasibility document (complete)
2. Start with **Phase 1: Foundation** (2 weeks)
3. Build a **minimal iOS prototype** to validate approach
4. Build a **minimal Android prototype** to validate approach
5. Iterate based on feedback and testing

**Estimated Timeline:** 8-12 weeks for full mobile support with proper testing and documentation.

**Resource Requirements:**
- 1-2 developers with Rust + mobile experience
- iOS device for testing (iPhone)
- Android device for testing (Pixel or Samsung)
- Apple Developer account ($99/year)
- Google Play Developer account ($25 one-time)

This feasibility assessment demonstrates that mobile support is achievable and would significantly expand ZeroClaw's reach while maintaining its core value propositions of performance, efficiency, and security.

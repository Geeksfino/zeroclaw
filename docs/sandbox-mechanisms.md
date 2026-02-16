# ZeroClaw Sandbox Mechanisms

This document explains how ZeroClaw isolates and secures the execution of tools and skill scripts, and proposes what needs to be implemented for mobile platforms (iOS/Android).

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Current Sandbox Layers](#current-sandbox-layers)
3. [Runtime Adapters](#runtime-adapters)
4. [Security Policy Framework](#security-policy-framework)
5. [Tool Execution Security](#tool-execution-security)
6. [Skill Script Sandboxing](#skill-script-sandboxing)
7. [Mobile Platform Requirements](#mobile-platform-requirements)
8. [Proposed Mobile Implementation](#proposed-mobile-implementation)

---

## Architecture Overview

ZeroClaw uses a **defense-in-depth** approach with multiple sandbox layers:

```
┌─────────────────────────────────────────────────┐
│          User Request / Agent Loop              │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  Layer 1: Security Policy (src/security/)      │
│  - Autonomy levels (ReadOnly/Supervised/Full)   │
│  - Command allowlisting                         │
│  - Risk classification (High/Medium/Low)        │
│  - Path validation & traversal blocking         │
│  - Rate limiting (20 actions/hr, $5/day)        │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  Layer 2: Tool Execution (src/tools/)          │
│  - Input validation & sanitization             │
│  - Output limits (1MB max)                     │
│  - Timeout enforcement (60s)                   │
│  - Environment variable scrubbing              │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  Layer 3: Runtime Adapter (src/runtime/)       │
│  - Platform-specific isolation                  │
│  - Resource constraints                         │
│  - Capability gating                            │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  Layer 4: Platform Sandbox                     │
│  - Native: OS-level permissions                │
│  - Docker: Container isolation                  │
│  - Mobile: App sandbox + restrictions          │
└─────────────────────────────────────────────────┘
```

---

## Current Sandbox Layers

### 1. Security Policy (`src/security/policy.rs`)

**Autonomy Levels:**
- `ReadOnly`: Agent can observe but not execute actions
- `Supervised` (default): Requires approval for medium/high-risk commands
- `Full`: Autonomous within policy bounds

**Command Risk Classification:**

| Risk Level | Default Behavior | Examples |
|-----------|------------------|----------|
| **High** | Blocked | `rm -rf`, `sudo`, `dd`, `shutdown`, `curl`, `wget`, `ssh` |
| **Medium** | Requires approval | `git push`, `npm install`, `mkdir`, `cp`, `touch` |
| **Low** | Allowed | `ls`, `cat`, `grep`, `echo`, `pwd` |

**Security Constraints:**
- **Path traversal blocking**: Rejects `..`, URL-encoded paths (`%2f`, `%2e`)
- **Forbidden paths**: `/etc`, `/root`, `/home`, `/usr`, `/bin`, `~/.ssh`, `~/.aws`
- **Subshell blocking**: Prevents `` ` ``, `$(...)`, `${...}` (CWE-200: secret leakage)
- **Output redirection blocking**: Forbids `>`, `>>` to prevent writes outside workspace
- **Workspace-only mode**: Restricts operations to configured workspace directory
- **Rate limiting**: Max 20 actions/hour, max 500 cents/day ($5.00)

**Default Allowed Commands:**
```
git, npm, cargo, python, node, go, make, docker,
ls, cat, grep, find, echo, pwd, wc, head, tail, less
```

### 2. Tool Execution Security (`src/tools/`)

Every tool implements the `Tool` trait:

```rust
pub trait Tool: Send + Sync {
    fn name(&self) -> &str;
    fn execute(&self, args: serde_json::Value) -> ToolResult;
}
```

**Security Measures per Tool:**

#### Shell Tool
- **Timeout**: 60 seconds (prevents runaway processes)
- **Output limit**: 1MB (prevents memory exhaustion)
- **Environment scrubbing**: Only safe variables passed (`PATH`, `HOME`, `TERM`)
  - Blocks: `AWS_*`, `GCP_*`, `GITHUB_TOKEN`, `OPENAI_API_KEY`, etc.
  - Prevents CWE-200 (sensitive data exposure)
- **Security policy validation**: Every command checked before execution

#### File Read/Write Tools
- **Path validation**: Canonical path resolution
- **Symlink attack prevention**: Resolves symlinks before access
- **Forbidden path blocking**: Rejects access to system directories
- **Size limits**: Configurable max file size

#### Browser Tool
- **Domain allowlisting**: Only approved domains accessible
- **Screenshot sanitization**: No credentials in visible UI
- **Resource limits**: Max page size, timeout

#### Memory Tools (Store/Recall/Forget)
- **Embedding validation**: Input sanitization
- **Injection prevention**: Parameterized queries for SQLite
- **Size limits**: Per-entry size constraints

### 3. Agent Loop Protection (`src/agent/loop_.rs`)

**Runaway Prevention:**
- **Max 10 iterations** per user message
- **Tool call parsing**: Validates XML structure
- **Error recovery**: Malformed tool calls don't crash the agent
- **Result wrapping**: All tool results sanitized before returning to LLM

---

## Runtime Adapters

Runtime adapters abstract platform-specific execution through the `RuntimeAdapter` trait:

```rust
pub trait RuntimeAdapter: Send + Sync {
    fn name(&self) -> &str;
    fn has_shell_access(&self) -> bool;
    fn has_filesystem_access(&self) -> bool;
    fn supports_long_running(&self) -> bool;
    fn memory_budget(&self) -> usize; // bytes, 0 = unlimited
}
```

### Native Runtime (`src/runtime/native.rs`)

**Capabilities:**
- Full shell access via OS process spawning
- Full filesystem access (limited by security policy)
- Supports long-running processes (gateway, heartbeat)
- No memory budget constraints

**Platform Support:**
- ✅ macOS (x86_64, ARM64)
- ✅ Linux (x86_64, ARM64)
- ✅ Windows (basic support)
- ✅ Raspberry Pi (ARM)

**Use Cases:**
- Local development
- Personal workstation automation
- Edge devices (Raspberry Pi)

### Docker Runtime (`src/runtime/docker.rs`)

**Capabilities:**
- Shell access within isolated container
- Filesystem access limited to mounted workspace
- Supports long-running containers
- Configurable resource limits

**Isolation Features:**
```toml
[runtime.docker]
image = "alpine:latest"
memory_limit = "512m"      # 512MB RAM limit
cpu_limit = 1.0            # 1 CPU core
network = "none"           # No network access
readonly_root = true       # Read-only root filesystem
workspace_mount = true     # Mount workspace as RW volume
```

**Security Benefits:**
- **Container isolation**: Separate PID, network, filesystem namespaces
- **Resource limits**: Prevents resource exhaustion attacks
- **Read-only root**: Immutable system files
- **Network isolation**: No outbound connections (unless enabled)
- **Workspace-only writes**: Only `/workspace` is writable

**Use Cases:**
- Untrusted code execution
- Multi-tenant environments
- CI/CD pipelines
- Production deployments

---

## Security Policy Framework

The `SecurityPolicy` struct enforces all constraints:

```rust
pub struct SecurityPolicy {
    pub autonomy_level: AutonomyLevel,
    pub allowed_commands: Vec<String>,
    pub forbidden_paths: Vec<String>,
    pub allow_subshells: bool,
    pub allow_output_redirection: bool,
    pub workspace_only: bool,
    pub workspace_dir: PathBuf,
    pub rate_limit: RateLimit,
}
```

**Validation Flow:**

1. **Command parsing**: Extract base command from arguments
2. **Allowlist check**: Command must be in `allowed_commands`
3. **Risk assessment**: Classify as High/Medium/Low
4. **Autonomy check**: Verify agent has permission for risk level
5. **Path validation**: Check for traversal attacks, forbidden paths
6. **Subshell detection**: Block command substitution patterns
7. **Redirection detection**: Block output redirection operators
8. **Workspace check**: Verify all paths within workspace (if enabled)
9. **Rate limit check**: Enforce action and cost limits

**Example Policy (Supervised Mode):**

```toml
[security]
autonomy_level = "supervised"
workspace_only = true
workspace_dir = "~/.zeroclaw/workspace"
allow_subshells = false
allow_output_redirection = false

allowed_commands = [
  "git", "npm", "cargo", "ls", "cat", "grep"
]

forbidden_paths = [
  "/etc", "/root", "/home", "~/.ssh", "~/.aws"
]

[security.rate_limit]
max_actions_per_hour = 20
max_cost_cents_per_day = 500  # $5.00
```

---

## Tool Execution Security

### Environment Variable Scrubbing

To prevent CWE-200 (exposure of sensitive information), ZeroClaw scrubs environment variables before executing shell commands:

**Allowed Variables:**
```rust
const SAFE_ENV_VARS: &[&str] = &[
    "PATH", "HOME", "USER", "TERM", "SHELL",
    "LANG", "LC_ALL", "TZ", "TMPDIR"
];
```

**Blocked Patterns:**
- `*_TOKEN`, `*_KEY`, `*_SECRET`, `*_PASSWORD`
- `AWS_*`, `GCP_*`, `AZURE_*`
- `GITHUB_TOKEN`, `GITLAB_TOKEN`
- `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`

### Timeout & Output Limits

**Timeout Enforcement (60s):**
```rust
let output = tokio::time::timeout(
    Duration::from_secs(60),
    tokio::process::Command::new(&cmd).output()
).await?;
```

**Output Truncation (1MB):**
```rust
if output.stdout.len() > 1_048_576 {
    output.stdout.truncate(1_048_576);
    output.stdout.extend_from_slice(b"\n[truncated]");
}
```

### Path Validation

**Traversal Attack Prevention:**

```rust
pub fn validate_path(path: &str) -> Result<()> {
    // Block obvious traversals
    if path.contains("..") || path.contains("%2e%2e") {
        bail!("Path traversal detected");
    }
    
    // Resolve to canonical path
    let canonical = std::fs::canonicalize(path)?;
    
    // Check against forbidden paths
    for forbidden in FORBIDDEN_PATHS {
        if canonical.starts_with(forbidden) {
            bail!("Access to {} is forbidden", forbidden);
        }
    }
    
    Ok(())
}
```

---

## Skill Script Sandboxing

Skills are user-defined capabilities stored in `~/.zeroclaw/workspace/skills/`.

### Skill Format

**`SKILL.toml` Structure:**
```toml
[skill]
name = "analyze-logs"
description = "Parse and analyze application logs"
version = "0.1.0"
author = "you@example.com"
tags = ["logging", "debugging"]

[[tools]]
name = "parse_logs"
description = "Extract errors from log file"
kind = "shell"
command = "grep ERROR {{log_file}} | tail -n 10"

[[tools]]
name = "fetch_metrics"
description = "Get metrics from API"
kind = "http"
url = "https://api.example.com/metrics"
method = "GET"
```

**`SKILL.md` Structure:**
```markdown
# Skill: Code Review Helper

Analyze pull requests and provide feedback.

## Instructions
1. Fetch PR diff
2. Check for common issues
3. Suggest improvements
```

### Skill Loading & Execution

**Loading Process:**
1. Scan `~/.zeroclaw/workspace/skills/` directory
2. Parse `SKILL.toml` or `SKILL.md` files
3. Validate skill schema
4. Convert to LLM-visible tool definitions
5. Inject into system prompt

**Execution Security:**
- **Path traversal checks**: Prevents `../../../etc/passwd` escapes
- **Canonical path validation**: Resolves symlinks
- **Workspace boundary enforcement**: Skills must reside in workspace
- **Tool-level security**: Shell commands subject to security policy
- **HTTP restrictions**: Domain allowlisting for HTTP tools

**Community Skills:**
- Auto-synced from `~/open-skills/` (if enabled)
- Installed via `zeroclaw skills install <name>`
- Subject to same security constraints

---

## Mobile Platform Requirements

### iOS Constraints

Apple's iOS platform imposes strict sandboxing:

**App Sandbox Restrictions:**
- ❌ **No shell access**: `/bin/sh` not available to third-party apps
- ❌ **No process spawning**: `fork()`, `exec()` not permitted
- ✅ **Filesystem access**: Limited to app's sandbox directory
- ✅ **Network access**: Allowed with permissions
- ❌ **No background execution**: Suspended after 30 seconds in background
- ✅ **Memory limit**: ~50MB for extensions, ~500MB for apps

**Security Features:**
- **Code signing**: All code must be signed by Apple
- **Entitlements**: Capabilities explicitly declared
- **Sandboxed containers**: Each app isolated
- **No root access**: Apps run as non-root user

**Technical Constraints:**
- Cannot execute arbitrary binaries
- Cannot access system directories
- Cannot run servers/daemons
- Limited to iOS SDK APIs

### Android Constraints

Android provides more flexibility but still has restrictions:

**App Sandbox Restrictions:**
- ⚠️ **Limited shell access**: `/system/bin/sh` available but restricted
- ⚠️ **Process spawning**: Possible but heavily restricted
- ✅ **Filesystem access**: Scoped storage (Android 10+)
- ✅ **Network access**: Allowed with permissions
- ✅ **Background execution**: WorkManager for tasks <10 minutes
- ✅ **Memory limit**: ~100MB typical, device-dependent

**Security Features:**
- **SELinux**: Mandatory access control
- **App sandboxing**: UID-based isolation
- **Permissions**: Runtime permission requests
- **Scoped storage**: Limits filesystem access

**Technical Constraints:**
- Shell commands require `/system/bin` presence
- Cannot access other apps' data
- Background tasks limited (battery optimization)
- NDK required for native code

---

## Proposed Mobile Implementation

To support iOS and Android, ZeroClaw needs a new `MobileRuntime` adapter with restricted capabilities.

### 1. Mobile Runtime Trait Implementation

**File: `src/runtime/mobile.rs`**

```rust
use crate::runtime::traits::RuntimeAdapter;
use anyhow::{bail, Result};

pub struct MobileRuntime {
    platform: MobilePlatform,
}

pub enum MobilePlatform {
    IOS,
    Android,
}

impl MobileRuntime {
    pub fn new(platform: MobilePlatform) -> Self {
        Self { platform }
    }
}

impl RuntimeAdapter for MobileRuntime {
    fn name(&self) -> &str {
        match self.platform {
            MobilePlatform::IOS => "mobile-ios",
            MobilePlatform::Android => "mobile-android",
        }
    }

    fn has_shell_access(&self) -> bool {
        match self.platform {
            MobilePlatform::IOS => false,      // No shell on iOS
            MobilePlatform::Android => true,   // Limited shell on Android
        }
    }

    fn has_filesystem_access(&self) -> bool {
        true  // Both have scoped filesystem access
    }

    fn supports_long_running(&self) -> bool {
        false  // Mobile apps cannot run indefinitely
    }

    fn memory_budget(&self) -> usize {
        match self.platform {
            MobilePlatform::IOS => 50 * 1024 * 1024,      // 50MB
            MobilePlatform::Android => 100 * 1024 * 1024,  // 100MB
        }
    }
}
```

### 2. Restricted Tool Set

**File: `src/tools/mobile.rs`**

Mobile platforms need a reduced tool set:

```rust
pub fn get_mobile_tools(platform: MobilePlatform) -> Vec<Box<dyn Tool>> {
    match platform {
        MobilePlatform::IOS => vec![
            Box::new(FileReadTool::new()),
            Box::new(FileWriteTool::new()),
            Box::new(MemoryStoreTool::new()),
            Box::new(MemoryRecallTool::new()),
            Box::new(HttpRequestTool::new()),
            // No shell tool - not supported
        ],
        MobilePlatform::Android => vec![
            Box::new(FileReadTool::new()),
            Box::new(FileWriteTool::new()),
            Box::new(MemoryStoreTool::new()),
            Box::new(MemoryRecallTool::new()),
            Box::new(HttpRequestTool::new()),
            Box::new(AndroidShellTool::new()),  // Limited shell
        ],
    }
}
```

**Android Shell Tool (Limited):**

```rust
pub struct AndroidShellTool {
    allowed_commands: Vec<String>,
}

impl AndroidShellTool {
    pub fn new() -> Self {
        Self {
            allowed_commands: vec![
                "ls".into(), "cat".into(), "grep".into(),
                "find".into(), "echo".into(), "pwd".into(),
            ],
        }
    }
}

impl Tool for AndroidShellTool {
    fn name(&self) -> &str {
        "android_shell"
    }

    fn execute(&self, args: serde_json::Value) -> ToolResult {
        let cmd = args["command"].as_str()?;
        let base = cmd.split_whitespace().next()?;
        
        // Only allow safe read-only commands
        if !self.allowed_commands.contains(&base.to_string()) {
            bail!("Command '{}' not allowed on Android", base);
        }
        
        // Execute via JNI bridge to Android Runtime.exec()
        execute_android_command(cmd)
    }
}
```

### 3. FFI Bridge Layer

**File: `src/ffi/mobile.rs`**

For iOS/Android integration, provide C-compatible FFI:

```rust
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Initialize ZeroClaw runtime for mobile
/// Returns 0 on success, -1 on error
#[no_mangle]
pub extern "C" fn zeroclaw_init(platform: u8) -> i32 {
    let platform = match platform {
        0 => MobilePlatform::IOS,
        1 => MobilePlatform::Android,
        _ => return -1,
    };
    
    // Initialize runtime, config, etc.
    match init_mobile_runtime(platform) {
        Ok(_) => 0,
        Err(_) => -1,
    }
}

/// Send a message to ZeroClaw agent
/// Returns response string (caller must free with zeroclaw_free_string)
#[no_mangle]
pub extern "C" fn zeroclaw_send_message(
    message: *const c_char
) -> *mut c_char {
    let c_str = unsafe { CStr::from_ptr(message) };
    let msg = c_str.to_str().unwrap_or("");
    
    // Process message through agent loop
    let response = match process_message(msg) {
        Ok(resp) => resp,
        Err(e) => format!("Error: {}", e),
    };
    
    CString::new(response).unwrap().into_raw()
}

/// Free string returned by zeroclaw_send_message
#[no_mangle]
pub extern "C" fn zeroclaw_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { CString::from_raw(ptr) };
    }
}
```

### 4. Platform-Specific Build Configuration

**iOS Build Script** (`scripts/build-ios.sh`):

```bash
#!/bin/bash
set -e

# Build for iOS simulator and devices
cargo build --release --target aarch64-apple-ios          # iPhone/iPad
cargo build --release --target x86_64-apple-ios           # Simulator
cargo build --release --target aarch64-apple-ios-sim      # M1 Simulator

# Create universal library
lipo -create \
    target/aarch64-apple-ios/release/libzeroclaw.a \
    target/x86_64-apple-ios/release/libzeroclaw.a \
    -output libzeroclaw-universal.a

# Generate C headers
cbindgen --config cbindgen-ios.toml --output zeroclaw.h

echo "iOS library built: libzeroclaw-universal.a"
echo "Header: zeroclaw.h"
```

**Android Build Script** (`scripts/build-android.sh`):

```bash
#!/bin/bash
set -e

# Build for Android architectures
cargo build --release --target aarch64-linux-android      # ARM64
cargo build --release --target armv7-linux-androideabi    # ARM32
cargo build --release --target x86_64-linux-android       # x86_64 emulator

# Copy to Android jniLibs structure
mkdir -p android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}
cp target/aarch64-linux-android/release/libzeroclaw.so android/app/src/main/jniLibs/arm64-v8a/
cp target/armv7-linux-androideabi/release/libzeroclaw.so android/app/src/main/jniLibs/armeabi-v7a/
cp target/x86_64-linux-android/release/libzeroclaw.so android/app/src/main/jniLibs/x86_64/

echo "Android libraries built in android/app/src/main/jniLibs/"
```

### 5. Configuration Updates

**File: `src/config/runtime.rs`**

Add mobile runtime configuration:

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RuntimeConfig {
    pub kind: String,  // "native" | "docker" | "mobile-ios" | "mobile-android"
    
    #[serde(default)]
    pub docker: DockerConfig,
    
    #[serde(default)]
    pub mobile: MobileConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MobileConfig {
    /// Memory limit in bytes (default: 50MB iOS, 100MB Android)
    pub memory_limit: Option<usize>,
    
    /// Allowed domains for HTTP requests
    pub allowed_domains: Vec<String>,
    
    /// Maximum file size for read/write operations (bytes)
    pub max_file_size: usize,  // Default: 10MB
}
```

**Factory Update (`src/runtime/mod.rs`):**

```rust
pub fn create_runtime(config: &RuntimeConfig) -> anyhow::Result<Box<dyn RuntimeAdapter>> {
    match config.kind.as_str() {
        "native" => Ok(Box::new(NativeRuntime::new())),
        "docker" => Ok(Box::new(DockerRuntime::new(config.docker.clone()))),
        "mobile-ios" => Ok(Box::new(MobileRuntime::new(MobilePlatform::IOS))),
        "mobile-android" => Ok(Box::new(MobileRuntime::new(MobilePlatform::Android))),
        // ... rest
    }
}
```

### 6. Skill Restrictions for Mobile

**File: `src/skills/mobile.rs`**

Mobile platforms need additional skill restrictions:

```rust
pub fn validate_mobile_skill(skill: &Skill, platform: MobilePlatform) -> Result<()> {
    for tool in &skill.tools {
        match tool.kind.as_str() {
            "shell" => {
                if platform == MobilePlatform::IOS {
                    bail!("Shell tools not supported on iOS");
                }
                validate_android_shell_command(&tool.command)?;
            }
            "http" => {
                validate_http_domain(&tool.url)?;
            }
            "script" => {
                bail!("Script execution not supported on mobile");
            }
            _ => {}
        }
    }
    Ok(())
}
```

---

## Implementation Roadmap

### Phase 1: Core Mobile Runtime (Week 1-2)
- [ ] Implement `MobileRuntime` trait for iOS/Android
- [ ] Create restricted tool set (no shell for iOS, limited for Android)
- [ ] Add memory budget enforcement
- [ ] Write unit tests for mobile runtime

### Phase 2: FFI Bridge (Week 3)
- [ ] Create C-compatible FFI layer
- [ ] Build iOS static library (`.a`)
- [ ] Build Android shared library (`.so`)
- [ ] Generate C headers with `cbindgen`
- [ ] Write integration tests

### Phase 3: Platform Adapters (Week 4-5)
- [ ] **iOS**: Swift wrapper around FFI
- [ ] **Android**: Kotlin/Java JNI wrapper
- [ ] Platform-specific configuration handling
- [ ] Example iOS app (SwiftUI)
- [ ] Example Android app (Jetpack Compose)

### Phase 4: Mobile Constraints (Week 6)
- [ ] Implement memory budget tracking
- [ ] Add background task limitations
- [ ] Enforce skill restrictions (no shell on iOS)
- [ ] Add mobile-specific security policies
- [ ] Test on physical devices

### Phase 5: Documentation & Examples (Week 7)
- [ ] Mobile deployment guide
- [ ] iOS integration tutorial
- [ ] Android integration tutorial
- [ ] Best practices for mobile skills
- [ ] Performance optimization guide

---

## Testing Strategy

### Desktop/Server Testing

**Current Tests (Keep Existing):**
```bash
cargo test --features native    # Native runtime tests
cargo test --features docker    # Docker runtime tests
cargo test security::           # Security policy tests
cargo test tools::              # Tool execution tests
```

### Mobile Testing

**New Test Suites:**

```bash
# Mobile runtime unit tests
cargo test --features mobile-ios mobile::runtime
cargo test --features mobile-android mobile::runtime

# FFI tests
cargo test --features mobile-ffi ffi::

# Integration tests (on device)
# iOS: via Xcode Test
# Android: via Android Instrumentation Tests
```

**Device Testing Checklist:**
- [ ] iOS Simulator (x86_64, ARM64)
- [ ] iPhone (physical device)
- [ ] Android Emulator (x86_64, ARM64)
- [ ] Android phone (physical device)

---

## Security Considerations for Mobile

### iOS-Specific Security

1. **Code Signing**: All code must be signed with Apple Developer certificate
2. **Entitlements**: Request only necessary permissions
3. **App Transport Security**: Enforce HTTPS for network requests
4. **Keychain**: Store API keys in iOS Keychain, not plaintext
5. **Background Execution**: Use Background Tasks API (limited to 30s)

### Android-Specific Security

1. **SELinux**: Respect Android's mandatory access control
2. **Permissions**: Request runtime permissions (storage, network)
3. **ProGuard/R8**: Obfuscate code for release builds
4. **Encrypted Storage**: Use Android Keystore for secrets
5. **WorkManager**: Use for background tasks (battery-friendly)

### Common Mobile Threats

| Threat | Mitigation |
|--------|-----------|
| API key extraction | Use platform keychain, not hardcoded |
| Man-in-the-middle | Enforce certificate pinning |
| Excessive permissions | Request minimum necessary |
| Data leakage | Clear logs, no sensitive data in logs |
| Reverse engineering | Obfuscate, use native code |

---

## Performance Optimization

### Memory Management

**iOS** (50MB budget):
- Use streaming for large responses
- Implement aggressive caching eviction
- Monitor with Instruments (Xcode)

**Android** (100MB budget):
- Use `WeakReference` for caches
- Monitor with Android Profiler
- Implement `onLowMemory()` callback

### Network Efficiency

- Compress requests/responses (gzip)
- Batch API calls when possible
- Implement exponential backoff for retries
- Cache embeddings locally

### Battery Optimization

- Minimize background work
- Use WorkManager constraints (WiFi, charging)
- Avoid polling; use push notifications
- Batch operations (don't wake CPU frequently)

---

## Deployment Checklist

### iOS Deployment

- [ ] Xcode project integration
- [ ] Build for Release configuration
- [ ] Code signing with distribution certificate
- [ ] TestFlight beta testing
- [ ] App Store submission

### Android Deployment

- [ ] Android Studio integration
- [ ] ProGuard/R8 configuration
- [ ] APK/AAB signing with keystore
- [ ] Google Play Internal Testing
- [ ] Google Play release

---

## Conclusion

ZeroClaw's sandbox architecture provides strong isolation through multiple layers:

1. **Security policy** (allowlisting, path validation, rate limiting)
2. **Tool-level validation** (input sanitization, output limits)
3. **Runtime adaptation** (platform-specific constraints)
4. **Platform sandbox** (OS-level isolation)

For **mobile deployment**, the proposed `MobileRuntime` adapter adds:
- Platform-specific capability restrictions
- Memory budget enforcement
- Reduced tool set (no shell on iOS, limited on Android)
- FFI bridge for native integration

The trait-based architecture makes mobile support straightforward—implement `RuntimeAdapter` for each platform, restrict tools appropriately, and expose via FFI for Swift/Kotlin integration.

**Next Steps:**
1. Implement `MobileRuntime` for iOS/Android
2. Create FFI bridge layer
3. Build platform-specific wrappers (Swift, Kotlin)
4. Test on physical devices
5. Document mobile deployment process

---

## References

- **Source Code**: `src/runtime/`, `src/security/`, `src/tools/`
- **Configuration**: `zeroclaw.toml` schema
- **Skills**: `~/.zeroclaw/workspace/skills/`
- **Community**: [ZeroClaw GitHub](https://github.com/theonlyhennygod/zeroclaw)

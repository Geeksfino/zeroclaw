//! Mobile runtime adapter for iOS and Android platforms
//!
//! This module provides a restricted runtime adapter for mobile platforms,
//! with platform-specific constraints and reduced capabilities.
//!
//! ## Platform Constraints
//!
//! ### iOS
//! - No shell access (iOS sandbox prohibits)
//! - Scoped filesystem access (app sandbox only)
//! - No long-running processes (app lifecycle restrictions)
//! - Memory budget: 50MB (typical extension limit)
//!
//! ### Android
//! - Limited shell access (read-only commands only)
//! - Scoped storage (Android 10+ restrictions)
//! - No long-running processes (battery optimization)
//! - Memory budget: 100MB (typical app constraint)

use crate::runtime::traits::RuntimeAdapter;
use std::path::{Path, PathBuf};

/// Mobile platform variants
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MobilePlatform {
    /// Apple iOS/iPadOS
    IOS,
    /// Google Android
    Android,
}

/// Runtime adapter for mobile platforms with restricted capabilities
///
/// Mobile platforms impose strict sandboxing and resource constraints:
/// - No arbitrary shell execution (iOS) or heavily restricted (Android)
/// - Memory budgets enforced by platform
/// - No long-running background processes
/// - Filesystem access limited to app sandbox
pub struct MobileRuntime {
    platform: MobilePlatform,
    memory_limit_bytes: u64,
    storage_path: PathBuf,
}

impl MobileRuntime {
    /// Create a new mobile runtime for the specified platform
    ///
    /// # Arguments
    /// * `platform` - Target mobile platform (iOS or Android)
    ///
    /// # Examples
    /// ```no_run
    /// use zeroclaw::runtime::mobile::{MobileRuntime, MobilePlatform};
    ///
    /// let ios_runtime = MobileRuntime::new(MobilePlatform::IOS);
    /// assert_eq!(ios_runtime.name(), "mobile-ios");
    /// assert!(!ios_runtime.has_shell_access());
    /// ```
    pub fn new(platform: MobilePlatform) -> Self {
        let memory_limit_bytes = match platform {
            MobilePlatform::IOS => 50 * 1024 * 1024, // 50MB for iOS extensions
            MobilePlatform::Android => 100 * 1024 * 1024, // 100MB typical Android app
        };

        // Default storage path for mobile platforms
        // In production, this would be set by the platform-specific code
        let storage_path = match platform {
            MobilePlatform::IOS => PathBuf::from("/app/Documents/zeroclaw"),
            MobilePlatform::Android => PathBuf::from("/data/data/com.zeroclaw/files"),
        };

        Self {
            platform,
            memory_limit_bytes,
            storage_path,
        }
    }

    /// Create a mobile runtime with custom memory limit
    ///
    /// # Arguments
    /// * `platform` - Target mobile platform
    /// * `memory_limit_mb` - Memory budget in megabytes
    ///
    /// # Examples
    /// ```no_run
    /// use zeroclaw::runtime::mobile::{MobileRuntime, MobilePlatform};
    ///
    /// // Create Android runtime with 200MB limit
    /// let runtime = MobileRuntime::with_memory_limit(MobilePlatform::Android, 200);
    /// assert_eq!(runtime.memory_budget(), 200 * 1024 * 1024);
    /// ```
    pub fn with_memory_limit(platform: MobilePlatform, memory_limit_mb: u64) -> Self {
        let storage_path = match platform {
            MobilePlatform::IOS => PathBuf::from("/app/Documents/zeroclaw"),
            MobilePlatform::Android => PathBuf::from("/data/data/com.zeroclaw/files"),
        };

        Self {
            platform,
            memory_limit_bytes: memory_limit_mb * 1024 * 1024,
            storage_path,
        }
    }

    /// Get the mobile platform for this runtime
    pub fn platform(&self) -> MobilePlatform {
        self.platform
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
            // iOS third-party apps cannot access /bin/sh or spawn processes
            MobilePlatform::IOS => false,

            // Android apps can access /system/bin/sh but with heavy restrictions
            // Only safe read-only commands should be allowed
            MobilePlatform::Android => true,
        }
    }

    fn has_filesystem_access(&self) -> bool {
        // Both platforms have scoped filesystem access:
        // - iOS: App sandbox directory
        // - Android: Scoped storage (Android 10+)
        true
    }

    fn storage_path(&self) -> PathBuf {
        self.storage_path.clone()
    }

    fn supports_long_running(&self) -> bool {
        // Mobile platforms cannot run indefinitely:
        // - iOS: Apps suspended after 30s in background
        // - Android: Battery optimization kills background processes
        // - Both: Designed for short-lived tasks
        false
    }

    fn memory_budget(&self) -> u64 {
        // Return configured memory budget in bytes
        // 0 would mean unlimited, but mobile always has constraints
        self.memory_limit_bytes
    }

    fn build_shell_command(
        &self,
        command: &str,
        _workspace_dir: &Path,
    ) -> anyhow::Result<tokio::process::Command> {
        match self.platform {
            MobilePlatform::IOS => {
                anyhow::bail!("Shell execution not supported on iOS")
            }
            MobilePlatform::Android => {
                // On Android, we can execute limited shell commands
                // Only safe read-only commands are allowed
                let base_cmd = command.split_whitespace().next().unwrap_or("");

                // Allowlist of safe Android commands
                let allowed = [
                    "ls", "cat", "grep", "find", "echo", "pwd", "wc", "head", "tail",
                ];

                if !allowed.contains(&base_cmd) {
                    anyhow::bail!(
                        "Command '{}' not allowed on Android mobile runtime. Allowed commands: {}",
                        base_cmd,
                        allowed.join(", ")
                    );
                }

                // Build command using Android's shell
                let mut cmd = tokio::process::Command::new("/system/bin/sh");
                cmd.arg("-c");
                cmd.arg(command);
                Ok(cmd)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ios_runtime_has_correct_constraints() {
        let runtime = MobileRuntime::new(MobilePlatform::IOS);

        assert_eq!(runtime.name(), "mobile-ios");
        assert!(
            !runtime.has_shell_access(),
            "iOS should not have shell access"
        );
        assert!(
            runtime.has_filesystem_access(),
            "iOS should have scoped filesystem"
        );
        assert!(
            !runtime.supports_long_running(),
            "iOS cannot run long tasks"
        );
        assert_eq!(
            runtime.memory_budget(),
            50 * 1024 * 1024,
            "iOS has 50MB budget"
        );
    }

    #[test]
    fn android_runtime_has_correct_constraints() {
        let runtime = MobileRuntime::new(MobilePlatform::Android);

        assert_eq!(runtime.name(), "mobile-android");
        assert!(
            runtime.has_shell_access(),
            "Android has limited shell access"
        );
        assert!(
            runtime.has_filesystem_access(),
            "Android has scoped storage"
        );
        assert!(
            !runtime.supports_long_running(),
            "Android cannot run long tasks"
        );
        assert_eq!(
            runtime.memory_budget(),
            100 * 1024 * 1024,
            "Android has 100MB budget"
        );
    }

    #[test]
    fn custom_memory_limit_works() {
        let runtime = MobileRuntime::with_memory_limit(MobilePlatform::Android, 200);

        assert_eq!(runtime.memory_budget(), 200 * 1024 * 1024);
        assert_eq!(runtime.platform(), MobilePlatform::Android);
    }

    #[test]
    fn platform_equality_works() {
        let ios1 = MobileRuntime::new(MobilePlatform::IOS);
        let ios2 = MobileRuntime::new(MobilePlatform::IOS);
        let android = MobileRuntime::new(MobilePlatform::Android);

        assert_eq!(ios1.platform(), ios2.platform());
        assert_ne!(ios1.platform(), android.platform());
    }
}

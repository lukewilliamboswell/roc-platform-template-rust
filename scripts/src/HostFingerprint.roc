## Files that can affect the native host, independent of product Roc sources.
HostFingerprint := [].{
	includes = |path|
		path.starts_with("src/") or path.starts_with(".cargo/") or ["Cargo.toml", "Cargo.lock", "Blueprint.roc", "Blueprint.lock", "scripts/build_platform.roc", "scripts/host_fingerprint.roc", "scripts/src/HostFingerprint.roc", "scripts/src/Targets.roc", "scripts/src/Script.roc", "runtime/link-inputs.lock.json"].contains(path)
}

expect HostFingerprint.includes("src/roc_platform_abi.rs")
expect HostFingerprint.includes("src/nested/host.rs")
expect HostFingerprint.includes(".cargo/config.toml")
expect HostFingerprint.includes("Blueprint.lock")
expect HostFingerprint.includes("scripts/build_platform.roc")
expect !HostFingerprint.includes("platform/main.roc")
expect !HostFingerprint.includes("examples/hello_world/main.roc")
expect !HostFingerprint.includes("docs/index.adoc")

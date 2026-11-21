#!/usr/bin/env bash
set -euo pipefail

# The native runner only needs the compiler and the shared archive verifier.
case "${RUNNER_OS:-$(uname -s)}:${RUNNER_ARCH:-$(uname -m)}" in
  Linux:X64|Linux:x86_64)
    system=x86_64-linux
    digest=105c7e9f3d7e3c516bc96741f4facd9cd7e4a84a01540ca865c5b17b55e0c316
    ;;
  Linux:ARM64|Linux:aarch64)
    system=aarch64-linux
    digest=2eecc1ef237e6d7d3ba598369664d1ffd7a08ee7b139a6dce82de164413f7843
    ;;
  macOS:ARM64|Darwin:arm64)
    system=aarch64-darwin
    digest=a02dba54f02ecf0c21f199f40fd553cbaff6fe88bc531d20f6f5f1b89baca00e
    ;;
  macOS:X64|Darwin:x86_64)
    system=x86_64-darwin
    digest=617634b73a0715529e08e42c8691f30cf298f23bda67d1fc4be91781e9550092
    ;;
  *)
    echo "No reviewed release-package executable for this runner" >&2
    exit 1
    ;;
esac

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
utility="$temp_dir/release-package"
curl --fail --silent --show-error --location --retry 3 \
  "https://github.com/lukewilliamboswell/roc-automation/releases/download/tools-0.12.0/release-package-$system" \
  --output "$utility"
printf '%s  %s\n' "$digest" "$utility" | shasum -a 256 -c -
chmod +x "$utility"
"$utility" test-archive

#!/bin/bash
set -e

# Detect the current platform
ARCH=$(uname -m)
OS=$(uname -s)

if [ "$OS" = "Darwin" ]; then
    if [ "$ARCH" = "arm64" ]; then
        TARGET="arm64mac"
    else
        TARGET="x64mac"
    fi
elif [ "$OS" = "Linux" ]; then
    if [ "$ARCH" = "aarch64" ]; then
        TARGET="arm64musl"
    else
        TARGET="x64musl"
    fi
else
    echo "Unsupported OS: $OS"
    exit 1
fi

echo "Building for target: $TARGET"

# Build host library
cargo build --release --lib

# Create target directory if it doesn't exist
mkdir -p platform/targets/$TARGET

# Copy to platform targets directory
cp target/release/libhost.a platform/targets/$TARGET/

echo "Build complete! Library copied to platform/targets/$TARGET/libhost.a"

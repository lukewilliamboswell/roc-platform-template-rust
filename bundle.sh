# ADD TARGETS
rustup target add aarch64-apple-darwin
rustup target add x86_64-unknown-linux-gnu
rustup target add x86_64-apple-darwin
rustup target add aarch64-unknown-linux-gnu

# LEGACY LINKER ARTEFACTS
cargo build --release --lib --target=aarch64-apple-darwin
cp target/aarch64-apple-darwin/release/libhost.a platform/macos-arm64.a

cargo build --release --lib --target=aarch64-unknown-linux-gnu
cp target/aarch64-unknown-linux-gnu/release/libhost.a platform/linux-arm64.a

cargo build --release --lib --target=x86_64-unknown-linux-gnu
cp target/x86_64-unknown-linux-gnu/release/libhost.a platform/linux-x64.a

cargo build --release --lib --target=x86_64-apple-darwin
cp target/aarch64-apple-darwin/release/libhost.a platform/macos-x64.a

# SURGICAL LINKER ARTEFACTS
# TODO -- the surgical prebuilt hosts will need to be build on the native machines I think

# BUNDLE INTO PACKAGE
roc build --bundle .tar.br platform/main.roc

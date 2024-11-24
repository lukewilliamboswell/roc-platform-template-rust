{
  description = "Roc Rust Platform Template";

  inputs = {
    roc.url = "github:roc-lang/roc";

    nixpkgs.follows = "roc/nixpkgs";

    # rust from nixpkgs has some libc problems, this is patched in the rust-overlay
    rust-overlay = {
        url = "github:oxalica/rust-overlay";
        inputs.nixpkgs.follows = "nixpkgs";
    };

    # to easily make configs for multiple architectures
    flake-utils.url = "github:numtide/flake-utils";

  };

  outputs = { self, roc, nixpkgs, rust-overlay, flake-utils  }:
    let supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
    in flake-utils.lib.eachSystem supportedSystems (system:
        let
            overlays = [ (import rust-overlay) ];
            pkgs = import nixpkgs { inherit system overlays; };

            rust = pkgs.rust-bin.fromRustupToolchainFile "${toString ./rust-toolchain.toml}";

            rocPkgs = roc.packages.${system};

            linuxInputs = with pkgs;
              lib.optionals stdenv.isLinux [
                valgrind
              ];

            darwinInputs = with pkgs;
              lib.optionals stdenv.isDarwin
              (with pkgs.darwin.apple_sdk.frameworks; [
                Security
              ]);

            sharedInputs = (with pkgs; [
              rust
              expect
              rocPkgs.cli
            ]);

        in {

            devShell = pkgs.mkShell {

                buildInputs = sharedInputs ++ darwinInputs ++ linuxInputs;

                shellHook = ''
                    if [ "$(uname)" = "Darwin" ]; then
                        export SDKROOT=$(xcrun --show-sdk-path)
                        export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath darwinInputs}:$LD_LIBRARY_PATH
                    fi

                    if [ "$(uname)" = "Linux" ]; then
                        export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath linuxInputs}:$LD_LIBRARY_PATH
                    fi
                '';
            };

            formatter = pkgs.nixpkgs-fmt;

        });
}

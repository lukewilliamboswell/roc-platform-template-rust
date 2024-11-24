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

            rocPkgs = roc.packages.${system};

            rust = pkgs.rust-bin.fromRustupToolchainFile "${toString ./rust-toolchain.toml}";

            linuxDeps = if pkgs.stdenv.isLinux then [] else [];
            macosDeps = if pkgs.stdenv.isDarwin then [] else [];

        in {

            devShell = pkgs.mkShell {

                packages = [
                        rocPkgs.cli
                        rust
                    ] ++ linuxDeps ++ macosDeps;

                shellHook = ''
                    if [ "$(uname)" = "Darwin" ]; then
                        export SDKROOT=$(xcrun --show-sdk-path)
                        export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath macosDeps}:$LD_LIBRARY_PATH
                    fi

                    if [ "$(uname)" = "Linux" ]; then
                        export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath linuxDeps}:$LD_LIBRARY_PATH
                    fi
                '';
            };

            formatter = pkgs.nixpkgs-fmt;

        });
}

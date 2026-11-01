{
  description = "hyperion";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, rust-overlay }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems
        (system: f (import nixpkgs {
          inherit system;
          overlays = [rust-overlay.overlays.default];
        }));
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          llvm = pkgs.llvmPackages;
          rust = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              llvm.clang-unwrapped
              llvm.lld
              llvm.llvm
              pkgs.just
              rust
            ];
            CLANG = "${llvm.clang-unwrapped}/bin/clang";
            RUSTC = "${rust}/bin/rustc";
            RUSTDOC = "${rust}/bin/rustdoc";
          };
        }
      );
    };
}

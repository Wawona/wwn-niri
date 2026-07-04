{
  description = "wwn-niri: Wawona's niri (scrollable-tiling, smithay-based) port for Apple platforms and Android. SKELETON — full port is downstream.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    wwn-toolchain.url = "github:Wawona/wwn-toolchain";
    wwn-toolchain.inputs.nixpkgs.follows = "nixpkgs";
    wwn-toolchain.inputs.rust-overlay.follows = "rust-overlay";
  };

  outputs = { self, nixpkgs, rust-overlay, wwn-toolchain, ... }:
    let
      darwinSystems = [ "x86_64-darwin" "aarch64-darwin" ];
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
      allSystems = darwinSystems ++ linuxSystems;
      forAll = nixpkgs.lib.genAttrs allSystems;
      inherit (wwn-toolchain.lib) withPlatformVariants;

      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
        config = { allowUnfree = true; allowUnsupportedSystem = true; android_sdk.accept_license = true; };
      };

      dir = ./dependencies/niri;
    in
    {
      # Registry fragment merged into Wawona's client registry. Points at
      # per-platform port definitions (currently stubs that fail the build with a
      # clear message until the port lands).
      registryFragment = {
        niri = withPlatformVariants {
          android = dir + "/stub.nix";
          wearos = dir + "/stub.nix";
          ios = dir + "/stub.nix";
          tvos = dir + "/stub.nix";
          ipados = dir + "/stub.nix";
          visionos = dir + "/stub.nix";
          watchos = dir + "/stub.nix";
          macos = dir + "/stub.nix";
        };
      };

      formatter = forAll (system: (pkgsFor system).nixfmt-rfc-style);
    };
}

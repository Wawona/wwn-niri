{
  description = "wwn-niri: Wawona's niri (scrollable-tiling, smithay-based) port for Apple platforms and Android. niri runs nested — a Wayland client of the Wawona compositor — via the Wawona nested backend patch.";

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
      inherit (wwn-toolchain.lib) withPlatformVariants baseRegistry mkToolchains;

      pkgsFor = system: import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
        config = { allowUnfree = true; allowUnsupportedSystem = true; android_sdk.accept_license = true; };
      };

      dir = ./dependencies/niri;
    in
    {
      # Registry fragment merged into Wawona's client registry. Real
      # per-platform derivations of the Wawona-patched niri (v26.04 + nested
      # Wayland-client backend); watchOS is excluded from the port (stub).
      registryFragment = {
        niri = withPlatformVariants {
          android = dir + "/android.nix";
          wearos = dir + "/android.nix";
          ios = dir + "/ios.nix";
          tvos = dir + "/ios.nix";
          ipados = dir + "/ios.nix";
          visionos = dir + "/ios.nix";
          watchos = dir + "/stub.nix";
          macos = dir + "/macos.nix";
        };
      };

      # Staged patched source (upstream v26.04 + Wawona nested-backend patch),
      # for consumers that need the source rather than a built artifact.
      lib = {
        niriSrc = pkgs: import (dir + "/src.nix") { inherit pkgs; };
        srcRecipe = dir + "/src.nix";
      };

      packages = forAll (system:
        let
          pkgs = pkgsFor system;
          tc = mkToolchains { inherit pkgs; registry = baseRegistry // self.registryFragment; };
          isDarwin = builtins.elem system darwinSystems;
        in
        # Android/wearOS need an androidSDK wired through mkToolchains; the
        # Wawona flake builds those (packages.*.niri-android) with its SDK.
        (if isDarwin then {
          niri-macos = tc.buildForMacOS "niri" { };
          niri-ios = tc.buildForIOS "niri" { };
          niri-ipados = tc.buildForIPadOS "niri" { };
          niri-tvos = tc.buildForTVOS "niri" { };
          niri-visionos = tc.buildForVisionOS "niri" { };
        } else { }));

      formatter = forAll (system: (pkgsFor system).nixfmt-rfc-style);
    };
}

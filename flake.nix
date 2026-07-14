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

      niriDir = ./dependencies/niri;
      fuzzelDir = ./dependencies/fuzzel;
    in
    {
      # Registry fragment merged into Wawona's client registry. Real
      # per-platform derivations of the Wawona-patched niri (v26.04 + nested
      # Wayland-client backend); watchOS is excluded from the port (stub).
      # fuzzel ships alongside niri as the default Mod+D launcher.
      registryFragment = {
        niri = withPlatformVariants {
          android = niriDir + "/android.nix";
          wearos = niriDir + "/android.nix";
          ios = niriDir + "/ios.nix";
          tvos = niriDir + "/ios.nix";
          ipados = niriDir + "/ios.nix";
          visionos = niriDir + "/ios.nix";
          watchos = niriDir + "/stub.nix";
          macos = niriDir + "/macos.nix";
        };
        fuzzel = withPlatformVariants {
          android = fuzzelDir + "/android.nix";
          wearos = fuzzelDir + "/stub.nix";
          ios = fuzzelDir + "/ios.nix";
          tvos = fuzzelDir + "/ios.nix";
          ipados = fuzzelDir + "/ios.nix";
          visionos = fuzzelDir + "/ios.nix";
          watchos = fuzzelDir + "/stub.nix";
          macos = fuzzelDir + "/macos.nix";
        };
      };

      # Staged patched source (upstream v26.04 + Wawona nested-backend patch),
      # for consumers that need the source rather than a built artifact.
      lib = {
        niriSrc = pkgs: import (niriDir + "/src.nix") { inherit pkgs; };
        srcRecipe = niriDir + "/src.nix";
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
          fuzzel-macos = tc.buildForMacOS "fuzzel" { };
          niri-ios = tc.buildForIOS "niri" { };
          fuzzel-ios = tc.buildForIOS "fuzzel" { };
          niri-ipados = tc.buildForIPadOS "niri" { };
          fuzzel-ipados = tc.buildForIPadOS "fuzzel" { };
          niri-tvos = tc.buildForTVOS "niri" { };
          fuzzel-tvos = tc.buildForTVOS "fuzzel" { };
          niri-visionos = tc.buildForVisionOS "niri" { };
          fuzzel-visionos = tc.buildForVisionOS "fuzzel" { };
        } else { }));

      formatter = forAll (system: (pkgsFor system).nixfmt-rfc-style);
    };
}

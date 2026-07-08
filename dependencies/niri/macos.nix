# niri for macOS — builds the Wawona-patched niri (v26.04 + nested backend)
# as a host binary plus a static library.
#
# Runtime model: Wawona macOS runs its compositor and launches niri nested
# (WAYLAND_DISPLAY -> Wawona's socket, NIRI_BACKEND=nested). niri renders with
# GLES through EGL_KHR_platform_wayland served by the wwn-iland/ANGLE EGL and
# hosts its own scrollable-tiling clients on its child Wayland socket.
#
# macOS may fork/exec the bundled binary (Developer ID posture); bin/niri is
# the primary artifact, lib/libniri.a (niri_main C ABI) is also shipped for
# the in-process option.
{
  lib,
  pkgs,
  common,
  buildModule,
}:

let
  niriSrc = import ./src.nix { inherit pkgs; };
  libwayland = buildModule.buildForMacOS "libwayland" { };
  xkbcommon = buildModule.buildForMacOS "xkbcommon" { };
  cargoTarget = pkgs.stdenv.hostPlatform.rust.rustcTarget;
in
pkgs.rustPlatform.buildRustPackage {
  pname = "niri";
  version = "26.04-wawona";
  src = niriSrc;

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "smithay-0.7.0" = "sha256-TV/GTfSvgfVwIFUGoASU7xm38opIBLjLMf1HeNTW07U=";
    };
  };

  # dbus/systemd/xdp-gnome-screencast are desktop-Linux session integration;
  # the nested session under Wawona uses none of them.
  buildNoDefaultFeatures = true;
  buildFeatures = [ ];

  nativeBuildInputs = [ pkgs.pkg-config ];

  buildInputs = [
    libwayland
    xkbcommon
    pkgs.pango
    pkgs.cairo
    pkgs.glib
    pkgs.libiconv
  ];

  CARGO_BUILD_TARGET = cargoTarget;

  doCheck = false;

  preConfigure = ''
    MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
    if [ ! -d "$MACOS_SDK" ]; then
      MACOS_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    fi
    export SDKROOT="$MACOS_SDK"
    export PKG_CONFIG_PATH="${libwayland}/lib/pkgconfig:${xkbcommon}/lib/pkgconfig:$PKG_CONFIG_PATH"
    export RUSTFLAGS="-A warnings $RUSTFLAGS"

    # smithay's EGL loader dlopens the Linux soname; on macOS the bundled
    # wwn-iland/ANGLE EGL ships as libEGL.dylib (found via the executable's
    # rpath → Wawona.app/Contents/Frameworks). Patch the writable vendor copy
    # (importCargoLock checksums carry empty "files" maps, so edits are fine).
    for sm in "$NIX_BUILD_TOP"/cargo-vendor-dir/smithay-*/src/backend/egl/ffi.rs; do
      if [ -f "$sm" ]; then
        sed -i 's/Library::new("libEGL\.so\.1")/Library::new("libEGL.dylib")/' "$sm"
        echo "Patched smithay EGL library name for macOS"
      fi
    done
  '';

  postInstall = ''
    # Ship the static lib (niri_main C ABI) next to the binary for the
    # in-process hosting option.
    mkdir -p $out/lib
    for cand in \
      "target/${cargoTarget}/release/libniri.a" \
      "target/release/libniri.a"; do
      if [ -f "$cand" ]; then
        cp "$cand" $out/lib/libniri.a
        break
      fi
    done

    # Bundle the default config as read-only data (sandbox-safe: the app
    # points NIRI_CONFIG here or copies it into the container).
    mkdir -p $out/share/niri
    cp ${niriSrc}/resources/default-config.kdl $out/share/niri/default-config.kdl
  '';

  meta = {
    description = "niri (scrollable-tiling Wayland compositor), Wawona nested port for macOS";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.darwin;
    mainProgram = "niri";
  };
}

# niri for iOS/iPadOS (also reused for tvOS/visionOS via the registry) —
# builds the Wawona-patched niri as a *static library* (libniri.a) exposing
# the niri_main C ABI (src/c_api.rs).
#
# App Store posture: iOS cannot fork/exec a bundled compositor binary, so
# Wawona links libniri.a and starts niri on a dedicated thread in-process.
# niri connects to Wawona through WAYLAND_DISPLAY (nested backend), renders
# GLES via the wwn-iland/ANGLE EGL (EGL_EXT_platform_wayland), and serves its
# own scrollable-tiling clients on a child socket inside the sandbox-safe
# XDG_RUNTIME_DIR under the app container. No JIT, no dlopen of downloaded
# code; the config KDL ships as read-only bundle data.
{
  lib,
  pkgs,
  buildPackages,
  common,
  buildModule,
  simulator ? false,
  iosToolchain ? null,
  xcodeUtils ? iosToolchain,
}:

let
  niriSrc = import ./src.nix { inherit pkgs; };
  libwayland = buildModule.buildForIOS "libwayland" { inherit simulator; };
  xkbcommon = buildModule.buildForIOS "xkbcommon" { inherit simulator; };
  cairo = buildModule.buildForIOS "cairo" { inherit simulator; };
  pango = buildModule.buildForIOS "pango" { inherit simulator; };
  glib = buildModule.buildForIOS "glib" { inherit simulator; };
  harfbuzz = buildModule.buildForIOS "harfbuzz" { inherit simulator; };
  fontconfig = buildModule.buildForIOS "fontconfig" { inherit simulator; };
  freetype = buildModule.buildForIOS "freetype" { inherit simulator; };
  pixman = buildModule.buildForIOS "pixman" { inherit simulator; };
  libpng = buildModule.buildForIOS "libpng" { inherit simulator; };
  fribidi = buildModule.buildForIOS "fribidi" { inherit simulator; };
  # Transitive Requires of glib-2.0.pc / gobject-2.0.pc / fontconfig.pc.
  pcre2 = buildModule.buildForIOS "pcre2" { inherit simulator; };
  libffi = buildModule.buildForIOS "libffi" { inherit simulator; };
  expat = buildModule.buildForIOS "expat" { inherit simulator; };
  # cairo-sys-rs (via pangocairo) links the cairo-gobject glue, which the
  # minimal cairo recipe leaves out (-Dglib=disabled).
  cairoGobject = buildModule.buildForIOS "cairo-gobject" { inherit simulator; };

  pcDeps = [
    libwayland xkbcommon cairo pango glib harfbuzz fontconfig freetype
    pixman libpng fribidi pcre2 libffi expat cairoGobject
  ];
  pcPath = lib.concatMapStringsSep ":" (d: "${d}/lib/pkgconfig") pcDeps;

  rustTarget = if simulator then "aarch64-apple-ios-sim" else "aarch64-apple-ios";
  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
    targets = [ rustTarget ];
  };
  rustPlatform = pkgs.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
in
rustPlatform.buildRustPackage {
  pname = "niri";
  version = "26.04-wawona";
  src = niriSrc;
  __noChroot = true;

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "smithay-0.7.0" = "sha256-TV/GTfSvgfVwIFUGoASU7xm38opIBLjLMf1HeNTW07U=";
    };
  };

  nativeBuildInputs = [ pkgs.pkg-config ];
  buildInputs = pcDeps;

  doCheck = false;
  dontFixup = true;

  preConfigure = ''
    ${xcodeUtils.mkIOSBuildEnv { inherit simulator; }}
    export IOS_SDK="$SDKROOT"

    # Isolate from Nix wrapper flags (they target the host).
    export NIX_CFLAGS_COMPILE=""
    export NIX_CXXFLAGS_COMPILE=""
    export NIX_LDFLAGS=""

    export IPHONEOS_DEPLOYMENT_TARGET="${xcodeUtils.deploymentTarget}"
    export CARGO_BUILD_TARGET="${rustTarget}"

    # Target-side C toolchain (cc-rs) — Xcode clang against the iOS SDK.
    target_underscore=$(echo "${rustTarget}" | tr '-' '_')
    export "CC_''${target_underscore}"="$XCODE_CLANG"
    export "CXX_''${target_underscore}"="$XCODE_CLANGXX"
    export "CFLAGS_''${target_underscore}"="-target $APPLE_LINKER_TARGET -isysroot $IOS_SDK $APPLE_DEPLOYMENT_FLAG"
    export "AR_''${target_underscore}"="ar"
    export "CARGO_TARGET_''${target_underscore^^}_LINKER"="$XCODE_CLANG"

    # Append — cargoSetupPostUnpackHook already wrote the vendored-sources
    # replacement into .cargo/config.toml; do not clobber it.
    mkdir -p .cargo
    cat >> .cargo/config.toml <<CARGO_EOF
    [target.${rustTarget}]
    linker = "$XCODE_CLANG"
    rustflags = [
      "-C", "link-arg=-arch", "-C", "link-arg=$IOS_ARCH",
      "-C", "link-arg=-isysroot", "-C", "link-arg=$IOS_SDK",
      "-C", "link-arg=$APPLE_DEPLOYMENT_FLAG"
    ]
    CARGO_EOF

    export PKG_CONFIG_PATH="${pcPath}:$PKG_CONFIG_PATH"
    export PKG_CONFIG_ALLOW_CROSS=1
    export RUSTFLAGS="-A warnings $RUSTFLAGS"

    # wayland-backend's pure-Rust impl (mod rs, always compiled) gates its
    # kqueue/socket paths on target_os = "macos" only; extend the cfgs to the
    # Apple mobile OSes — the same rewrite Wawona's own rust backend applies
    # (dependencies/wawona/rust-backend-c2n.nix). cargoSetupPostUnpackHook
    # already copied the vendor dir writable into $NIX_BUILD_TOP as
    # cargo-vendor-dir (and pointed vendored-sources at it); importCargoLock's
    # .cargo-checksum.json files carry empty "files" maps, so in-place source
    # edits do not trip cargo's vendor verification.
    vendor_dir="$NIX_BUILD_TOP/cargo-vendor-dir"
    wb_found=0
    for wb in "$vendor_dir"/wayland-backend-*/src "$vendor_dir"/calloop-*/src; do
      if [ -d "$wb" ]; then
        find "$wb" -name '*.rs' -exec sed -i \
          's/target_os[[:space:]]*=[[:space:]]*"macos"/any(target_os = "macos", target_os = "ios", target_os = "tvos", target_os = "visionos", target_os = "watchos")/g' {} +
        wb_found=1
      fi
    done
    if [ "$wb_found" != 1 ]; then
      echo "ERROR: vendored wayland-backend/calloop not found under $vendor_dir" >&2
      exit 1
    fi
    echo "Patched vendored wayland-backend + calloop cfgs for Apple mobile"

    # smithay's EGL loader dlopens the Linux soname; on Apple mobile the
    # ANGLE EGL ships as an embedded libEGL.dylib (app Frameworks dir).
    # DYLD_LIBRARY_PATH is stripped on iOS, so use @executable_path.
    for sm in "$vendor_dir"/smithay-*/src/backend/egl/ffi.rs; do
      if [ -f "$sm" ]; then
        sed -i 's/Library::new("libEGL\.so\.1")/Library::new("@executable_path\/Frameworks\/libEGL.dylib")/' "$sm"
        echo "Patched smithay EGL library name for Apple mobile"
      fi
    done

    # ANGLE on Apple mobile lacks GL_OES_EGL_image_external, but smithay
    # always compiles an EXTERNAL texture shader variant at GLES init. Alias it
    # to the normal shader so nested niri can boot (wl_shm presentation path).
    for sh in "$vendor_dir"/smithay-*/src/backend/renderer/gles/shaders/mod.rs; do
      if [ -f "$sh" ]; then
        sed -i 's/create_variant(&\[shaders::EXTERNAL\])?/create_variant(\&[])?/' "$sh"
        echo "Patched smithay GLES EXTERNAL shader for Apple mobile ANGLE"
      fi
    done

    # Host-side build scripts / proc-macros need the macOS SDK.
    export MACOS_SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
    export HOST_CC="/usr/bin/clang"
    export HOST_CFLAGS="-isysroot $MACOS_SDK"
    export HOST_LDFLAGS="-isysroot $MACOS_SDK"
    export SDKROOT="$MACOS_SDK"
  '';

  # Static library only: iOS has no exec, the binary target is pointless.
  # Explicit buildPhase because the stock cargoBuildHook pins --target to the
  # Nix host platform (aarch64-apple-darwin), not our iOS cross target.
  buildPhase = ''
    runHook preBuild
    echo "Building niri static library for ${rustTarget}..."
    # niri's release profile uses thin LTO, which leaves LLVM bitcode (from
    # Rust's LLVM) in the staticlib members; Xcode's older libLTO cannot read
    # it at app link time. Force plain machine-code objects instead.
    export CARGO_PROFILE_RELEASE_LTO=false
    cargo build --lib --target ${rustTarget} --release --offline --no-default-features
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib $out/share/niri
    if [ ! -f "target/${rustTarget}/release/libniri.a" ]; then
      echo "ERROR: libniri.a not found for ${rustTarget}" >&2
      find target -name "libniri.a" 2>/dev/null || true
      exit 1
    fi
    cp "target/${rustTarget}/release/libniri.a" $out/lib/libniri.a
    cp ${niriSrc}/resources/default-config.kdl $out/share/niri/default-config.kdl
    # Desktop autostart helpers (waybar, etc.) are not bundled on Apple mobile.
    sed -i 's/^spawn-at-startup "waybar"/\/-spawn-at-startup "waybar"/' \
      $out/share/niri/default-config.kdl
    # Nested Mod=Alt; also bind Super+D (⌘ on hardware keyboards) for fuzzel.
    sed -i '/Mod+D hotkey-overlay-title="Run an Application: fuzzel"/a\
    Super+D hotkey-overlay-title="Run an Application: fuzzel" { spawn "fuzzel"; }' \
      $out/share/niri/default-config.kdl
    runHook postInstall
  '';

  meta = {
    description = "niri (scrollable-tiling Wayland compositor), Wawona nested in-process port for Apple mobile targets";
    license = lib.licenses.gpl3Plus;
  };
}

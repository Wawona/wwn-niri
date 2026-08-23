# Staged niri source for the Wawona port: upstream v26.04 plus the Wawona
# nested-backend patch (niri as a Wayland client of the Wawona compositor).
#
# The patch:
# - adds src/backend/nested/ (Wayland-client backend: xdg_toplevel output,
#   GLES over EGL_KHR_platform_wayland, host-seat input translation),
# - gates the Linux-only stacks (DRM/KMS tty backend, winit backend, libinput,
#   udev/libseat, pipewire, drm-lease, gamma) behind cfg(target_os = "linux"),
# - adds the niri_main C ABI entry (src/c_api.rs) + staticlib crate-type so
#   mobile targets can host niri in-process (App Store posture),
# - keeps desktop-Linux builds byte-for-byte functional (all gates are
#   cfg(target_os = "linux") supersets of upstream behavior).
{ pkgs }:

pkgs.applyPatches {
  name = "niri-src-wawona-v26.04";
  src = pkgs.fetchFromGitHub {
    owner = "YaLTeR";
    repo = "niri";
    rev = "v26.04";
    hash = "sha256-ehSMsSpE+0k8r+2Vseu8kangsYxToZv3vinynsDp9zs=";
  };
  patches = [
    ./wawona-nested-port.patch
    ./wawona-spawn-mobile.patch
    # Keep panics inside niri_main from aborting the host Wawona process
    # (extern "C" + panic_cannot_unwind → SIGABRT on iOS Simulator).
    ./wawona-niri-main-catch-unwind.patch
    # iOS/tvOS/watchOS/visionOS/Android: ANGLE has no wl_egl_window. Nested
    # niri uses iland's Wayland-EGL on every GPU target; watchOS (blocked)
    # and tvOS (GPU still planned) stay on offscreen GLES + wl_shm.
    ./wawona-nested-apple-shm.patch
    # ANGLE on Apple mobile often rejects 10-bit GLES 3.0 configs. Fall back
    # to 8-bit GLES 3.0 then GLES 2.0, and keep the smithay error in the
    # anyhow chain so niri_main can print it.
    ./wawona-nested-egl-context.patch
    # macOS Mode B: compile the DRM/KMS tty backend (NIRI_BACKEND=tty) against
    # iland userspace KMS. iOS/Android stay nested-only. winit stays Linux-only.
    ./wawona-macos-drm-tty.patch
  ];
}

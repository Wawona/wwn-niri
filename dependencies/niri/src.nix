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
  patches = [ ./wawona-nested-port.patch ];
}

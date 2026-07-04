# wwn-niri

Wawona's port of **niri** — a scrollable-tiling, smithay-based Wayland
compositor — to run under Wawona on the Apple ecosystem and Android, App Store
compliant. Aligns with `wwn-toolchain` like every other `wwn-*` port.

> **Status: SKELETON.** This repo currently provides only the flake +
> `registryFragment` skeleton and this port plan. The build stubs
> (`dependencies/niri/stub.nix`) intentionally fail with a clear message. The
> full cross-compiled port is downstream.

## Delivery model

niri is itself a Wayland compositor, so under Wawona it runs **nested** (as a
client of the Wawona compositor) rather than replacing it. See
[Wawona docs: wlroots compat](https://github.com/Wawona/Wawona/blob/main/docs/2026-wlroots-compat.md)
and the platform delivery matrix.

## Port plan

1. **Toolchain**: consume `wwn-toolchain` cross toolchains (`buildForIOS`,
   `buildForMacOS`, `buildForAndroid`).
2. **Compliance deltas**: no JIT, no `fork+exec` of external binaries, sandbox-
   safe runtime dirs (`XDG_RUNTIME_DIR` under app container), bundled config.
3. **Backends**: niri targets a nested Wayland backend (client of Wawona); DRM/
   libinput backends are not used on Apple/Android.
4. **Wire up**: replace `dependencies/niri/stub.nix` with per-platform
   derivations; expose `niri-{ios,macos,android}` packages; register in Wawona.
5. **Catalog**: `wwn-apt` already lists `niri` with `status: planned`; flip to
   `approved` once the port passes CI + App Store review.

## Convention

Follows [wwn-* porting convention](https://github.com/Wawona/Wawona/blob/main/docs/2026-wwn-porting-convention.md).

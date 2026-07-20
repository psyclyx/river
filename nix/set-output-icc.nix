{
  lib,
  stdenv,
  pkg-config,
  wayland,
  wayland-scanner,
  wayland-protocols,
  libevdev,
  libinput,
  libxkbcommon,
  pixman,
  libGL,
  udev,
  wlroots_0_20,
  zig_0_16,
  # The zig package cache (zon2nix output), supplied by the caller so it can be
  # shared with river's own derivation rather than duplicating the lock.
  deps,
}:
# Client for the private psyclyx_color_management_v1 protocol. It lives in
# river's tree (contrib/set-output-icc.zig) and shares the scanned protocol
# bindings with the compositor — no duplicated XML. river's build.zig exposes
# it under its own `set-output-icc` step; this derivation builds only that
# step, producing just the client without the compositor.
stdenv.mkDerivation {
  pname = "set-output-icc";
  version = "0.1.0";

  src = lib.cleanSource ../.;

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
    zig_0_16
  ];

  # build.zig's build() evaluates the whole graph (including the compositor's
  # module and translate-c declarations, which resolve pkg-config eagerly), so
  # the compositor's build inputs must be present even though only the client is
  # compiled. These are build-time only and do not enter the client's runtime
  # closure (it links just wayland-client).
  buildInputs = [
    wayland
    wayland-protocols
    libevdev
    libinput
    libxkbcommon
    pixman
    libGL
    udev
    wlroots_0_20
  ];

  zigBuildFlags = [
    "--system"
    "${deps}"
  ];

  # Skip the default zig build step (the compositor) and run only our step,
  # installing straight into $out.
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    zig build set-output-icc \
      -j"$NIX_BUILD_CORES" \
      $zigBuildFlags \
      -Dcpu=baseline --release=safe \
      --prefix "$out" \
      --verbose
    runHook postInstall
  '';

  meta = {
    description = "Assign a display ICC profile to a river output (psyclyx_color_management_v1)";
    homepage = "https://github.com/psyclyx/river";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "set-output-icc";
  };
}

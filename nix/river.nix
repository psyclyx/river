{
  lib,
  stdenv,
  callPackage,
  libGL,
  libx11,
  libevdev,
  libinput,
  libxkbcommon,
  pixman,
  pkg-config,
  scdoc,
  udev,
  wayland,
  wayland-protocols,
  wayland-scanner,
  xwayland,
  zig_0_16,
  wlroots_0_20,
  withManpages ? true,
  xwaylandSupport ? true,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "river";
  version = "0.5.0-dev";

  # Only the files the zig build consumes: the build graph (build.zig +
  # zon), the shared modules (common/), the compositor (river/), the
  # protocols (scanned and installed), the contrib files (the desktop
  # entry installed by postInstall and the companion client), and the
  # scdoc man page. Entry points (default.nix, overlay.nix, nix/), npins/,
  # and docs are not package inputs, so editing them must not churn the
  # source hash.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../build.zig
      ../build.zig.zon
      ../common
      ../contrib
      ../doc/river.1.scd
      ../protocol
      ../river
    ];
  };

  deps = callPackage ./build.zig.zon.nix {};

  nativeBuildInputs =
    [
      pkg-config
      wayland-scanner
      xwayland
      zig_0_16
    ]
    ++ lib.optional withManpages scdoc;

  buildInputs =
    [
      libGL
      libevdev
      libinput
      libxkbcommon
      pixman
      udev
      wayland
      wayland-protocols
      wlroots_0_20
    ]
    ++ lib.optional xwaylandSupport libx11;

  zigBuildFlags =
    [
      "--system"
      "${finalAttrs.deps}"
    ]
    ++ lib.optional withManpages "-Dman-pages"
    ++ lib.optional xwaylandSupport "-Dxwayland";

  postInstall = ''
    install contrib/river.desktop -Dt $out/share/wayland-sessions
  '';

  meta = {
    homepage = "https://codeberg.org/river/river";
    description = "Dynamic tiling Wayland compositor (0.5.0-dev)";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "river";
  };
})

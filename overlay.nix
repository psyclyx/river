final: prev: {
  # ICC black-point-compensation patch for river's per-output color management.
  wlroots_0_20 = prev.wlroots_0_20.overrideAttrs (old: {
    patches = prev.lib.unique ((old.patches or [ ]) ++ [ ./nix/patches/wlroots-icc-bpc.patch ]);
  });
  river = final.callPackage ./nix/river.nix { };
  set-output-icc = final.callPackage ./nix/set-output-icc.nix {
    deps = final.callPackage ./nix/build.zig.zon.nix { };
  };
}

let
  npins = import ./npins;
  overlay = import ./overlay.nix;
in
{ nixpkgs ? npins.nixpkgs, pkgs ? import nixpkgs { } }:
let finalPkgs = pkgs.extend overlay;
in {
  packages = { inherit (finalPkgs) river set-output-icc; };
  inherit overlay;
  default = finalPkgs.river;
}

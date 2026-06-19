# This file gets copied into the installation

let
  nixpkgs = "@nixpkgs@";
in

{
  evalConfig ? import "${nixpkgs}/nixos/lib/eval-config.nix",
}:

evalConfig {
  modules = [
    ./configuration.nix
    (import "${nixpkgs}/nixos/lib/testing/nixos-test-base.nix")
    {
      # Disable nix channels
      nix.channel.enable = false;
    }
  ];
}

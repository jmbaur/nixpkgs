{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkPackageOption
    ;

  cfg = config.networking.bpfilter;
in
{
  options.networking.bpfilter = {
    enable = mkEnableOption "bpfilter";

    package = mkPackageOption pkgs "bpfilter" { };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ ];
  };
}

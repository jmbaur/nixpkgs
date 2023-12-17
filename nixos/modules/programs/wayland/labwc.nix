{ config, pkgs, lib, ... }:

let
  cfg = config.programs.labwc;
in
{
  options.programs.labwc = with lib; {
    enable = mkEnableOption (lib.mdDoc ''TODO'');

    package = mkPackageOption pkgs "labwc" { };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [ cfg.package ];

      # https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1050913
      xdg.portal.config.wlroots.default = lib.mkDefault [ "wlr" "gtk" ];

      # To make a labwc session available if a display manager like SDDM is enabled:
      services.xserver.displayManager.sessionPackages = [ cfg.package ];
    }

    (import ./wayland-session.nix { inherit lib pkgs; })
  ]);

  meta.maintainers = with lib.maintainers; [ jmbaur ];
}

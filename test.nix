let
  pkgs = import ./. { };
in
(pkgs.nixos (
  { lib, ... }:
  {
    services.displayManager.autoLogin.user = "foo";
    services.xserver = {
      enable = true;
      displayManager.gdm.enable = true;
      desktopManager.gnome.enable = true;
    };

    boot = {
      initrd.systemd.enable = true;
      plymouth.enable = true;
    };

    users.users.foo = {
      initialPassword = "foo";
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };

    boot.loader.external = {
      enable = true;
      installHook = lib.getExe' pkgs.coreutils "true";
    };

    system.switch.enableNg = true;

    specialisation.simpleService.configuration = {
      systemd.services.test = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.coreutils}/bin/true";
          ExecReload = "${pkgs.coreutils}/bin/true";
        };
      };
    };
  }
)).config.system.build.vm

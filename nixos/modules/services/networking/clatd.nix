{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.services.clatd;

  configFormat = pkgs.formats.keyValue {
    listToValue = lib.concatMapStringsSep "," toString;
  };

  configFile = configFormat.generate "clatd.conf" cfg.settings;

  isNetworkd = config.networking.useNetworkd;
in
{
  options.services.clatd = with lib; {
    enable = mkEnableOption "clatd";

    settings = mkOption {
      type = configFormat.type;
      default = { };
      description = ''
        Clatd configuration. See
        <https://github.com/toreanderson/clatd?tab=readme-ov-file#configuration>.
      '';
    };
  };

  config = lib.mkIf config.services.clatd.enable {
    systemd.services.clatd = {
      after = [
        "modprobe@tun.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];
      unitConfig = {
        StartLimitIntervalSec = 5;
      };
      serviceConfig = {
        ExecStart = toString [ (lib.getExe pkgs.clatd) "-c" configFile ];
        # DynamicUser = true;
        # PrivateTmp = true;
        # TemporaryFileSystem = [ "/" ];
        # AmbientCapabilities = [ "CAP_NET_ADMIN" ];
        # CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
        # RestrictAddressFamilies = [
        #   "AF_NETLINK"
        #   "AF_INET"
        #   "AF_INET6"
        # ];
        # # TODO(jared): probably don't need this
        # RestrictNamespaces = [ "net" ];
        # SystemCallFilter = [ "@system-service" ];
      };
      wantedBy = [ "multi-user.target" ];
    };

    systemd.network.networks."50-clatd" = lib.mkIf isNetworkd {
      matchConfig.Name = cfg.settings.clat-dev or "clat"; # default is "clat"
      linkConfig = {
        Unmanaged = true;
        ActivationPolicy = "manual";
      };
    };
  };
}

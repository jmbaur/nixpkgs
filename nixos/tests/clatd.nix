import ./make-test-python.nix ({ pkgs, lib, ... }: {
  meta.maintainers = with lib.maintainers; [ jmbaur ];

  name = "clatd";

  nodes =
    let
      ulaPrefix = "fdd9:46c0:11a0";
      platPrefix = "2001:db8";

      commonConfig = { lib, ... }: {
        networking.useDHCP = lib.mkDefault false;
        networking.useNetworkd = true;

        networking.interfaces.eth1.ipv4.addresses = lib.mkVMOverride [ ];

        users.users.root.initialPassword = "";
        environment.systemPackages = [ pkgs.tcpdump ];
      };
    in
    {
      plat = { config, lib, ... }: {
        imports = [ commonConfig ];

        # run an arbitrary service that will be exposed to the clat node
        services.journald.gateway.enable = true;

        # get an IPv4 address via DHCP from qemu
        networking.useDHCP = true;

        # allow forwarding to the qemu DHCP server
        boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = true;

        networking.interfaces.eth1.ipv6.addresses = [{
          address = "${ulaPrefix}::1";
          prefixLength = 64;
        }];

        networking.jool = {
          enable = true;
          nat64.default.global.pool6 = "${platPrefix}::/96";
        };

        networking.firewall.allowedUDPPorts = [ 53 /* DNS */ ];
        networking.firewall.allowedTCPPorts = [ config.services.journald.gateway.port ];

        # clatd will perform a DNS query of "ipv4only.arpa." and expect for the
        # response to contain an indication that DNS64 translation of the well
        # known addresses for this name was performed, so we can manually
        # perform this translation and tell systemd-resolved to serve it up for
        # us.
        services.resolved = {
          enable = true;
          extraConfig = ''
            ReadEtcHosts=yes
            DNSStubListenerExtra=::
          '';
        };
        networking.hosts = lib.genAttrs [
          "192.0.0.170"
          "192.0.0.171"
          "${platPrefix}::192.0.0.170"
          "${platPrefix}::192.0.0.171"
        ]
          (_: [ "ipv4only.arpa." ]);
      };

      clat = { nodes, ... }: {
        imports = [ commonConfig ];
        networking.nameservers = [
          (lib.head nodes.plat.networking.interfaces.eth1.ipv6.addresses).address
        ];

        networking.interfaces.eth1.ipv6 = {
          addresses = [{
            address = "${ulaPrefix}::2";
            prefixLength = 64;
          }];
          routes = [{
            address = "::";
            prefixLength = 0;
          }];
        };

        services.clatd = {
          enable = true;
          # TODO(jared): shouldn't have to set this
          settings.dns64-servers = [ "fdd9:46c0:11a0::1" ];
        };
      };
    };

  testScript = { nodes, ... }: ''
    plat.wait_for_open_port(${toString nodes.plat.services.journald.gateway.port})

    # Test that using an IPv4 literal works
    clat.succeed("curl 10.0.2.15:${toString nodes.plat.services.journald.gateway.port}")
  '';
})

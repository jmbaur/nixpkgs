# The options of the composefs /etc overlay that system.etc.confext replaced,
# which are kept for compatibility.
{ lib, ... }:
{

  name = "activation-etc-overlay-mutable";

  meta.maintainers = with lib.maintainers; [
    nikstur
    jmbaur
  ];

  nodes.machine =
    { pkgs, ... }:
    {
      system.etc.overlay.enable = true;
      system.etc.overlay.mutable = true;

      environment.etc = {
        modetest = {
          text = "foo";
          mode = "300";
        };
        modetest2 = {
          text = "foo";
          mode = "0300";
        };
      };

      # Prerequisites
      boot.initrd.systemd.enable = true;

      specialisation.new-generation.configuration = {
        environment.etc."newgen".text = "newgen";
        # A symlink in a subdirectory that does not exist in the base
        # generation. stage-2-init.sh creates /etc/nixos at runtime, which must
        # not hide what a new generation adds below it.
        environment.etc."nixos/newlink".source = pkgs.emptyDirectory;
      };
      specialisation.newer-generation.configuration = {
        environment.etc."newergen".text = "newergen";
      };
    };

  testScript = # python
    ''
      newergen = machine.succeed("realpath /run/current-system/specialisation/newer-generation/bin/switch-to-configuration").rstrip()

      with subtest("/etc is merged from a configuration extension image"):
        machine.succeed("findmnt --kernel --type overlay /etc")
        machine.succeed("grep -qx '~nixos' /etc/.systemd-confext/confexts")

      with subtest("modes work correctly"):
        machine.succeed("stat --format '%F' /etc/modetest | tee /dev/stderr | grep -Eq '^regular file$'")
        machine.succeed("stat --format '%a' /etc/modetest | tee /dev/stderr | grep -Eq '^300$'")
        machine.succeed("stat --format '%F' /etc/modetest2 | tee /dev/stderr | grep -Eq '^regular file$'")
        machine.succeed("stat --format '%a' /etc/modetest2 | tee /dev/stderr | grep -Eq '^300$'")

      with subtest("switching to the same generation"):
        machine.succeed("/run/current-system/bin/switch-to-configuration test")

      with subtest("the initrd didn't get rebuilt"):
        machine.succeed("test /run/current-system/initrd -ef /run/current-system/specialisation/new-generation/initrd")

      with subtest("switching to a new generation"):
        machine.fail("stat /etc/newgen")
        machine.succeed("echo -n 'mutable' > /etc/mutable")

        machine.succeed("/run/current-system/specialisation/new-generation/bin/switch-to-configuration switch")

        assert machine.succeed("cat /etc/newgen") == "newgen"
        assert machine.succeed("cat /etc/mutable") == "mutable"
        machine.succeed("test -L /etc/nixos/newlink")

        machine.succeed(f"{newergen} switch")
        assert machine.succeed("cat /etc/newergen") == "newergen"
        assert machine.succeed("cat /etc/mutable") == "mutable"
    '';
}

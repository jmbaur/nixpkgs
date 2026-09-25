# The options of the composefs /etc overlay that system.etc.confext replaced,
# which are kept for compatibility.
{ lib, ... }:
{

  name = "activation-etc-overlay-immutable";

  meta.maintainers = with lib.maintainers; [
    nikstur
    jmbaur
  ];

  nodes.machine = {
    system.etc.overlay.enable = true;
    system.etc.overlay.mutable = false;

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
    systemd.sysusers.enable = true;
    users.mutableUsers = false;
    boot.initrd.systemd.enable = true;
    time.timeZone = "Utc";

    # The standard resolvconf service tries to write to /etc and crashes,
    # which makes nixos-rebuild exit uncleanly when switching into the new generation
    services.resolved.enable = true;

    specialisation.new-generation.configuration = {
      environment.etc."newgen".text = "newgen";
    };
    specialisation.newer-generation.configuration = {
      environment.etc."newergen".text = "newergen";
    };
  };

  testScript = # python
    ''
      newergen = machine.succeed("realpath /run/current-system/specialisation/newer-generation/bin/switch-to-configuration").rstrip()

      with subtest("/etc is merged read-only from a configuration extension image"):
        machine.succeed("findmnt --kernel --type overlay /etc")
        machine.succeed("grep -qx '~nixos' /etc/.systemd-confext/confexts")
        machine.fail("touch /etc/nope")

      with subtest("machine-id is set up without first-boot looping"):
        # The baked-in placeholder is an empty regular file; systemd overlays
        # /run/machine-id on top so the session has a valid ID while the
        # commit service is condition-skipped (no writable /etc to commit to).
        machine.succeed("stat --format '%F' /etc/machine-id | tee /dev/stderr | grep -q 'regular'")
        machine.succeed("grep -qE '^[0-9a-f]{32}$' /etc/machine-id")
        machine.fail("journalctl -b | grep -F 'System cannot boot: Missing /etc/machine-id'")
        machine.fail("journalctl -b | grep -F 'Detected first boot'")
        machine.fail("systemctl is-failed --quiet systemd-machine-id-commit.service")
        assert machine.succeed(
            "systemctl show -P ConditionResult systemd-machine-id-commit.service"
        ).strip() == "no"

      with subtest("modes work correctly"):
        machine.succeed("stat --format '%F' /etc/modetest | tee /dev/stderr | grep -q 'regular file'")
        machine.succeed("stat --format '%F' /etc/modetest2 | tee /dev/stderr | grep -q 'regular file'")

      with subtest("direct symlinks point to the target without indirection"):
        assert machine.succeed("readlink -n /etc/localtime") == "/etc/zoneinfo/Utc"

      with subtest("/etc/mtab points to the right file"):
        assert "/proc/mounts" == machine.succeed("readlink --no-newline /etc/mtab")

      with subtest("Correct mode on the source password files"):
        assert machine.succeed("stat -c '%a' /var/lib/nixos/etc/passwd") == "644\n"
        assert machine.succeed("stat -c '%a' /var/lib/nixos/etc/group") == "644\n"
        assert machine.succeed("stat -c '%a' /var/lib/nixos/etc/shadow") == "0\n"
        assert machine.succeed("stat -c '%a' /var/lib/nixos/etc/gshadow") == "0\n"

      with subtest("Password files are symlinks to /var/lib/nixos/etc"):
        assert machine.succeed("readlink -f /etc/passwd") == "/var/lib/nixos/etc/passwd\n"
        assert machine.succeed("readlink -f /etc/group") == "/var/lib/nixos/etc/group\n"
        assert machine.succeed("readlink -f /etc/shadow") == "/var/lib/nixos/etc/shadow\n"
        assert machine.succeed("readlink -f /etc/gshadow") == "/var/lib/nixos/etc/gshadow\n"

      with subtest("switching to the same generation"):
        machine.succeed("/run/current-system/bin/switch-to-configuration test")

      with subtest("the initrd didn't get rebuilt"):
        machine.succeed("test /run/current-system/initrd -ef /run/current-system/specialisation/new-generation/initrd")

      with subtest("switching to a new generation"):
        machine.fail("stat /etc/newgen")
        machine.succeed("/run/current-system/specialisation/new-generation/bin/switch-to-configuration switch")
        assert machine.succeed("cat /etc/newgen") == "newgen"

        machine.succeed(f"{newergen} switch")
        assert machine.succeed("cat /etc/newergen") == "newergen"
        machine.fail("touch /etc/nope")
    '';
}

# Builds /etc itself as a systemd-confext image.
#
# The image is part of the system closure and is deployed with the toplevel;
# the initrd and every switch-to-configuration point systemd-confext at the
# image of the generation they belong to and merge it. By default, the
# underlying /etc is the overlay's upper layer, so it stays writable and keeps
# everything that is not managed by NixOS, while images dropped into
# /var/lib/confexts at runtime layer on top of the NixOS-provided files.
#
# The preparation is done by nixos-init (etc-confext-sysroot in the initrd,
# before systemd-confext-sysroot.service merges /etc, and etc-confext-activate
# on activation), which reads what it needs to know about the image from the
# bootspec of the toplevel.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.system.etc.confext;
  confextCfg = config.systemd.confext;
  mutable = confextCfg.settings.ConfExt.Mutable;

  normalizeTarget =
    target:
    lib.concatStringsSep "/" (
      lib.filter (part: part != "" && part != ".") (lib.splitString "/" target)
    );

  etcFiles = lib.filterAttrs (_: f: f.enable) config.environment.etc;

  files =
    lib.mapAttrs' (
      _: f:
      lib.nameValuePair (normalizeTarget f.target) {
        inherit (f)
          source
          mode
          uid
          gid
          ;
      }
    ) etcFiles
    // {
      # nixpkgs points systemd at /etc/static/... for files it must not modify,
      # and a handful of modules reference paths below it directly.
      static = {
        source = "${config.system.build.etc}/etc";
        mode = "symlink";
      };
    };

  image = pkgs.makeConfext {
    inherit (cfg) name format;
    inherit files;
    # The system's own image is deployed with the toplevel, so the store it
    # points into is the one it is merged on.
    allowStoreReferences = true;
  };

  # Every path the image provides, leading directories included. Used to clear
  # overlayfs whiteouts and opaque markers that would hide them for good from
  # the upper layer. Other paths there are left alone.
  prefixesOf =
    target:
    let
      parts = lib.splitString "/" target;
    in
    lib.genList (i: lib.concatStringsSep "/" (lib.take (i + 1) parts)) (builtins.length parts);

  targets = pkgs.writeText "etc-confext-targets" (
    lib.concatLines (lib.unique (lib.concatMap prefixesOf (lib.attrNames files)))
  );

  # Entries that name an owner without giving a uid and a gid: the names
  # cannot be resolved when the image is built, so the ids win.
  namesOwner =
    name: id:
    !(lib.elem name [
      "+${toString id}"
      "root"
    ])
    && id == 0;
  namedOwners = lib.filter (
    f: f.mode != "symlink" && (namesOwner f.user f.uid || namesOwner f.group f.gid)
  ) (lib.attrValues etcFiles);

  nixos-init = config.system.nixos-init.package;
in
{
  imports = [
    (lib.mkRenamedOptionModule
      [ "system" "etc" "overlay" "enable" ]
      [ "system" "etc" "confext" "enable" ]
    )
  ];

  options.system.etc.overlay.mutable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether {file}`/etc` is writable.

      This is kept for compatibility with the composefs based
      {file}`/etc` overlay that {option}`system.etc.confext.enable`
      replaced. Setting it to `false` is the same as setting
      {option}`systemd.confext.settings.ConfExt.Mutable` to `"no"`, which
      is the option to use instead.
    '';
  };

  options.system.etc.confext = {
    enable = lib.mkEnableOption ''
      building {file}`/etc` as a systemd-confext image instead of populating it
      with symlinks at activation time, see [](#sec-etc-confext).

      The image is part of the system closure. It is merged in the initrd, and
      every {command}`switch-to-configuration` migrates {file}`/etc` to the
      image of the new generation. By default, the underlying {file}`/etc`
      remains the overlay's writable upper layer, and images installed in
      {file}`/var/lib/confexts` at runtime are layered in between
    '';

    name = lib.mkOption {
      type = lib.types.str;
      default = "~nixos";
      description = ''
        Name of the system's configuration extension image.

        systemd orders extensions by name with the rules of
        {manpage}`systemd.version(7)` and lets the highest one win, so the
        default starts with `~`, which sorts below everything else. Images
        installed at runtime can then override files NixOS manages.
      '';
    };

    format = lib.mkOption {
      type = lib.types.enum [
        "erofs"
        "squashfs"
        "directory"
      ];
      default = "erofs";
      description = ''
        Format of the system's configuration extension image.

        A `directory` image needs no filesystem driver and can be inspected in
        the store, but the store cannot carry file modes or ownership, so
        {option}`environment.etc` entries that ask for them are not represented
        faithfully.
      '';
    };

    image = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = image;
      defaultText = lib.literalMD "the image built from {option}`environment.etc`";
      description = "The system's configuration extension image.";
    };

    # Consulted by the modules that write state to /etc, systemd-sysusers and
    # userborn, to put it somewhere else.
    immutable = lib.mkOption {
      type = lib.types.bool;
      internal = true;
      readOnly = true;
      default = cfg.enable && (!confextCfg.writable || !confextCfg.persistent);
      defaultText = lib.literalMD "whether writes to the merged {file}`/etc` are impossible or lost";
      description = ''
        Whether {file}`/etc` cannot keep state: it is read-only, or what is
        written to it does not survive a reboot.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable;
        message = ''
          system.etc.confext.enable requires boot.initrd.systemd.enable: /etc
          has to be merged before the service manager of the system starts.
        '';
      }
      {
        # TODO: support containers. They have no initrd and no bootspec, and
        # systemd-confext cannot open a disk image without a loop device, which
        # containers do not have.
        assertion = !config.boot.isContainer;
        message = "system.etc.confext.enable is not supported in containers yet.";
      }
      {
        assertion = config.environment.etc ? "os-release";
        message = "system.etc.confext.enable requires environment.etc.\"os-release\", which systemd matches extension images against.";
      }
      {
        # update-users-groups.pl writes the password files to /etc with no way
        # to redirect it. systemd-sysusers and userborn both put them
        # somewhere else when /etc is immutable.
        assertion =
          !confextCfg.writable -> (config.systemd.sysusers.enable || config.services.userborn.enable);
        message = ''
          A read-only /etc (systemd.confext.settings.ConfExt.Mutable =
          "${toString mutable}") requires systemd.sysusers.enable or
          services.userborn.enable: the password files cannot be written to
          /etc.
        '';
      }
    ];

    warnings =
      lib.optional (namedOwners != [ ]) ''
        These environment.etc entries name their owner instead of giving a uid
        and a gid, which cannot be resolved when the /etc image is built. They
        will be owned by root: ${lib.concatMapStringsSep ", " (f: f.target) namedOwners}.
      ''
      ++
        lib.optional
          (!confextCfg.persistent && !(config.systemd.sysusers.enable || config.services.userborn.enable))
          ''
            systemd.confext.settings.ConfExt.Mutable = "${toString mutable}" throws
            away everything written to /etc when extensions are unmerged, password
            hashes in /etc/shadow included. Enable systemd.sysusers or
            services.userborn so that the password files live outside /etc.
          '';

    systemd.confext.settings.ConfExt.Mutable = lib.mkIf (!config.system.etc.overlay.mutable) (
      lib.mkDefault "no"
    );

    # s-t-c compares /etc/NIXOS to decide whether it is dealing with a NixOS
    # system; the classic activation creates it as a side effect.
    environment.etc.NIXOS.text = lib.mkDefault "";

    system.requiredKernelConfig =
      with config.lib.kernelConfig;
      [
        (isEnabled "OVERLAY_FS")
      ]
      ++ lib.optional (cfg.format == "erofs") (isEnabled "EROFS_FS")
      ++ lib.optional (cfg.format == "squashfs") (isEnabled "SQUASHFS");

    # An empty regular file means systemd will bind mount /run/machine-id on
    # top, and ConditionFirstBoot will be false (the file will never change,
    # so this makes sense). See machine-id(5) "First Boot Semantics". It also
    # serves as a target to bind mount an actually persistent machine-id onto.
    # A symlink doesn't work here since systemd-machine-id-commit checks
    # /etc/machine-id itself for being a mountpoint without following
    # symlinks, so it would never commit through a symlink.
    environment.etc.machine-id = lib.mkIf cfg.immutable (
      lib.mkDefault {
        text = "";
        mode = "0444";
      }
    );

    # The upstream unit has ConditionPathIsReadWrite=/etc, which is always
    # false here. Replace it with ConditionFirstBoot: with the empty
    # placeholder above first-boot is "no" and commit stays skipped, but when
    # a persistence module bind-mounts a writable file containing
    # "uninitialized" over /etc/machine-id, first-boot is "yes" once and
    # commit writes the generated ID through the bind mount.
    #
    # An empty Condition*= assignment resets *all* condition types, and this
    # attrset is serialised in key order, so the reset goes through
    # ConditionFirstBoot (sorts first) and we re-add the upstream
    # ConditionPathIsMountPoint afterwards.
    systemd.services.systemd-machine-id-commit.unitConfig = lib.mkIf cfg.immutable {
      ConditionFirstBoot = lib.mkDefault [
        ""
        "true"
      ];
      ConditionPathIsMountPoint = lib.mkDefault "/etc/machine-id";
    };

    systemd.services.systemd-confext = {
      # Only needed to take down the /etc of the earlier system.etc.overlay.
      path = [ pkgs.util-linux ];
      serviceConfig = {
        # The initrd merges /etc before switch-root, and the mount id systemd
        # records for the image changes across it, so a plain refresh here
        # would always find a change and take /etc apart again in the middle
        # of the boot. This refreshes only when /etc has not been merged with
        # the image of the running generation yet. Reloading the unit still
        # refreshes unconditionally, to pick up images installed at runtime.
        ExecStart = [
          ""
          "${nixos-init}/bin/etc-confext-activate ${config.systemd.package}/bin/systemd-confext /run/current-system"
        ];
        # /etc is the confext, so unmerging it on shutdown would take the
        # configuration away from everything that shuts down after it.
        ExecStop = [ "" ];
      };
    };

    # Everything nixos-init needs to know about the image of a generation,
    # which lets the initrd merge the /etc of the generation that was booted
    # without depending on it.
    boot.bootspec.extensions."org.nixos.nixos-init.v1".etc_confext = {
      inherit (cfg) name;
      image = "${image}";
      targets = "${targets}";
      inherit (confextCfg) flags;
      mutable_directory = confextCfg.mutableDirectory;
      upper_directory = confextCfg.upperDirectory;
    };

    system.systemBuilderCommands = ''
      ln -s ${image} $out/etc-confext
    '';

    boot.initrd.availableKernelModules = [
      "loop"
      "overlay"
    ]
    ++ lib.optional (cfg.format == "erofs") "erofs"
    ++ lib.optional (cfg.format == "squashfs") "squashfs";

    boot.initrd.systemd = {
      # systemd's own unit for merging configuration extensions into the root
      # filesystem before switch-root, which NixOS only extends with a drop-in.
      additionalUpstreamUnits = [ "systemd-confext-sysroot.service" ];

      storePaths = [
        "${config.boot.initrd.systemd.package}/bin/systemd-confext"
        "${nixos-init}/bin/etc-confext-sysroot"
      ];

      # Points systemd-confext at the image of the generation that was booted,
      # which only init= on the kernel command line says, and prepares the
      # root for it.
      services.nixos-etc-confext-prepare = {
        description = "Prepare /sysroot/etc for Merging";
        requiredBy = [ "systemd-confext-sysroot.service" ];
        before = [ "systemd-confext-sysroot.service" ];
        unitConfig = {
          DefaultDependencies = false;
          ConditionKernelCommandLine = "!systemd.confext=0";
          WantsMountsFor = [ "/sysroot/var" ];
          RequiresMountsFor = [
            "/sysroot/nix/store"
            "/sysroot/run"
          ];
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${nixos-init}/bin/etc-confext-sysroot";
        };
      };

      services.systemd-confext-sysroot = {
        requiredBy = [ "initrd-fs.target" ];
        unitConfig = {
          # Upstream only looks for images on the root filesystem. The image
          # of the generation is installed in /run/confexts, which the initrd
          # binds to /sysroot/run.
          ConditionDirectoryNotEmpty = "|/sysroot/run/confexts";
          # Upstream merges before initrd-root-fs.target, which is too early
          # here: the image is in the store and the images an admin installs
          # are in /var, either of which can be a filesystem of its own that
          # is mounted from the root's fstab once the root itself is up.
          Before = [
            ""
            "initrd-fs.target"
            "shutdown.target"
          ];
          WantsMountsFor = [ "/sysroot/var" ];
          RequiresMountsFor = [
            "/sysroot/nix/store"
            "/sysroot/run"
          ];
        };
        serviceConfig = {
          # The os-release of the host lives in the image itself, so systemd
          # cannot read it from /sysroot/etc before the merge. It resolves this
          # path below /sysroot, where the system closure has it. It only
          # changes with the NixOS version, which the initrd depends on anyway.
          Environment = "SYSTEMD_OS_RELEASE=${config.environment.etc."os-release".source}";
          # Upstream's command, with the options that can only be passed on
          # the command line.
          ExecStart = [
            ""
            "${config.boot.initrd.systemd.package}/bin/systemd-confext --root=/sysroot ${lib.escapeShellArgs confextCfg.flags} refresh"
          ];
        };
      };
    };

    # Replaces the classic /etc activation. $systemConfig is the toplevel
    # being activated.
    system.build.etcActivationCommands = ''
      ${nixos-init}/bin/etc-confext-activate ${config.systemd.package}/bin/systemd-confext "$systemConfig"
    '';
  };

  meta.maintainers = [ lib.maintainers.jmbaur ];
}

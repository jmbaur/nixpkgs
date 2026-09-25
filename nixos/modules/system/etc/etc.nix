# Management of static files in /etc.
{
  config,
  lib,
  pkgs,
  ...
}:
let

  etc' = lib.filter (f: f.enable) (lib.attrValues config.environment.etc);

  etc =
    pkgs.runCommandLocal "etc"
      {
        # This is needed for the systemd module
        passthru.targets = map (x: x.target) etc';
      } # sh
      ''
        set -euo pipefail

        makeEtcEntry() {
          src="$1"
          target="$2"
          mode="$3"
          user="$4"
          group="$5"

          if [[ "$src" = *'*'* ]]; then
            # If the source name contains '*', perform globbing.
            mkdir -p "$out/etc/$target"
            for fn in $src; do
                ln -s "$fn" "$out/etc/$target/"
            done
          else

            mkdir -p "$out/etc/$(dirname "$target")"
            if ! [ -e "$out/etc/$target" ]; then
              ln -s "$src" "$out/etc/$target"
            else
              echo "duplicate entry $target -> $src"
              if [ "$(readlink "$out/etc/$target")" != "$src" ]; then
                echo "mismatched duplicate entry $(readlink "$out/etc/$target") <-> $src"
                ret=1
              fi
            fi

            if [ "$mode" != symlink ]; then
              echo "$mode" > "$out/etc/$target.mode"
              echo "$user" > "$out/etc/$target.uid"
              echo "$group" > "$out/etc/$target.gid"
            fi
          fi
        }

        mkdir -p "$out/etc"
        ${lib.concatMapStringsSep "\n" (
          etcEntry:
          lib.escapeShellArgs [
            "makeEtcEntry"
            # Force local source paths to be added to the store
            "${etcEntry.source}"
            etcEntry.target
            etcEntry.mode
            etcEntry.user
            etcEntry.group
          ]
        ) etc'}
      '';

in

{

  imports = [ ../build.nix ];

  ###### interface

  options = {

    environment.etc = lib.mkOption {
      default = { };
      example = lib.literalExpression ''
        { example-configuration-file =
            { source = "/nix/store/.../etc/dir/file.conf.example";
              mode = "0440";
            };
          "default/useradd".text = "GROUP=100 ...";
        }
      '';
      description = ''
        Set of files that have to be linked in {file}`/etc`.
      '';

      type =
        with lib.types;
        attrsOf (
          submodule (
            {
              name,
              config,
              options,
              ...
            }:
            {
              options = {

                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = ''
                    Whether this /etc file should be generated.  This
                    option allows specific /etc files to be disabled.
                  '';
                };

                target = lib.mkOption {
                  type = lib.types.str;
                  description = ''
                    Name of symlink (relative to
                    {file}`/etc`).  Defaults to the attribute
                    name.
                  '';
                };

                text = lib.mkOption {
                  default = null;
                  type = lib.types.nullOr lib.types.lines;
                  description = "Text of the file.";
                };

                source = lib.mkOption {
                  type = lib.types.path;
                  description = "Path of the source file.";
                };

                mode = lib.mkOption {
                  type = lib.types.str;
                  default = "symlink";
                  example = "0600";
                  description = ''
                    If set to something else than `symlink`,
                    the file is copied instead of symlinked, with the given
                    file mode.
                  '';
                };

                uid = lib.mkOption {
                  default = 0;
                  type = lib.types.int;
                  description = ''
                    UID of created file. Only takes effect when the file is
                    copied (that is, the mode is not 'symlink').
                  '';
                };

                gid = lib.mkOption {
                  default = 0;
                  type = lib.types.int;
                  description = ''
                    GID of created file. Only takes effect when the file is
                    copied (that is, the mode is not 'symlink').
                  '';
                };

                user = lib.mkOption {
                  default = "+${toString config.uid}";
                  type = lib.types.str;
                  description = ''
                    User name of file owner.

                    Only takes effect when the file is copied (that is, the
                    mode is not `symlink`).

                    When `services.userborn.enable`, this option has no effect.
                    You have to assign a `uid` instead. Otherwise this option
                    takes precedence over `uid`.
                  '';
                };

                group = lib.mkOption {
                  default = "+${toString config.gid}";
                  type = lib.types.str;
                  description = ''
                    Group name of file owner.

                    Only takes effect when the file is copied (that is, the
                    mode is not `symlink`).

                    When `services.userborn.enable`, this option has no effect.
                    You have to assign a `gid` instead. Otherwise this option
                    takes precedence over `gid`.
                  '';
                };

              };

              config = {
                target = lib.mkDefault name;
                source = lib.mkIf (config.text != null) (
                  let
                    name' = "etc-" + lib.replaceStrings [ "/" ] [ "-" ] name;
                  in
                  lib.mkDerivedConfig options.text (pkgs.writeText name')
                );
              };

            }
          )
        );

    };

  };

  ###### implementation

  config = {

    system.build.etc = etc;
    # Overridden by system.etc.confext.
    system.build.etcActivationCommands = lib.mkDefault ''
      # Set up the statically computed bits of /etc.
      echo "setting up /etc..."
      ${pkgs.perl.withPackages (p: [ p.FileSlurp ])}/bin/perl ${./setup-etc.pl} ${etc}/etc
    '';

  };

}

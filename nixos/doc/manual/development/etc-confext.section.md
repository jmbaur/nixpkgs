# `/etc` as a configuration extension image {#sec-etc-confext}

Instead of populating `/etc` with symlinks from a Perl script at activation
time, NixOS can build it as a [systemd-confext](https://www.freedesktop.org/software/systemd/man/latest/systemd-sysext.html)
image:

```nix
{
  boot.initrd.systemd.enable = true;
  system.etc.confext.enable = true;
}
```

This removes Perl from activation, and makes `/etc` a stack of images that
systemd knows how to manage: images installed at runtime in
{file}`/var/lib/confexts` are layered on top of the files NixOS manages, and
can override them.

Switching to such a configuration migrates a running machine, and needs no
reboot. Rolling back to an older generation puts the old `/etc` back.

## How it works {#sec-etc-confext-how}

`/etc` is an overlayfs mount that systemd-confext assembles:

| layer            | contents                                                                                       |
| ---------------- | ---------------------------------------------------------------------------------------------- |
| upper (writable) | the underlying `/etc`: `passwd`, `machine-id`, `/etc/nixos`, whatever services and admins write |
| lower            | images installed in {file}`/var/lib/confexts`, highest name first                              |
| lower            | {file}`/run/confexts/~nixos.raw`, the image built from [](#opt-environment.etc)                 |

- The image is built with `pkgs.makeConfext`, and is part of the system
  closure. The toplevel describes it in its [bootspec](#sec-bootspec) document.
- systemd's own `systemd-confext-sysroot.service` merges it from the initrd,
  before switch-root. NixOS extends the unit with a drop-in, and runs
  `etc-confext-sysroot` from `nixos-init` before it, which picks the image of
  the generation that was booted from `init=` on the kernel command line. The
  initrd does not depend on the image, and booting an older generation merges
  its `/etc`.
- Activation, including the one {command}`nixos-enter` runs, uses
  `etc-confext-activate` from `nixos-init` to point {file}`/run/confexts` at
  the image of the new generation and run {command}`systemd-confext refresh`.
  A switch that does not change `/etc` leaves the merge alone.
- The system image is named `~nixos`, which sorts below any other name, so any
  image installed at runtime takes precedence over the files NixOS manages.

## Mutability {#sec-etc-confext-mutability}

[](#opt-systemd.confext.settings.ConfExt.Mutable) picks one of the mutability
modes of {manpage}`systemd-sysext(8)`, and
[](#opt-systemd.confext.mutableDirectory) where writes to `/etc` go:

| `Mutable`             | `mutableDirectory`                          | `/etc` is | writes go to                                                        |
| --------------------- | ------------------------------------------- | --------- | ------------------------------------------------------------------- |
| `auto`, `yes`         | `"/etc"` (default)                          | writable  | the underlying `/etc`, which becomes the upper layer of the overlay |
| `auto`, `yes`         | {file}`/var/lib/extensions.mutable/etc`     | writable  | that directory; the underlying `/etc` stays below the images        |
| `no`                  | ignored                                     | read-only | nowhere                                                             |
| `import`              | {file}`/var/lib/extensions.mutable/etc`     | read-only | nowhere; the directory is merged *above* the images instead         |
| `ephemeral`           | ignored                                     | writable  | a directory on {file}`/run`, discarded when `/etc` is unmerged      |
| `ephemeral-import`    | {file}`/var/lib/extensions.mutable/etc`     | writable  | as `ephemeral`, plus the directory merged above the images          |

A mode that leaves `/etc` read-only, or that throws writes away, needs the
password files to live somewhere else: enable
[](#opt-systemd.sysusers.enable) or [](#opt-services.userborn.enable), which
then keep them in {file}`/var/lib/nixos`. `/etc/machine-id` becomes the empty
placeholder systemd expects, so that it keeps the machine id on {file}`/run`.

A read-only `/etc` also stops anything else that writes there: `resolvconf`,
for instance, fails. `import` is the escape hatch for such files, since the
directory it merges sits above the images.

## Installing an image at runtime {#sec-etc-confext-runtime}

```ShellSession
# cp motd.raw /var/lib/confexts/
# systemctl reload systemd-confext.service
```

`systemctl reload` is preferred over {command}`systemd-confext refresh`,
since the unit passes the options NixOS needs, `--noexec=false` in particular.
Images are built with `pkgs.makeConfext`:

```nix
pkgs.makeConfext {
  name = "motd";
  files = {
    "motd" = ./motd;
    "ssh/sshd_config.d/motd.conf" = {
      source = ./sshd-motd.conf;
      mode = "0400";
    };
  };
}
```

`files` is keyed by the path below `/etc`. A value is a file to copy in, or an
attribute set with the `source`, `mode`, `uid` and `gid` of
[](#opt-environment.etc). Files are copied with mode `0444` unless they say
otherwise. An image carries `/etc` and nothing else, so the build refuses one
that references the Nix store, which rules out `mode = "symlink"` for anything
but the image NixOS builds for its own `/etc`.

Merging images installed at runtime ([](#opt-systemd.confext.enable)) is only
supported together with [](#opt-system.etc.confext.enable), which enables it:
on a classic `/etc` the files NixOS manages would be in the upper layer, where
no image can override them.

## Migrating from `system.etc.overlay` {#sec-etc-confext-migration}

`system.etc.overlay.enable` is an alias of
[](#opt-system.etc.confext.enable), and
`system.etc.overlay.mutable = false` is the same as setting
[](#opt-systemd.confext.settings.ConfExt.Mutable) to `"no"`.

The composefs based `/etc` these options used to build kept its writes in
{file}`/.rw-etc/upper`. The first time a system with a writable `/etc` is
activated or booted with a configuration extension image, a copy of that upper
layer becomes the underlying `/etc`. The directory that was hidden below the
overlay is moved to {file}`/.rw-etc/etc.pre-confext`, and
{file}`/.rw-etc/upper` itself is left in place for a rollback.

## Limitations {#sec-etc-confext-limitations}

- [](#opt-boot.initrd.systemd.enable) is required.
- Containers are not supported yet. They have no initrd and no bootspec to
  find the image in, and systemd-confext cannot open a disk image without a
  loop device, which containers do not have. Supporting them is future work.
- In the default mode, the underlying `/etc` wins over the images. A file
  written there shadows the NixOS-managed file of the same name from then on.
  Routing writes to a directory of their own puts the underlying `/etc` below
  the images instead.
- Deleting a file NixOS manages only lasts until the next switch or boot,
  which brings it back. Deleting any other file is kept, including one that an
  image installed at runtime provides.
- `/etc` is briefly the bare underlying directory while a switch that changes
  it is refreshed: systemd-confext unmerges the old overlay before it puts
  the new one in place.
- [](#opt-environment.etc) entries that name their owner instead of setting
  `uid` and `gid` are owned by root, since names cannot be resolved when the
  image is built.

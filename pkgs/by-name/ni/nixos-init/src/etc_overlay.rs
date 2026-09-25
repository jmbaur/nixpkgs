//! `/etc` as a systemd-confext image.
//!
//! The image is built from `environment.etc` and deployed with the toplevel. Before it can be
//! merged, a root has to be prepared for it: systemd-confext has to be pointed at the image of the
//! generation that is booted or activated, the write routing directory has to be set up for the
//! mutability mode, and state from earlier ways of managing `/etc` has to be cleaned up.

use std::{
    env,
    fs::{self, DirBuilder, File, Metadata, Permissions},
    io,
    os::{
        fd::{AsRawFd, OwnedFd},
        unix::{
            self,
            fs::{DirBuilderExt, FileTypeExt, MetadataExt, PermissionsExt},
        },
    },
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{Context, Result, bail};
use rustix::{
    fs::CWD,
    mount::{OpenTreeFlags, open_tree},
};

use crate::{
    SYSROOT_PATH,
    config::{Config, EtcConfext},
    find_init_in_prefix,
    fs::atomic_symlink,
    verify_init_is_nixos,
};

/// The directory systemd looks for to route writes to the merged `/etc` to. When it is a symlink,
/// systemd follows it.
const ROUTING_DIRECTORY: &str = "/var/lib/extensions.mutable/etc";

/// The search directory the image of the running generation is installed in.
///
/// It names a store path of the generation that is running, so it is worth no more than the boot
/// it was made in. `/var/lib/confexts` is left to the images an admin installs.
const RUN_CONFEXTS: &str = "/run/confexts";

/// What systemd-confext records about a merged hierarchy.
const MERGED_MARKER: &str = "/etc/.systemd-confext/dev";

/// Where the composefs `/etc` of the earlier `system.etc.overlay` kept its state, relative to the
/// root.
const LEGACY_OVERLAY: &str = ".rw-etc";

const OVERLAY_OPAQUE_XATTR: &str = "trusted.overlay.opaque";
const OVERLAY_METACOPY_XATTR: &str = "trusted.overlay.metacopy";

/// Entrypoint for the `etc-confext-sysroot` binary.
///
/// Prepares `/sysroot` in the initrd for `systemd-confext-sysroot.service`, which merges `/etc`
/// before switch-root. Which image to merge depends on the generation that was booted, which only
/// `init=` on the kernel command line says.
///
/// Usage: `etc-confext-sysroot`
pub fn etc_confext_sysroot() -> Result<()> {
    let init = match find_init_in_prefix(SYSROOT_PATH) {
        Ok(init) => init,
        Err(err) => {
            log::info!("Not merging /etc: {err:#}.");
            return Ok(());
        }
    };
    let Ok(toplevel) = verify_init_is_nixos(SYSROOT_PATH, &init) else {
        log::info!(
            "{} is not a NixOS system, not merging /etc.",
            init.display()
        );
        return Ok(());
    };
    let config = Config::from_toplevel(&toplevel, SYSROOT_PATH)?;
    let Some(etc) = config.etc_confext else {
        log::info!(
            "{} has no /etc image, not merging /etc.",
            toplevel.display()
        );
        return Ok(());
    };

    prepare(
        SYSROOT_PATH,
        Path::new(&format!("{SYSROOT_PATH}/etc")),
        &etc,
    )
}

/// Entrypoint for the `etc-confext-activate` binary.
///
/// Migrates the merged `/etc` of the running system to the image of the toplevel, unless it has
/// already been merged. This runs on every activation, including the one of `nixos-enter`.
///
/// Usage: `etc-confext-activate <systemd-confext> <toplevel>`
pub fn etc_confext_activate() -> Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        bail!("Usage: {} <systemd-confext> <toplevel>", args[0]);
    }

    let config = Config::from_toplevel(&args[2], "/")?;
    let Some(etc) = config.etc_confext else {
        bail!("{} has no /etc image", args[2]);
    };

    activate(&args[1], &args[2], &etc)
}

fn activate(systemd_confext: &str, toplevel: &str, etc: &EtcConfext) -> Result<()> {
    // At boot, the initrd has merged the image of the generation that was booted already. A
    // refresh would find a change anyway, since the mount id systemd records for the image changes
    // across switch-root, and take /etc apart in the middle of the boot.
    if Path::new(MERGED_MARKER).exists()
        && current_image(&etc.name).as_deref() == Some(Path::new(&etc.image))
    {
        log::info!("/etc is up to date.");
        return Ok(());
    }

    log::info!("Merging /etc...");

    let submounts = unmount_legacy_overlay()?;

    let underlying = UnderlyingEtc::open()?;
    prepare("", &underlying.path, etc)?;

    let mut refresh = Command::new(systemd_confext);
    // There is no service manager to reload in a chroot, as under nixos-enter, and asking for it
    // fails the merge.
    if !Path::new("/run/systemd/system").is_dir() {
        refresh.arg("--no-reload");
    }
    let refresh = run(refresh
        .args(&etc.flags)
        .arg("refresh")
        // The os-release of the new generation is in its image, which is not merged yet.
        .env("SYSTEMD_OS_RELEASE", format!("{toplevel}/etc/os-release")));

    if !submounts.is_empty() {
        restore_submounts(&submounts);
    }

    refresh.context(
        "Failed to merge /etc; the system is running without the files NixOS manages there until \
         this is fixed or the machine reboots",
    )
}

/// The directory below the merged `/etc`, which is the upper layer of the overlay when writes are
/// routed to `/etc`.
///
/// It is reached through a clone of the root mount without anything mounted on top of it, so that
/// it can be prepared without unmerging `/etc`. The clone is detached, so it is visible to nobody
/// else, and goes away with the file descriptor.
struct UnderlyingEtc {
    _root: OwnedFd,
    path: PathBuf,
}

impl UnderlyingEtc {
    fn open() -> Result<Self> {
        let root = open_tree(
            CWD,
            "/",
            OpenTreeFlags::OPEN_TREE_CLONE | OpenTreeFlags::OPEN_TREE_CLOEXEC,
        )
        .context("Failed to clone the root mount")?;
        let path = PathBuf::from(format!("/proc/self/fd/{}/etc", root.as_raw_fd()));
        Ok(Self { _root: root, path })
    }
}

/// The image systemd-confext is currently pointed at, if any.
fn current_image(name: &str) -> Option<PathBuf> {
    let run_confexts = Path::new(RUN_CONFEXTS);
    fs::read_link(run_confexts.join(format!("{name}.raw")))
        .or_else(|_| fs::read_link(run_confexts.join(name)))
        .ok()
}

/// Prepare a root for merging the image into it.
///
/// `root` is the prefix of the tree to prepare, empty for the running system. `underlying_etc` is
/// the directory the image is merged on top of, which the merged `/etc` hides.
fn prepare(root: &str, underlying_etc: &Path, etc: &EtcConfext) -> Result<()> {
    migrate_legacy_overlay(root)?;

    create_dir_all(underlying_etc)?;

    // nixos-enter refuses a root without this tag, and looks for it before anything is merged, so
    // the image carrying it is not enough.
    let tag = underlying_etc.join("NIXOS");
    if !tag.exists() {
        File::create(&tag).with_context(|| format!("Failed to create {}", tag.display()))?;
    }

    setup_routing_directory(root, etc.mutable_directory.as_deref())?;
    install_image(root, etc)?;
    remove_symlink_farm(underlying_etc)?;

    // A file deleted from the merged /etc leaves a whiteout in the upper layer. For the paths the
    // image provides, that would hide what NixOS manages from every later generation, so it is
    // dropped. Anything else in the upper layer is the admin's.
    if let Some(upper) = &etc.upper_directory {
        let upper = if upper == "/etc" {
            underlying_etc.to_path_buf()
        } else {
            PathBuf::from(format!("{root}{upper}"))
        };
        clear_whiteouts(&upper, Path::new(&format!("{root}{}", etc.targets)))?;
    }

    Ok(())
}

/// Set up the write routing directory the mutability mode asks for.
///
/// It has to be in place before the initrd merges `/etc`, which is why this is not left to
/// anything that runs after switch-root. Pointing it at `/etc` is what makes the underlying `/etc`
/// the upper layer of the overlay. systemd only ever looks at [`ROUTING_DIRECTORY`], so it is
/// either that symlink, a directory of its own, or absent.
fn setup_routing_directory(root: &str, target: Option<&str>) -> Result<()> {
    let routing = PathBuf::from(format!("{root}{ROUTING_DIRECTORY}"));
    let is_symlink = is_symlink(&routing);

    match target {
        None | Some(ROUTING_DIRECTORY) => {
            // A symlink here is ours to replace, a directory holds writes.
            if is_symlink {
                fs::remove_file(&routing)
                    .with_context(|| format!("Failed to remove {}", routing.display()))?;
            }
            if target.is_some() {
                create_dir_all(&routing)?;
            }
        }
        Some("/etc") => {
            if routing.is_dir() && !is_symlink {
                log::warn!(
                    "{} is a directory, not routing writes to /etc.",
                    routing.display()
                );
            } else {
                if let Some(parent) = routing.parent() {
                    create_dir_all(parent)?;
                }
                atomic_symlink("/etc", &routing)?;
            }
        }
        Some(target) => {
            bail!("Cannot route writes to {target}, only to /etc or {ROUTING_DIRECTORY}")
        }
    }

    Ok(())
}

/// Point the search directory at the image. Directory images are installed under their bare
/// name, disk images with a `.raw` suffix.
///
/// `/run` is not prefixed with the root, since the initrd shares its own with the system it is
/// preparing.
fn install_image(root: &str, etc: &EtcConfext) -> Result<()> {
    let name = &etc.name;
    let (link, stale) = if Path::new(&format!("{root}{}", etc.image)).is_dir() {
        (name.clone(), format!("{name}.raw"))
    } else {
        (format!("{name}.raw"), name.clone())
    };

    let run_confexts = Path::new(RUN_CONFEXTS);
    create_dir_all(run_confexts)?;
    remove_all(&run_confexts.join(stale))?;
    atomic_symlink(&etc.image, run_confexts.join(link))
}

/// Remove the symlink farm the classic `/etc` activation leaves behind in `etc`.
///
/// With writes routed to `/etc` it lives in the upper layer, where it would shadow the image for
/// good, and below the image it would still show where the image has nothing.
///
/// TODO: remove this once setup-etc.pl, which builds the symlink farm, is gone, and there is no
/// classic `/etc` left to migrate from.
fn remove_symlink_farm(etc: &Path) -> Result<()> {
    if !is_symlink(&etc.join("static")) {
        return Ok(());
    }

    log::info!("Migrating /etc to a configuration extension image...");

    // The files the classic activation copied rather than linked.
    if let Ok(clean) = fs::read_to_string(etc.join(".clean")) {
        for copied in clean.lines().filter(|line| !line.is_empty()) {
            remove_all(&etc.join(copied))?;
        }
    }
    remove_static_symlinks(etc, &etc.join("nixos"))?;
    remove_all(&etc.join("static"))?;
    remove_all(&etc.join(".clean"))
}

/// Recursively remove symlinks into `/etc/static` below `directory`, leaving `skip` alone.
fn remove_static_symlinks(directory: &Path, skip: &Path) -> Result<()> {
    let entries = fs::read_dir(directory)
        .with_context(|| format!("Failed to read directory {}", directory.display()))?;

    for entry in entries {
        let entry =
            entry.with_context(|| format!("Failed to read entry in {}", directory.display()))?;
        let path = entry.path();
        let file_type = entry
            .file_type()
            .with_context(|| format!("Failed to stat {}", path.display()))?;

        if file_type.is_dir() && path != skip {
            remove_static_symlinks(&path, skip)?;
        } else if file_type.is_symlink()
            && fs::read_link(&path).is_ok_and(|target| target.starts_with("/etc/static/"))
        {
            remove_all(&path)?;
        }
    }

    Ok(())
}

/// Clear whiteouts and opaque markers in `upper` for every path listed in `targets`.
fn clear_whiteouts(upper: &Path, targets: &Path) -> Result<()> {
    let targets = fs::read_to_string(targets)
        .with_context(|| format!("Failed to read {}", targets.display()))?;

    for target in targets.lines().filter(|line| !line.is_empty()) {
        let path = upper.join(target);
        let Ok(metadata) = fs::symlink_metadata(&path) else {
            continue;
        };
        if is_whiteout(&metadata) {
            fs::remove_file(&path)
                .with_context(|| format!("Failed to remove whiteout {}", path.display()))?;
        } else if metadata.is_dir() {
            remove_opaque_xattr(&path);
        }
    }

    Ok(())
}

/// Carry the writes of the composefs `/etc` of the earlier `system.etc.overlay` over.
///
/// That kept its writes in `/.rw-etc/upper`, and the underlying `/etc` hidden below the overlay.
/// Make a copy of the upper layer the underlying `/etc`, which is what takes the writes now, so
/// that what was in `/etc` before still is. The hidden directory is kept next to it, and the upper
/// layer itself is left alone for a rollback.
fn migrate_legacy_overlay(root: &str) -> Result<()> {
    let legacy = PathBuf::from(format!("{root}/{LEGACY_OVERLAY}"));
    let upper = legacy.join("upper");
    let marker = legacy.join("migrated-to-confext");
    if !upper.is_dir() || marker.exists() {
        return Ok(());
    }

    log::info!("Migrating the upper layer of the /etc overlay to /etc...");

    let etc = PathBuf::from(format!("{root}/etc"));
    let hidden = legacy.join("etc.pre-confext");
    remove_all(&hidden)?;
    if fs::symlink_metadata(&etc).is_ok()
        && let Err(err) = fs::rename(&etc, &hidden)
    {
        log::warn!(
            "Failed to move {} out of the way, not migrating {}: {err}.",
            etc.display(),
            upper.display()
        );
        return Ok(());
    }

    copy_upper_layer(&upper, &etc)?;
    File::create(&marker).with_context(|| format!("Failed to create {}", marker.display()))?;

    Ok(())
}

/// Copy an overlayfs upper layer, keeping modes, ownership and modification times, but none of
/// the overlayfs metadata.
///
/// A whiteout hid a file the composefs image provided, and is cleared for the paths the image
/// provides anyway. A metacopy file only carries the metadata of a file whose data is in that
/// image, which is gone.
fn copy_upper_layer(source: &Path, destination: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(source)
        .with_context(|| format!("Failed to stat {}", source.display()))?;
    create_dir_all(destination)?;
    copy_metadata(&metadata, destination)?;

    let entries = fs::read_dir(source)
        .with_context(|| format!("Failed to read directory {}", source.display()))?;
    for entry in entries {
        let entry =
            entry.with_context(|| format!("Failed to read entry in {}", source.display()))?;
        let path = entry.path();
        let target = destination.join(entry.file_name());
        let metadata = fs::symlink_metadata(&path)
            .with_context(|| format!("Failed to stat {}", path.display()))?;
        let file_type = metadata.file_type();

        if file_type.is_dir() {
            copy_upper_layer(&path, &target)?;
        } else if file_type.is_symlink() {
            let link = fs::read_link(&path)
                .with_context(|| format!("Failed to read symlink {}", path.display()))?;
            unix::fs::symlink(&link, &target)
                .with_context(|| format!("Failed to create symlink {}", target.display()))?;
            unix::fs::lchown(&target, Some(metadata.uid()), Some(metadata.gid()))
                .with_context(|| format!("Failed to change owner of {}", target.display()))?;
        } else if file_type.is_file() && !has_xattr(&path, OVERLAY_METACOPY_XATTR) {
            fs::copy(&path, &target).with_context(|| {
                format!("Failed to copy {} to {}", path.display(), target.display())
            })?;
            copy_metadata(&metadata, &target)?;
            File::options()
                .write(true)
                .open(&target)
                .and_then(|file| file.set_modified(metadata.modified()?))
                .with_context(|| format!("Failed to set mtime of {}", target.display()))?;
        } else if !is_whiteout(&metadata) {
            log::warn!(
                "Not migrating {}, which is not a regular file.",
                path.display()
            );
        }
    }

    Ok(())
}

/// Give `path` the ownership and mode `metadata` describes. The mode comes last, since changing
/// the owner clears setuid and setgid bits.
fn copy_metadata(metadata: &Metadata, path: &Path) -> Result<()> {
    unix::fs::chown(path, Some(metadata.uid()), Some(metadata.gid()))
        .with_context(|| format!("Failed to change owner of {}", path.display()))?;
    fs::set_permissions(path, Permissions::from_mode(metadata.mode() & 0o7777))
        .with_context(|| format!("Failed to change mode of {}", path.display()))
}

/// Take down the composefs `/etc` of the earlier `system.etc.overlay`, so that the underlying
/// `/etc` is reachable.
///
/// The mounts on top of it, like the one systemd puts over `/etc/machine-id` when `/etc` is
/// read-only, are set aside, to be put on top of the merged `/etc` again with
/// [`restore_submounts`].
fn unmount_legacy_overlay() -> Result<Vec<Submount>> {
    if Path::new(MERGED_MARKER).exists() {
        return Ok(Vec::new());
    }
    let mounts = MountInfo::read()?;
    if !mounts
        .find("/etc")
        .is_some_and(|etc| etc.super_options.contains("nixos-etc-metadata"))
    {
        return Ok(Vec::new());
    }

    let submounts = set_aside_submounts(&mounts)?;

    log::info!("Unmounting the /etc overlay...");
    run(Command::new("umount").args(["--lazy", "--recursive", "/etc"]))?;

    for mount in &mounts.0 {
        if mount.fs_type == "erofs"
            && (mount.target == "/run/nixos-etc-metadata"
                || mount.target.starts_with("/run/nixos-etc-metadata."))
        {
            run(Command::new("umount").args(["--lazy", &mount.target]))?;
            fs::remove_dir(&mount.target).ok();
        }
    }

    Ok(submounts)
}

const SUBMOUNTS_ASIDE: &str = "/run/nixos-etc-confext/submounts";

/// A mount below `/etc`, bound to a path outside of it.
struct Submount {
    target: String,
    aside: PathBuf,
}

/// Bind every mount below `/etc` to a path outside of it, parents before their children.
fn set_aside_submounts(mounts: &MountInfo) -> Result<Vec<Submount>> {
    let mut targets: Vec<&str> = Vec::new();
    for mount in &mounts.0 {
        if mount.target.starts_with("/etc/") && !targets.contains(&mount.target.as_str()) {
            targets.push(&mount.target);
        }
    }

    let mut submounts = Vec::new();
    for (i, target) in targets.into_iter().enumerate() {
        let aside = Path::new(SUBMOUNTS_ASIDE).join(i.to_string());
        create_dir_all(SUBMOUNTS_ASIDE)?;
        if Path::new(target).is_dir() {
            create_dir_all(&aside)?;
        } else {
            File::create(&aside)
                .with_context(|| format!("Failed to create {}", aside.display()))?;
        }
        run(Command::new("mount").arg("--bind").arg(target).arg(&aside))?;
        log::info!("Set aside the mount on {target}.");
        submounts.push(Submount {
            target: target.to_string(),
            aside,
        });
    }

    Ok(submounts)
}

/// Bind the mounts set aside by [`set_aside_submounts`] over the merged `/etc` again.
fn restore_submounts(submounts: &[Submount]) {
    for submount in submounts {
        let target = Path::new(&submount.target);
        if !target.exists() {
            let created = if submount.aside.is_dir() {
                create_dir_all(target)
            } else {
                File::create(target)
                    .map(|_| ())
                    .with_context(|| format!("Failed to create {}", target.display()))
            };
            if let Err(err) = created {
                log::warn!(
                    "Not restoring the mount on {}, which the new /etc lacks: {err:#}.",
                    target.display()
                );
                continue;
            }
        }
        if let Err(err) = run(Command::new("mount")
            .arg("--bind")
            .arg(&submount.aside)
            .arg(target))
        {
            log::warn!(
                "Failed to restore the mount on {}: {err:#}.",
                target.display()
            );
        }
    }

    for submount in submounts.iter().rev() {
        release_aside(&submount.aside);
    }
    remove_aside_directory(Path::new(SUBMOUNTS_ASIDE));
}

/// Unmount a path set aside and remove it, but never recursively: should the unmount fail, it
/// still has a mount of someone else's below it.
fn release_aside(aside: &Path) {
    if let Err(err) = run(Command::new("umount").arg(aside)) {
        log::warn!("{err:#}.");
        return;
    }
    let removed = if aside.is_dir() {
        fs::remove_dir(aside)
    } else {
        fs::remove_file(aside)
    };
    if let Err(err) = removed {
        log::warn!("Failed to remove {}: {err}.", aside.display());
    }
}

/// Remove a directory paths were set aside in, and the one containing it, if they are empty.
fn remove_aside_directory(directory: &Path) {
    fs::remove_dir(directory).ok();
    if let Some(parent) = directory.parent() {
        fs::remove_dir(parent).ok();
    }
}

/// An entry of `/proc/self/mountinfo`, see `proc_pid_mountinfo(5)`.
#[derive(Debug)]
struct Mount {
    target: String,
    fs_type: String,
    super_options: String,
}

struct MountInfo(Vec<Mount>);

impl MountInfo {
    fn read() -> Result<Self> {
        let mountinfo = fs::read_to_string("/proc/self/mountinfo")
            .context("Failed to read /proc/self/mountinfo")?;
        Self::parse(&mountinfo)
    }

    fn parse(s: &str) -> Result<Self> {
        let mut mounts = Vec::new();
        for line in s.lines() {
            let (mount, superblock) = line
                .split_once(" - ")
                .with_context(|| format!("Failed to parse mountinfo line: {line}"))?;
            let mount: Vec<&str> = mount.split(' ').collect();
            let superblock: Vec<&str> = superblock.split(' ').collect();
            if mount.len() < 6 || superblock.len() < 3 {
                bail!("Failed to parse mountinfo line: {line}");
            }
            mounts.push(Mount {
                target: unescape(mount[4]),
                fs_type: superblock[0].to_string(),
                super_options: superblock[2].to_string(),
            });
        }
        Ok(Self(mounts))
    }

    /// The topmost mount at `target`.
    fn find(&self, target: &str) -> Option<&Mount> {
        self.0.iter().rev().find(|m| m.target == target)
    }
}

/// Undo the octal escapes of `proc_pid_mountinfo(5)`.
fn unescape(s: &str) -> String {
    let mut out = Vec::with_capacity(s.len());
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\'
            && let Some(code) = s
                .get(i + 1..i + 4)
                .and_then(|octal| u8::from_str_radix(octal, 8).ok())
        {
            out.push(code);
            i += 4;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn run(command: &mut Command) -> Result<()> {
    let status = command
        .status()
        .with_context(|| format!("Failed to run {command:?}"))?;
    if !status.success() {
        bail!("{command:?} failed with {status}");
    }
    Ok(())
}

fn create_dir_all(path: impl AsRef<Path>) -> Result<()> {
    DirBuilder::new()
        .recursive(true)
        .mode(0o755)
        .create(&path)
        .with_context(|| format!("Failed to create directory {}", path.as_ref().display()))
}

/// Remove a path of any type, if it exists.
fn remove_all(path: &Path) -> Result<()> {
    let result = match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_dir() => fs::remove_dir_all(path),
        Ok(_) => fs::remove_file(path),
        Err(err) if err.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(err),
    };
    result.with_context(|| format!("Failed to remove {}", path.display()))
}

fn is_symlink(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok_and(|metadata| metadata.file_type().is_symlink())
}

/// Whether a file is an overlayfs whiteout, a character device with device number 0/0.
fn is_whiteout(metadata: &Metadata) -> bool {
    metadata.file_type().is_char_device() && metadata.rdev() == 0
}

fn has_xattr(path: &Path, name: &str) -> bool {
    matches!(xattr::get(path, name), Ok(Some(_)))
}

/// Remove the opaque marker from a directory, if it has one.
fn remove_opaque_xattr(path: &Path) {
    // Check first instead of removing unconditionally: lremovexattr(2) reports a missing attribute
    // as ENODATA, which std does not map to a stable io::ErrorKind.
    if !has_xattr(path, OVERLAY_OPAQUE_XATTR) {
        return;
    }
    match xattr::remove(path, OVERLAY_OPAQUE_XATTR) {
        Ok(()) => log::info!("Cleared stale opaque marker from {}.", path.display()),
        // Don't abort over this; the worst case is that some NixOS-managed files stay hidden.
        Err(err) => log::warn!(
            "Failed to remove {OVERLAY_OPAQUE_XATTR} from {}: {err}.",
            path.display()
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use indoc::indoc;
    use tempfile::tempdir;

    #[test]
    fn test_mountinfo_parsing() -> Result<()> {
        let mounts = MountInfo::parse(indoc! {r"
            22 1 0:21 / / rw,relatime shared:1 - ext4 /dev/vda rw
            23 22 0:22 / /etc rw,relatime - overlay overlay rw,lowerdir=/run/nixos-etc-metadata::/nix/store/x-etc-lowerdir
            24 23 0:23 / /etc/resolv\040conf rw shared:5 - tmpfs tmpfs rw
        "})?;

        assert!(mounts.find("/etc").is_some_and(
            |m| m.fs_type == "overlay" && m.super_options.contains("nixos-etc-metadata")
        ));
        assert!(
            mounts
                .find("/etc/resolv conf")
                .is_some_and(|m| m.fs_type == "tmpfs")
        );
        assert!(mounts.find("/var").is_none());
        Ok(())
    }

    #[test]
    fn test_remove_symlink_farm() -> Result<()> {
        let root = tempdir()?;
        let etc = root.path().join("etc");
        fs::create_dir_all(etc.join("ssh"))?;
        fs::create_dir_all(etc.join("nixos"))?;
        unix::fs::symlink("/nix/store/x-etc/etc", etc.join("static"))?;
        unix::fs::symlink("/etc/static/ssh/sshd_config", etc.join("ssh/sshd_config"))?;
        unix::fs::symlink("/etc/static/nixos/kept", etc.join("nixos/kept"))?;
        unix::fs::symlink("/elsewhere", etc.join("local"))?;
        fs::write(etc.join("sudoers"), "copied")?;
        fs::write(etc.join(".clean"), "sudoers\n")?;

        remove_symlink_farm(&etc)?;

        assert!(!is_symlink(&etc.join("static")));
        assert!(!is_symlink(&etc.join("ssh/sshd_config")));
        assert!(!etc.join("sudoers").exists());
        assert!(!etc.join(".clean").exists());
        assert!(is_symlink(&etc.join("nixos/kept")));
        assert!(is_symlink(&etc.join("local")));
        Ok(())
    }

    #[test]
    fn test_migrate_legacy_overlay() -> Result<()> {
        let root = tempdir()?;
        let root_str = root.path().to_str().unwrap();
        let upper = root.path().join(".rw-etc/upper");
        fs::create_dir_all(upper.join("ssh"))?;
        fs::write(upper.join("ssh/key"), "key")?;
        fs::set_permissions(upper.join("ssh/key"), Permissions::from_mode(0o600))?;
        unix::fs::symlink("/somewhere", upper.join("link"))?;
        fs::create_dir_all(root.path().join("etc"))?;
        fs::write(root.path().join("etc/hidden"), "hidden")?;

        migrate_legacy_overlay(root_str)?;

        let etc = root.path().join("etc");
        assert_eq!(fs::read_to_string(etc.join("ssh/key"))?, "key");
        assert_eq!(
            fs::metadata(etc.join("ssh/key"))?.permissions().mode() & 0o7777,
            0o600
        );
        assert_eq!(fs::read_link(etc.join("link"))?, Path::new("/somewhere"));
        assert!(!etc.join("hidden").exists());
        assert!(root.path().join(".rw-etc/etc.pre-confext/hidden").exists());
        assert!(upper.join("ssh/key").exists());

        // It only happens once.
        fs::write(upper.join("again"), "again")?;
        migrate_legacy_overlay(root_str)?;
        assert!(!etc.join("again").exists());
        Ok(())
    }

    #[test]
    fn test_setup_routing_directory() -> Result<()> {
        let root = tempdir()?;
        let root_str = root.path().to_str().unwrap();
        let routing = PathBuf::from(format!("{root_str}{ROUTING_DIRECTORY}"));

        setup_routing_directory(root_str, Some("/etc"))?;
        assert_eq!(fs::read_link(&routing)?, Path::new("/etc"));

        setup_routing_directory(root_str, None)?;
        assert!(fs::symlink_metadata(&routing).is_err());

        setup_routing_directory(root_str, Some(ROUTING_DIRECTORY))?;
        assert!(routing.is_dir() && !is_symlink(&routing));

        // A directory holds writes and is left alone.
        setup_routing_directory(root_str, Some("/etc"))?;
        assert!(routing.is_dir() && !is_symlink(&routing));

        assert!(setup_routing_directory(root_str, Some("/persist/etc")).is_err());
        Ok(())
    }
}

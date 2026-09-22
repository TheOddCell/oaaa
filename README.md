# oaaa
very odd and atomic

build a bootable system with `./build-all`, and build individual system images with `./mkoaaafs [extra-packages]`

bootstrap script available at https://ba.sh/rcnC

## Architecture

oaaa is a semi-mutable atomic distro. The root filesystem is an overlayfs:
a read-only `system*.erofs` image (`lowerdir`) plus a writable
`upperdir` on a single ext4 data partition. That data partition (labeled
`OAAA_DATA`, mounted at `/data` pre-boot / `/oaaa` post-boot) is the only
partition that actually matters - everything else (the erofs image, the ESP
contents) is disposable and regenerable.

Boot is two-stage, via kexec:
- **Stage 1** (the initramfs on the ESP): finds `OAAA_DATA`, handles
  pending factory/cleanup resets, optionally launches `oaaat`, then builds
  a one-off **stage 2** initramfs in `/tmp` with kernel modules baked
  directly into it, and kexecs into the kernel embedded in the erofs image.
- **Stage 2** (the dynamically-built initramfs from stage 1): loads the
  embedded modules, mounts the erofs image + overlay, and `switch_root`s
  into the real system.

---

## Build scripts

### `build-all`
Full build: kernel + initramfs + system image, in one command.
```
sudo ./build-all [--skip-kernel] [--skip-initramfs] [--skip-image]
```
Runs `mkoaaakernel`, `mkoaaainitramfs`, and `mkoaaafs` in order (any of
which can be skipped), then renames the resulting `system.erofs` to
`system-<date>.erofs`. Prints follow-up commands for install/test/ISO at
the end.

### `mkoaaakernel`
Builds the oaaa kernel from source.
```
sudo ./mkoaaakernel
```
No arguments. Downloads/extracts the kernel tarball (version pinned in the
script) next to itself if not already present, applies `kernel.config`
(must exist next to the script), builds `bzImage` with all available
cores, and copies the result out as `vmlinuz-oaaa`.

### `mkoaaainitramfs`
Builds the fully static initramfs used for both stage 1 and stage 2 boot.
```
sudo ./mkoaaainitramfs
```
No arguments. Requires a Go toolchain on the host (for `gum`); everything
else (busybox, zlib, zstd, kexec-tools) is compiled from source, fully
static, nothing borrowed from the host. Assembles `busybox`, `kexec`,
`zstd`, `gum`, this repo's `initramfs-init` (as `/init`), `oaaat`,
`reisub`, `boot-to-oaaat`, and `oaaa-update-grub` into `initramfs-oaaa.img`.
Intermediate build artifacts are cached under `initramfs-build/` and
`initramfs-root/` so re-runs are incremental.

### `mkoaaafs [extra-packages...]`
Builds a system image (`system.erofs`) from a fresh Arch install.
```
sudo ./mkoaaafs [pkg1 pkg2 ...]
```
Any arguments are passed through as extra AUR packages installed via `yay`
during the build (on top of the fixed pacstrap package list baked into the
script). Sets up an `oobe` user with a first-login setup script (see
"OOBE flow" below) baked into `.bashrc`, enables NetworkManager/gpm, then
packs the result into `system.erofs` with `mkfs.erofs -z zstd`.

### `mkoaaaiso [erofs] [initramfs] [vmlinuz]`
Builds a live/rescue ISO (via `mkarchiso`) that bundles `oaaa-install`
plus the three prebuilt artifacts, so booting the ISO and running
`./oaaa-install` is the entire install procedure with no network needed.
```
sudo ./mkoaaaiso [system.erofs] [initramfs-oaaa.img] [vmlinuz-oaaa]
```
All three arguments are optional and default to those filenames next to
the script. Requires `archiso` (for `mkarchiso`) on the build host.

### `clean [--kernel] [--initramfs] [--image] [--disk] [--iso] [--all]`
Removes build artifacts.
```
sudo ./clean [--kernel] [--initramfs] [--image] [--disk] [--iso] [--all]
```
- `--kernel`: removes `vmlinuz-oaaa`, extracted kernel source, and the
  downloaded tarball
- `--initramfs`: removes `initramfs-build/`, `initramfs-root/`,
  `initramfs-oaaa.img`
- `--image`: unmounts any stale `oaaa_rootfs` mounts, removes
  `oaaa_rootfs/` and all `system*.erofs`
- `--disk`: detaches any loop device using `oaaa-test.img` and removes it
- `--iso`: removes the `iso/` directory and any `*.iso` files
- `--all`: does all of the above

Running with no flags at all prints usage and exits (this is the one
script here that refuses to silently no-op).

---

## Install scripts

### `oaaa-bootstrap [--build]`
Meant to be run from a live Arch ISO. Sets up everything needed to either
install a prebuilt oaaa (default) or build oaaa from source (`--build`).
```
./oaaa-bootstrap [--build]
```
Remounts the archiso cowspace bigger, installs install-only deps (or
install+build deps with `--build`), clones this repo, and either leaves
you ready to run `./build-all` (`--build`) or downloads the three
prebuilt artifacts (kernel/initramfs/erofs) and leaves you ready to run
`oaaa-install`. Refuses to run anywhere that isn't a live Arch ISO.

### `oaaa-install [--download] <disk> [system.erofs]`
Installs oaaa onto a target disk. **Destructive** - wipes the target disk.
```
sudo ./oaaa-install /dev/sdX system-2026-06-21.erofs
sudo ./oaaa-install --download /dev/sdX
```
- `--download`: fetches `system.erofs`, `initramfs-oaaa.img`, and
  `vmlinuz-oaaa` from `files.obsidianos.xyz` first, instead of expecting
  them to already exist next to the script
- `<disk>`: target block device (required)
- `[system.erofs]`: erofs image to install (defaults to `system.erofs`
  next to the script; ignored/unused in `--download` mode since that
  mode always fetches fresh)

Partitions the disk as ESP (512M FAT32) + `OAAA_DATA` (rest, ext4),
formats, sets up the `images/` and `overlay/{upper,work}` layout on the
data partition, copies the erofs image and initramfs, runs
`grub-install`, and writes the standard `grub.cfg` (see "GRUB menu"
below). Uses the pre-built `vmlinuz-oaaa` next to the script if present,
otherwise extracts a kernel from the erofs image itself.

### `oaaa-qemu [--fresh] [--size 12G] [--nvme]`
Creates a test disk image and launches it in QEMU, for testing without
touching real hardware.
```
sudo ./oaaa-qemu [--fresh] [--size 30G] [--nvme]
```
- `--fresh`: recreate the test disk from scratch even if
  `oaaa-test.img` already exists (normally it's reused across runs)
- `--size <size>`: disk size for a freshly created image (default `30G`,
  only takes effect together with `--fresh` or on first creation)
- `--nvme`: attach the test disk as a virtual NVMe device instead of
  virtio-blk (useful for testing the nvme module-loading path)

Auto-detects the most recent `system*.erofs` next to the script, installs
it onto the test disk via `oaaa-install` if the disk doesn't exist yet,
finds OVMF firmware on the host, and launches `qemu-system-x86_64` with
KVM, 4G RAM, 4 cores, and a GTK display + serial-on-stdio.

---

## Runtime tools

These ship inside the initramfs (`/bin/...`) and, for `oaaat`, are also
kept in sync onto the data partition (`/data/oaaat`) every stage-2 boot so
the booted system always has the latest version.

### `oaaat`
Interactive recovery/maintenance TUI (built on `gum choose`). Available
from GRUB's "OAAAT" entry, from a booted system via `sudo oaaat` (it
re-execs the copy on `/oaaa` if run from a booted system, so it's always
using the system's current version), or via `boot-to-oaaat`.

Menu options (which ones show up depends on state - see below):
- **Rollback**: pick an older snapshot in `images/` and mark it for use
  on next boot (`touch`es it so it becomes the newest-by-mtime image).
  Hidden if there's only one image.
- **Delete Snapshot**: delete an old snapshot from `images/`. Hidden if
  there's only one image. When run from a booted system, excludes
  whichever image is currently loaded (via `/sys/block/loop0/loop/backing_file`).
- **Factory Reset**: wipes `/data/overlay/upper` **and** `/data/plugins`
  entirely on next boot (after a confirmation prompt) - deletes all user
  data, unrecoverable.
- **Cleanup Reset**: wipes everything under `/data/overlay/upper` on next
  boot *except* entries literally named `home` and `etc` (after a
  confirmation prompt). Note this does **not** restore `home`/`etc` from
  the erofs lower layer - it just skips deleting whatever currently
  exists there. If those paths were already destroyed, the system comes
  back as an unconfigured fresh install, not your prior configuration.
- **Download System Update**: downloads a new `system-<date>.erofs` into
  `images/` from `files.obsidianos.xyz`. Only shown when running from a
  fully booted system.
- **Update OAAA**: downloads a fresh `initramfs-oaaa.img` and
  `vmlinuz-oaaa` from `files.obsidianos.xyz` onto the ESP (and copies the
  initramfs onto the data partition too). Only shown when running from a
  fully booted system. Downloads go to a `.part` file first and are only
  renamed into place once the download succeeds, so an interrupted
  update can't leave a corrupt file under the real name.
- **Reboot To OAAAT**: schedules `oaaat` to run automatically on the very
  next boot (writes `/data/oaaa-command-stage1`), then reboots. Only
  shown when running from a fully booted system.
- **Enable/Disable mounting of /oaaa and /boot**: toggles
  `/data/oaaa-nomount` - see "Data partition marker files" below.
- **Reboot**: runs the REISUB sequence (see `reisub` below).
- **Exit**: quits `oaaat`.

### `boot-to-oaaat`
One-shot: schedules `oaaat` to run automatically on the next boot, then
immediately reboots. Must be run as root from a booted system (`/oaaa`
must exist).
```
sudo boot-to-oaaat
```
Equivalent to `oaaat`'s own "Reboot To OAAAT" menu option, but callable
directly without going through the menu.

### `reisub [pid-to-spare...]`
Triggers a manual emergency REISUB reboot (unRaw keyboard, tErminate,
kIll, Sync, Unmount/remount-ro, reBoot) via sysrq + `killall5`, for a
clean reboot when a normal `reboot` won't work.
```
reisub [extra killall5 args, e.g. -o <pid>]
```
Any arguments are passed straight through to both `killall5` calls (its
own process-exclude flag), letting you spare a specific process that
sysrq's term/kill keys have no equivalent for.

### `oaaa-update-grub`
Regenerates `grub.cfg` on the ESP of the **currently booted** oaaa
system, without repartitioning, reformatting, or rerunning
`grub-install`. For picking up grub.cfg changes on a machine that was
installed before they existed.
```
sudo oaaa-update-grub
```
No arguments. Refuses to run anywhere except a fully booted oaaa system
(checks for `/oaaa`).

---

## GRUB menu

Every entry boots the same kernel/initramfs pair with different
`oaaa.*` kernel command-line parameters appended (see below):

- **OAAA** - normal boot, no extra parameters
- **OAAAT** - boots straight into the `oaaat` recovery tool
  (`oaaa.oaaat=1`)
- **Shells > Shell (Stage 1) > setsid+cttyhack** - drop to a stage 1
  rescue shell (`oaaa.shell=1`)
- **Shells > Shell (Stage 1) > disable cttyhack** - same, but without
  the `cttyhack` wrapper (`oaaa.shell=1 oaaa.cttyhack=0`)
- **Shells > Shell (Stage 2) > setsid+cttyhack** - drop to a stage 2
  rescue shell, after modules are loaded and OAAA_DATA/ESP are mounted
  (`oaaa.shell=2`)
- **Shells > Shell (Stage 2) > disable cttyhack** - same, without
  `cttyhack` (`oaaa.shell=2 oaaa.cttyhack=0`)
- **Shells > Booted Shell** - boot all the way through overlay setup and
  `switch_root` into `/bin/sh` instead of `/sbin/init`
  (`oaaa.shell=3`)

---

## Kernel command-line parameters (`oaaa.*`)

All read from `/proc/cmdline` by `initramfs-init`:

| Parameter | Effect |
|---|---|
| `oaaa.oaaat=1` | Stage 1 launches `oaaat` interactively instead of continuing to boot. |
| `oaaa.shell=1` | Drop to a stage 1 shell instead of continuing to kexec into stage 2. |
| `oaaa.shell=2` | Drop to a stage 2 shell after modules are loaded, before mounting the overlay. |
| `oaaa.shell=3` | Boot all the way through overlay setup, then `switch_root` into `/bin/sh` instead of `/sbin/init`. |
| `oaaa.cttyhack=0` | Use a plain `exec sh` instead of `setsid cttyhack sh` for any rescue shell/oaaat launch. |
| `oaaa.plugins=0` | Disable all `/data/plugins/*` hooks for this boot (stage1, pre2, stage2, and preboot all skipped). |
| `oaaa.stage=2` | Internal - set by stage 1's own `kexec --append` to tell the dynamically-built initramfs it's running as stage 2. Not meant to be set manually from GRUB. |

---

## Data partition marker files

These live directly on `OAAA_DATA` (`/data` pre-boot, `/oaaa` post-boot)
and are checked/consumed by `initramfs-init` and `oaaat`. Most are
one-shot (deleted once acted on); a few are persistent toggles.

- **`oaaa-factory-reset`** (one-shot) - set by oaaat's Factory Reset.
  On next stage 1 boot: deletes `overlay/upper` and `plugins/` entirely,
  then deletes itself.
- **`oaaa-cleanup`** (one-shot) - set by oaaat's Cleanup Reset. On next
  stage 1 boot: deletes everything under `overlay/upper` except `home`
  and `etc`, then deletes itself.
- **`oaaa-nomount`** (persistent toggle) - toggled by oaaat's
  Enable/Disable mounting menu item. When present, stage 2 skips
  bind-mounting `/data` to `/overlay/oaaa` and moving `/boot` to
  `/overlay/boot`, so the booted system won't have `/oaaa` or `/boot`
  available at all. Survives Factory Reset and Cleanup Reset (neither
  touches it).
- **`oaaa-command-stage1`** / **`oaaa-command-pre2`** /
  **`oaaa-command-stage2`** / **`oaaa-command-preboot`** (one-shot) - an
  arbitrary shell script to run at that specific point in the boot
  sequence, then delete. `boot-to-oaaat` and oaaat's "Reboot To OAAAT"
  both work by writing one of these (`oaaa-command-stage1`, containing a
  script that launches `oaaat` then `reisub`s).
- **`oaaa-modorder`** (persistent cache) - the module load order from
  the last successful stage 2 boot, written by stage 2 and read by
  stage 1 to seed the next boot's dynamic initramfs, so stage 2 can try
  a fast single-pass load instead of blind multi-pass retry.
- **`plugins/{stage1,pre2,stage2,preboot}/*.sh`** - drop-in scripts run
  in lexical order at the matching boot stage (see `run_plugins` in
  `initramfs-init`). Each runs in its own subshell, so a broken plugin
  can't corrupt the boot script's own state. Persistent by default (run
  every boot); a plugin that wants to run once can `rm "$0"` as its own
  last line. Deleted entirely by Factory Reset (not by Cleanup Reset).
  Globally disabled for a single boot with `oaaa.plugins=0`.
- **`images/*.erofs`** - available system snapshots; the newest by
  mtime is what actually gets booted (this is how Rollback works - it
  just `touch`es an older one).

---

## OOBE flow

`mkoaaafs` bakes a first-login setup flow into the `oobe` user's
`.bashrc` (guarded by `~/.oaaa-firstboot`, so it only runs once): asks
for a username, a user password, an admin (root) password, offers
`nmtui` for network setup, enables `plasmalogin`, renames the `oobe` account to
the chosen username everywhere (`passwd`/`shadow`/`group`/`gshadow`),
marks first-boot done, and reboots via `systemctl reboot` once
configuration is complete.

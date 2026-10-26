# MXeneOS port notes: Samsung Galaxy A22 5G (a22x, SM-A226B) on LineageOS 23.2 (Android 16)

This branch (`mxeneos/lineage-23.2`) is `loftenth-eepy/android_device_samsung_a22x` branch `lineage` at `55d4ae4485f0`
plus the small commits needed to build and boot **Android 16 / LineageOS 23.2 on the stock Android 12 vendor** of the
phone. The result boots on a real SM-A226B. Nothing in this branch is about hardening; the hardening layer
(MXeneOS core) is applied by the product makefile in `docs/mxeneos/port/`.

Everything below was learnt by building and flashing; the failure timeline is in the last section.

## Status (2026-10-26)
- Booted on a real SM-A226B, Android 16 (SDK 36.1), SELinux Enforcing, kernel 4.14.186-27218697.
- Works: Wi-Fi, audio, vibration, fingerprint (HIDL HAL up), Bluetooth on, GPS provider enabled, five camera devices listed, no crash in a full boot's logcat.
- Not tested: calls, SMS and mobile data (no SIM in the test phone), NFC, camera capture quality, long-term battery and thermals.
- Not enforced on this phone: Android 16 *local network access* rules (see "Changes outside this repository").

## Hardware and baseline this was done on
- SM-A226B, MT6833, stock firmware `A226BXXSBDZC3` (Android 12 vendor, kernel 4.14.186). Bootloader unlocked, TWRP installed.
- Non-A/B, dynamic partitions (`super` holds `system`, `odm`, `product`, `vendor`).
- The phone's own `vendor` and `odm` are kept. The sideload zip built here writes only `system`, `product` and `boot`.

## Commits on top of upstream (`55d4ae4485f0`), and why
| Commit | Change | Why |
|---|---|---|
| `b62d5f8` | Clean kernel and DTB from the Samsung OSS source, Enforcing cmdline, super size from the phone | Upstream's prebuilt kernel is a fork with KernelSU etc. This one is the Samsung drop (first commit of the fork), built from the phone's `a22x_defconfig`. `androidboot.selinux=permissive` removed. Super size read with `lpdump`. |
| `913fe2c` | `device.mk`: drop `MtkInCallService` | Module does not exist in the tree (build error). |
| `139c8ea` | `lineage_a22x.mk`: drop `PRIVATE_BUILD_DESC` | Android 16 `gen_build_prop` rejects the override (build error). |
| `5234808` | `product.prop`: drop `setupwizard.theme` | vendor/lineage already sets it (duplicate sysprop error). |
| `a88d00b` | `BoardConfig.mk`: `AB_OTA_UPDATER := false` | The phone is non-A/B; Android 16 defaults to true. |
| `fd18bb1` | `BoardConfig.mk`: `TARGET_NO_RECOVERY := true` | The prebuilt vendor has no `etc` for Lineage's recovery copy, and the zip must not write recovery anyway. |
| `25a6924` + `c66c1ff` | `ro.bpf.kver_override=5.10.239` and its revert | The override (used by LineageOS ginkgo) makes the loader choose the 5.4/5.10 BPF programs, which need helpers this 4.14 kernel lacks. Found offline, rejected, reverted. Kept in history on purpose. |

The net diff against upstream is 4 files, +11/-9 lines (`git diff 55d4ae4 c66c1ff`).

## Changes outside this repository (all a22x-only, needed to boot)
Android 16 assumes kernel 4.19+/5.4+ in the BPF networking stack, and Lineage's sepolicy conflicts with the stock Samsung
vendor. These live in forks, on branches named `mxeneos/a22x-lineage-23.2`:

| Fork (MXeneOS org) | Base | What |
|---|---|---|
| `android_packages_modules_Connectivity` | `c9f3e77952` | 3 commits. (1) `NetBpfLoad` warns instead of aborting on kernels < 4.19 / < 5.4 (same relaxation Lineage made for 5.10). The real kernel version is kept so the 4.9/4.14 program variants load. (2) `BpfHandler::initPrograms()` gates warn instead of failing; `libnetd_updatable_init` returns an error instead of `abort()`. (3) `BpfNetMaps` runs without `local_net_access_map` when it cannot be opened (the only LPM-trie map; 4.14 cannot iterate it, errno 524, which killed `system_server` every few seconds). |
| `android_system_netd` | `796eaca5` | 1 commit. `main.cpp`: no `exit(1)` when `libnetd_updatable_init` fails; netd keeps running without BPF. |
| `android_device_lineage_sepolicy` | `0a9e752` | 2 commits. Drop `genfscon iso9660 /` and `genfscon udf /` (the stock vendor labels both `vfat`) and the `vendor.camera.aux.packagelist` property rule (the vendor defines it with another type). Without this `secilc` fails in init and the phone does not boot. |

Patches of the same commits: `docs/mxeneos/patches/`. Pinned local manifest: `docs/mxeneos/local_manifest.xml`.
Effect to know about: Android 16 local network access rules are not enforced on this phone (as in TrebleDroid).

## How to build
1. LineageOS 23.2 tree (`android-16.0.0_r4` based). Add `docs/mxeneos/local_manifest.xml` to `.repo/local_manifests/`
   (it pins this device tree branch and the three forks), `repo sync`.
2. Build the kernel (below) and place `Image.gz` and `mt6833.dtb` in a `kernel/` folder as the `BoardConfig.mk` expects
   (`device/mxeneos/a22x/kernel/` in the MXeneOS layout; adjust the paths for a plain Lineage tree).
3. `source build/envsetup.sh && lunch mxeneos_a22x-bp4a-userdebug` (MXeneOS) or `lunch lineage_a22x-bp4a-userdebug` (plain Lineage),
   `export LINEAGE_BUILD=a22x`, then `m target-files-package otatools-package`. The stock `bacon` target is not used:
   it needs a recovery and rewrites the dynamic-partition layout including vendor/odm.
4. Zip: `docs/mxeneos/scripts/mkzip.py <target_files.zip> <out.zip>` (partial sideload zip; writes only system, product, boot;
   asserts device `a22x` / `SM-A226B`).
5. Preflight before flashing: `docs/mxeneos/scripts/check-policy.sh` (init's exact `secilc` compile with the phone's own
   vendor and odm policy, `property_info_checker`, `checkseapp`, `checkfc`, genfscon conflicts) and `verify_zip.py`
   (payload equals the built images, no vendor/odm/dtbo/vbmeta/recovery operations).
6. Flash: TWRP, `adb sideload <zip>`. Back up `boot` first.

### Kernel
Samsung OSS first commit `05a32cd5f` of `loftenth-eepy/android_kernel_samsung_a22x` (not the fork's head, which adds KernelSU).
`docs/mxeneos/scripts/build-kernel.sh`: `git archive` export (no `.git`, so the release string has no `+`), `a22x_defconfig`,
AOSP clang r383902 + gcc 4.9 binutils, `LOCALVERSION=-27218697`. The vendor modules require vermagic `4.14.186-27218697`,
and all 1034 symbol CRCs (MODVERSIONS) were checked against the vendor modules (0 mismatches). 39-bit VA space.
Kernel binaries are not published here; the config matches the phone's `/proc/config.gz`.

## Known limitations and risks
- Android 16 on a 4.14 kernel and a 3-major-version-old vendor is outside what Google or Lineage support. Expect surprises.
- hardened_malloc needs a smaller class region on this kernel (39-bit VA): 1 GiB (`docs/mxeneos/port/hardened-malloc.mk`). That value is untested for long-run stability.
- Local network access rules not enforced (above). Other Android 16 BPF features that need newer kernels are silently absent (25 of 73 program sections load on 4.14.186; the required ones only use helpers in upstream 4.14).
- Known cosmetic issues in the v7 build, fixed in the next build: status-bar clock too close to the rounded corner (no overlay for the display), default wallpaper (Lineage's runtime overlay wins because `device.mk` sets `PRODUCT_ENFORCE_RRO_TARGETS := *`).
- TWRP could not mount encrypted `/data` after some boots; that is a TWRP decryption issue, not something this branch changes.
- Flashing is at your own risk. Keep a `boot` backup and the stock firmware at hand.

## What is deliberately not here
Kernel and image binaries, signing keys, and the raw survey of the test phone (it contains device identifiers). The vendor and odm partitions
are never modified.

## Failure timeline (each step is one flashed zip)
- v2: kernel booted, init aborted at 3.7 s, SELinux policy compile failed on the two genfscon conflicts. Reproduced offline with the phone's own vendor policy; a second conflict (camera property) found by the new preflight before flashing.
- v3: `NetBpfLoad: Android V requires kernel 4.19` and a `reboot,bpfloader-failed` loop.
- v4: `ro.bpf.kver_override` analysed offline as likely to fail, not flashed.
- v5: reached the boot animation; `netd` aborted ~30 ms after each start (BpfHandler gates plus `abort()`), init restarted the framework in a loop.
- v6: netd stayed up; `system_server` died every few seconds on `Cannot open local_net_access map` (errno 524).
- v7: that map made optional. Boots to the launcher, setup wizard completes.

Diagnosis used pstore (`console-ramoops`, `pmsg` persisted logcat) read from TWRP after each failed boot.

## Layout of `docs/mxeneos/`
- `port/`: product makefile (`mxeneos_a22x.mk`), `hardened-malloc.mk`, `AndroidProducts.mk`, port manifest. A snapshot of the separate port repo `device/mxeneos/a22x`.
- `patches/`: `git format-patch` of the three out-of-tree changes above, with `BASES.txt`.
- `scripts/`: `mkzip.py`, `check-policy.sh`, `verify_zip.py`, `build-kernel.sh` (written for the author's build node; paths are variables near the top).
- `KNOWN-DEVIATIONS.md`: where every change lives and what was tried and dropped.
- `local_manifest.xml`: pinned manifest for the three forks.
